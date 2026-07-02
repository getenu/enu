# Plant the canyon: same Cactus, different heights. (Variables at work
# before anyone names them.)
lock = true
speed = 0
show = false

let spots = [
  (vec3(-18, 4, -12), 5),
  (vec3(-2, 4, -38), 6),
  (vec3(10, 1, -14), 4), # down in the gorge
  (vec3(26, 4, -10), 7),
  (vec3(40, 4, -36), 5),
]
for spot in spots:
  var c = Cactus.new(global = true, height = spot[1])
  c.position = spot[0]
