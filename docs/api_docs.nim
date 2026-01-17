## API Documentation Generator Module
## Extracts and formats API documentation from jsondoc output for Mustache templates.

import std/[json, tables, strutils, sequtils, algorithm, sets, re]

type
  SymbolKind* = enum
    skConst, skEnum, skType, skProc, skIterator, skTemplate, skMacro

  Symbol* = object
    name*: string
    display_name*: string  # For static methods: "TypeName.name"
    kind*: SymbolKind
    code*: string
    description*: string
    line*: int
    module*: string
    is_static*: bool  # True for type-bound procs like Ed.init

  TypeDoc* = object
    name*: string
    type_symbol*: Symbol     # The type definition itself
    has_type*: bool          # Whether we have a type definition
    procs*: seq[Symbol]     # Operations on this type
    static_procs*: seq[Symbol]  # Static methods (init, bootstrap, etc.)

  DocData* = object
    constants*: seq[Symbol]
    enums*: seq[Symbol]
    types*: Table[string, TypeDoc]  # Type name -> TypeDoc

  ModuleConfig* = tuple[name: string, json: string]

proc parse_kind*(s: string): SymbolKind =
  case s
  of "skConst": skConst
  of "skType": skType
  of "skProc": skProc
  of "skIterator": skIterator
  of "skTemplate": skTemplate
  of "skMacro": skMacro
  else: skProc

proc is_enum*(entry: JsonNode): bool =
  if entry["type"].get_str != "skType":
    return false
  let code = entry["code"].get_str
  code.contains(" = enum")

proc is_static_method*(entry: JsonNode): bool =
  ## Check if this is a static method (first arg is `type` or `typedesc`)
  if "signature" notin entry:
    return false
  let sig = entry["signature"]
  if "arguments" notin sig or sig["arguments"].len == 0:
    return true  # No arguments = static
  let first_arg = sig["arguments"][0]
  let type_name = first_arg["type"].get_str
  type_name.starts_with("type") or type_name.starts_with("typedesc")

proc strip_generic_params*(type_name: string): string =
  ## Strip generic parameters from a type name: "EdSeq[string]" -> "EdSeq"
  result = type_name.replace(re"\[.*\]", "")

proc extract_operating_type*(entry: JsonNode): string =
  ## Extract the base type name from the first argument of a proc
  if "signature" notin entry:
    return ""
  let sig = entry["signature"]
  if "arguments" notin sig or sig["arguments"].len == 0:
    return ""
  let first_arg = sig["arguments"][0]
  var type_name = first_arg["type"].get_str

  # Strip prefixes: "var ", "type ", "typedesc"
  type_name = type_name.replace(re"^(var|type|typedesc)\s*", "")

  # Strip generic parameters
  type_name = type_name.strip_generic_params()

  # Skip single-letter generic type params like T
  if type_name.len <= 2 and type_name.match(re"^[A-Z]$"):
    return ""

  result = type_name

proc parse_symbol*(entry: JsonNode, module: string): Symbol =
  result.name = entry["name"].get_str
  result.display_name = result.name
  result.kind = parse_kind(entry["type"].get_str)
  result.code = entry["code"].get_str
  result.description = entry.get_or_default("description").get_str
  result.line = entry.get_or_default("line").get_int
  result.module = module
  result.is_static = is_static_method(entry)

proc collect_symbols*(modules: seq[ModuleConfig]): DocData =
  ## Collect symbols from pre-loaded JSON module data
  result.types = init_table[string, TypeDoc]()
  var seen_names = init_hash_set[string]()
  var exported_types = init_hash_set[string]()

  # First pass: collect all exported types
  for (module_name, json_content) in modules:
    if json_content.len == 0:
      continue
    let doc = parse_json(json_content)
    if "entries" notin doc:
      continue
    for entry in doc["entries"]:
      if entry["type"].get_str == "skType":
        let name = entry["name"].get_str
        if not name.starts_with("_") and not name.contains("gensym"):
          exported_types.incl(name)

  # Second pass: collect all symbols
  for (module_name, json_content) in modules:
    if json_content.len == 0:
      continue

    let doc = parse_json(json_content)
    if "entries" notin doc:
      continue

    for entry in doc["entries"]:
      let name = entry["name"].get_str
      let entry_type = entry["type"].get_str

      if name.starts_with("_") or name.contains("gensym"):
        continue

      let unique_key = name & ":" & entry_type & ":" & module_name
      if unique_key in seen_names:
        continue
      seen_names.incl(unique_key)

      var symbol = parse_symbol(entry, module_name)

      case entry_type
      of "skConst":
        result.constants.add(symbol)
      of "skType":
        if is_enum(entry):
          result.enums.add(symbol)
        else:
          # Add as a type
          if name notin result.types:
            result.types[name] = TypeDoc(name: name)
          result.types[name].type_symbol = symbol
          result.types[name].has_type = true
      of "skProc", "skIterator", "skTemplate", "skMacro":
        let op_type = extract_operating_type(entry)
        if op_type.len > 0 and op_type in exported_types:
          if op_type notin result.types:
            result.types[op_type] = TypeDoc(name: op_type)

          if symbol.is_static:
            symbol.display_name = op_type & "." & name
            result.types[op_type].static_procs.add(symbol)
          else:
            result.types[op_type].procs.add(symbol)
      else:
        discard

proc escape_html*(s: string): string =
  s.multi_replace([
    ("&", "&amp;"),
    ("<", "&lt;"),
    (">", "&gt;"),
    ("\"", "&quot;"),
  ])

