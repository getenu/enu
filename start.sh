set -e
cd app
../vendor/godot/bin/godot.macos.editor.arm64 scenes/game.tscn -- --verify
