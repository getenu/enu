# Exercises the player.tools set-like surface and its host bridge.
import types, players

# `self` is ignored by the test mocks, so a nil player is fine here.
var p: Player

p.tools = {BlueBlock, CodeMode}
assert CodeMode in p.tools
assert BlueBlock in p.tools
assert RedBlock notin p.tools
assert p.tools.len == 2

p.tools.incl RedBlock
assert RedBlock in p.tools
assert p.tools.len == 3

p.tools.excl CodeMode
assert CodeMode notin p.tools
assert p.tools.len == 2

var seen: seq[Tools]
for tool in p.tools:
  seen.add tool
assert seen == @[BlueBlock, RedBlock]

p.tools.clear()
assert p.tools.len == 0
assert BlueBlock notin p.tools

echo "  [VM] tool set tests passed!"
