import std/[macros, strutils, sequtils, base64, os]
import class_macros

export class_macros

macro load_enu_script_from_file*(
    filename: static[string],
    base_type: untyped,
    class_specific_props: varargs[untyped],
): untyped =
  # Resolve absolute path relative to the caller (project file)
  let abs_path = callsite().line_info_obj.filename.parent_dir / filename
  let code = read_file(abs_path)
  let base64_code = encode(code)

  var call = new_call(
    "load_enu_script",
    new_str_lit_node(base64_code),
    new_str_lit_node(abs_path),
    base_type,
  )
  for child in class_specific_props:
    call.add(child)
  result = call
