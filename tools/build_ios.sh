#!/bin/bash
set -e

export SDK=$(xcrun --sdk iphoneos --show-sdk-path)
export CC=$(xcrun --sdk iphoneos -f clang)
export CFLAGS="-arch arm64 -isysroot $SDK -mios-version-min=12.0"
export LDFLAGS="-arch arm64 -isysroot $SDK"

cd "$(dirname "$0")/../vendor/pcre"
# ./configure --disable-shared --disable-cpp --enable-unicode-properties --enable-pcre16 --enable-pcre32 --host=arm-apple-darwin
# make

cd ../..

nim c --os:ios --debugger:native -o:libenu.a src/enu.nim

libtool -static -o dist/ios/Enu/libenu.a libenu.a vendor/pcre/.libs/libpcre.a

cp vendor/godot/bin/libgodot.iphone.debug.arm64.a dist/ios/Enu.xcframework/ios-arm64/libgodot.a
