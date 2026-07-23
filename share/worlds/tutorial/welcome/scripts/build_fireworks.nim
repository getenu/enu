speed = 0

# A little red firework shell, sitting on the rack. It's a dud -- it just
# sits there.
color = red
place(0, 0, 0, brown)               # its stubby fuse
sphere(size = 2, at = vec3(0, 1, 0), color = red)

# A dud. Fireworks are just code that runs over and over, fast.
# hint: `10.times:` ... `up 8` ... `color = cycle(red, white, blue)`
# hint: draw, `sleep 0.1`, `reset()`, draw again -- that's animation
