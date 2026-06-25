# A road with raised curbs so it clearly reads "walk here." The black
# surface doubles as a canvas for direction arrows, added later as
# persistent JSON edits (white arrows down the middle).
color = black
box(vec3(-1, 0, 0), vec3(1, 0, -22), color = black) # road surface
color = white
box(vec3(-2, 0, 0), vec3(-2, 1, -22), color = white) # left curb
box(vec3(2, 0, 0), vec3(2, 1, -22), color = white) # right curb
