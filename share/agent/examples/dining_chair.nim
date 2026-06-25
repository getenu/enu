# Dining chair: 2 x 5 x 2 voxels at scale 0.25. The `anchor:` block
# puts the pivot at the seat centre, so `position` places the centre
# and `rotation` spins it in place — see furniture_plaza.nim for four
# chairs around a table on clean grid coords, no offset arithmetic.
name DiningChair
scale = 0.25

anchor:
  forward 1 # move pivot into the middle of the depth
  right 1 # ...and the middle of the width

box(width = 2, height = 1, depth = 2, color = brown) # legs row
box(width = 2, height = 1, at = position + vec3(0, 1, -1), depth = 2, color = brown) # seat
box(width = 2, height = 3, at = position + vec3(0, 2, 0), depth = 1, color = brown) # backrest