proc decode_html_entities*(s: string): string =
  ## Decode HTML entities from nimdoc JSON
  s.multi_replace([
    ("&amp;", "&"),
    ("&lt;", "<"),
    ("&gt;", ">"),
    ("&quot;", "\""),
  ])

proc to_display_name*(s: string): string =
  ## Remove backticks and decode HTML entities for display
  s.replace("`", "").decode_html_entities

proc highlight_code*(code: string): string =
  result = escape_html(code)
  let keywords = ["proc", "template", "macro", "iterator", "type", "const",
                  "var", "let", "object", "ref", "enum", "tuple", "set", "seq",
                  "Table", "string", "int", "bool", "float", "void", "auto",
                  "discardable", "gcsafe", "raises", "tags", "forbids", "for", "in"]

  for kw in keywords:
    result = result.replace(" " & kw & " ", " <span class=\"kw\">" & kw & "</span> ")
    result = result.replace(" " & kw & "[", " <span class=\"kw\">" & kw & "</span>[")
    result = result.replace(" " & kw & "\n", " <span class=\"kw\">" & kw & "</span>\n")
    if result.starts_with(kw & " "):
      result = "<span class=\"kw\">" & kw & "</span>" & result[kw.len..^1]

proc generate_anchor*(name: string, suffix: string = ""): string =
  var base = name
  if suffix.len > 0:
    base = name & "_" & suffix
  base.to_lower_ascii.multi_replace([
    ("[", ""), ("]", ""), ("=", "eq"), (",", "_"), (" ", "_"),
    ("(", ""), (")", ""), ("*", ""), ("+", "plus"), ("-", ""),
    ("&", "amp"), ("?", "q"), ("$", "dollar"), ("`", ""), (".", "_")
  ])

# Mustache context generation - returns JsonNode for direct use with Mustache

proc to_symbol_json*(sym: Symbol, suffix: string = ""): JsonNode =
  result = %*{
    "name": sym.name.to_display_name,
    "anchor": generate_anchor(sym.name, suffix),
    "description": sym.description,
    "code": highlight_code(sym.code),
    "module": sym.module
  }

proc to_api_json*(data: DocData): JsonNode =
  ## Convert DocData to JSON for Mustache template
  result = %*{
    "hasConstants": data.constants.len > 0,
    "constants": new_j_array(),
    "hasEnums": data.enums.len > 0,
    "enums": new_j_array(),
    "types": new_j_array()
  }

  # Constants
  for sym in data.constants:
    result["constants"].add(sym.to_symbol_json("const"))

  # Enums
  for sym in data.enums:
    result["enums"].add(sym.to_symbol_json("enum"))

  # Types - sorted by name
  var type_names = to_seq(data.types.keys)
  type_names.sort()

  for type_name in type_names:
    let td = data.types[type_name]
    var tc = %*{
      "name": type_name,
      "anchor": generate_anchor(type_name, "type"),
      "hasType": td.has_type,
      "hasOps": td.procs.len > 0 or td.static_procs.len > 0,
      "description": "",
      "code": "",
      "module": "",
      "hasStaticProcs": td.static_procs.len > 0,
      "staticProcs": new_j_array(),
      "hasProcs": td.procs.len > 0,
      "procs": new_j_array(),
      "staticProcNames": new_j_array(),
      "procNames": new_j_array()
    }

    if td.has_type:
      tc["description"] = %td.type_symbol.description
      tc["code"] = %highlight_code(td.type_symbol.code)
      tc["module"] = %td.type_symbol.module

    # Static procs - group by display name
    if td.static_procs.len > 0:
      var static_by_name = init_table[string, seq[Symbol]]()
      for p in td.static_procs:
        if p.display_name notin static_by_name:
          static_by_name[p.display_name] = @[]
        static_by_name[p.display_name].add(p)

      var static_names = to_seq(static_by_name.keys)
      static_names.sort()

      for disp_name in static_names:
        let overloads = static_by_name[disp_name]
        let proc_anchor = generate_anchor(disp_name.decode_html_entities)
        var pc = %*{
          "name": disp_name.to_display_name,
          "anchor": proc_anchor,
          "overloads": new_j_array()
        }

        for ovl in overloads:
          pc["overloads"].add(%*{
            "description": ovl.description,
            "code": highlight_code(ovl.code),
            "module": ovl.module
          })

        tc["staticProcs"].add(pc)
        tc["staticProcNames"].add(%*{"name": disp_name.to_display_name, "anchor": proc_anchor})

    # Regular procs - group by name
    if td.procs.len > 0:
      var procs_by_name = init_table[string, seq[Symbol]]()
      for p in td.procs:
        if p.name notin procs_by_name:
          procs_by_name[p.name] = @[]
        procs_by_name[p.name].add(p)

      var proc_names = to_seq(procs_by_name.keys)
      proc_names.sort()

      for proc_name in proc_names:
        let overloads = procs_by_name[proc_name]
        let proc_anchor = generate_anchor(proc_name.decode_html_entities, type_name)
        var pc = %*{
          "name": proc_name.to_display_name,
          "anchor": proc_anchor,
          "overloads": new_j_array()
        }

        for ovl in overloads:
          pc["overloads"].add(%*{
            "description": ovl.description,
            "code": highlight_code(ovl.code),
            "module": ovl.module
          })

        tc["procs"].add(pc)
        tc["procNames"].add(%*{"name": proc_name.to_display_name, "anchor": proc_anchor})

    result["types"].add(tc)
