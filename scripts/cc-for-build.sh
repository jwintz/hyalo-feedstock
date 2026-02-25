#!/bin/bash
# cc-for-build.sh - Native compiler for build-time tools
# This script wraps the native clang for building tools that run on the build machine

exec /usr/bin/clang "$@"
