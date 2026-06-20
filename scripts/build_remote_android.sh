#!/usr/bin/env bash
#
# Build the `hm-remote` native library (the iroh P2P endpoint) for Android and
# drop it into the app's jniLibs so the phone can be linked across networks.
#
# One-time setup:
#   rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
#   cargo install cargo-ndk
#   # plus the Android NDK installed (Android Studio → SDK Manager → NDK), and
#   # ANDROID_NDK_HOME exported, e.g.
#   #   export ANDROID_NDK_HOME=$HOME/Library/Android/sdk/ndk/<version>
#
# Run:    ./scripts/build_remote_android.sh
#
set -euo pipefail

HYPE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# The hm-remote crate lives in the sibling desktop repo by default; override with
# HM_REMOTE_REPO=/path/to/hypemuzik-desktop if yours is elsewhere.
REMOTE_REPO="${HM_REMOTE_REPO:-$HYPE_ROOT/../hypemuzik-desktop}"
JNILIBS="$HYPE_ROOT/android/app/src/main/jniLibs"

if [ ! -f "$REMOTE_REPO/crates/hm-remote/Cargo.toml" ]; then
  echo "error: hm-remote crate not found at $REMOTE_REPO/crates/hm-remote" >&2
  echo "       set HM_REMOTE_REPO to your hypemuzik-desktop checkout." >&2
  exit 1
fi

echo "Building libhm_remote.so for arm64-v8a, armeabi-v7a, x86_64 …"
cd "$REMOTE_REPO"
cargo ndk \
  -t arm64-v8a \
  -t armeabi-v7a \
  -t x86_64 \
  -o "$JNILIBS" \
  build --release -p hm-remote

echo
echo "Done → $JNILIBS/<abi>/libhm_remote.so"
echo "Now rebuild the app:  cd \"$HYPE_ROOT\" && flutter run"
