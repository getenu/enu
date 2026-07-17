import
  std/[
    json, jsonutils, sugar, tables, strutils, strformat, os, times, algorithm,
    math, sets,
  ]
import pkg/zippy/ziparchives_v1
import core except to_json
import models
import models/voxels
import controllers/script_controllers/scripting
import controllers/script_controllers/vars
import libs/eval

var load_chunks {.threadvar.}: bool

type LevelInfo = object
  enu_version*, format_version*: string
  load_order*: seq[string]
  show_prototypes*: bool
  show_tools*: bool

proc from_json_hook*(self: var LevelInfo, json: JsonNode) =
  self.enu_version = json{"enu_version"}.get_str
  self.format_version = json{"format_version"}.get_str

  if "load_order" in json:
    self.load_order = json["load_order"].json_to(seq[string])
  else:
    self.load_order = @[]

  if "show_prototypes" in json:
    self.show_prototypes = json["show_prototypes"].get_bool
  else:
    self.show_prototypes = true

  if "show_tools" in json:
    self.show_tools = json["show_tools"].get_bool
  else:
    self.show_tools = true

proc to_json_hook*(self: VoxelInfo): JsonNode =
  %[%self.kind.ord, self.color.to_json_hook]

proc from_json_hook*(self: var VoxelInfo, json: JsonNode) =
  self.kind = VoxelKind(json[0].get_int)
  self.color = json[1].json_to(Color)

proc to_json_hook(self: Vector3): JsonNode =
  %[self.x, self.y, self.z]

proc from_json_hook(self: var Vector3, json: JsonNode) =
  self.x = json[0].get_float
  self.y = json[1].get_float
  self.z = json[2].get_float

proc from_json_hook(
    self: var EdTable[Vector3, VoxelInfo], json: JsonNode
) {.gcsafe.} =
  assert load_chunks
  self = EdTable[Vector3, VoxelInfo].init()
  for chunks in json:
    for chunk in chunks[1]:
      let location = chunk[0].json_to(Vector3)
      let info = chunk[1].json_to(VoxelInfo)
      self[location] = info

proc from_json_hook(self: var Transform, json: JsonNode) =
  self = Transform.init(origin = json["origin"].json_to(Vector3))
  let elements =
    if json["basis"].kind == JObject:
      # old way
      json["basis"]["elements"]
    else:
      # new way
      json["basis"]
  self.basis.elements.from_json(elements)

