# The invisible rats' foundation. Follow the green outline: build white walls
# around it, about three blocks tall (the rat-catcher will nag you through it).
#
# When he gives you the magic words, add ONE line where it says YOUR LINE below
# to make the walls invisible — still solid, the rats still use them, you just
# can't see them. Only WHITE turns invisible; the green outline stays.

# --- green footprint outline on the ground (also covers the origin block) ---
color = green
for x in 0 .. 10:
  place(x, 0, 0, green)
  place(x, 0, 12, green)
for z in 0 .. 12:
  place(0, 0, z, green)
  place(10, 0, z, green)

# --- one starter "invisible wall" segment, here the whole time. The
# rat-catcher makes it visible for you as a demonstration; it renders as
# nothing but still collides, like every invisible wall. ---
box(vec3(1, 1, 0), vec3(4, 3, 0), color = invisible)

# ┌──────────────────────────── YOUR LINE ────────────────────────────┐
# │ When the rat-catcher says so, add this on the line just below:      │
# │                                                                     │
# │     swap_color white, invisible                                     │
# │                                                                     │
# └─────────────────────────────────────────────────────────────────────┘


# --- exercise monitor: leave this at the bottom. It quietly reports progress
# to the rat-catcher and the rocket through this build's pen colour (which
# nothing draws with, so it's invisible bookkeeping): green while you build,
# blue once the walls are up, red once they're invisible. ---
forever:
  var white_n = 0
  var invis_n = 0
  let o = position   # block_color_at reads WORLD coords, so offset by our origin
  for x in 0 .. 10:
    for z in 0 .. 12:
      let c = block_color_at(vec3(o.x + x.float, o.y + 2.0, o.z + z.float))
      if c == white:
        inc white_n
      elif c == invisible:
        inc invis_n
  if invis_n >= 15:
    color = red
  elif white_n >= 15:
    color = blue
  else:
    color = green
  sleep 1
