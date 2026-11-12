## `bake` blocks: memoized drawing. The first time a block's key comes up,
## its body runs and every computed block it draws is recorded relative to
## the turtle pose and frame it started on. After that the body is skipped
## and the blocks are replayed wherever the turtle is.
##
## A key is `<enu key>|<site>|<inputs>`. The site of a keyless block is its
## line plus a hash of its script and the scripts that one imports, so any
## edit there draws it again; a keyed block's site is just its key. A
## recording is only dropped once its key provably can't come up again: when
## a compile no longer has its site, or the Enu bake key changed.

import std/[tables, algorithm, math, options, sets, os, strutils, monotimes, times]
import dist/checksums/src/checksums/md5
import core, models/[states, things, builds, voxels]

var last_bake_call {.threadvar.}: MonoTime

proc normalized_source(path: string): string =
  try:
    read_file(path).replace("\r\n", "\n")
  except IOError, OSError:
    ""

proc owner_ctx(self: Build, file: string): ScriptCtx =
  ## The script context compiled from `file`: usually this build's own.
  if ?self.script_ctx and self.script_ctx.script == file:
    return self.script_ctx
  var found: ScriptCtx
  state.things.value.walk_tree proc(thing: Thing) =
    if found.is_nil and ?thing.script_ctx and thing.script_ctx.script == file:
      found = thing.script_ctx
  found

proc source_key(self: Build, file: string): string =
  ## A hash of `file` and the sibling scripts it imports, newlines
  ## normalized. Cached until this build's script compiles again.
  let ctx = self.script_ctx
  if ?ctx:
    ctx.source_keys.with_value(file, known):
      return known[]
  var text = normalized_source(file)
  let owner = self.owner_ctx(file)
  if ?owner:
    for dep in owner.dependencies.sorted:
      text.add "\0" & dep & "\0" & normalized_source(file.parent_dir / dep)
  result = $to_md5(text)
  if ?ctx:
    ctx.source_keys[file] = result

proc site_part(self: Build, site: BakeSite): string =
  if site.key != "":
    "#" & site.key
  else:
    "@" & self.source_key(site.file) & ":" & $site.line

proc bake_key*(enu, site, inputs: string): string =
  enu & "|" & site & "|" & (if inputs == "": "" else: $to_md5(inputs))

proc chunk_aligned(pose: Transform): bool =
  ## Whether blocks recorded at the identity pose land on whole chunks here.
  if pose.basis != init_basis():
    return false
  for value in [pose.origin.x, pose.origin.y, pose.origin.z]:
    if value != value.round or value.int.floor_mod(ChunkDim) != 0:
      return false
  true

proc replay(self: Build, entry: BakeEntry) =
  let pose = self.draw_transform
  let base = self.frame
  let fast = self.baking.len == 0 and pose.chunk_aligned
  let shift = pose.origin / ChunkDim.float
  var offsets: seq[int]
  for offset in entry.frames.keys:
    offsets.add offset
  offsets.sort
  for offset in offsets:
    self.go_to_frame(base + offset)
    let frame_id = self.frame_id(self.frame)
    for chunk_id, packed in entry.frames[offset].chunks:
      if fast and self.voxels.stamp_chunk((frame_id, chunk_id + shift), packed):
        continue
      let cells = decode_chunk(packed)
      for linear in 0 ..< CHUNK_VOLUME:
        if cells[linear] == EMPTY_VOXEL:
          continue
        let (color_idx, _) = unpack_voxel(cells[linear])
        let local = chunk_id * ChunkDim.float + from_linear(linear)
        let cell = pose.xform_vector3(local)
        self.draw(
          vec3(cell.x.round, cell.y.round, cell.z.round),
          (TRANSIENT, resolve_color(self.shared, color_idx)),
        )
  self.go_to_frame(base + entry.end_frame)
  self.draw_transform = pose * entry.end_pose
  self.sync_turtle()
  if entry.color.is_some:
    self.color_value.value = entry.color.get
  if entry.drawing.is_some:
    self.drawing = entry.drawing.get

const BAKE_CHECK_QUIET = init_duration(seconds = 5)

proc check_bakes*() =
  ## --check-bakes: pass once the level has loaded and no `bake` has been
  ## reached for a while; any one that had to run its body failed it.
  if CHECK_BAKES notin state.local_flags or QUITTING in state.local_flags or
      LOADING_LEVEL in state.global_flags:
    return
  if last_bake_call == MonoTime() or
      get_mono_time() - last_bake_call > BAKE_CHECK_QUIET:
    notice "bakes are current"
    state.test_exit_code = 0
    state.push_flag QUITTING

