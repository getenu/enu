lock = true

# The island landing pad: a 5x5 stone square with white corner markers,
# a twin of the peninsula pad across the water. The ferry raft berths here.

# stone slab, two voxels thick so the top sits flush at world y3
box(vec3(-2, 0, -2), vec3(2, 1, 2), color = brown)

# white corner markers, short posts at each corner
for cx in [-2, 2]:
  for cz in [-2, 2]:
    box(vec3(cx, 2, cz), vec3(cx, 4, cz), color = white)