proc from_json_hook(self: var Build, json: JsonNode) =
  let color = json["start_color"].json_to(Color)
  self = Build.init(
    id = json["id"].json_to(string),
    transform = json["start_transform"].json_to(Transform),
    color = color,
  )

  if "palette" in json:
    # Restore the static palette in saved order BEFORE anything packs a
    # color: frame files (and future binary edits) reference palette
    # indices, so the sequence must match the one they were written with.
    for entry in json["palette"]:
      discard pack_color_index(self.shared, entry.json_to(Color))

  if load_chunks:
    # Old chunks format - group by chunk and load with EditKey
    # This is a bit inefficient as it creates a big list, but safe for migration
    var all_voxels: seq[(Vector3, VoxelInfo)] = @[]
    for chunk_data in json["chunks"]:
      for voxel_data in chunk_data[1]:
        let world_pos = voxel_data[0].json_to(Vector3)
        let info = voxel_data[1].json_to(VoxelInfo)
        all_voxels.add((world_pos, info))

    if all_voxels.len > 0:
      self.shared.pack_and_store_edited_voxels(self.id, all_voxels)
  else:
    # New edits format
    if "edits_file" in json:
      # big-build sidecar: packed chunks stored directly (palette already
      # restored above, so the indices inside resolve)
      let path = self.data_dir / json["edits_file"].json_to(string)
      if file_exists(path):
        for thing_id, chunks in decode_edits_file(read_file(path)):
          for chunk_id, snapshot in chunks:
            self.shared.edit_snapshots[(thing_id, chunk_id)] = snapshot
      else:
        warn "edits sidecar missing", unit = self.id, path = path
    elif "edits" in json:
      for id, edits in json["edits"]:
        var current_chunk_edits: seq[(Vector3, VoxelInfo)] = @[]
        for edit in edits:
          let world_pos = edit[0].json_to(Vector3)
          let info = edit[1].json_to(VoxelInfo)
          current_chunk_edits.add((world_pos, info))

        if current_chunk_edits.len > 0:
          self.shared.pack_and_store_edited_voxels(id, current_chunk_edits)

    self.voxels.rebuild_local_edits()

  if "frames" in json:
    let meta = json["frames"]
    let dir = self.data_dir / "frames"
    let count = meta["count"].get_int
    var prev = none(FrameData)
    var loaded = 0
    for i in 0 ..< count:
      let path = dir / \"{i:03}.bin"
      if not file_exists(path):
        warn "frame sidecar file missing; dropping later frames",
          unit = self.id, frame = i
        break
      try:
        let frame = decode_frame_file(read_file(path), prev)
        self.frames[i] = frame
        prev = some(frame)
        inc loaded
      except ValueError as e:
        warn "frame sidecar file unreadable; dropping later frames",
          unit = self.id, frame = i, error = e.msg
        break
    self.reset_bounds() # frame chunks count toward bounds (see reset_bounds)
    self.frames_dirty = false # loaded verbatim from disk; nothing to re-save
    info "frames sidecar loaded",
      unit = self.id,
      loaded = loaded,
      fps = meta["fps"].get_float,
      current = meta{"current"}.get_int(-1)
    if loaded > 0:
      self.frames_loop = meta["loop"].get_bool
      # Playback is never auto-resumed: it's a runtime action a script
      # triggers with `play()`. On reload we only restore the displayed
      # frame so the unit comes back visible (its voxels are TRANSIENT, so
      # only frames survive) — a script then takes over if it plays.
      if "current" in meta:
        let current = meta["current"].get_int
        if current >= 0 and current < loaded:
          self.current_frame = current

proc from_json_hook(self: var Bot, json: JsonNode) =
  # `start_color` is always written (the shared thing serializer), but tolerate
  # hand-authored or ancient files that lack it.
  let color =
    if "start_color" in json:
      json["start_color"].json_to(Color)
    else:
      ACTION_COLORS[BLACK]
  self = Bot.init(
    id = json["id"].json_to(string),
    transform = json["start_transform"].json_to(Transform),
    color = color,
  )

  if "palette" in json:
    for entry in json["palette"]:
      discard pack_color_index(self.shared, entry.json_to(Color))

  if not load_chunks and "edits_file" in json:
    let path = self.data_dir / json["edits_file"].json_to(string)
    if file_exists(path):
      for thing_id, chunks in decode_edits_file(read_file(path)):
        for chunk_id, snapshot in chunks:
          self.shared.edit_snapshots[(thing_id, chunk_id)] = snapshot
    else:
      warn "edits sidecar missing", unit = self.id, path = path
  elif not load_chunks and "edits" in json:
    for id, edits in json["edits"]:
      var current_chunk_edits: seq[(Vector3, VoxelInfo)] = @[]
      for edit in edits:
        let world_pos = edit[0].json_to(Vector3)
        let info = edit[1].json_to(VoxelInfo)
        current_chunk_edits.add((world_pos, info))

      if current_chunk_edits.len > 0:
        self.shared.pack_and_store_edited_voxels(id, current_chunk_edits)

proc `$`(self: Color): string =
  $json_utils.to_json(self)

proc `$`(self: VoxelInfo): string =
  \"[{self.kind.ord}, \"{self.color}\"]"

proc `$`(self: tuple[voxel: Vector3, info: VoxelInfo]): string =
  \"[{$[self.voxel.x, self.voxel.y, self.voxel.z]}, [{int self.info.kind}, {self.info.color}]]"

