# Level setup: the course is code-only — no block tools, no bot placement.
# (level.json sets show_tools false; we add back just the Code tool.)
lock = true
speed = 0
show = false

player.tools.incl CodeMode
# TODO(course): disable flying once a proper flying_allowed flag exists.
# For now the level is designed so flying doesn't skip anything.
