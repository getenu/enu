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

proc to_json_hook(self: Color): JsonNode =
  result =
    if self == ACTION_COLORS[ERASER]:
      %""
    else:
      for i, color in Colors.enum_fields:
        if self == ACTION_COLORS[Colors(i)]:
          return %color
      %self.to_html_hex

proc from_json_hook(self: var Color, json: JsonNode) =
  let hex = json.get_str
  if hex == "":
    self = ACTION_COLORS[ERASER]
  else:
    for i, color in Colors.enum_fields:
      if color.to_lower == hex.to_lower:
        self = ACTION_COLORS[Colors(i)]
        return
    self = hex.parse_html_hex

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
    if "edits" in json:
      for id, edits in json["edits"]:
        var current_chunk_edits: seq[(Vector3, VoxelInfo)] = @[]
        for edit in edits:
          let world_pos = edit[0].json_to(Vector3)
          let info = edit[1].json_to(VoxelInfo)
          current_chunk_edits.add((world_pos, info))

        if current_chunk_edits.len > 0:
          self.shared.pack_and_store_edited_voxels(id, current_chunk_edits)

    self.voxels.rebuild_local_edits()

proc from_json_hook(self: var Bot, json: JsonNode) =
  self = Bot.init(
    id = json["id"].json_to(string),
    transform = json["start_transform"].json_to(Transform),
  )

  if not load_chunks and "edits" in json:
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

proc edits_to_string(edit_snapshots: EdTable[EditKey, SnapshotData]): string =
  ## Serialize edit_snapshots to JSON format for backwards compatibility
  # Group edits by unit_id
  var by_unit: Table[string, seq[tuple[pos: Vector3, info: VoxelInfo]]]

  for key, packed in edit_snapshots.value:
    let unit_id = key.id
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
        let info = (VoxelKind(kind_ord), ACTION_COLORS[Colors(color_idx)])
        if unit_id notin by_unit:
          by_unit[unit_id] = @[]
        by_unit[unit_id].add((world_pos, info))

  # Format output
  let edits = collect:
    for unit_id, voxels in by_unit:
      let json = voxels.map_it($(it.pos, it.info))
      if json.len > 0:
        let elements = json.join(",\n").indent(2)
        \"\"{unit_id}\": [\n{elements}\n]"
  result = edits.join(",\n")

