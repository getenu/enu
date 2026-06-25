# Dining table: 6 x 6 top on corner legs at scale 0.25 (1.5 m square),
# anchored at its centre so placement + rotation behave like the chair.
name DiningTable
scale = 0.25

anchor:
  forward 3
  right 3

box(width = 6, height = 1, at = position + vec3(0, 4, -5), depth = 6, color = brown) # top
box(width = 1, height = 4, at = position + vec3(0, 0, 0), depth = 1, color = brown)
box(width = 1, height = 4, at = position + vec3(5, 0, 0), depth = 1, color = brown)
box(width = 1, height = 4, at = position + vec3(0, 0, -5), depth = 1, color = brown)
box(width = 1, height = 4, at = position + vec3(5, 0, -5), depth = 1, color = brown)
