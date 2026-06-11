# Spawner for SpiralTree (see spiral_tree.nim): a row of instances.
# The first two use IDENTICAL params on purpose — the proto's internal
# randomness still makes them differ. Spawners set drawing = false so
# the spawner unit itself places no blocks.
drawing = false

SpiralTree.new(position = vec3(-50, 0, -370))
SpiralTree.new(position = vec3(-34, 0, -370))
SpiralTree.new(position = vec3(-16, 0, -370), trunk_color = white, leaf_color = green, trunk_height = 32)
SpiralTree.new(position = vec3(2, 0, -370), leaf_color = blue, twist = 0.34)
SpiralTree.new(position = vec3(20, 0, -370), trunk_color = black, leaf_color = green, trunk_height = 20)
SpiralTree.new(position = vec3(38, 0, -370), leaf_color = red, twist = 0.15, trunk_height = 30)
