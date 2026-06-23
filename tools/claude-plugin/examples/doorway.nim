# Doorway spawner: a wall with a gap, a sliding Door filling it, and a
# Button in front wired to the door. Walk into the button to open it.
# - Pass `color` explicitly: `.new()` defaults it to eraser, and a
#   turtle-drawn instance paints in the unit color.
# - Nudge a sliding part off the wall plane (z + 0.1 here) so it doesn't
#   z-fight the static geometry it slides past.
drawing = false

# wall with a 6-wide gap (door slides left into the wall's hollow side)
box(vec3(-12, 0, 0), vec3(-1, 8, 0), brown)
box(vec3(5, 0, 0), vec3(16, 8, 0), brown)

let d = Door.new(position = vec3(-41, 0, 30.1), door_width = 5, color = green)
Button.new(position = vec3(-38, 0, 36), door = d, color = red)