proc edits_to_string(shared: Shared): string =
  ## Serialize edit_snapshots to JSON format for backwards compatibility
  # Group edits by thing_id
  var by_thing: Table[string, seq[tuple[pos: Vector3, info: VoxelInfo]]]

  for key, packed in shared.edit_snapshots.value:
    let thing_id = key.id
    let chunk_id = key.loc

    let decoded = decode_chunk(packed)
    for linear in 0 ..< CHUNK_VOLUME:
      let packed_voxel = decoded[linear]
      if packed_voxel != EMPTY_VOXEL:
        let (color_idx, kind_ord) = unpack_voxel(packed_voxel)
        let local_pos = from_linear(linear)
        # Convert to world position
        let world_pos = vec3(
          chunk_id.x * ChunkDim + local_pos.x,
          chunk_id.y * ChunkDim + local_pos.y,
          chunk_id.z * ChunkDim + local_pos.z,
        )
        let info = (VoxelKind(kind_ord), resolve_color(shared, color_idx))
        if thing_id notin by_thing:
          by_thing[thing_id] = @[]
        by_thing[thing_id].add((world_pos, info))

  # Format output
  let edits = collect:
    for thing_id, voxels in by_thing:
      let json = voxels.map_it($(it.pos, it.info))
      if json.len > 0:
        let elements = json.join(",\n").indent(2)
        \"\"{thing_id}\": [\n{elements}\n]"
  result = edits.join(",\n")

proc count_frame_files(dir: string): int =
  for kind, path in walk_dir(dir):
    if kind == pcFile and path.ends_with(".bin"):
      inc result

proc save_frames(self: Build) =
  ## Frame animation sidecar: data/<id>/frames/NNN.bin, keyframes every
  ## FRAME_KEYFRAME_INTERVAL frames and per-chunk deltas between. The unit
  ## JSON carries the metadata (count, fps, loop) and the static palette
  ## the packed values reference.
  let dir = self.data_dir / "frames"
  if self.frames.len == 0:
    if dir_exists(dir):
      remove_dir(dir)
    return
  if not self.frames_dirty and dir_exists(dir) and
      count_frame_files(dir) == self.frames.len:
    # Untouched since load/last save: skip 24 frame re-encodes per save.
    # (Local frame mutations set frames_dirty; client-synced frames are
    # covered by the dir/count checks — a same-count in-place replacement
    # from a remote client is the one uncovered case, and the generator
    # workflow always starts from a deleted data dir.)
    return
  create_dir dir
  var prev = none(FrameData)
  for i in 0 ..< self.frames.len:
    let frame = self.frames[i]
    let key = i mod FRAME_KEYFRAME_INTERVAL == 0
    let data = encode_frame_file(
      frame,
      if key: none(FrameData) else: prev
    )
    write_file_if_changed(dir / \"{i:03}.bin", data)
    prev = some(frame)
  for kind, path in walk_dir(dir):
    if kind == pcFile and path.ends_with(".bin"):
      let name = path.extract_filename
      var stale = true
      try:
        let idx = parse_int(name[0 ..^ 5])
        stale = idx < 0 or idx >= self.frames.len
      except ValueError:
        discard
      if stale:
        remove_file path
  self.frames_dirty = false

proc extras_json(self: Thing): string =
  ## Optional trailing sections for the unit JSON: frame-animation metadata
  ## and the static color palette (frame files reference palette indices,
  ## so the palette must restore in the same order on load).
  if self of Build and Build(self).frames.len > 0:
    let build = Build(self)
    result.add \""",
  "frames": {{
    "version": {FRAME_FILE_VERSION},
    "count": {build.frames.len},
    "fps": {build.frames_fps},
    "loop": {build.frames_loop},
    "current": {build.current_frame},
    "keyframe_interval": {FRAME_KEYFRAME_INTERVAL}
  }}"""
  if ?self.shared and self.shared.palette.len > 0:
    # One color per line: a gradient build's palette runs to hundreds of
    # entries, and a single wrapped line is unreadable / undiffable.
    let entries = collect:
      for color in self.shared.palette:
        \"    {$color}"
    result.add \""",
  "palette": [
{entries.join(",\n")}
  ]"""

