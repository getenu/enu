import core, bots

proc play*(animation_name: string) =
  Bot(active_thing()).play(animation_name)

proc walk*() =
  Bot(active_thing()).walk()

proc run*() =
  Bot(active_thing()).run()
