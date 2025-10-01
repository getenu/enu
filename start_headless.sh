set -e
cd app
../vendor/godot/bin/godot.macos.editor.dev.arm64 --headless --quit-after 600 scenes/game.tscn
