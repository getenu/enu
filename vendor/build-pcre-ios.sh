TOOLCHAIN_ROOT="/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer"
SYSROOT="${TOOLCHAIN_ROOT}/SDKs/iPhoneOS.sdk"

DEV_ARCHS="-arch armv7 -arch armv7s -arch arm64"

export CC=${TOOLCHAIN_ROOT}/usr/bin/gcc
export CXX=${TOOLCHAIN_ROOT}/usr/bin/g++
export LD=${TOOLCHAIN_ROOT}/usr/bin/ld\ -r
export CPP=${TOOLCHAIN_ROOT}/usr/bin/cpp
export CXXCPP=${TOOLCHAIN_ROOT}/usr/bin/cpp
export LDFLAGS="-isysroot ${SYSROOT} ${DEV_ARCHS}"
export AR=${TOOLCHAIN_ROOT}/usr/bin/ar
export AS=${TOOLCHAIN_ROOT}/usr/bin/as
export LIBTOOL=${TOOLCHAIN_ROOT}/usr/bin/libtool
export STRIP=${TOOLCHAIN_ROOT}/usr/bin/strip
export RANLIB=${TOOLCHAIN_ROOT}/usr/bin/ranlib

if [ ! -d ${SYSROOT} ]; then
  echo
  echo "Cannot find iOS developer tools at ${SYSROOT}."
  echo
  exit
fi

if [ -f Makefile ]; then
  make clean
fi

./configure \
CFLAGS="-O -isysroot ${SYSROOT} ${DEV_ARCHS}" \
CXXFLAGS="-O -isysroot ${SYSROOT} ${DEV_ARCHS}" \
--disable-dependency-tracking \
--host=arm-apple-darwin10 \
--target=arm-apple-darwin10 \
--disable-shared \
--enable-utf8 \
--prefix=${DEST_DIR}/device

make
