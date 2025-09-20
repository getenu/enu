set -e
cd app
../vendor/godot/bin/godot.macos.editor.arm64 --verbose --headless scenes/game.tscn