proc edited_voxel_count(shared: Shared): int =
  for _, packed in shared.edit_snapshots.value:
    let decoded = decode_chunk(packed)
    for linear in 0 ..< CHUNK_VOLUME:
      if decoded[linear] != EMPTY_VOXEL:
        inc result

proc save_edits_sidecar(self: Thing): bool =
  ## Big builds persist their hand edits as packed chunks in
  ## data/<id>/edits.bin instead of the per-voxel JSON list (~30-40x
  ## smaller before compression). Returns whether the sidecar was written
  ## — the JSON then records "edits_file" instead of inline edits.
  if state.is_nil or not state.config_value.loaded:
    # No level dir (bare `$unit`, e.g. a unit test with no game state) —
    # there's nowhere to write a sidecar, so keep edits inline and touch no
    # files. `data_dir` dereferences `state.config`, absent here.
    return false
  if edited_voxel_count(self.shared) <= EDITS_SIDECAR_THRESHOLD:
    let stale = self.data_dir / "edits.bin"
    if file_exists(stale):
      remove_file stale
    return false
  var edits: Table[string, Table[Vector3, SnapshotData]]
  for key, packed in self.shared.edit_snapshots.value:
    edits.mget_or_put(key.id, Table[Vector3, SnapshotData]())[key.loc] = packed
  create_dir self.data_dir
  write_file_if_changed(self.data_dir / "edits.bin", encode_edits_file(edits))
  true

proc `$`(self: Thing): string =
  let elements =
    self.start_transform.basis.elements.map_it($[it.x, it.y, it.z]).join(",\n")
  let origin = self.start_transform.origin
  let edits_section =
    if self.save_edits_sidecar():
      "\"edits_file\": \"edits.bin\""
    else:
      let edits = edits_to_string(self.shared)
      \""""edits": {{
{edits.indent(4)}
  }}"""
  result = \"""
{{
  "id": "{self.id}",
  "start_transform": {{
    "basis": [
{elements.indent(6)}
    ],
    "origin": {$[origin.x, origin.y, origin.z]}
  }},
  "start_color": {self.start_color},
  {edits_section}{self.extras_json}
}}
    """

proc save*(thing: Thing) =
  if not ?thing.clone_of:
    if thing of Build:
      Build(thing).voxels.flush_edits_for_save()

    let data =
      if thing of Build or thing of Bot:
        $thing
      else:
        return
    # Things are marked DIRTY at init, so freshly-deserialized things get
    # re-saved verbatim on the next save_level; write_file_if_changed keeps
    # that from bumping the mtime and reload-looping another instance
    # watching the same level dir.
    create_dir thing.data_dir
    write_file_if_changed(thing.data_file, data)
    if thing of Build:
      Build(thing).save_frames()

    for thing in thing.things:
      thing.save

proc topo_sort(
    nodes: seq[string], graph: Table[string, seq[string]]
): seq[string] =
  var
    visited = initHashSet[string]()
    temp_visited = initHashSet[string]()
    order = newSeq[string]()

  proc visit(node: string) =
    if node in temp_visited:
      raise ValueError.init(
        "Circular dependency detected involving script: " & node
      )
    if node in visited:
      return

    temp_visited.incl(node)

    if node in graph:
      for dep_path in graph[node]:
        visit(dep_path.extract_filename)

    temp_visited.excl(node)
    visited.incl(node)
    order.add(node)

  for node in nodes:
    visit(node)

  result = order

