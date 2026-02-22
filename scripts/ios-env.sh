#!/bin/bash
# iOS Cross-Compilation Environment Setup
# Source this file before building any iOS dependencies

set -e

# SDK and toolchain paths
export SDKPATH=$(xcrun --sdk iphoneos --show-sdk-path)
export DEVELOPER_DIR=$(xcode-select -p)
export TOOLCHAIN="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain"

# Target configuration
export IOS_MIN_VERSION=26.0
export ARCH=arm64
export HOST=aarch64-apple-darwin
export TARGET=arm64-apple-ios

# Installation prefix for cross-compiled libraries
export IOS_PREFIX="${IOS_PREFIX:-$(cd "$(dirname "$0")/.." && pwd)/ios-deps}"

# Compiler and tools
export CC="${TOOLCHAIN}/usr/bin/clang"
export CXX="${TOOLCHAIN}/usr/bin/clang++"
export AR="${TOOLCHAIN}/usr/bin/ar"
export RANLIB="${TOOLCHAIN}/usr/bin/ranlib"
export STRIP="${TOOLCHAIN}/usr/bin/strip"
export NM="${TOOLCHAIN}/usr/bin/nm"

# Common flags
export CFLAGS="-arch ${ARCH} -isysroot ${SDKPATH} -miphoneos-version-min=${IOS_MIN_VERSION} -fembed-bitcode -O2 -I${IOS_PREFIX}/include"
export CXXFLAGS="${CFLAGS}"
export CPPFLAGS="-isysroot ${SDKPATH} -I${IOS_PREFIX}/include"
export LDFLAGS="-arch ${ARCH} -isysroot ${SDKPATH} -miphoneos-version-min=${IOS_MIN_VERSION} -L${IOS_PREFIX}/lib"

# pkg-config for finding cross-compiled libraries
export PKG_CONFIG_PATH="${IOS_PREFIX}/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="${IOS_PREFIX}/lib/pkgconfig"

# Build-time tools need native compiler (not cross-compiler)
# Use wrapper script to ensure iOS CFLAGS don't pollute native builds
SCRIPT_DIR_FOR_CC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CC_FOR_BUILD="${SCRIPT_DIR_FOR_CC}/cc-for-build.sh"
export CXX_FOR_BUILD="/usr/bin/clang++"
export CFLAGS_FOR_BUILD="-O2"
export LDFLAGS_FOR_BUILD=""

# Create prefix directory
mkdir -p "${IOS_PREFIX}/lib" "${IOS_PREFIX}/include" "${IOS_PREFIX}/bin"

echo "iOS Cross-Compilation Environment:"
echo "  SDK:     ${SDKPATH}"
echo "  Target:  ${TARGET} (min iOS ${IOS_MIN_VERSION})"
echo "  Prefix:  ${IOS_PREFIX}"
echo "  CC:      ${CC}"
echo "  CC_FOR_BUILD: ${CC_FOR_BUILD}"
