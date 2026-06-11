# Collectible: spins until the player touches it, then disappears.
# The spinning turn yields on its own; the collected branch idles with a
# duration sleep so the loop never spins hot.
sphere(size = 3, color = green)

move me
speed = 20
var collected = false

forever:
  if not collected:
    turn right, 5.0
    if Player.hit:
      collected = true
      show = false
      echo "Coin collected!"
  else:
    sleep 1
