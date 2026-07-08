import std/[tables, typetraits]
import pkg/godot except print
import godotapi/[node, spatial]
import core, models, nodes/[bot_node, build_node, sign_node, player_node]

proc remove_from_scene(thing: Thing) =
  debug "removing thing", thing = thing.id
  if not ?thing.node:
    # Worker added the thing to its parent's `things` collection, but the
    # main-thread watcher hadn't run `add_to_scene` yet. Nothing to remove
    # from the scene tree; just destroy the thing.
    thing.destroy
    thing.parent = nil
    return
  if thing == previous_build:
    previous_build = nil
  if thing == current_build:
    current_build = nil

  # Untrack the thing's watchers up front — before the teardown below mutates
  # flags / clears children — so no watcher fires against the node we're about
  # to free. `destroy` finishes the lifetime again at the end (idempotent).
  if ?thing.lifetime:
    thing.lifetime.finish()

  thing.global_flags -= READY

  let things = thing.things.value
  thing.things.clear
  for child in things:
    child.remove_from_scene()

  if thing.node of BuildNode:
    BuildNode(thing.node).model = nil
  elif thing.node of BotNode:
    BotNode(thing.node).model = nil
  elif thing.node of SignNode:
    SignNode(thing.node).model = nil
  thing.node.queue_free()
  debug "removing node", thing_id = thing.id
  thing.node = nil

  thing.destroy
  thing.parent = nil

proc add_to_scene(thing: Thing) =
  debug "adding thing to scene", thing = thing.id
  proc add(thing: auto, T: type, parent_node: Node) =
    thing.frame_created = state.frame_count
    var node = thing.node as T
    if node.is_nil:
      node = T.init
    thing.node = node
    node.model = thing
    node.transform = thing.transform
    if node.owner != nil:
      fail \"{T.name} node shouldn't be owned. thing = {thing.id}"
    thing.node.visible =
      VISIBLE in thing.global_flags and
      (SCRIPT_INITIALIZING notin thing.global_flags)

    info "add_to_scene: adding child", thing_id = thing.id, global = (GLOBAL in thing.global_flags)
    parent_node.add_child(thing.node)
    thing.node.owner = parent_node
    when compiles(node.setup):
      node.setup
    thing.main_thread_joined
    thing.global_flags += READY

  let parent_node =
    if GLOBAL in thing.global_flags: state.nodes.data else: thing.parent.node

  if thing of Bot:
    Bot(thing).add(BotNode, parent_node)
  elif thing of Build:
    Build(thing).add(BuildNode, parent_node)
  elif thing of Sign:
    Sign(thing).add(SignNode, parent_node)
  elif thing of Player:
    let player = Player(thing)
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
    fail "unknown thing type for " & thing.id

  for child in thing.things:
    child.parent = thing
    child.add_to_scene

proc set_global(thing: Thing, global: bool) =
  var parent_node = thing.node.get_node("..")
  parent_node.remove_child(thing.node)
  # During a transfer (adopt/release) the node reparents here, but `adopt`
  # sets the thing's parent-local transform explicitly, so skip the
  # start_transform-based origin shift (it's the wrong offset for an arbitrary
  # adoptee — it assumes the thing was instanced at its parent).
  let transferring = TRANSFERRING in thing.global_flags
  if global:
    state.nodes.data.add_child(thing.node)
    thing.node.owner = state.nodes.data
    if not transferring:
      thing.transform_value.origin =
        thing.transform.origin + thing.start_transform.origin
  else:
    thing.parent.node.add_child(thing.node)
    thing.node.owner = thing.parent.node
    if not transferring:
      thing.transform_value.origin =
        thing.transform.origin - thing.start_transform.origin

proc reset_nodes() =
  current_build = nil
  previous_build = nil

proc find_nested_changes(parent: Change[Thing]) =
  for change in parent.triggered_by:
    if change.type_name == $Change[Thing]:
      let change = Change[Thing](change)
      if Modified in change.changes:
        find_nested_changes(change)
      elif Added in change.changes:
        # FIXME: this is being set for the worker thread in script_controller
        change.item.fix_parents(parent.item)
        change.item.add_to_scene()
      elif Removed in change.changes:
        if TRANSFERRING notin change.item.global_flags:
          reset_nodes()
          change.item.remove_from_scene()
    elif change.type_name == $Change[GlobalModelFlags]:
      let change = Change[GlobalModelFlags](change)
      if change.item == GLOBAL:
        if Added in change.changes:
          parent.item.set_global(true)
        elif Removed in change.changes:
          parent.item.set_global(false)

proc add_or_defer(self: NodeController, thing: Thing) {.gcsafe.}

proc watch_things(self: NodeController, thing: Thing) {.gcsafe.} =
  thing.things.watch(thing):
    if added:
      change.item.fix_parents(thing)
      self.add_or_defer(change.item)
    elif removed:
      if TRANSFERRING notin change.item.global_flags:
        reset_nodes()
        change.item.remove_from_scene()

  thing.global_flags.watch(thing):
    if GLOBAL.added:
      thing.set_global(true)
    elif GLOBAL.removed:
      thing.set_global(false)

proc add_or_defer(self: NodeController, thing: Thing) {.gcsafe.} =
  ## Narrow partial replicas: a thing can arrive before its data (placeholder
  ## containers). Defer the scene add until the core containers fill — the
  ## worker's deep fetch brings them, and `drain_pending` (per frame) finishes
  ## the join. Field watchers self-heal the rest via Fill changes.
  if ?thing.node:
    # Relink: the thing already has a node (it's moving between collections, not
    # being freshly spawned). Don't re-instance or re-watch — the live node is
    # reparented by `set_global` when the synced GLOBAL change lands.
    return
  if thing.sync_ready:
    thing.add_to_scene()
    self.watch_things(thing)
  else:
    debug "deferring scene add until materialized", thing_id = thing.id
    self.pending.add thing

proc drain_pending*(self: NodeController) =
  if self.pending.len == 0:
    return
  var still: seq[Thing]
  for thing in self.pending:
    if thing.destroyed:
      continue
    if thing.sync_ready:
      thing.add_to_scene()
      self.watch_things(thing)
    else:
      still.add thing
  self.pending = still

proc watch*(self: NodeController, state: GameState) =
  state.things.changes:
    info "node_ctrl state.things change", added, removed, id = change.item.id
    if added:
      # A direct member of root `state.things` is top-level (parentless). Clear a
      # stale back-ref left by `release` (which re-roots an adopted thing).
      change.item.parent = nil
      self.add_or_defer(change.item)
    elif removed:
      if TRANSFERRING in change.item.global_flags:
        discard
      else:
        change.item.remove_from_scene()
      # No explicit queue_free: the Thing is an EdRef, reclaimed by ORC once
      # unreferenced (ed then prunes its ref_pool entry). remove_from_scene
      # already handles the Godot node teardown. (step 4.3)

proc init*(_: type NodeController): NodeController =
  result = NodeController()
  result.watch state
