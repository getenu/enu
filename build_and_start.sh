set -e
./build.sh
cd app
../vendor/godot/bin/godot.macos.editor.arm64 --headless --quit-after 60 scenes/game.tscn --verify
