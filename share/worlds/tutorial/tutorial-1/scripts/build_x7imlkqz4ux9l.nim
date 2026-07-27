let menu* = me

speed = 0
show = false
lock = true

let overview = """
  # `    ` Menu

  - `Reset Tutorial`
  - `Help`
  - `...`
  """.dedent

let details = """
  # Menu

  Welcome! This is Tutorial 1, which covers the basics of playing and coding in
  Enu. If you're new, you should try it. It won't take long.

  If you're not new, here are some other things to do:

  - [Clear Changes and Reset Tutorial](<nim://reset_level()>). This resets and
    restarts this tutorial. Any changes you've made to the world will be lost.

  - [Help](https://getenu.com/docs/intro.html). Help!

  - [Load Welcome](<nim://load_level("welcome")>). Load the Enu 0.3 welcome
    level. The best place to start for new players.

  - [Load Examples](<nim://load_level("tutorial-2")>). See some other things you
    can build with Enu.

  - [Load Inky: Isolation](<nim://load_level("tutorial-3")>). `Inky: Isolation`
    is a simple game made with Enu. You can see how it was built in
    [this video](https://youtu.be/9e9sLsmsu_o)
  """

say overview, details, height = 3, width = 3, size = 0.26

move me

forever:
  turn player
  sleep()
