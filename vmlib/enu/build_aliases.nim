## Build-specific aliases - templates for Build properties
## Included (not imported) to avoid export conflicts with builds.nim procs

template drawing: untyped = Build(me).drawing
template draw_position: untyped = Build(me).draw_position