proc load_things*(parent: Thing, load_order: seq[string] = newSeq[string]()) =
  let opts = JOptions(allow_missing_keys: true)
  let path = if ?parent: parent.data_dir else: state.config.data_dir

  var loaded_data:
    seq[tuple[id: string, dir: string, json: JsonNode, script: string]] = @[]
  var sort_nodes = newSeq[string]()
  var script_to_data = initTable[string, int]()

  for dir in walk_dirs(path / "*"):
    let thing_id = dir.split_path.tail
    let file_name = dir / thing_id & ".json"
    if not file_exists(file_name):
      continue

    try:
      let data_file = read_file(file_name).parse_json
      let script_name = thing_id
      loaded_data.add((thing_id, dir, data_file, script_name))
      # players.nim is loaded separately or always first, so exclude it from
      # the dependency graph sort to avoid circular dependency issues or
      # confusion.
      if script_name != "players":
        sort_nodes.add(script_name)
      script_to_data[script_name] = loaded_data.high
    except Exception as e:
      error "Failed to read thing file", thing_id, error = e

  var sorted_scripts = load_order

  # Things missing from the saved list get slotted in: script-less data
  # units (the terrain and other pure-JSON builds) load FIRST — they have
  # no dependencies and they're the ground the player needs under their
  # feet — while unlisted scripted things append at the end as before.
  for (id, dir, _, script) in loaded_data:
    if script notin sorted_scripts:
      if not file_exists(state.config.script_dir / script & ".nim") and
          not file_exists(dir / script & ".nim"):
        sorted_scripts.insert(script, 0)
      else:
        sorted_scripts.add script

  for script_name in sorted_scripts:
    if script_name notin script_to_data:
      continue

    let idx = script_to_data[script_name]
    let (thing_id, dir, data_file, _) = loaded_data[idx]

    try:
      var thing: Thing
      if thing_id.starts_with("bot_"):
        thing = data_file.json_to(Bot, opts)
      elif thing_id.starts_with("build_"):
        thing = data_file.json_to(Build, opts)
      else:
        # quit "Unknown thing type: " & thing_id
        error "Unknown thing type", thing_id
        continue

      thing.global_flags += SCRIPT_INITIALIZING
      if parent.is_nil:
        state.things.add(thing)
      else:
        parent.things.add(thing)
      if thing of Build:
        Build(thing).reset_bounds
        Build(thing).restore_edits

      if file_exists(thing.script_ctx.script):
        thing.code = Code.init(read_file(thing.script_ctx.script))
      else:
        thing.global_flags -= SCRIPT_INITIALIZING
        # A scripted build renders its restored edits when its code loads
        # (change_code -> reset, then end_asap when the script finishes). A
        # build with no script never gets that pass, so do it here: reset()
        # restores+draws into the ASAP buffer, end_asap() flushes it to a mesh.
        if thing of Build:
          Build(thing).reset()
          Build(thing).end_asap()
    except Exception as e:
      error "Failed to load thing", thing_id, error = e

const
  # Distinctive token present in every managed file's marker, in any format.
  # A file is Enu-managed if it contains this (or doesn't exist yet); the user
  # opts out by deleting the marker. Kept short and shared so the legacy
  # `# AUTOGENERATED` header and the new markdown/JSON markers all match.
  autogenerated_sentinel = "AUTOGENERATED"
  autogenerated_header =
    "# AUTOGENERATED\n# This file is managed by Enu. Delete the line above to manage it yourself.\n"
  autogenerated_md_header =
    "<!-- AUTOGENERATED — managed by Enu. Delete this line to manage it yourself. -->\n"
  autogenerated_json_notice =
    "AUTOGENERATED — managed by Enu. Delete this line to manage this file yourself."
  enu_managed_marker = ".enu_managed"

proc try_write_autogenerated(path, content: string) =
  # Write only if the file is missing or still carries the marker; once the
  # user removes the marker the file is theirs and we leave it alone.
  if file_exists(path) and autogenerated_sentinel notin read_file(path):
    return
  write_file_if_changed(path, content)

