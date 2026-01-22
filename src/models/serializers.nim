import std/[json, jsonutils, sugar, tables, strutils, strformat, os, times, algorithm, math]
import pkg/zippy/ziparchives_v1
import core except to_json
import models
import controllers/script_controllers/scripting
import libs/eval

var load_chunks {.threadvar.}: bool

type LevelInfo = object
  enu_version, format_version: string

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

proc from_json_hook(self: var VoxelInfo, json: JsonNode) =
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

proc chunk_id_for_world_pos(pos: Vector3): Vector3 =
  ## Get chunk ID for a world position (16x16x16 chunks)
  vec3(
    math.floor(pos.x / ChunkDim).int.float,
    math.floor(pos.y / ChunkDim).int.float,
    math.floor(pos.z / ChunkDim).int.float,
  )

proc local_pos_for_world_pos(pos: Vector3): Vector3 =
  ## Get local position within chunk (0-15 for each axis)
  let chunk_id = chunk_id_for_world_pos(pos)
  vec3(
    pos.x - chunk_id.x * ChunkDim,
    pos.y - chunk_id.y * ChunkDim,
    pos.z - chunk_id.z * ChunkDim,
  )

proc load_edits_from_json(
    shared: Shared, json: JsonNode
) =
  ## Load edits from JSON format into the new packed edit_snapshots format
  ## Supports both old format (single chunk per unit) and new format (chunked with composite keys)
  for id, edits in json:
    # Group edits by chunk
    var chunks: Table[Vector3, array[CHUNK_VOLUME, PackedVoxel]]
    for edit in edits:
      let world_pos = edit[0].json_to(Vector3)
      let info = edit[1].json_to(VoxelInfo)
      let chunk_id = chunk_id_for_world_pos(world_pos)
      let local_pos = local_pos_for_world_pos(world_pos)
      let linear = linear_position(local_pos)
      if linear >= 0 and linear < CHUNK_VOLUME:
        if chunk_id notin chunks:
          var empty_chunk: array[CHUNK_VOLUME, PackedVoxel]
          chunks[chunk_id] = empty_chunk
        chunks[chunk_id][linear] = pack_voxel(info.color.action_index.ord, info.kind.ord)

    # Encode and store each chunk with EditKey
    for chunk_id, voxels in chunks:
      let packed = encode_chunk(voxels)
      if not packed.is_empty:
        let key: EditKey = (id, chunk_id)
        shared.edit_snapshots[key] = packed

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
    var chunks: Table[Vector3, array[CHUNK_VOLUME, PackedVoxel]]
    for chunk_data in json["chunks"]:
      for voxel_data in chunk_data[1]:
        let world_pos = voxel_data[0].json_to(Vector3)
        let info = voxel_data[1].json_to(VoxelInfo)
        let chunk_id = chunk_id_for_world_pos(world_pos)
        let local_pos = local_pos_for_world_pos(world_pos)
        let linear = linear_position(local_pos)
        if linear >= 0 and linear < CHUNK_VOLUME:
          if chunk_id notin chunks:
            var empty_chunk: array[CHUNK_VOLUME, PackedVoxel]
            chunks[chunk_id] = empty_chunk
          chunks[chunk_id][linear] = pack_voxel(info.color.action_index.ord, info.kind.ord)
    for chunk_id, voxels in chunks:
      let packed = encode_chunk(voxels)
      if not packed.is_empty:
        let key: EditKey = (self.id, chunk_id)
        self.shared.edit_snapshots[key] = packed
  else:
    # New edits format
    if "edits" in json:
      load_edits_from_json(self.shared, json["edits"])

proc from_json_hook(self: var Bot, json: JsonNode) =
  self = Bot.init(
    id = json["id"].json_to(string),
    transform = json["start_transform"].json_to(Transform),
  )

  if not load_chunks and "edits" in json:
    load_edits_from_json(self.shared, json["edits"])

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
  let elements = self.start_transform.basis.elements.map_it($[it.x, it.y, it.z]).join(",\n")
  let origin = self.start_transform.origin
  let edits = edits_to_string(self.shared.edit_snapshots)
  result =
    \"""
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
    let data =
      if unit of Build or unit of Bot:
        $unit
      else:
        return
    create_dir unit.data_dir
    write_file unit.data_file, data

    for unit in unit.units:
      unit.save

proc save_level*(level_dir: string, save_all = false) =
  if SERVER in state.local_flags and TEST_MODE notin state.local_flags:
    debug "saving level"
    let level = LevelInfo(enu_version: enu_version, format_version: "v0.9.2")
    write_file level_dir / "level.json", jsonutils.to_json(level).pretty

    for unit in state.units:
      if save_all or DIRTY in unit.global_flags:
        unit.save
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

proc load_units(parent: Unit) =
  let opts = JOptions(allow_missing_keys: true)
  let path = if ?parent: parent.data_dir else: state.config.data_dir
  for dir in walk_dirs(path / "*"):
    let unit_id = dir.split_path.tail
    let file_name = dir / unit_id & ".json"
    if not file_exists(file_name):
      notice "Missing unit file", file_name
      continue

    try:
      let data_file = read_file(dir / unit_id & ".json").parse_json
      var unit: Unit
      if unit_id.starts_with("bot_"):
        unit = data_file.json_to(Bot, opts)
      elif unit_id.starts_with("build_"):
        unit = data_file.json_to(Build, opts)
      else:
        quit "Unknown unit type: " & unit_id

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
  if file_exists(level_file):
    try:
      let level_json = read_file(level_file)
      let level = level_json.parse_json.json_to(LevelInfo)
      load_chunks = level.format_version == "v0.9"
    except Exception as e:
      error "Failed to load level", error = e

  let init_proc =
    worker.interpreter.select_routine("initialize_state", "base_api")

  assert not init_proc.is_nil,
    "initialize_state routine not found in base_api module. " &
      "Ensure base_api defines and exports initialize_state()."

  # Set player as active unit so VM hooks work correctly during initialization
  assert worker.active_unit.is_nil, "active_unit should be nil at this point"
  worker.active_unit = state.player

  {.gcsafe.}:
    discard worker.interpreter.call_routine(init_proc, [])

  worker.active_unit = nil

  dont_join = true
  worker.retry_failures = true
  load_units(nil)
  worker.retry_failed_scripts()
  worker.retry_failures = false
  dont_join = false

  for unit in state.units:
    unit.global_flags -= DIRTY
  state.pop_flag LOADING_SCRIPT
  state.global_flags -= LOADING_LEVEL
