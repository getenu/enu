# Spawner for the anchored furniture protos: four chairs around the
# table on clean grid coords. The anchors mean `position` is the piece's
# centre and `rotation` spins in place — no corner-pivot offset math.
drawing = false

DiningTable.new(position = vec3(-18, 0, 62))
DiningChair.new(position = vec3(-18, 0, 60.8), rotation = 0) # N
DiningChair.new(position = vec3(-18, 0, 63.2), rotation = 180) # S
DiningChair.new(position = vec3(-16.8, 0, 62), rotation = 270) # E
DiningChair.new(position = vec3(-19.2, 0, 62), rotation = 90) # W
