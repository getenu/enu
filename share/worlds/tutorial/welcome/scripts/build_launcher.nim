lock = true

# The bounce launcher on the island's west shore. Stand dead-centre on the
# springy coil, face the arrow, and it flings the player clear across the
# water to the peninsula meadow.

# ----- the springy coil: blue/white rings stacked two high on a base -----
box(vec3(-1, 0, -1), vec3(1, 0, 1), color = blue)    # base
box(vec3(-1, 1, -1), vec3(1, 1, 1), color = white)   # white coil band
box(vec3(-1, 2, -1), vec3(1, 2, 1), color = blue)    # blue coil top (stand here)

# ----- a white arrow on the ground, aimed at the meadow (95, -133) -----
# unit heading from the launcher toward the meadow, in the xz plane
# (pre-rounded shaft cells for heading (-0.78, 0.626) — the VM stdlib
# has no float.round)
color = white
for c in [(-2, 1), (-2, 2), (-3, 3), (-4, 3), (-5, 4), (-6, 5)]:
  place(c[0], 0, c[1], white)
for c in [(-5, 5), (-4, 5), (-5, 4), (-6, 4), (-5, 3)]:   # the arrowhead
  place(c[0], 0, c[1], white)

# ----- the instruction sign -----
say "LAUNCH PAD -- face the arrow, hold nothing", width = 5.0, height = 1.2

# ----- launch behavior -----
# The travel heading matches the boost vector below: aimed at the meadow.
# player.rotation is set empirically so the player faces where they're thrown.
const LAUNCH_FACING = 129.0
let pad_center = me.position + vec3(0.0, 3.0, 0.0)

forever:
  if (player.position - pad_center).length < 1.8:
    say "3"
    sleep 1
    say "2"
    sleep 1
    say "1"
    sleep 1
    say "Liftoff!"
    player.rotation = LAUNCH_FACING
    player.boost vec3(-51.0, 60.0, 41.0)
    sleep 5
    say "LAUNCH PAD -- face the arrow, hold nothing", width = 5.0, height = 1.2
  else:
    sleep 0.3
