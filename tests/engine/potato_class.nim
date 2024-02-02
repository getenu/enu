import enu/types, enu/class_macros
import macros except name
import pkg/print
import enu/base_api
import enu/state_machine

let instance_global_by_default = false
var move_mode = 1
load_enu_script "potato_code.nim", Bot, speed, global, color
