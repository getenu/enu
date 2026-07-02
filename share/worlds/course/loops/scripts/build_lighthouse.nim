# The lighthouse tower is missing! Boats can't find the harbor.
# Stack layers up to the dark lamp overhead.

# Here's one layer:
color = red
box(3, 1, 3)

# Now repeat it — up to the lamp! You'll need a loop:
#
#   10.times:
#     box(3, 1, 3)
#     up 1
#
# Want stripes? Put   color = cycle(red, white)   inside your loop.
