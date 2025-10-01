import types, base_api, bots

proc play*(animation_name: string) =
  Bot(active_unit()).play(animation_name)

proc walk*() =
  Bot(active_unit()).walk()

proc run*() =
  Bot(active_unit()).run()
