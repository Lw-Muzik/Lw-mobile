#!/usr/bin/env bash
# Keeps the iOS copy of the live-stem engine identical to the canonical one.
#
#   tool/sync_stems_native.sh          copy android/.../cpp/stems -> ios/HypeDSP/src/stems
#   tool/sync_stems_native.sh --check  exit 1 if the copies differ (run before builds/commits)
#
# CocoaPods only compiles sources inside the pod folder, so the iOS pod cannot
# point at the Android tree; the engine is shared by copy instead.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
src="$repo/android/app/src/main/cpp/stems"
dst="$repo/ios/HypeDSP/src/stems"

if [[ "${1:-}" == "--check" ]]; then
  if diff -r "$src" "$dst" >/dev/null 2>&1; then
    echo "stems: iOS copy in sync"
  else
    echo "stems: iOS copy differs from $src — run tool/sync_stems_native.sh" >&2
    diff -rq "$src" "$dst" >&2 || true
    exit 1
  fi
  exit 0
fi

mkdir -p "$dst"
rsync -a --delete "$src/" "$dst/"
echo "stems: synced $(ls "$dst" | wc -l | tr -d ' ') files to ios/HypeDSP/src/stems"
