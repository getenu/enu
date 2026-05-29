import std/[os, with, tables]
import godotapi/spatial
from pkg/core/godotcoretypes import Basis
import core, models/[states, colors], libs/interpreters

proc fix_parents*(self: Unit, parent: Unit) =
  self.parent = parent
  for unit in self.units:
    unit.fix_parents(self)

proc init_shared*(self: Unit) =
  assert ?self.shared_value
  if ?self.parent:
    self.shared = self.parent.shared
  elif not ?self.shared:
    self.shared_value.init
    var shared = Shared(id: self.id & "-shared")
    shared.init_ed_fields
    self.shared = shared

proc init_unit*[T: Unit](self: T, shared = true) =
  with self:
    units = EdSeq[Unit].init()
    transform_value = ed(self.start_transform)
    global_flags = EdSet[GlobalModelFlags].init()
    local_flags = EdSet[LocalModelFlags].init(flags = {SYNC_LOCAL})
    code_value = EdValue[Code].init()
    velocity_value = EdValue[Vector3].init()
    scale_value = ed(1.0)
    glow_value = EdValue[float].init()
    color_value = ed(self.start_color)
    errors = ScriptErrors.init
    current_line_value = ed(0)
    collisions = EdSeq[(string, Vector3)].init(flags = {SYNC_LOCAL})
    shared_value = EdValue[Shared].init()
    sight_query_value = EdValue[SightQuery].init(flags = {SYNC_LOCAL})
    eval_value = EdValue[string].init("", flags = {SYNC_LOCAL})
    anchor_value = ed(Transform.init)
    rendered_voxel_count_value = ed(0)

  self.init_shared
  self.global_flags += VISIBLE
  self.global_flags += DIRTY

proc pivot_local*(self: Unit): Vector3 =
  ## The unit's anchor pivot in parent-local coords (or world coords if
  ## the unit is GLOBAL). Defaults to `transform.origin` when no anchor
  ## has been set, since the anchor's identity Transform has origin = 0.
  self.transform.origin + self.transform.basis.xform(self.anchor.origin)

proc pivot_basis*(self: Unit): Basis =
  ## The basis the unit is "rotated to" from the user's perspective —
  ## i.e. the basis at the anchor pivot. Composes the stored transform
  ## basis with the anchor's basis offset.
  self.transform.basis * self.anchor.basis

proc set_pivot_local*(self: Unit, pivot_in_parent_local: Vector3) =
  ## Reposition the unit so its anchor pivot lands at the given
  ## parent-local coord. Leaves rotation/scale alone.
  self.transform_value.origin =
    pivot_in_parent_local - self.transform.basis.xform(self.anchor.origin)

proc set_pivot_basis*(self: Unit, new_pivot_basis: Basis) =
  ## Re-orient the unit so the anchor pivot adopts the given basis,
  ## keeping the pivot's parent-local position fixed.
  let pivot = self.pivot_local
  let new_basis = new_pivot_basis * self.anchor.basis.inverse
  var t = Transform.init
  t.basis = new_basis
  t.origin = pivot - new_basis.xform(self.anchor.origin)
  self.transform = t

proc position*(self: Unit): Vector3 =
  if GLOBAL in self.global_flags:
    self.pivot_local
  else:
    self.pivot_local.global_from(self.parent)

proc find_root*(self: Unit, all_clones = false): Unit =
  result = self
  var parent = self.parent

  while parent != nil:
    result = parent

    if (all_clones and not ?parent.clone_of) or
        (not all_clones and GLOBAL in parent.global_flags):
      parent = nil
    else:
      parent = parent.parent

proc walk_tree*(units: seq[Unit], callback: proc(unit: Unit) {.gcsafe.}) =
  for unit in units:
    walk_tree(unit.units.value, callback)
    callback(unit)

proc walk_tree*(root: Unit, callback: proc(unit: Unit) {.gcsafe.}) =
  walk_tree(@[root], callback)

proc data_dir*(self: Unit): string =
  if self.parent.is_nil:
    state.config.data_dir / self.id
  else:
    self.parent.data_dir / self.id

proc data_file*(self: Unit): string =
  self.data_dir / self.id & ".json"

method main_thread_joined*(self: Unit) {.base, gcsafe.} =
  discard

method worker_thread_joined*(self: Unit, worker: Worker) {.base, gcsafe.} =
  discard

method batch_changes*(self: Unit): bool {.base, gcsafe.} =
  discard

method apply_changes*(self: Unit) {.base, gcsafe.} =
  discard

method on_begin_move*(
    self: Unit, direction: Vector3, steps: float, move_mode: int
): Callback {.base, gcsafe.} =
  fail "override me"

method on_begin_turn*(
    self: Unit, direction: Vector3, degrees: float, lean: bool, move_mode: int
): Callback {.base, gcsafe.} =
  fail "override me"

method clone*(self: Unit, clone_to: Unit, id: string): Unit {.base, gcsafe.} =
  fail "override me"

method code_template*(self: Unit, imports: string): string {.base, gcsafe.} =
  read_file self.script_ctx.script

method reset*(self: Unit) {.base, gcsafe.} =
  discard

method collect_garbage*(self: Unit) {.base, gcsafe.} =
  # Edit garbage collection now happens via the packed format
  # The edit_snapshots are re-encoded when changes are made
  discard

method ensure_visible*(self: Unit) {.base, gcsafe.} =
  discard

method on_collision*(
    self: Model, partner: Model, normal: Vector3
) {.base, gcsafe.} =
  discard

method off_collision*(self: Model, partner: Model) {.base, gcsafe.} =
  discard

method destroy*(self: Unit) {.base, gcsafe.} =
  fail "override me"

proc destroy_impl*(self: Bot | Build | Sign) =
  if self.is_destroyed:
    return
  self.is_destroyed = true
  assert ?self

  let units = self.units.value
  for unit in units:
    unit.destroy

  when self is Sign:
    self.owner = nil

  if self.parent == nil:
    let shared = self.shared
    if ?shared.edit_snapshots:
      shared.edit_snapshots.destroy
    if ?shared.edit_deltas:
      shared.edit_deltas.destroy
    self.shared = nil
    Ed.thread_ctx.free(shared)
  else:
    self.shared = nil

  for zid in self.eids:
    Ed.thread_ctx.untrack zid
  self.eids = @[]

  let parent = self.parent
  self.parent = nil
  for field in self[].fields:
    when field is Ed:
      if ?field and not field.destroyed:
        field.destroy

  if state.open_unit == self:
    state.open_unit = nil

  when self is Sign:
    if state.open_sign_value.valid and state.open_sign == self:
      state.open_sign = nil

  if ?parent:
    parent.units.pause:
      parent.units -= self
  Ed.thread_ctx.free(self)

proc clear_all*(units: EdSeq[Unit]) =
  var roots = units.value
  for unit in roots:
    if not (unit of Player):
      unit.walk_tree proc(unit: Unit) =
        unit.units.clear
      units -= unit
