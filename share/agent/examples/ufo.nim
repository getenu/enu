# Flying saucer: draws itself, then patrols forever. The template for
# any ambient moving thing. Key patterns: near/far hysteresis (enter
# buzz at 60, leave at 80 — no flickering), and a tether with a longer
# leash while engaged (the player can lure it, but not steal it).
# Spawn it high (its data json origin sets the altitude, e.g. y = 80).

# body: a lens of stacked disks, blue cockpit dome, green rim lights
cylinder(size = 5, height = 1, at = vec3(0, 0, 0), color = black)
cylinder(size = 9, height = 1, at = vec3(0, 1, 0), color = black)
cylinder(size = 11, height = 1, at = vec3(0, 2, 0), color = black)
cylinder(size = 9, height = 1, at = vec3(0, 3, 0), color = white)
sphere(size = 5, at = vec3(0, 4, 0), color = blue)

place(5, 2, 0, green)
place(-5, 2, 0, green)
place(0, 2, 5, green)
place(0, 2, -5, green)
place(4, 2, 3, green)
place(-4, 2, 3, green)
place(4, 2, -3, green)
place(-4, 2, -3, green)

move me

-cruise:
  speed = 8 .. 16
  glow = cycle(0.2, 0.6)
  turn -50.0 .. 50.0
  forward 12 .. 30

-scan: # stop and slowly spin in place, lights up
  speed = 5
  glow = cycle(0.6, 1.0)
  8.times:
    turn right

-buzz: # shadow the player from above
  speed = 25
  glow = 1
  turn player
  forward 5 .. 10

-go_home:
  speed = 20
  glow = 0.3
  me.go(start_position)

loop:
  nil -> cruise
  if 1 in 12:
    cruise -> scan
  scan -> cruise
  if ?player and player.near(60):
    (cruise, scan) ==> buzz
  if ?player and player.far(80):
    buzz -> cruise
  if start_position.far(130):
    (cruise, scan) ==> go_home
  if start_position.far(200): # buzz gets a longer leash, not an infinite one
    buzz -> go_home
  go_home -> cruise
