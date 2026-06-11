# Candy-stripe spiral tower (~60 m). Walk a hexagon but UNDER-turn each
# corner (46 vs 60 degrees), so every ring lands slightly rotated and the
# shaft twists as it climbs. cycle() alternates the stripe colour per edge.
# Variants: any polygon + over/under-turn drifts the same way; rare flecks
# via `color = if 1 in 10: green else: black` give a circuit-board look.
60.times:
  6.times:
    color = cycle(white, red)
    forward 7
    turn 46
  up 1
