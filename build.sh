set -e
cd app/extension
nim c --app:lib --out:lib/enu.dylib enu.nim
