import std/[macros, strutils, sequtils, base64, os, json]
import class_macros

export class_macros

macro load_scripts_from_level_config*(project_path: static string): untyped =
  let dir = project_path.splitFile().dir
  let level_json_path = dir / "level.json"
  result = newStmtList()

  if fileExists(level_json_path):
    let data = parseJson(readFile(level_json_path))
    if data.hasKey("load_order"):
      for item in data["load_order"]:
        let script_name = item.getStr()
        let file_path = dir / "generated" / (script_name & ".nim")
        result.add(nnkImportStmt.newTree(newLit(file_path)))