proc mcp_bin_path(): string =
  ## Absolute path to the Enu MCP server binary (`bin/enu`), derived from
  ## lib_dir so it tracks the install: dev -> <repo>/bin/enu, dist -> the
  ## `bin/` next to the bundled share.
  let exe = when defined(windows): "enu.exe" else: "enu"
  normalized_path(state.config.lib_dir.parent_dir / "bin" / exe)

proc mcp_json_content(mcp_bin: string): string =
  let node =
    %*{
      "//": autogenerated_json_notice,
      "mcpServers": {
        "enu": {"type": "stdio", "command": mcp_bin, "args": ["mcp"]}
      },
    }
  node.pretty & "\n"

proc settings_local_content(): string =
  # Pre-approve the Enu MCP server so agents (and users) get the tools with no
  # approval prompt — the one bit of provisioning Claude Code requires to be
  # explicit. Skills/commands auto-load straight from .claude/, no plugin.
  let node =
    %*{"//": autogenerated_json_notice, "enabledMcpjsonServers": ["enu"]}
  node.pretty & "\n"

proc save_agent_support(level_dir: string) =
  # CLAUDE.md — bundled level guide, with the marker prepended.
  let claude_src = state.config.lib_dir / "agent" / "CLAUDE.md"
  if file_exists(claude_src):
    try_write_autogenerated(
      level_dir / "CLAUDE.md", autogenerated_md_header & read_file(claude_src)
    )
  # .mcp.json — Enu MCP server (machine-specific binary path, so gitignored).
  # Skip it when the binary isn't built, rather than write a command that fails.
  let mcp_bin = mcp_bin_path()
  if file_exists(mcp_bin):
    try_write_autogenerated(level_dir / ".mcp.json", mcp_json_content(mcp_bin))
  else:
    debug "Enu MCP binary not found; skipping .mcp.json", path = mcp_bin
  # .claude/ — skills, commands, examples, and MCP auto-approval, managed as a
  # thing: a single `.enu_managed` marker means Enu owns the whole dir and rewrites
  # it wholesale on load; delete the marker to take it over yourself. Skills
  # auto-load from .claude/skills (no plugin/install), commands are namespaced
  # under enu/ (→ /enu:<cmd>), and settings.local.json pre-approves the MCP.
  let claude_dir = level_dir / ".claude"
  if dir_exists(claude_dir) and not file_exists(claude_dir / enu_managed_marker):
    return
  remove_dir(claude_dir)
  create_dir(claude_dir)
  write_file(claude_dir / enu_managed_marker, autogenerated_json_notice & "\n")
  write_file(claude_dir / "settings.local.json", settings_local_content())
  let agent_src = state.config.lib_dir / "agent"
  if dir_exists(agent_src / "skills"):
    copy_dir(agent_src / "skills", claude_dir / "skills")
  if dir_exists(agent_src / "commands"):
    copy_dir(agent_src / "commands", claude_dir / "commands" / "enu")
  if dir_exists(agent_src / "examples"):
    copy_dir(agent_src / "examples", claude_dir / "examples")

proc save_ide_support(level_dir: string, sorted_scripts: seq[string]) =
  let imports = sorted_scripts.map_it("import " & it).join("\n")
  try_write_autogenerated(
    level_dir / "project.nim", autogenerated_header & imports & "\n"
  )
  try_write_autogenerated(
    level_dir / "project.nimble",
    autogenerated_header &
      "version = \"0.1.0\"\nauthor = \"Enu\"\ndescription = \"Enu world scripts\"\nlicense = \"MIT\"\nsrcDir = \".\"\nbin = @[\"project\"]\n",
  )
  try_write_autogenerated(
    level_dir / "nim.cfg",
    autogenerated_header & "--path:\"" & state.config.lib_dir / "vmlib" / "enu" &
      "\"\n--path:\"generated\"\n",
  )
  try_write_autogenerated(
    level_dir / ".gitignore",
    autogenerated_header &
      "generated/\nnim.cfg\n.gitignore\n.mcp.json\nCLAUDE.md\n.claude/\n",
  )
  save_agent_support(level_dir)

