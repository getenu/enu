import std/[macros, strutils, sequtils, base64, os, json]
import class_macros

export class_macros

macro load_scripts_from_level_config*(project_path: static string): untyped =
  let dir = project_path.split_file.dir
  let level_json_path = dir / "level.json"
  result = new_stmt_list()

  if file_exists(level_json_path):
    let data = parse_json(read_file(level_json_path))
    if data.has_key("load_order"):
      for item in data["load_order"]:
        let script_name = item.get_str()
        let file_path = dir / "generated" / (script_name & ".nim")
        result.add(nnkImportStmt.new_tree(new_lit(file_path)))
