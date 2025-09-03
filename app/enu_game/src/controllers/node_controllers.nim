{.push warning[GcUnsafe2]: off.}
{.push warning[GcUnsafe]: off.}

import std/[tables, typetraits]
import gdext
import gdext/classes/[gdnode, gdnode3d]
import core, models, nodes/[bot_node, build_node, sign_node, player_node]

proc remove_from_scene(unit: Unit) {.gcsafe.} =
  debug "removing unit", unit = unit.id
  assert not unit.node.is_nil
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
  {.cast(gcsafe).}:
    unit.node.queue_free()
  debug "removing node", unit_id = unit.id
  unit.node = nil

  unit.destroy
  unit.parent = nil

proc add_to_scene(unit: Unit) {.gcsafe.} =
  debug "adding unit to scene", unit = unit.id
  proc add(unit: auto, T: type, parent_node: Node3D) {.gcsafe.} =
    unit.frame_created = state.frame_count
    var node: T
    {.cast(gcsafe).}:
      node = unit.node.as(T)
    if node.is_nil:
      {.cast(gcsafe).}:
        node = T.init
    unit.node = node
    node.model = unit
    {.cast(gcsafe).}:
      node.transform = unit.transform
    {.cast(gcsafe).}:
      if node.owner != nil:
        fail \"{T.name} node shouldn't be owned. unit = {unit.id}"
    {.cast(gcsafe).}:
      unit.node.visible =
        Visible in unit.global_flags and (ScriptInitializing notin unit.global_flags)

    {.cast(gcsafe).}:
      parent_node.add_child(unit.node)
    {.cast(gcsafe).}:
      unit.node.owner = parent_node
    when compiles(node.setup):
      node.setup
    unit.main_thread_joined
    unit.global_flags += Ready

  var parent_node: Node3D
  {.cast(gcsafe).}:
    parent_node =
      if Global in unit.global_flags:
        state.nodes.data.as(Node3D)
      else:
        unit.parent.node.as(Node3D)

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
      var global_node: Node3D
      {.cast(gcsafe).}:
        global_node = state.nodes.data.as(Node3D)
      player.add(BotNode, global_node)
  else:
    fail "unknown unit type for " & unit.id

  for child in unit.units:
    child.parent = unit
    child.add_to_scene

proc set_global(unit: Unit, global: bool) {.gcsafe.} =
  {.cast(gcsafe).}:
    var parent_node = unit.node.get_node("..")
    parent_node.remove_child(unit.node)
    if global:
      state.nodes.data.add_child(unit.node)
      unit.node.owner = state.nodes.data
    else:
      unit.parent.node.add_child(unit.node)
      unit.node.owner = unit.parent.node
  unit.transform_value.origin =
    if global:
      unit.transform.origin + unit.start_transform.origin
    else:
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
  # Debug: Check unit validity before setting up tracking
  if unit.is_nil() or unit.id == "":
    print("[DEBUG] watch_units: unit is nil or has empty ID, skipping tracking setup")
    return

  if not unit.units.valid:
    print("[DEBUG] watch_units: unit.units is not valid, skipping tracking setup. Unit ID: ", unit.id)
    return

  print("[DEBUG] watch_units: setting up tracking for unit ", unit.id)

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
      let unit_valid = not change.item.is_nil() and change.item.id != ""
      print("[DEBUG] Adding unit to scene: ", change.item.id, " valid: ", unit_valid)
      change.item.add_to_scene()
      self.watch_units(change.item)
    elif removed:
      print("[DEBUG] Removing unit from scene: ", change.item.id)
      change.item.remove_from_scene()
      let unit = change.item
      Zen.thread_ctx.queue_free(unit)

proc init*(_: type NodeController): NodeController =
  result = NodeController()
  result.watch state
