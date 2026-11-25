import core, bots

proc play*(animation_name: string) =
  Bot(active_thing()).play(animation_name)
