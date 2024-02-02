import globals, os

proc echo(args: varargs[string, `$`]) =
  stdout.write "Enu: " & args.join() & "\n"

echo_console =
  proc(msg: string) =
    echo msg

logger =
  proc(level, msg: string) =
    echo level, ": ", msg

game_node = gdnew[Node]()
config =
  Config(
    lib_dir: get_current_dir() & "/../vmlib",
    script_dir: nim_filename().parent_dir & "/scripts",
  )