proc save_level*(level_dir: string, save_all = false, force = false) =
  if (SERVER in state.local_flags and TEST_MODE notin state.local_flags) or force:
    var graph = initTable[string, seq[string]]()
    var sort_nodes = newSeq[string]()
    var error_nodes = newSeq[string]()
    for thing in state.things:
      if EPHEMERAL in thing.global_flags:
        continue
      if thing.script_ctx != nil:
        let filename = thing.script_ctx.file_name.extract_filename
        if filename != "":
          let name =
            if filename.ends_with(".nim"):
              filename[0 .. ^5]
            else:
              filename
          if thing.errors.value.len > 0:
            if name notin error_nodes:
              error_nodes.add(name)
          else:
            if name notin sort_nodes:
              sort_nodes.add(name)
            if thing.script_ctx.dependencies.len > 0:
              var deps: seq[string] = @[]
              for dep in thing.script_ctx.dependencies:
                let dep_name = dep.extract_filename
                deps.add(
                  if dep_name.ends_with(".nim"):
                    dep_name[0 .. ^5]
                  else:
                    dep_name
                )
              graph[name] = deps

    var sorted_scripts: seq[string]
    try:
      sorted_scripts = error_nodes & topo_sort(sort_nodes, graph)
      debug "saving level sorted scripts", scripts_len = sorted_scripts.len
    except ValueError as e:
      error "Cannot save level script order due to circular dependency",
        error = e.msg
      sorted_scripts = error_nodes & sort_nodes # fallback: save unordered

    if sorted_scripts.len > 0:
      debug "load_order content", load_order = sorted_scripts

    let level = LevelInfo(
      enu_version: enu_version,
      format_version: "v0.9.2",
      load_order: sorted_scripts,
      show_prototypes: state.show_prototypes,
      show_tools: state.show_tools,
    )
    write_file_if_changed level_dir / "level.json",
      jsonutils.to_json(level).pretty
    save_ide_support(level_dir, sorted_scripts)

    for thing in state.things:
      if EPHEMERAL in thing.global_flags:
        continue
      if save_all or DIRTY in thing.global_flags:
        thing.save
        if ?thing.script_ctx:
          try:
            thing.script_ctx.last_saved_json_mtime =
              get_last_modification_time(thing.data_file)
          except OSError:
            discard
        thing.global_flags -= DIRTY
  else:
    debug "not server. Skipping save."

proc backup_level*(level_dir: string) =
  if SERVER in state.local_flags:
    let backup_dir = state.config.world_dir / "backups"
    create_dir backup_dir

    let backup_file =
      backup_dir / state.config.level & "_" &
      times.now().format("yyyy-MM-dd-HH-mm-ss") & ".zip"

    let backups = walk_files(
      backup_dir / state.config.level & "_????-??-??-??-??-??.zip"
    ).to_seq.sorted

    if backups.len > 19:
      for file in backups[0 ..^ 20]:
        remove_file file

    create_zip_archive(level_dir, backup_file)

proc load_user_config*(dir = ""): UserConfig =
  var work_dir = dir
  if not ?dir:
    work_dir = state.config.work_dir
  let config_file = join_path(work_dir, "config.json")
  if file_exists(config_file):
    let opt = Joptions(allow_missing_keys: true, allow_extra_keys: true)
    try:
      result.from_json(read_file(config_file).parse_json, opt)
    except Exception as e:
      error "Failed to load user config", error = e

proc build_user_config*(config: Config): UserConfig =
  for config_name, config_field in config.field_pairs:
    for user_name, user_field in result.field_pairs:
      when config_name == user_name:
        user_field = some(config_field)

proc save_user_config*(config: UserConfig) =
  let
    work_dir = state.config.work_dir
    config_file = join_path(work_dir, "config.json")
  write_file(config_file, jsonutils.to_json(config).pretty)

