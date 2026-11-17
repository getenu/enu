## Prototype 5 driver: every script under the given directories goes
## text -> blocks -> text, and must come back identical (modulo nph
## formatting). Prints coverage: how much became real blocks vs CODE.

import std/[os, strutils, tables, algorithm, strformat]
import blocks

var
  files, identical, formatted_already: int
  total: Stats
  failures: seq[string]

for dir in command_line_params():
  for path in walk_dir_rec(dir):
    if not path.ends_with(".nim") or "/generated/" in path:
      continue
    inc files
    let src = read_file(path)
    let canonical = render(parse(src))
    if canonical.strip == src.strip:
      inc formatted_already
    var stats: Stats
    let blocks = to_blocks(parse(src), stats)
    let back = to_source(blocks)
    if back == canonical:
      inc identical
    else:
      failures.add path
      if failures.len <= 3:
        write_file(get_temp_dir() / &"rt_{failures.len}_canonical.nim", canonical)
        write_file(get_temp_dir() / &"rt_{failures.len}_back.nim", back)
    total.blocks += stats.blocks
    total.code += stats.code
    total.fallbacks.add stats.fallbacks

echo &"files: {files}, round-trip identical: {identical}, already nph-formatted: {formatted_already}"
echo &"statements: {total.blocks}, real blocks: {total.blocks - total.code} " &
  &"({100 * (total.blocks - total.code) / max(1, total.blocks):.1f}%), code blocks: {total.code}"
var counts: CountTable[string]
var examples: Table[string, seq[string]]
for f in total.fallbacks:
  let (kind, line) = (f.split('\t')[0], f.split('\t')[1])
  counts.inc kind
  if line notin examples.mget_or_put(kind, @[]) and examples[kind].len < 4:
    examples[kind].add line
counts.sort
echo "code-block fallbacks by node kind:"
for k, v in counts:
  echo &"  {v:4}  {k}"
  for e in examples[k]:
    echo "          ", e
for f in failures:
  echo "MISMATCH ", f
