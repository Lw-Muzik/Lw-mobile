# Remote Phone Link (phone side)

Lets a desktop stream this phone's library across **different networks** (not
just the same Wi‑Fi), peer-to-peer over [iroh](https://www.iroh.computer)
(QUIC + NAT hole-punching, relay fallback, end-to-end encrypted). The LAN path
(mDNS + PIN) is unchanged and stays the fast default.

## How it works

- The shared Rust crate **`hm-remote`** (in the `hypemuzik-desktop` repo) runs
  this phone's iroh endpoint. It **serves a tunnel**: a desktop dials in and the
  node pipes the bytes to the phone's existing local HTTP shelf
  (`StreamServerController`), so `/library`, `/stream`, `/art`, … all work
  across networks unchanged.
- `lib/services/remote_link.dart` is the `dart:ffi` binding (`RemoteLink`).
  `ShareService.enable()` starts it with the shelf's port; `disable()` stops it.
- **Pairing**: the desktop shows a QR (Settings → Connect across networks). On
  the phone, Stream → "Link a desktop on another network" → **Scan desktop
  code** (`lib/pages/scan_desktop.dart`). The phone mints a bearer token,
  registers it in the shelf (`registerDesktop`), and dials the desktop over iroh
  with `{addr, name, pin, token}`. The desktop then redials the phone for media,
  authenticated by that token.

The QR encodes `hypemuzik://pair?ep=<desktopEndpointId>&pin=<6 digits>`.

## Building the native library

The native `libhm_remote.so` is **not** checked in — build it once (and after
any `hm-remote` change):

```sh
# one-time
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cargo install cargo-ndk
export ANDROID_NDK_HOME=$HOME/Library/Android/sdk/ndk/<version>

# build → android/app/src/main/jniLibs/<abi>/libhm_remote.so
./scripts/build_remote_android.sh
```

Then `flutter run`. (If your `hypemuzik-desktop` checkout isn't a sibling of
this repo, set `HM_REMOTE_REPO=/path/to/hypemuzik-desktop`.)

The library bundles iroh + tokio, so each `.so` is sizeable (~20 MB); it only
loads when "Share my music" is enabled.

## iOS (TODO)

Not wired yet. Plan: build `hm-remote` as a static lib for the iOS targets
(`aarch64-apple-ios`, `aarch64-apple-ios-sim`), `lipo` into a universal `.a`,
link it into the Runner (a small podspec or an Xcode "Link Binary With
Libraries" entry), and add `NSCameraUsageDescription` to `Info.plist`. The Dart
side already falls back to `DynamicLibrary.process()` on iOS.

## Notes

- Camera permission (`android.permission.CAMERA`) is declared for the scanner.
- The phone's iroh identity persists at
  `getApplicationSupportDirectory()/remote-identity.bin` (stable id across runs).
- If the native lib is missing, sharing still works on the LAN — the remote
  features just no-op (`remoteLinkSupported` / null-checks).
