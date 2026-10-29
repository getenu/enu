import std/[macros, strutils]
import shared/errors, handles

const thing_types = ["Thing", "Bot", "Build", "Sign", "Player"]

proc get_last_error_impl(): ErrorData =
  raise_assert "get_last_error_impl must be implemented by host"

# Set by the host when a call into it failed, so a call that succeeded
# doesn't need a second trip to the host to find that out. Exported so the
# host can find it.
var host_error_pending*: bool

proc check_errors*() =
  if host_error_pending:
    host_error_pending = false
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

proc is_thing(typ: NimNode): bool =
  typ.kind == nnk_ident and typ.str_val in thing_types

proc is_thing_seq(typ: NimNode): bool =
  typ.kind == nnk_bracket_expr and typ.len == 2 and typ[0].eq_ident("seq") and
    typ[1].is_thing

macro bridged_to_host*(body: untyped): untyped =
  ## Declares procs the host implements. Things cross the bridge as handles:
  ## the `_impl` the host sees takes and returns ints, and the wrapper
  ## converts.
  result = new_stmt_list()
  var defs = new_stmt_list()
  var calls = new_stmt_list()
  for node in body:
    if node.kind == nnk_proc_def:
      let impl_proc = get_name(node[0]).replace("=", "_set") & "_impl"
      let params = node.params
      var call = new_call impl_proc
      var def = copy_nim_tree(node)
      def.body = quote:
        raise_assert `impl_proc` & " must be implemented by host"
      def[0] = ident(impl_proc)

      for i in 1 ..< params.len:
        let defs = params[i]
        let typ = defs[^2]
        for name in defs[0 ..^ 3]:
          if typ.is_thing:
            call.add new_call(bind_sym"bridge_handle", name)
          else:
            call.add name
        if typ.is_thing:
          def.params[i][^2] = ident"int"
          def.params[i][^1] = new_empty_node()

      let ret = params[0]
      let thing_for_handle = bind_sym"thing_for_handle"
      node.body =
        if ret.kind == nnk_empty:
          quote:
            `call`
            check_errors()
        elif ret.is_thing:
          def.params[0] = ident"int"
          quote:
            let handle = `call`
            check_errors()
            result = `ret`(`thing_for_handle`(handle))
        elif ret.is_thing_seq:
          def.params[0] = nnk_bracket_expr.new_tree(ident"seq", ident"int")
          let elem = ret[1]
          quote:
            let handles = `call`
            check_errors()
            for handle in handles:
              result.add `elem`(`thing_for_handle`(handle))
        else:
          quote:
            result = `call`
            check_errors()

      defs.add def
      calls.add node

  result.add(defs)
  result.add(calls)

when is_main_module:
  import types

  proc check_errors() =
    discard

  bridged_to_host:
    proc write_stack_trace*()
    proc id*(self: Thing): string
