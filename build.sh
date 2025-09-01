set -e
cd app/enu_game
nim c --app:lib --out:lib/libEnugame.macos.debug.dylib --hints:off --warnings:off bootstrap.nim
