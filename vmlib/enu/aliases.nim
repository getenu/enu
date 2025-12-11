## Property aliases - templates that expand for both read and write access
## These replace the AST transformation previously done in class_macros.nim
## Not exported to avoid conflicts with procs of the same name in base_bridge

# Public properties -> enu_target
template position: untyped = enu_target.position
template start_position: untyped = enu_target.start_position
template speed: untyped = enu_target.speed
template scale: untyped = enu_target.scale
template glow: untyped = enu_target.glow
template global: untyped = enu_target.global
template seed: untyped = enu_target.seed
template color: untyped = enu_target.color
template height: untyped = enu_target.height
template show: untyped = enu_target.show
template sign: untyped = enu_target.sign

# Private properties -> me
template lock: untyped = me.lock
