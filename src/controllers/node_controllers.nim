import std/[tables, typetraits]
import pkg/godot except print
import godotapi/[node, spatial]
import core, models, nodes/[bot_node, build_node, sign_node, player_node]

proc remove_from_scene(unit: Unit) =
  debug "removing unit", unit = unit.id
  if not ?unit.node:
    # Worker added the unit to its parent's `units` collection, but the
    # main-thread watcher hadn't run `add_to_scene` yet. Nothing to remove
    # from the scene tree; just destroy the unit.
    unit.destroy
    unit.parent = nil
    return
  if unit == previous_build:
    previous_build = nil
  if unit == current_build:
    current_build = nil

  # Untrack the unit's watchers up front — before the teardown below mutates
  # flags / clears children — so no watcher fires against the node we're about
  # to free. `destroy` finishes the lifetime again at the end (idempotent).
  if ?unit.lifetime:
    unit.lifetime.finish()

  unit.global_flags -= READY

  let units = unit.units.value
  unit.units.clear
  for child in units:
    child.remove_from_scene()

  if unit.node of BuildNode:
    BuildNode(unit.node).model = nil
  elif unit.node of BotNode:
    BotNode(unit.node).model = nil
  elif unit.node of SignNode:
    SignNode(unit.node).model = nil
  unit.node.queue_free()
  debug "removing node", unit_id = unit.id
  unit.node = nil

  unit.destroy
  unit.parent = nil

proc add_to_scene(unit: Unit) =
  debug "adding unit to scene", unit = unit.id
  proc add(unit: auto, T: type, parent_node: Node) =
    unit.frame_created = state.frame_count
    var node = unit.node as T
    if node.is_nil:
      node = T.init
    unit.node = node
    node.model = unit
    node.transform = unit.transform
    if node.owner != nil:
      fail \"{T.name} node shouldn't be owned. unit = {unit.id}"
    unit.node.visible =
      VISIBLE in unit.global_flags and
      (SCRIPT_INITIALIZING notin unit.global_flags)

    info "add_to_scene: adding child", unit_id = unit.id, global = (GLOBAL in unit.global_flags)
    parent_node.add_child(unit.node)
    unit.node.owner = parent_node
    when compiles(node.setup):
      node.setup
    unit.main_thread_joined
    unit.global_flags += READY

  let parent_node =
    if GLOBAL in unit.global_flags: state.nodes.data else: unit.parent.node

  if unit of Bot:
    Bot(unit).add(BotNode, parent_node)
  elif unit of Build:
    Build(unit).add(BuildNode, parent_node)
  elif unit of Sign:
    Sign(unit).add(SignNode, parent_node)
  elif unit of Player:
    let player = Player(unit)
    # TODO: PlayerNode should work for connected players as well
    if player.id == state.player.id:
      player.add(PlayerNode, parent_node)
      # The local player is a bodiless first-person camera, so a bot's camera
      # can't photograph it. Add a BotNode avatar that every other camera draws
      # (and that casts a shadow) but the player's own camera culls. Always on,
      # even solo — so you cast a shadow.
      let avatar = BotNode.init
      avatar.model = player
      avatar.transform = player.transform
      state.nodes.data.add_child(avatar)
      avatar.owner = state.nodes.data
      avatar.setup
      avatar.as_self_avatar
    else:
      player.start_transform = player.transform
      player.add(BotNode, state.nodes.data)
  else:
    fail "unknown unit type for " & unit.id

  for child in unit.units:
    child.parent = unit
    child.add_to_scene

proc set_global(unit: Unit, global: bool) =
  var parent_node = unit.node.get_node("..")
  parent_node.remove_child(unit.node)
  if global:
    state.nodes.data.add_child(unit.node)
    unit.node.owner = state.nodes.data
    unit.transform_value.origin =
      unit.transform.origin + unit.start_transform.origin
  else:
    unit.parent.node.add_child(unit.node)
    unit.node.owner = unit.parent.node
    unit.transform_value.origin =
      unit.transform.origin - unit.start_transform.origin

proc reset_nodes() =
  current_build = nil
  previous_build = nil

proc find_nested_changes(parent: Change[Unit]) =
  for change in parent.triggered_by:
    if change.type_name == $Change[Unit]:
      let change = Change[Unit](change)
      if Modified in change.changes:
        find_nested_changes(change)
      elif Added in change.changes:
        # FIXME: this is being set for the worker thread in script_controller
        change.item.fix_parents(parent.item)
        change.item.add_to_scene()
      elif Removed in change.changes:
        reset_nodes()
        change.item.remove_from_scene()
    elif change.type_name == $Change[GlobalModelFlags]:
      let change = Change[GlobalModelFlags](change)
      if change.item == GLOBAL:
        if Added in change.changes:
          parent.item.set_global(true)
        elif Removed in change.changes:
          parent.item.set_global(false)

proc add_or_defer(self: NodeController, unit: Unit) {.gcsafe.}

proc watch_units(self: NodeController, unit: Unit) {.gcsafe.} =
  unit.units.watch(unit):
    if added:
      change.item.fix_parents(unit)
      self.add_or_defer(change.item)
    elif removed:
      reset_nodes()
      change.item.remove_from_scene()

  unit.global_flags.watch(unit):
    if GLOBAL.added:
      unit.set_global(true)
    elif GLOBAL.removed:
      unit.set_global(false)

proc add_or_defer(self: NodeController, unit: Unit) {.gcsafe.} =
  ## Narrow partial replicas: a unit can arrive before its data (placeholder
  ## containers). Defer the scene add until the core containers fill — the
  ## worker's deep fetch brings them, and `drain_pending` (per frame) finishes
  ## the join. Field watchers self-heal the rest via Fill changes.
  if unit.sync_ready:
    unit.add_to_scene()
    self.watch_units(unit)
  else:
    debug "deferring scene add until materialized", unit_id = unit.id
    self.pending.add unit

proc drain_pending*(self: NodeController) =
  if self.pending.len == 0:
    return
  var still: seq[Unit]
  for unit in self.pending:
    if unit.destroyed:
      continue
    if unit.sync_ready:
      unit.add_to_scene()
      self.watch_units(unit)
    else:
      still.add unit
  self.pending = still

proc watch*(self: NodeController, state: GameState) =
  state.units.changes:
    info "node_ctrl state.units change", added, removed, id = change.item.id
    if added:
      self.add_or_defer(change.item)
    elif removed:
      change.item.remove_from_scene()
      # No explicit queue_free: the Unit is an EdRef, reclaimed by ORC once
      # unreferenced (ed then prunes its ref_pool entry). remove_from_scene
      # already handles the Godot node teardown. (step 4.3)

proc init*(_: type NodeController): NodeController =
  result = NodeController()
  result.watch state
