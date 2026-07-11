import std/[macros, strutils, sequtils, os]
import core, macro_helpers, base_bridge_private

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
    result.seed = active_thing().seed
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
  # 0 scale would be invisible, neither is a useful value to actually
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

# Property access uses Nim's own scoping instead of AST rewriting. Each
# property gets a parenless template (`template speed: untyped =
# enu_target.speed`), so a bare `speed` read expands through normal symbol
# lookup — and a user variable named `speed` shadows it wherever Nim says
# it should, with no alias tracking. `dirty` makes the receiver bind where
# the template is expanded rather than where it's defined, which is what
# retargets `enu_target` after `move`/`build` and picks up run_script's
# `me` parameter for instances.
#
# Writes can't go through the templates alone: Nim only rewrites `a.b = c`
# to a setter call when the assignment is syntactically a dot expression,
# so `speed = 1` with a template-expanded lhs fails to compile. Instead
# `rewrite_prop_writes` turns bare-ident assignments to property names
# into `enu_assign(speed, 1)` calls, unconditionally — by the time
# `enu_assign` runs, Nim has already resolved what `speed` means here.

proc prop_template(prop, receiver: string): NimNode =
  let prop_ident = ident(prop)
  let recv = ident(receiver)
  result = quote do:
    template `prop_ident`: untyped {.dirty.} =
      `recv`.`prop_ident`

macro enu_assign*(lhs: typed, rhs: typed): untyped =
  ## `speed = 1` in a script is rewritten to `enu_assign(speed, 1)`. A
  ## user variable arrives here as a plain symbol and stays a plain
  ## assignment; a property template arrives expanded (a getter call, or
  ## a field access for same-module class params) and becomes a setter
  ## call.
  # sem wraps a `ref` receiver in a hidden deref for field access; the
  # setter wants the ref back
  proc unwrap(node: NimNode): NimNode =
    result = node
    while result.kind in {nnkHiddenDeref, nnkHiddenAddr, nnkHiddenStdConv}:
      result = result[^1]

  if lhs.kind == nnkSym:
    result = nnkAsgn.new_tree(lhs, rhs)
  elif lhs.kind in CallNodes:
    result = new_call(ident(lhs[0].str_val & "="), unwrap(lhs[1]), rhs)
  elif lhs.kind == nnkDotExpr:
    result = new_call(ident(lhs[1].str_val & "="), unwrap(lhs[0]), rhs)
  elif lhs.kind in {nnkClosedSymChoice, nnkOpenSymChoice}:
    # ambiguous, e.g. a parenless prop template vs a unary accessor with
    # the same name. Find the prop template and rebuild
    # `receiver.prop = rhs` from its body.
    for choice in lhs:
      let impl = choice.get_impl
      if impl.kind == nnkTemplateDef and impl.params.len == 1:
        var body = impl.body
        while body.kind == nnkStmtList:
          body = body[^1]
        body.expect_kind nnkDotExpr
        result =
          new_call(ident(body[1].str_val & "="), ident(body[0].str_val), rhs)
        break
    if result.is_nil:
      error("'" & lhs.repr & "' cannot be assigned to", lhs)
  else:
    error("'" & lhs.repr & "' cannot be assigned to", lhs)
  result.copy_line_info(lhs)

const COMPARISON_OPS = ["==", "!=", "<=", ">="]

proc decl_name(node: NimNode): string =
  var node = node
  while node.kind in {nnkPostfix, nnkPragmaExpr}:
    node = node[if node.kind == nnkPostfix: 1 else: 0]
  if node.kind == nnkAccQuoted:
    node = node[0]
  $node

proc declared_top_level_names(ast: NimNode): seq[string] =
  ## Names declared at a script's top level. These share the module scope
  ## with the property templates, where Nim reports a redefinition instead
  ## of shadowing — so templates for these names aren't generated at all.
  for node in ast:
    case node.kind
    of nnkVarSection, nnkLetSection, nnkConstSection:
      for def in node:
        if def.kind in {nnkIdentDefs, nnkConstDef, nnkVarTuple}:
          for j in 0 .. def.len - 3:
            result.add decl_name(def[j])
    of nnkProcDef, nnkFuncDef, nnkTemplateDef, nnkMacroDef, nnkIteratorDef,
        nnkConverterDef:
      result.add decl_name(node[0])
    else:
      discard

proc rewrite_prop_writes(parent: NimNode, props: open_array[string]) =
  for i, node in parent:
    rewrite_prop_writes(node, props)
    if node.kind == nnkAsgn and node[0].kind == nnkIdent and
        $node[0] in props:
      parent[i] =
        new_call(ident"enu_assign", node[0], node[1]).with_line_info(node)
    elif node.kind == nnkInfix and node[0].kind == nnkIdent and
        node[1].kind == nnkIdent and $node[1] in props:
      # `speed += 1` -> `enu_assign(speed, speed + 1)`
      let op = $node[0]
      if op.len > 1 and op.ends_with("=") and op[0] notin {'=', '<', '>', '!'} and
          op notin COMPARISON_OPS:
        let base_op = ident(op[0 ..^ 2]).with_line_info(node[0])
        let read =
          nnkInfix.new_tree(base_op, node[1], node[2]).with_line_info(node)
        parent[i] =
          new_call(ident"enu_assign", node[1], read).with_line_info(node)

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

  # a parenless read template per property, most specific receiver first —
  # duplicate names keep the first receiver
  let user_top_level_names = declared_top_level_names(script_start)
  var prop_names: seq[string]
  for (props, receiver) in [
    (class_specific_props, "me"),
    (@private_props, "me"),
    (@public_props, "enu_target"),
  ]:
    for prop in props:
      if prop notin prop_names and prop notin user_top_level_names:
        prop_names.add prop
        result.add prop_template(prop, receiver)

  rewrite_prop_writes(script_start, prop_names)
  # templates for `name foo(health = 3)` params, injected inside
  # run_script so they're more local than the module-level accessors
  var param_templates = new_stmt_list()
  if name_node.kind != nnkNilLit:
    let (name, params) = extract_class_info(name_node)
    var all_props = prop_names
    for param in params:
      let param_name = $param[0]
      if param_name notin all_props:
        all_props.add param_name
      param_templates.add prop_template(param_name, "me")
    rewrite_prop_writes(ast, all_props)
    result.add build_class(name_node, base_type)
    let assignments = params_to_assignments(params)
    inner.add quote do:
      `assignments`
  else:
    rewrite_prop_writes(ast, prop_names)
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
      var enu_target {.inject.}: Thing = me
      let home {.inject.} = PositionOffset(position: me.local_position)
      var move_mode {.inject.} = 1
      include loops
      `param_templates`
      # user code goes in a block so `var health = ...` shadows the
      # templates above instead of colliding with them
      block:
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
