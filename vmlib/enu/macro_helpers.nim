import std/[macros, strformat, strutils]

proc parse_sig*(
    sig: NimNode, return_type = new_empty_node()
): (string, seq[NimNode], NimNode) =
  var
    name = ""
    args = @[return_type]
    vars = new_stmt_list()
  if sig.kind == nnkIdent:
    name = $sig
  else:
    name = $sig[0]
    for i, arg in sig[1 ..^ 1]:
      case arg.kind
      of nnkExprColonExpr:
        args.add new_ident_defs(arg[0], arg[1])
        vars.add new_var_stmt(arg[0], arg[0])
      of nnkExprEqExpr:
        args.add new_ident_defs(arg[0], new_empty_node(), arg[1])
        vars.add new_var_stmt(arg[0], arg[0])
      of nnkIdent:
        args.add new_ident_defs(arg, ident"auto")
        vars.add new_var_stmt(arg, arg)
      else:
        error "invalid signature", sig
  return (name, args, vars)
