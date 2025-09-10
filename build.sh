set -e
cd app/extension
nim c --app:lib --out:lib/libEnugame.macos.debug.dylib enu.nim