proc fail_check(self: Build, msg: string) =
  error "bake check failed", unit = self.id, reason = msg
  state.test_exit_code = 1
  state.push_flag QUITTING

proc bake_begin*(
    self: Build,
    file: string,
    line: int,
    key: string,
    inputs: string,
    rebake: bool,
    enu_key: string,
): bool =
  ## True when the key's blocks were replayed and the body should be
  ## skipped. A clone doesn't keep bakes, and neither does code run outside
  ## a script (an eval): both just run the body.
  last_bake_call = get_mono_time()
  if ?self.clone_of or file == "":
    return false
  if key != "":
    let here = file.extract_filename & ":" & $line
    self.bake_key_sites.with_value(key, other):
      if other[] != here:
        raise ValueError.init(
          "two `bake` blocks use the key \"" & key & "\": " & other[] & " and " &
            here
        )
    do:
      self.bake_key_sites[key] = here
  let full = bake_key(enu_key, self.site_part((file, line, key, enu_key)), inputs)
  if CHECK_BAKES in state.local_flags:
    # skip the body either way: it can take minutes
    if rebake:
      self.fail_check("`rebake` left in a script: change it back to `bake`")
    elif full notin self.bakes:
      self.fail_check("bake is stale: its code changed since it was saved")
    else:
      self.replay(self.bakes[full])
    return true
  if full in self.bakes and not rebake:
    debug "bake replaying", unit = self.id, key = full
    self.replay(self.bakes[full])
    return true
  info "bake recording", unit = self.id, key = full
  self.baking.add BakeCapture(
    key: full,
    start: self.draw_transform,
    start_frame: self.frame,
    start_color: self.color_value.value,
    start_drawing: self.drawing,
  )
  false

proc bake_end*(self: Build, finished: bool) =
  ## The body of the innermost running `bake` is done. If it ran to the end,
  ## keep what it drew; if it raised or returned early, forget it.
  if self.baking.len == 0:
    return
  let capture = self.baking.pop
  if not finished:
    return
  var entry = BakeEntry(
    end_pose: capture.start.affine_inverse * self.draw_transform,
    end_frame: self.frame - capture.start_frame,
  )
  if self.color_value.value != capture.start_color:
    entry.color = some(self.color_value.value)
  if self.drawing != capture.start_drawing:
    entry.drawing = some(self.drawing)
  for offset, chunks in capture.cells:
    var frame: FrameData
    for chunk_id, cells in chunks:
      let packed = encode_chunk(cells)
      if not packed.is_empty:
        frame.chunks[chunk_id] = packed
    entry.frames[offset] = frame
  self.bakes[capture.key] = entry
  inc self.bakes_serial
  self.global_flags += DIRTY

proc drop_stale_bakes*(self: Build) =
  ## The script just compiled: drop recordings whose key can't come up
  ## again, because their block is gone from it (and from the sibling
  ## scripts it imports) or the Enu bake key changed. Skipped while an
  ## imported script hasn't compiled yet, since its blocks aren't known.
  if ?self.clone_of or self.bakes.len == 0 or not ?self.script_ctx:
    return
  var sites = self.script_ctx.bake_sites
  for dep in self.script_ctx.dependencies:
    let name = dep.split_file.name
    var known = false
    state.things.value.walk_tree proc(thing: Thing) =
      let ctx = thing.script_ctx
      if ?ctx and ctx.module_name == name and ctx.bakes_known:
        known = true
        sites.add ctx.bake_sites
    if not known:
      return
  var live: HashSet[string]
  for site in sites:
    live.incl site.enu & "|" & self.site_part(site)
  var stale: seq[string]
  for key in self.bakes.keys:
    if key.rsplit('|', 1)[0] notin live:
      stale.add key
  for key in stale:
    self.bakes.del key
  if stale.len > 0:
    info "dropped stale bakes", unit = self.id, count = stale.len
    inc self.bakes_serial
    self.global_flags += DIRTY

proc clear_bakes*(self: Build) =
  if self.bakes.len > 0:
    self.bakes.clear
    inc self.bakes_serial
    self.global_flags += DIRTY

proc clear_all_bakes*() =
  state.things.value.walk_tree proc(thing: Thing) =
    if thing of Build:
      Build(thing).clear_bakes()

proc baked_voxel_count*(self: Build, limit = int.high): int =
  ## Blocks across every bake, counting no further than past `limit`.
  for entry in self.bakes.values:
    for frame in entry.frames.values:
      for packed in frame.chunks.values:
        let cells = decode_chunk(packed)
        for v in cells:
          if v != EMPTY_VOXEL:
            inc result
            if result > limit:
              return
