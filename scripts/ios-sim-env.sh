#!/bin/bash
# iOS Simulator Cross-Compilation Environment Setup
# Source this file before building any iOS Simulator dependencies
# Note: Do NOT use 'set -e' here as this script is meant to be sourced

# SDK and toolchain paths
export SDKPATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
export DEVELOPER_DIR=$(xcode-select -p)
export TOOLCHAIN="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain"

# Target configuration - Simulator on Apple Silicon
export IOS_MIN_VERSION=17.0
export ARCH=arm64
export HOST=aarch64-apple-darwin
export TARGET=arm64-apple-ios-simulator

# Installation prefix for cross-compiled libraries
export IOS_SIM_PREFIX="${IOS_SIM_PREFIX:-$(cd "$(dirname "$0")/.." && pwd)/ios-sim-deps}"

# Compiler and tools
export CC="${TOOLCHAIN}/usr/bin/clang"
export CXX="${TOOLCHAIN}/usr/bin/clang++"
export AR="${TOOLCHAIN}/usr/bin/ar"
export RANLIB="${TOOLCHAIN}/usr/bin/ranlib"
export STRIP="${TOOLCHAIN}/usr/bin/strip"
export NM="${TOOLCHAIN}/usr/bin/nm"

# Common flags - note the -simulator suffix and target triple
export CFLAGS="-arch ${ARCH} -isysroot ${SDKPATH} -mios-simulator-version-min=${IOS_MIN_VERSION} -target ${ARCH}-apple-ios${IOS_MIN_VERSION}-simulator -O2 -I${IOS_SIM_PREFIX}/include"
export CXXFLAGS="${CFLAGS}"
export CPPFLAGS="-isysroot ${SDKPATH} -I${IOS_SIM_PREFIX}/include"
export LDFLAGS="-arch ${ARCH} -isysroot ${SDKPATH} -mios-simulator-version-min=${IOS_MIN_VERSION} -target ${ARCH}-apple-ios${IOS_MIN_VERSION}-simulator -L${IOS_SIM_PREFIX}/lib"

# pkg-config for finding cross-compiled libraries
export PKG_CONFIG_PATH="${IOS_SIM_PREFIX}/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="${IOS_SIM_PREFIX}/lib/pkgconfig"

# Build-time tools need native compiler (not cross-compiler)
SCRIPT_DIR_FOR_CC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CC_FOR_BUILD="/usr/bin/clang"
export CXX_FOR_BUILD="/usr/bin/clang++"
export CFLAGS_FOR_BUILD="-O2"
export LDFLAGS_FOR_BUILD=""

# Create prefix directory
mkdir -p "${IOS_SIM_PREFIX}/lib" "${IOS_SIM_PREFIX}/include" "${IOS_SIM_PREFIX}/bin"

echo "iOS Simulator Cross-Compilation Environment:"
echo "  SDK:     ${SDKPATH}"
echo "  Target:  ${TARGET} (min iOS ${IOS_MIN_VERSION})"
echo "  Prefix:  ${IOS_SIM_PREFIX}"
echo "  CC:      ${CC}"
echo "  CFLAGS:  ${CFLAGS}"
