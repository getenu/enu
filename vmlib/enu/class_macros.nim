import std/[macros, strutils, sequtils, os]
import types
import base_api, macro_helpers, base_bridge_private

template with_line_info(node, source: NimNode): NimNode =
  let n = node
  n.copy_line_info(source)
  n

proc fix_line_info(node, source: NimNode): NimNode =
  node.copy_line_info(source)
  for child in node:
    discard fix_line_info(child, source)
  node

const private_props = ["lock"]
const public_props = [
  "position", "start_position", "speed", "scale", "glow", "global", "seed",
  "color", "height", "show", "sign",
]

proc params_to_assignments(nodes: seq[NimNode]): NimNode =
  result = new_stmt_list()
  for node in nodes:
    let prop = node[0]
    if node.kind == nnkExprEqExpr:
      let value = node[1]
      result.add quote do:
        if not is_instance:
          me.`prop` = `value`

proc params_to_ident_defs(nodes: seq[NimNode]): seq[NimNode] =
  for node in nodes:
    let node = node.copy_nim_tree
    let prop = node[0]
    if prop.str_val notin ["global", "speed", "color", "position"]:
      if node.kind == nnkExprEqExpr:
        result.add nnkIdentDefs.new_tree(node[0], new_empty_node(), node[1])
      elif node.kind == nnkExprColonExpr:
        result.add nnkIdentDefs.new_tree(node[0], node[1], new_empty_node())
      else:
        error(
          "expected `my_param = 1`, `my_param: int` kind: " & $node.kind, node
        )

proc params_to_properties(nodes: seq[NimNode]): NimNode =
  result = new_nim_node(kind = nnkRecList)
  let empty = new_empty_node()
  for node in nodes:
    let node = node.copy_nim_tree
    let prop = node[0]
    if prop.str_val notin ["global", "speed", "color", "position"]:
      if node.kind == nnkExprEqExpr:
        result.add nnkIdentDefs.new_tree(
          node[0], new_call(ident"type", node[1]), empty
        )
      elif node.kind == nnkExprColonExpr:
        result.add nnkIdentDefs.new_tree(node[0], node[1], empty)
      else:
        error(
          "expected `my_param = 1`, `my_param: int` kind: " & $node.kind, node
        )

proc params_to_accessors(type_name: NimNode, nodes: seq[NimNode]): NimNode =
  result = new_stmt_list()
  let empty = new_empty_node()
  for node in nodes:
    let node = node.copy_nim_tree
    let getter = node[0]
    if getter.str_val notin ["global", "speed", "color", "position"]:
      let setter = ident(getter.str_val & "=")
      let typ =
        if node.kind == nnkExprEqExpr:
          new_call(ident"type", node[1])
        else:
          node[1]

      result.add quote do:
        proc `getter`*(self: `type_name`): `typ` =
          self.`getter`

        proc `setter`*(self: `type_name`, value: `typ`) =
          if value != self.`getter`:
            self.`getter` = value
            self.wake

proc build_ctors(
    name_str: string, type_name: NimNode, params: seq[NimNode]
): NimNode =
  var ctor_body = quote:
    assert not instance.is_nil

    result = `type_name`()
    result.seed = active_unit().seed
    new_instance(instance, result)

  for param in params:
    let prop = param[0]
    ctor_body.add quote do:
      result.`prop` = `prop`

  let vars = params_to_ident_defs(params)
  let var_names = vars.map_it $it[0]
  let instance_def = new_ident_defs("instance".ident, type_name)
  var params = @[type_name] & instance_def & vars

  var global = "global".ident
  if "global" notin var_names:
    params &=
      new_ident_defs(
        global, new_empty_node(), ident"instance_global_by_default"
      )

  ctor_body.add quote do:
    result.global = `global`

  var speed = "speed".ident
  if "speed" notin var_names:
    params &= new_ident_defs(speed, new_empty_node(), new_float_lit_node(1.0))
  ctor_body.add quote do:
    result.speed = `speed`

  var color = "color".ident
  var eraser = bind_sym"eraser"
  if "color" notin var_names:
    params &= new_ident_defs(color, new_empty_node(), ident"eraser")
  ctor_body.add quote do:
    if `color` != `eraser`:
      result.color = `color`

  var position = "position".ident
  if "position" notin var_names:
    params &= new_ident_defs(position, new_empty_node(), ident"UNSET_POSITION")
  ctor_body.add quote do:
    apply_position(result, `position`)

  var rotation = "rotation".ident
  if "rotation" notin var_names:
    params &= new_ident_defs(rotation, new_empty_node(), new_float_lit_node(0.0))

  var scale = "scale".ident
  if "scale" notin var_names:
    params &= new_ident_defs(scale, new_empty_node(), new_float_lit_node(0.0))

  ctor_body.add quote do:
    exec_instance(result)

  # Apply rotation and scale after the proto body has drawn its voxels so
  # the body can't accidentally clobber the caller's requested values. 0
  # is the "not specified" sentinel for both (a 0 rotation is a no-op, a
  # 0 scale would be invisible — neither is a useful value to actually
  # pass through).
  ctor_body.add quote do:
    if `rotation` != 0.0:
      result.rotation = `rotation`
    if `scale` != 0.0:
      result.scale = `scale`
    # The clone was seeded with the spawner's transform as its
    # start_transform; re-stamp it now that the requested spawn pose is
    # applied so start_position is the instance's own spawn point.
    capture_start_transform(result)

  # add baked in constructor params for speed, color, etc.
  # probably shouldn't be here.
  result = new_proc(
    name = "new".ident.postfix("*"),
    params = params,
    pragmas = nnkPragma.new_tree("discardable".ident),
    body = ctor_body,
  )