proc change_loaded_level*(level, world: string) =
  var config = state.config
  config.world = world
  config.level = level
  state.level_name = config.world & "/" & config.level
  config.world_dir = join_path(config.work_dir, config.world)
  config.level_dir = join_path(config.world_dir, config.level)
  state.config = config

proc run_state_initializers*(worker: Worker) =
  # Re-establish VM-side globals (players.nim's `player`, etc.) registered via
  # register_state_init. Must run after every interpreter rebuild before any
  # thing script executes — thing scripts reference `player` at top level.
  let init_proc =
    worker.interpreter.select_routine("initialize_state", "core")

  assert not init_proc.is_nil,
    "initialize_state routine not found in core module. " &
      "Ensure core defines and exports initialize_state()."

  # Set player as active thing so VM hooks work correctly during initialization
  assert worker.active_thing.is_nil, "active_thing should be nil at this point"
  worker.active_thing = state.player
  state.player.script_ctx.fuel = script_fuel

  try:
    {.gcsafe.}:
      discard worker.interpreter.call_routine(init_proc, [])
  except VMQuit as e:
    state.err(e.msg)

  worker.active_thing = nil

proc unload_level*(worker: Worker) =
  state.global_flags += LOADING_LEVEL
  state.push_flag LOADING_SCRIPT
  state.pop_flag PLAYING
  state.things.clear_all
  state.pop_flag LOADING_SCRIPT
  state.global_flags -= LOADING_LEVEL

var level_loading* = false
  ## True while load_level populates things. watch_code's autosave consults
  ## this: the loader assigning each unit's code was triggering a full
  ## save_level (frame re-encodes included) synchronously inside the load —
  ## most of a debug build's 5-10s boot penalty.

proc load_level*(worker: Worker, level_dir: string) =
  level_loading = true
  defer:
    level_loading = false
  state.global_flags += LOADING_LEVEL
  state.push_flag LOADING_SCRIPT
  if not state.player.is_nil:
    state.player.block_log_entries.clear
  var config = state.config

  config.level_dir = level_dir
  config.data_dir = join_path(config.level_dir, "data")
  config.script_dir = join_path(config.level_dir, "scripts")

  let level_file = level_dir / "level.json"

  if not file_exists(level_file):
    let
      base = config.lib_dir / "worlds" / config.world
      level = base / config.level
      tmpl = base / "template"

    if dir_exists(level):
      copy_dir(level, config.level_dir)
    elif dir_exists(config.world_dir / "template"):
      copy_dir(config.world_dir / "template", config.level_dir)
    elif dir_exists(tmpl):
      copy_dir(tmpl, config.level_dir)

  create_dir(config.data_dir)
  create_dir(config.script_dir)

  state.config = config

  debug "loading ", level_file
  var load_order = newSeq[string]()

  state.show_prototypes = true
  state.show_tools = true
  if file_exists(level_file):
    try:
      let level_json = read_file(level_file)
      let level = level_json.parse_json.json_to(LevelInfo)
      load_chunks = level.format_version == "v0.9"
      if level.load_order.len > 0:
        load_order = level.load_order
      state.show_prototypes = level.show_prototypes
      state.show_tools = level.show_tools
    except Exception as e:
      error "Failed to load level", error = e

  # Seed the available tools before scripts run and the player can interact:
  # full set by default, empty when the level opts out (its script adds back
  # what it needs). Happens inside LOADING_LEVEL so the toolbar snaps, no slide.
  if state.show_tools:
    state.tools.value = {CODE_MODE .. PLACE_BOT}
  else:
    state.tools.clear()

  worker.run_state_initializers()

  dont_join = true
  worker.retry_failures = true
  load_things(nil, load_order)

  worker.retry_failed_scripts()
  worker.retry_failures = false
  dont_join = false

  # Save after retry so all deps (including those from retried scripts) are captured
  save_level(state.config.level_dir, save_all = true)

  for thing in state.things:
    thing.global_flags -= DIRTY
  state.pop_flag LOADING_SCRIPT
  state.global_flags -= LOADING_LEVEL
