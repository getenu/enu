set -e
cd app
../vendor/godot/bin/godot.macos.editor.arm64 scenes/game.tscn 2>&1 | tee ../enu.log
