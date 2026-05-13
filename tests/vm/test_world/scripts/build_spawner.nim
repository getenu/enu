speed = 0
show = false

# Heavy instancing of multiple proto types under register pressure.
# Mirrors what build_castle_spawner.nim does in production worlds.
var w01 = 1; var w02 = 2; var w03 = 3; var w04 = 4; var w05 = 5
var w06 = 6; var w07 = 7; var w08 = 8; var w09 = 9; var w10 = 10
var w11 = 11; var w12 = 12; var w13 = 13; var w14 = 14; var w15 = 15
var w16 = 16; var w17 = 17; var w18 = 18; var w19 = 19; var w20 = 20

for i in 0 ..< 30:
  tree.new(height = 5 + (i mod 4), position = vec3(float(i * 4), 0, 0))
  fence_post.new(height = 3, position = vec3(float(i * 2), 0, 10))
  echo "  spawned ", i, " w20=", w20
