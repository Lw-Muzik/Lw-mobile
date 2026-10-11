#!/usr/bin/env bash
# Builds and runs the host unit tests for the live stem engine.
#
#   ORT_DIR=/path/to/onnxruntime-osx-arm64-1.31.0 native_tests/stems/run.sh [test-name-filter]
#
# ORT_DIR is an ONNX Runtime release folder (include/ + lib/) from
# https://github.com/microsoft/onnxruntime/releases. Optional real-model check:
# STEMS_MODEL_DIR (vocals/drums/bass/other.onnx) + STEMS_REF_DIR (reference.py output).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
src="$repo/android/app/src/main/cpp/stems"
: "${ORT_DIR:?set ORT_DIR to an onnxruntime release folder (include/, lib/)}"
out="${TMPDIR:-/tmp}/hype_stems_test"
mkdir -p "$out"

clang++ -std=c++17 -O2 -Wall -Wextra -Wno-unused-parameter \
  -I"$src" -I"$here" -I"$ORT_DIR/include" \
  "$src"/*.cpp "$here/stems_test.cpp" \
  -L"$ORT_DIR/lib" -lonnxruntime -Wl,-rpath,"$ORT_DIR/lib" \
  -o "$out/stems_test"

"$out/stems_test" "$@"
