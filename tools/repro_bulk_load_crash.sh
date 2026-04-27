#!/bin/bash
# Full-scale repro mimicking original crash: M prototypes + K one-off scripted builds + 1 big spawner
set -e
LD="/Users/scott/Library/Application Support/enu/default/api-test"

M=${1:-10}    # prototypes
K=${2:-50}    # one-off builds (scripted)
S=${3:-80}    # spawner instance count

rm -rf "$LD/data" "$LD/scripts" "$LD/generated"
mkdir -p "$LD/scripts"
cat > "$LD/level.json" << 'EOF'
{
  "enu_version": "v0.2.2-197-g46a2cea0",
  "format_version": "v0.9.2",
  "load_order": []
}
EOF

# M prototypes
for j in $(seq 1 $M); do
  mkdir -p "$LD/data/build_proto_$j"
  cat > "$LD/data/build_proto_$j/build_proto_$j.json" <<EOF
{
  "id": "build_proto_$j",
  "start_transform": {
    "basis": [[1,0,0],[0,1,0],[0,0,1]],
    "origin": [0.0, 0.0, 50.0]
  },
  "start_color": "BROWN",
  "edits": {}
}
EOF
  cat > "$LD/scripts/build_proto_$j.nim" <<EOF
name thing_$j(size = 2)
if not is_instance:
  show = false
  quit()
speed = 0
fill_box(0, 0, 0, size, size, size, red)
EOF
done

# K one-off scripted builds (just fill_box)
for k in $(seq 1 $K); do
  mkdir -p "$LD/data/build_uniq_$k"
  x=$((k % 10 * 6 + 30))
  z=$((-20 - (k / 10) * 6))
  cat > "$LD/data/build_uniq_$k/build_uniq_$k.json" <<EOF
{
  "id": "build_uniq_$k",
  "start_transform": {
    "basis": [[1,0,0],[0,1,0],[0,0,1]],
    "origin": [$x.0, 0.0, $z.0]
  },
  "start_color": "BROWN",
  "edits": {}
}
EOF
  cat > "$LD/scripts/build_uniq_$k.nim" <<EOF
speed = 0
fill_box(0, 0, 0, 3, 3, 3, brown)
EOF
done

# 1 big spawner: cycles through M prototypes for S instances
mkdir -p "$LD/data/build_spawner"
cat > "$LD/data/build_spawner/build_spawner.json" <<EOF
{
  "id": "build_spawner",
  "start_transform": {
    "basis": [[1,0,0],[0,1,0],[0,0,1]],
    "origin": [-30.0, 0.0, -20.0]
  },
  "start_color": "BROWN",
  "edits": {}
}
EOF
{
  echo "speed = 0"
  echo "show = false"
  for i in $(seq 1 $S); do
    j=$(( (i - 1) % M + 1 ))
    x=$(( -30 - (i % 10) * 4 ))
    z=$(( -20 - (i / 10) * 4 ))
    echo "thing_$j.new(size = 2, position = vec3($x, 0, $z))"
  done
} > "$LD/scripts/build_spawner.nim"

find "$LD/data" "$LD/scripts" -type f -exec touch {} +
echo "Wrote $M prototypes + $K one-offs + 1 spawner ($S instances)"
echo "Total scripts: $((M + K + 1))"