proc `$`(self: Unit): string =
  let elements =
    self.start_transform.basis.elements.map_it($[it.x, it.y, it.z]).join(",\n")
  let origin = self.start_transform.origin
  let edits = edits_to_string(self.shared.edit_snapshots)
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
  "edits": {{
{edits.indent(4)}
  }}
}}
    """

proc save*(unit: Unit) =
  if not ?unit.clone_of:
    if unit of Build:
      Build(unit).voxels.flush_edits_for_save()

    let data =
      if unit of Build or unit of Bot:
        $unit
      else:
        return
    # Units are marked DIRTY at init, so freshly-deserialized units get
    # re-saved verbatim on the next save_level; write_file_if_changed keeps
    # that from bumping the mtime and reload-looping another instance
    # watching the same level dir.
    create_dir unit.data_dir
    write_file_if_changed(unit.data_file, data)

    for unit in unit.units:
      unit.save

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

proc load_units*(parent: Unit, load_order: seq[string] = newSeq[string]()) =
  let opts = JOptions(allow_missing_keys: true)
  let path = if ?parent: parent.data_dir else: state.config.data_dir

  var loaded_data:
    seq[tuple[id: string, dir: string, json: JsonNode, script: string]] = @[]
  var sort_nodes = newSeq[string]()
  var script_to_data = initTable[string, int]()

  for dir in walk_dirs(path / "*"):
    let unit_id = dir.split_path.tail
    let file_name = dir / unit_id & ".json"
    if not file_exists(file_name):
      continue

    try:
      let data_file = read_file(file_name).parse_json
      let script_name = unit_id
      loaded_data.add((unit_id, dir, data_file, script_name))
      # players.nim is loaded separately or always first, so exclude it from
      # the dependency graph sort to avoid circular dependency issues or
      # confusion.
      if script_name != "players":
        sort_nodes.add(script_name)
      script_to_data[script_name] = loaded_data.high
    except Exception as e:
      error "Failed to read unit file", unit_id, error = e

  var sorted_scripts = load_order

  # Add any scripts that might have been missed by the saved list
  # and players.nim if it exists in loaded_data
  for (id, _, _, script) in loaded_data:
    if script notin sorted_scripts:
      sorted_scripts.add script

  for script_name in sorted_scripts:
    if script_name notin script_to_data:
      continue

    let idx = script_to_data[script_name]
    let (unit_id, dir, data_file, _) = loaded_data[idx]

    try:
      var unit: Unit
      if unit_id.starts_with("bot_"):
        unit = data_file.json_to(Bot, opts)
      elif unit_id.starts_with("build_"):
        unit = data_file.json_to(Build, opts)
      else:
        # quit "Unknown unit type: " & unit_id
        error "Unknown unit type", unit_id
        continue

      unit.global_flags += SCRIPT_INITIALIZING
      if parent.is_nil:
        state.units.add(unit)
      else:
        parent.units.add(unit)
      if unit of Build:
        Build(unit).reset_bounds
        Build(unit).restore_edits

      if file_exists(unit.script_ctx.script):
        unit.code = Code.init(read_file(unit.script_ctx.script))
      else:
        unit.global_flags -= SCRIPT_INITIALIZING
    except Exception as e:
      error "Failed to load unit", unit_id, error = e

const autogenerated_header =
  "# AUTOGENERATED\n# This file is managed by Enu. Delete the line above to manage it yourself.\n"

proc try_write_autogenerated(path, content: string) =
  if file_exists(path):
    let first_line = read_file(path).split_lines[0]
    if first_line != "# AUTOGENERATED":
      return
  write_file_if_changed(path, content)

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
    autogenerated_header & "--path:\"" & state.config.lib_dir / "enu" &
      "\"\n--path:\"generated\"\n",
  )
  try_write_autogenerated(
    level_dir / ".gitignore",
    autogenerated_header & "generated/\nnim.cfg\n.gitignore\n",
  )

proc save_level*(level_dir: string, save_all = false, force = false) =
  if (SERVER in state.local_flags and TEST_MODE notin state.local_flags) or force:
    var graph = initTable[string, seq[string]]()
    var sort_nodes = newSeq[string]()
    var error_nodes = newSeq[string]()
    for unit in state.units:
      if AGENT in unit.global_flags:
        continue
      if unit.script_ctx != nil:
        let filename = unit.script_ctx.file_name.extract_filename
        if filename != "":
          let name =
            if filename.ends_with(".nim"):
              filename[0 .. ^5]
            else:
              filename
          if unit.errors.value.len > 0:
            if name notin error_nodes:
              error_nodes.add(name)
          else:
            if name notin sort_nodes:
              sort_nodes.add(name)
            if unit.script_ctx.dependencies.len > 0:
              var deps: seq[string] = @[]
              for dep in unit.script_ctx.dependencies:
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
    )
    write_file_if_changed level_dir / "level.json",
      jsonutils.to_json(level).pretty
    save_ide_support(level_dir, sorted_scripts)

    for unit in state.units:
      if AGENT in unit.global_flags:
        continue
      if save_all or DIRTY in unit.global_flags:
        unit.save
        if ?unit.script_ctx:
          try:
            unit.script_ctx.last_saved_json_mtime =
              get_last_modification_time(unit.data_file)
          except OSError:
            discard
        unit.global_flags -= DIRTY
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
  # unit script executes — unit scripts reference `player` at top level.
  let init_proc =
    worker.interpreter.select_routine("initialize_state", "base_api")

  assert not init_proc.is_nil,
    "initialize_state routine not found in base_api module. " &
      "Ensure base_api defines and exports initialize_state()."

  # Set player as active unit so VM hooks work correctly during initialization
  assert worker.active_unit.is_nil, "active_unit should be nil at this point"
  worker.active_unit = state.player
  state.player.script_ctx.fuel = script_fuel

  try:
    {.gcsafe.}:
      discard worker.interpreter.call_routine(init_proc, [])
  except VMQuit as e:
    state.err(e.msg)

  worker.active_unit = nil

proc unload_level*(worker: Worker) =
  state.global_flags += LOADING_LEVEL
  state.push_flag LOADING_SCRIPT
  state.pop_flag PLAYING
  state.units.clear_all
  state.pop_flag LOADING_SCRIPT
  state.global_flags -= LOADING_LEVEL

proc load_level*(worker: Worker, level_dir: string) =
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
  if file_exists(level_file):
    try:
      let level_json = read_file(level_file)
      let level = level_json.parse_json.json_to(LevelInfo)
      load_chunks = level.format_version == "v0.9"
      if level.load_order.len > 0:
        load_order = level.load_order
      state.show_prototypes = level.show_prototypes
    except Exception as e:
      error "Failed to load level", error = e

  worker.run_state_initializers()

  dont_join = true
  worker.retry_failures = true
  load_units(nil, load_order)

  worker.retry_failed_scripts()
  worker.retry_failures = false
  dont_join = false

  # Save after retry so all deps (including those from retried scripts) are captured
  save_level(state.config.level_dir, save_all = true)

  for unit in state.units:
    unit.global_flags -= DIRTY
  state.pop_flag LOADING_SCRIPT
  state.global_flags -= LOADING_LEVEL
