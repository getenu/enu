# Exercises player.colors and the col() hex parser.
import types, core, players

var p: Player

p.colors = [black, white, red, green, blue, brown]
assert p.colors[0] == black
assert p.colors[5] == brown
assert p.colors.len == 6

p.colors[1] = "#123456"
assert p.colors[1] == col"123456"
assert p.colors[1].r == float32(0x12) / 255

p.colors[2] = blue
assert p.colors[2] == blue

p.colors = ["#000000", "#ffffff"]
assert p.colors[0] == black
assert p.colors[1] == (r: 1.0'f32, g: 1.0'f32, b: 1.0'f32, a: 1.0'f32)
assert p.colors[2] == blue

var seen: seq[Color]
for color in p.colors:
  seen.add color
assert seen.len == 6

var failed = false
try:
  discard col"#12345"
except ValueError:
  failed = true
assert failed

echo "  [VM] tool colors tests passed!"
