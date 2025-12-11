## Property aliases - templates that expand for both read and write access
## These replace the AST transformation previously done in class_macros.nim
## Not exported to avoid conflicts with procs of the same name in base_bridge

# Public properties -> enu_target
# Trying explicit float return type
template position: Vector3 = enu_target.position
template start_position: Vector3 = enu_target.start_position
template speed: float = enu_target.speed
template scale: typed = enu_target.scale
template glow: typed = enu_target.glow
template global: typed = enu_target.global
template seed: typed = enu_target.seed
template color: typed = enu_target.color
template height: typed = enu_target.height
template show: typed = enu_target.show
template sign: typed = enu_target.sign

# Private properties -> me
template lock: typed = me.lock