proc extract_class_info(
    name_node: NimNode
): tuple[name: string, params: seq[NimNode]] =
  result =
    if name_node.kind == nnkIdent:
      (name_node.str_val, @[])
    elif name_node.kind in [nnkCall, nnkCommand, nnkObjConstr]:
      name_node[0].expect_kind nnkIdent
      (name_node[0].str_val, name_node[1 ..^ 1])
    else:
      error(
        "expected `name my_name` or `name my_name(my_param1 = 1, " &
          "my_param2 = 2, ...)`",
        name_node,
      )

proc build_class(name_node: NimNode, base_type: NimNode): NimNode =
  let (name, params) = extract_class_info(name_node)

  let
    name_node_actual =
      if name_node.kind == nnkIdent:
        name_node
      else:
        name_node[0]
    type_name = (name & "Type").to_upper_ascii.nim_ident_normalize.ident.with_line_info(
      name_node_actual
    )
    var_name = name.ident.with_line_info(name_node_actual)
    ctors = build_ctors(name, type_name, params)

  result = new_stmt_list()

  let name_str = name
  var type_def = quote:
    type `type_name`* = ref object of `base_type`
  type_def.copy_line_info(name_node_actual)

  type_def[0][2][0][2] = params_to_properties(params)
  let accessors = params_to_accessors(type_name, params)
  result.add (
    quote do:
      `type_def`
      `accessors`
      let me {.inject.} = `type_name`(name: `name_str`)
      var enu_target {.inject.} = me
      include loops

      register_active(me)
      claim_name(`name_str`)
      let home {.inject.} = PositionOffset(position: me.local_position)
      let `var_name`* {.inject.} = me
      `ctors`
  ).fix_line_info(name_node_actual)

proc pop_name_node(ast: NimNode): tuple[start: NimNode, name_node: NimNode] =
  let ident_name = "name"
  result.start = new_stmt_list()
  for i, node in ast:
    if node.kind in [nnkCommand, nnkCall]:
      if node.len == 2 and node[1].kind in [nnkIdent, nnkCall, nnkObjConstr] and
          node[0].eq_ident(ident_name):
        result.name_node = node[1]
        ast.del(i)
        break
    result.start.add node
  for i, node in result.start:
    ast.del(i)

proc visit_tree(
    parent: NimNode,
    convert: open_array[string],
    receiver: string,
    alias: ptr seq[NimNode],
) =
  for i, node in parent:
    if node.kind in [nnkProcDef, nnkBlockStmt, nnkIfExpr, nnkIfStmt]:
      # The alias list should only live as long as a scope. We need to make a
      # new copy each time a scope is opened. The above list needs to be
      # expanded.
      var alias = alias[]
      visit_tree(node, convert, receiver, addr alias)
    else:
      if node.kind == nnkIdent:
        if $node in convert and parent.kind == nnkIdentDefs:
          if i == 0:
            alias[].add node
          elif i == 2 and node notin alias[]:
            parent[i] = new_dot_expr(ident(receiver), node).with_line_info(node)
        elif $node in convert and node notin alias[] and
            parent.kind != nnk_expr_eq_expr and
            not (parent.kind == nnk_dot_expr and i == 1):
          parent[i] = new_dot_expr(ident(receiver), node).with_line_info(node)
      visit_tree(node, convert, receiver, alias)

