lock = true
color = white

var test_mode = false

var bot_id = ""
var maze: MazeType

proc get_bot(): Bot =
  # each time the code for the bot is reloaded we need to
  # grab a new reference to it. Eventually an easy way to
  # do this will be built in.
  for bot in Bot.all:
    if test_mode and bot.id != me.id:
      return bot
    elif not test_mode and bot.id == bot_id:
      return bot

-setup:
  reset()
  position = position + LEFT
  speed = 10
  turn player

-approach:
  sleep 2
  say "# - Hi!", width = 1.0
  sleep 2
  forward 8
  turn player
  sleep 1

  say "- Welcome to **Enu**!", width = 2.0
  sleep 1.5
  say "- Click this text for a short tutorial.", "# Welcome to Enu!"
  while not sign.open:
    turn(player)

-movement_info:
  say "# . . .",
    """

# Welcome to Enu!

Enu is a 3D world where you can code and create almost anything using a
programming language called [Nim](https://nim-lang.org). It's a place to make
games, experiment, and learn to code. You're using an early prototype that's
missing important features and is full of bugs, but it's getting better quickly.
Please contact me at [dsrw@me.com](mailto:dsrw@me.com) if you have any questions
or suggestions.

In this tutorial you'll learn to move and do some simple coding. In later
tutorials we'll make towers, tunnels, characters, and will finish with a 3D
survival game called `Inky: Isolation`.

Move with the `W`, `A`, `S`, and `D` keys, or with the left stick of your game
controller. Look around with the mouse, trackpad, or right stick of your game
controller.

You can close this window by pressing `ESC` on your keyboard or `B` on your
controller, and can come back at any time by clicking on the text block next to
the `Bot`. You can also move without closing the window by using your
controller, or by holding down left `alt/option (⌥)` on your keyboard.

Sneak behind the `Bot` to continue the tutorial.

  """,
    width = 0.6

  menu.show = true
  while me.angle_to(player).abs notin 150 .. 210:
    sleep 0.5

-flying_info:
  say "- Good!",
    """

# Jumping and Flying

Jump with the `space` bar, or the `A` button on your game controller.

Fly by jumping twice quickly. Fly upwards by holding the jump button, and
downwards by holding crouch (`C` on the keyboard or `B` on a game controller).
Return to the ground by pressing the `jump` button twice.

Flying is a great way to see things from a better angle and to zip around your
world at high speed. It also lets you move through objects and blocks, so if you
ever get yourself stuck you can probably fly your way out.

Jump, fly, then returning to the ground to continue the tutorial.

  """,
    width = 1.4

  speed = 1
  turn player
  sign.open = true
  while not player.flying:
    sleep()

-flying_done:
  say "- Now drop!"
  while player.flying:
    sleep()

-good_job:
  sign.open = false
  say "- Good Job!", "# Good Job!"
  sleep 2

-tool_info:
  say "- Switch to `Place Bot`",
    """

# Changing tools

Tools are selected from the `Tool Bar` on the bottom of the screen.

Change tools with the keyboard keys `1` - `8`, the `L1` and `R1` controller
buttons, or by releasing the mouse with `ESC` and selecting a tool with the
mouse pointer.

Enu currently has 8 tools. Tool `1` on the left is the `Code` tool. It can
program almost anything in Enu, and will be explained in more detail later.
Tool `8` on the right is the `Place Bot` tool. Use it to fill your world with
friendly robots. Tools `2` - `7` are the `blue`, `red`, `green`, `black`,
`white`, and `brown` colored blocks.

Select the `Place Bot` tool to continue the tutorial.

  """,
    width = 2.5

  sign.open = true
  while player.tool != PlaceBot:
    sleep()
  sleep 0.5

-bot_info:
  say "- Place a `Bot`",
    """

# Bots

`Bots` are NPCs in Enu, and can be programmed to explore, change their
appearance, or offer information.

They can be placed with the `left` mouse button or the `R1` gamepad trigger.

Place a `Bot` on the ground to continue the tutorial.

  """,
    width = 2.0

  sign.open = true
  var last_bot_frame = frame_count()
  var og_bot_count = Bot.all.len

  while Bot.all.len <= og_bot_count:
    turn player
  for bot in Bot.all:
    if bot.frame_created > last_bot_frame:
      last_bot_frame = bot.frame_created
      bot_id = bot.id

-draw_maze:
  var bot = get_bot()
  turn bot
  maze = Maze.new(global = true)
  maze.show = true
  maze.rotation = 0
  maze.position = bot.position + (LEFT * 4.0) + (FORWARD * 1.0)

  while not maze.finished:
    sleep 0.5
  sleep 1

-code_info:
  say "- Coding",
    """

# Coding Enu

We control Enu using [Nim](https://nim-lang.org), a powerful programming
language that's useful for a wide variety of tasks. Almost everything in Enu
can be coded with Nim. Let's start by teaching our `Bot` to walk to the end of
the course.

Switch to the `Code` tool to continue the tutorial.

  """

  sign.open = true
  while player.tool != CodeMode:
    turn player
  sleep 0.5

-open_code:
  sign.more =
    """

# Coding Enu

With the `Code` tool selected, you can code anything you've created by clicking
on it with the `left` mouse button, or `R1` on the controller

Open the code for your `Bot` to continue the tutorial.

  """

  sign.open = true
  var bot = get_bot()

  while player.coding != bot:
    turn player
  sleep 0.5

-bot_navigation:
  sign.more =
    """

# Coding Bots

We control the bot with simple commands like `forward` and `turn`. Here's some
code to get our `Bot` partway through the course:

```nim
forward 17
turn right
forward 10
turn left
```

Please finish the code to get the `Bot` get to the end of the course.

Run your code by pressing left `alt/option (⌥)`. Keep left `alt/option (⌥)` held 
down to move around while you're coding. Flying is a great way to get yourself 
into position to see what's happening, so try double jumping to get a better 
view.

If your `Bot` is moving too slowly for your tastes, make her run by setting the
`speed` value.

```nim
speed = 10

forward 17
turn right
forward 10
turn left
```

Good luck! We'll conclude this tutorial when your `Bot` goes past the
`FINISH HERE!` sign at the end of the course.

  """

  sign.open = true
  var bot = get_bot()
  while maze.position.x - bot.position.x < 5:
    bot = get_bot()
    turn bot

-win:
  maze.won = true
  say "- Great Job!", "# Great Job!"
  sleep 15
  say "- All Done!",
    """

# Great Job!

Good work! You learned the basics of Enu, and you coded your first robot.
There's a lot more to come. Everything here - the signs, the course, the giant
spinning confetti monster, were created with `Nim` code inside Enu, and we'll
cover how to do all of it in future tutorials.

This is supposed to be where you move to the next tutorial, but it hasn't been
written yet. For now, you can try some
[Enu examples](<nim://load_level("tutorial-2")>) or load
[Inky: Isolation](<nim://load_level("tutorial-3")>), a simple
game written in Enu that's loosley inspired by **Alien: Isolation**, but
features Inky, the blue ghost from Pac-Man. If you're curious how this tutorial
was written, click [HERE](<nim://player.god = true;sign.open = false>) to turn
on `God Mode`, which will let you see and modify its code. It's a bit of a mess,
but some folks might find it interesting.

Contact me at [dsrw@me.com](mailto:dsrw@me.com) if you have any questions or
suggestions. Thanks for trying Enu!

  """

  sign.open = true

setup()
if not test_mode:
  approach()
  movement_info()
  flying_info()
  flying_done()
  good_job()
  tool_info()
  bot_info()
draw_maze()
code_info()
open_code()
bot_navigation()
win()
