set -e
cd app/enu_game
nim c --app:lib --out:lib/libEnugame.macos.debug.dylib bootstrap.nim
cd ..
../vendor/godot/bin/godot.macos.editor.arm64 --verbose --headless --quit-after 1 scenes/game.tscn