# Converts variable access to property access. Ex. `speed = 1` -> `me.speed = 1`
# Anything for `enu_target` must work for all units. `me` can be class specific.
# This tries to take aliasing into account. If a variable called `speed` is
# created, anywhere it's in scope won't get `me` prefixed.
proc auto_insert_receiver(
    ast: NimNode, class_specific_props: open_array[string]
): NimNode =
  var alias: seq[NimNode] = @[]
  visit_tree(ast, class_specific_props, "me", addr alias)
  visit_tree(ast, private_props, "me", addr alias)
  visit_tree(ast, public_props, "enu_target", addr alias)
  result = ast

proc build_proc(sig, body: NimNode, return_type = new_empty_node()): NimNode =
  let (name, params, vars) = sig.parse_sig(return_type)
  let new_body = new_stmt_list(vars, body)
  result = new_proc(
    name = ident(name).with_line_info(sig),
    params = params,
    body = new_body,
    pragmas = new_nim_node(nnkPragma).add(ident"discardable"),
  ).fix_line_info(sig)

proc transform_commands(parent: NimNode): NimNode =
  for i, node in parent:
    if parent.kind == nnkStmtList and node.kind == nnkPrefix and
        node[0] == ident"-":
      if node[1].kind in [nnkIdent, nnkCall]:
        let new_proc = build_proc(node[1], transform_commands node[2])
        parent[i] = new_proc
      elif node[1].kind == nnkCommand:
        let new_proc =
          build_proc(node[1][0], transform_commands node[2], node[1][1])

        parent[i] = new_proc
      else:
        parent[i] = transform_commands(node)
    else:
      parent[i] = transform_commands(node)
  parent

macro load_enu_script*(
    file_name: string,
    base_type: untyped,
    class_specific_props: varargs[untyped],
): untyped =
  var class_specific_props = class_specific_props.map_it($it)
  let raw_file_name = file_name.str_val
  let resolved_file_name =
    if raw_file_name.isAbsolute:
      raw_file_name
    else:
      (file_name.lineInfoObj.filename.parent_dir / raw_file_name).normalized_path

  let code = read_enu_script(resolved_file_name)
  when compiles(parse_stmt(code, resolved_file_name)):
    var ast = parse_stmt(code, resolved_file_name).transform_commands
  else:
    # Just for tests running in Nim <= 1.6. Enu VM and Nim 2.0 can take both
    # Nim code and a file name.
    var ast = parse_stmt(code).transform_commands
  var (script_start, name_node) = pop_name_node(ast)
  result = new_stmt_list()
  var inner = new_stmt_list()
  script_start = script_start.auto_insert_receiver(class_specific_props)
  if name_node.kind != nnkNilLit:
    let (name, params) = extract_class_info(name_node)
    for param in params:
      class_specific_props.add($param[0])
    ast = ast.auto_insert_receiver(class_specific_props)
    result.add build_class(name_node, base_type)
    let assignments = params_to_assignments(params)
    inner.add quote do:
      `assignments`
  else:
    ast = ast.auto_insert_receiver(class_specific_props)
    result.add quote do:
      let me {.inject.} = `base_type`()
      var enu_target {.inject.} = me
      register_active(me)
      let home {.inject.} = PositionOffset(position: me.local_position)
      include loops

  inner.add ast
  result.add script_start
  let run_script_def = quote do:
    proc run_script*(me {.inject.}: me.type, is_instance {.inject.}: bool) =
      var enu_target {.inject.}: Unit = me
      let home {.inject.} = PositionOffset(position: me.local_position)
      var move_mode {.inject.} = 1
      include loops
      `inner`
      # If a new instance doesn't ever yield the interpreter can crash. Unsure
      # why, but probably fixable. Sleep before exit as a workaround.
      sleep 0.0

    run_script(me, false)
  # Set the proc body's line info to the script file so nimsuggest's cursorInProc
  # check passes and the body gets processed, enabling go-to-definition in scripts.
  if ast.len > 0:
    run_script_def[0].body.copy_line_info(ast[0])
  result.add run_script_def
