set -e
cd app
../vendor/godot/bin/godot.macos.editor.arm64 --headless --quit-after 600 scenes/game.tscn
