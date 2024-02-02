import std/[json, jsonutils, sugar, tables, strutils, os, times, algorithm]
import pkg/zippy/ziparchives_v1
import core except to_json
import models
import controllers/script_controllers/scripting

var load_chunks {.threadvar.}: bool

type LevelInfo = object
  enu_version, format_version: string

proc to_json_hook(self: Color): JsonNode =
  result =
    if self == action_colors[eraser]:
      %""
    else:
      for i, color in Colors.enum_fields:
        if self == action_colors[Colors(i)]:
          return %color
      %self.to_html_hex

proc from_json_hook(self: var Color, json: JsonNode) =
  let hex = json.get_str
  if hex == "":
    self = action_colors[eraser]
  else:
    for i, color in Colors.enum_fields:
      if color == hex:
        self = action_colors[Colors(i)]
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
    self: var ZenTable[Vector3, VoxelInfo], json: JsonNode
) {.gcsafe.} =
  assert load_chunks
  self = ~Table[Vector3, VoxelInfo]
  for chunks in json:
    for chunk in chunks[1]:
      let location = chunk[0].json_to(Vector3)
      let info = chunk[1].json_to(VoxelInfo)
      self[location] = info

proc from_json_hook(
    self: var ZenTable[string, ZenTable[Vector3, VoxelInfo]], json: JsonNode
) =
  assert not load_chunks
  for id, edits in json:
    for edit in edits:
      if id notin self:
        self[id] = ~Table[Vector3, VoxelInfo]
      let location = edit[0].json_to(Vector3)
      let info = edit[1].json_to(VoxelInfo)
      var locations = self[id]
      locations[location] = info
      self[id] = locations

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
  self =
    Build.init(
      id = json["id"].json_to(string),
      transform = json["start_transform"].json_to(Transform),
      color = color,
    )

  if load_chunks:
    var edit = ~Table[Vector3, VoxelInfo]()
    edit.from_json(json["chunks"])
    self.shared.edits[self.id] = edit
  else:
    self.shared.edits.from_json(json["edits"])

proc from_json_hook(self: var Bot, json: JsonNode) =
  self =
    Bot.init(
      id = json["id"].json_to(string),
      transform = json["start_transform"].json_to(Transform),
    )

  if not load_chunks:
    self.shared.edits.from_json(json["edits"])

proc `$`(self: Color): string =
  $json_utils.to_json(self)

proc `$`(self: VoxelInfo): string =
  \"[{self.kind.ord}, \"{self.color}\"]"

proc `$`(self: Vector3): string =
  \"[{self.x}, {self.y}, {self.z}]"

proc `$`(self: tuple[voxel: Vector3, info: VoxelInfo]): string =
  \"[{self.voxel}, [{int self.info.kind}, {self.info.color}]]"

proc `$`(self: ZenTable[string, ZenTable[Vector3, VoxelInfo]]): string =
  let edits =
    collect:
      for id, edit in self.value:
        let json =
          collect:
            for voxel, info in edit.value:
              $(voxel, info)
        if json.len > 0:
          let elements = json.join(",\n").indent(2)
          \"\"{id}\": [\n{elements}\n]"
  result = edits.join(",\n")

proc `$`(self: Unit): string =
  let elements = self.start_transform.basis.elements.map_it($it).join(",\n")
  let edits = $self.shared.edits
  result =
    \"""

{{
  "id": "{self.id}",
  "start_transform": {{
    "basis": [
{elements.indent(6)}
    ],
    "origin": {$self.start_transform.origin}
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
  if Server in state.local_flags:
    debug "saving level"
    let level = LevelInfo(enu_version: enu_version, format_version: "v0.9.2")
    write_file level_dir / "level.json", jsonutils.to_json(level).pretty

    for unit in state.units:
      if save_all or Dirty in unit.global_flags:
        unit.save
        unit.global_flags -= Dirty
  else:
    debug "not server. Skipping save."

proc backup_level*(level_dir: string) =
  if Server in state.local_flags:
    let backup_dir = state.config.world_dir / "backups"
    create_dir backup_dir

    let backup_file =
      backup_dir / state.config.level & "_" &
      times.now().format("yyyy-MM-dd-HH-mm-ss") & ".zip"

    let backups =
      walk_files(backup_dir / state.config.level & "_????-??-??-??-??-??.zip").to_seq.sorted

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
      error "Missing unit file", file_name
      continue
    let data_file = read_file(dir / unit_id & ".json").parse_json
    var unit: Unit
    if unit_id.starts_with("bot_"):
      unit = data_file.json_to(Bot, opts)
    elif unit_id.starts_with("build_"):
      unit = data_file.json_to(Build, opts)
    else:
      quit "Unknown unit type: " & unit_id

    unit.global_flags += ScriptInitializing
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
      unit.global_flags -= ScriptInitializing

proc load_user_config*(dir = ""): UserConfig =
  var work_dir = dir
  if not ?dir:
    work_dir = state.config.work_dir
  let config_file = join_path(work_dir, "config.json")
  if file_exists(config_file):
    let opt = Joptions(allow_missing_keys: true, allow_extra_keys: true)
    result.from_json(read_file(config_file).parse_json, opt)

proc save_user_config*(config: UserConfig) =
  let
    work_dir = state.config.work_dir
    config_file = join_path(work_dir, "config.json")
  write_file(config_file, jsonutils.to_json(config).pretty)

proc change_loaded_level*(level, world: string) =
  var config = state.config
  var user_config = load_user_config()
  config.world = world
  config.level = level
  state.level_name = config.world & "/" & config.level
  user_config.world = some(config.world)
  user_config.level = some(config.level)
  save_user_config(user_config)
  config.world_dir = join_path(config.work_dir, config.world)
  config.level_dir = join_path(config.world_dir, config.level)
  state.config = config

proc unload_level*(worker: Worker) =
  state.global_flags += LoadingLevel
  state.push_flag LoadingScript
  state.pop_flag Playing
  state.units.clear_all
  state.pop_flag LoadingScript
  state.global_flags -= LoadingLevel

proc load_level*(worker: Worker, level_dir: string) =
  state.global_flags += LoadingLevel
  state.push_flag LoadingScript
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
    let level_json = read_file(level_file)
    let level = level_json.parse_json.json_to(LevelInfo)
    load_chunks = level.format_version == "v0.9"

  dont_join = true
  worker.retry_failures = true
  load_units(nil)
  worker.retry_failed_scripts()
  worker.retry_failures = false
  dont_join = false
  for unit in state.units:
    unit.global_flags -= Dirty
  state.pop_flag LoadingScript
  state.global_flags -= LoadingLevel
