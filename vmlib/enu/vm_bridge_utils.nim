import std/[macros, strutils]
import shared/errors

proc get_last_error_impl(): ErrorData =
  raise_assert "get_last_error_impl must be implemented by host"

proc check_errors*() =
  let err = get_last_error_impl().to_exception
  if err != nil:
    raise err

proc get_name(node: NimNode): string =
  result =
    case node.kind
    of nnk_ident:
      $node.str_val
    of nnk_postfix:
      get_name(node[1])
    of nnk_acc_quoted:
      $node[0].str_val & $node[1].str_val
    else:
      raise_assert "Can't handle " & $node.kind

macro bridged_to_host*(body: untyped): untyped =
  result = new_stmt_list()
  var defs = new_stmt_list()
  var calls = new_stmt_list()
  for node in body:
    if node.kind == nnk_proc_def:
      let impl_proc = get_name(node[0]).replace("=", "_set") & "_impl"
      let params = node.params
      var call = new_call impl_proc
      var def = copy_nim_tree(node)
      def.body =
        quote:
          raise_assert `impl_proc` & " must be implemented by host"
      def[0] = ident(impl_proc)

      if params.len > 1:
        for defs in params[1 ..^ 1]:
          call.add(defs[0 ..^ 3])
      node.body =
        if params[0].kind == nnk_empty:
          quote:
            `call`
            check_errors()
        else:
          quote:
            result = `call`
            check_errors()

      defs.add def
      calls.add node

  result.add(defs)
  result.add(calls)

when is_main_module:
  type
    Unit = ref object
    Vector3 = object
    Colors = object

  proc check_errors() =
    discard

  bridged_to_host:
    proc write_stack_trace*()
    proc id*(self: Unit): string
