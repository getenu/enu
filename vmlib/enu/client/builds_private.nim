import types, base_api, builds

proc fill_square*(length = 1) =
  Build(active_unit()).fill_square(length)

proc save*(name = "default") =
  Build(active_unit()).save(name)

proc restore*(name = "default") =
  Build(active_unit()).restore(name)
