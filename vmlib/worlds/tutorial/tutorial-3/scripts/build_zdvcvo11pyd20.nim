proc restart*() =
  player.flying = false
  player.open_sign = nil
  player.position = start_spot
  player.rotation = 180

proc stop_playing*() =
  player.playing = false
  player.running = false

proc level_menu*(me: Build, show_restart = true) =
  let blurb =
    "`Inky: Isolation` is a simple survivial game created in Enu. Find buttons to open new areas of the space station. Hit the top of Inky's head to defeat them."

  let copy =
    \"""

# Inky: Isolation

{blurb}

- CLICK TO OPEN MENU

  """

  me.right 3

  let sign1 = me.say(copy, width = 4, height = 2, size = 200)
  me.up 1
  me.left 3
  me.turn 180
  me.down 1

  let sign2 = me.say(copy, width = 4, height = 2, size = 200)
  me.left 3

  forever:
    let return_action =
      if show_restart: "- [RETURN TO START](<nim://restart()>)" else: ""

    let toolbar_action =
      if player.playing:
        "- [SHOW TOOLBAR AND STOP PLAYING](<nim://player.playing = false;player.running = false;player.open_sign = nil>)"
      else:
        ""

    let more =
      \"""

# Menu

{blurb}

See how `Inky: Isolation` was built in the video [Inky: Isolation. A 90 minute game built with Enu and Nim](https://youtu.be/9e9sLsmsu_o)

{toolbar_action}

{return_action}

- [LOAD TUTORIAL](<nim://load_level("tutorial-1")>)

- [LOAD EXAMPLES](<nim://load_level("tutorial-2")>)

- [CLEAR CHANGES AND RESET LEVEL](<nim://reset_level()>)

    """
    sign1.more = more
    sign2.more = more
    sleep 1

level_menu(me)
