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
# Force 16 KB page-size alignment on the produced .so files (required for
# Android 15+ / 16 KB-page devices). Rust drives the NDK linker itself, so we
# pass the flag through RUSTFLAGS rather than relying on the NDK default.
export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,-z,max-page-size=16384"
cargo ndk \
  -t arm64-v8a \
  -t armeabi-v7a \
  -t x86_64 \
  -o "$JNILIBS" \
  build --release -p hm-remote

# cargo-ndk copies every .so it finds into the output dir, which includes
# stray Rust dependency dylib artifacts (libiroh-<hash>.so, libiroh_relay-…).
# `libhm_remote.so` statically links iroh (its only NEEDED libs are libc/libm/
# libdl), so these orphans are never loaded — they just bloat the APK and trip
# the 16 KB page-size checker. Drop everything except our cdylib.
echo "Pruning stray dependency artifacts from jniLibs …"
find "$JNILIBS" -name '*.so' ! -name 'libhm_remote.so' \
  \( -name 'libiroh*.so' -o -name 'libiroh_relay*.so' \) -delete

echo
echo "Done → $JNILIBS/<abi>/libhm_remote.so"
echo "Now rebuild the app:  cd \"$HYPE_ROOT\" && flutter run"
