# Compiled by the VM runner more than once, and from another directory: its
# bake digests must come out the same every time.
import builds

type Shade = enum
  light
  dark

template twice(body: untyped) =
  # `n` is a hidden local: its name carries a counter that moves with every
  # use of the template before this one
  let n = 2
  for _ in 0 ..< n:
    body

# EXTRA

proc tone(shade: Shade): float =
  assert shade in {light, dark}
  if shade == light: 1.0 else: 0.5

bake:
  twice:
    discard tone(dark)

bake 3:
  discard tone(light)

# the same body as the first, under a key of its own: a different digest
bake "v2":
  twice:
    discard tone(dark)
