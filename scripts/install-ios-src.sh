#!/bin/bash
# Install iOS-specific source files into the Emacs source tree
#
# This script copies the iOS port source files from the project's src/
# directory into the build directory's src/ directory.
#
# Usage: BUILD_DIR=<build-dir> ./install-ios-src.sh
# Example: BUILD_DIR=emacs-build-ios-sim ./install-ios-src.sh
#
# Run this before configuring/building Emacs for iOS.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
IOS_SRC_DIR="$PROJECT_ROOT/ios"
# Allow BUILD_DIR to be overridden via environment variable
BUILD_DIR="${BUILD_DIR:-emacs-build-ios-sim}"
EMACS_SRC_DIR="$PROJECT_ROOT/$BUILD_DIR/src"
EMACS_LISP_TERM_DIR="$PROJECT_ROOT/$BUILD_DIR/lisp/term"

echo "Installing iOS source files..."
echo "  Build dir: $BUILD_DIR"
echo "  From: $IOS_SRC_DIR"
echo "  To:   $EMACS_SRC_DIR"

echo "Installing iOS source files..."
echo "  From: $IOS_SRC_DIR"
echo "  To:   $EMACS_SRC_DIR"

# List of iOS-specific source files
IOS_FILES=(
    "iosgui.h"
    "iosterm.h"
    "iosterm.m"
    "iosfns.m"
    "ios-termstubs.c"
)

for file in "${IOS_FILES[@]}"; do
    if [ -f "$IOS_SRC_DIR/$file" ]; then
        cp -v "$IOS_SRC_DIR/$file" "$EMACS_SRC_DIR/$file"
    else
        echo "Warning: $file not found in $IOS_SRC_DIR"
    fi
done

# Install iOS Lisp files
if [ -f "$IOS_SRC_DIR/ios-win.el" ]; then
    echo "Installing ios-win.el to lisp/term/..."
    cp -v "$IOS_SRC_DIR/ios-win.el" "$EMACS_LISP_TERM_DIR/ios-win.el"
fi

echo "iOS source files installed successfully."

