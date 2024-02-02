import std/[tables, typetraits]
import pkg/godot except print
import godotapi/[node, spatial]
import core, models, nodes/[bot_node, build_node, sign_node, player_node]

proc remove_from_scene(unit: Unit) =
  debug "removing unit", unit = unit.id
  assert ?unit.node
  if unit == previous_build:
    previous_build = nil
  if unit == current_build:
    current_build = nil

  for zid in unit.zids:
    Zen.thread_ctx.untrack zid
  unit.zids = @[]

  unit.global_flags -= Ready

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
      Visible in unit.global_flags and ScriptInitializing notin unit.global_flags

    parent_node.add_child(unit.node)
    unit.node.owner = parent_node
    when compiles(node.setup):
      node.setup
    unit.main_thread_joined
    unit.global_flags += Ready

  let parent_node =
    if Global in unit.global_flags: state.nodes.data else: unit.parent.node

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
      if change.item == Global:
        if Added in change.changes:
          parent.item.set_global(true)
        elif Removed in change.changes:
          parent.item.set_global(false)

proc watch_units(self: NodeController, unit: Unit) {.gcsafe.} =
  unit.units.watch(unit):
    if added:
      change.item.fix_parents(unit)
      change.item.add_to_scene()
      self.watch_units(change.item)
    elif removed:
      reset_nodes()
      change.item.remove_from_scene()

  unit.global_flags.watch(unit):
    if Global.added:
      unit.set_global(true)
    elif Global.removed:
      unit.set_global(false)

proc watch*(self: NodeController, state: GameState) =
  state.units.changes:
    if added:
      change.item.add_to_scene()
      self.watch_units(change.item)
    elif removed:
      change.item.remove_from_scene()
      let unit = change.item
      Zen.thread_ctx.queue_free(unit)

proc init*(_: type NodeController): NodeController =
  result = NodeController()
  result.watch state
