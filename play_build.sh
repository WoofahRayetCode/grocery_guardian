#!/usr/bin/env bash
set -euo pipefail

# Play Store oriented build script (no PayPal donations, ads enabled)
# - Initializes/ensures SDK and Java like release_build_fresh.sh
# - Builds a release APK/AAB with compile-time flags for ads and without donations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/release_build_fresh.sh" >/dev/null 2>&1 || true

# Determine flutter
if command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN="$(command -v flutter)"
elif [[ -x "$SCRIPT_DIR/flutter/bin/flutter" ]]; then
  FLUTTER_BIN="$SCRIPT_DIR/flutter/bin/flutter"
else
  echo "Error: flutter not found"; exit 1
fi

# Use AAB for Play
BUILD_TARGET="appbundle" # or apk
FLAVOR="play"

# Env flags for compile-time features
export GG_WIRELESS="${GG_WIRELESS:-192.168.0.244:33647}"

echo "==> flutter pub get"
"$FLUTTER_BIN" pub get

# Build with defines: disable donations, enable ads, set test banner id unless ADMOB_BANNER_ANDROID_ID provided
DEFINES=(
  "--dart-define=DONATIONS=false"
  "--dart-define=ADS=true"
)
if [[ -n "${ADMOB_BANNER_ANDROID_ID:-}" ]]; then
  DEFINES+=("--dart-define=ADMOB_BANNER_ANDROID_ID=${ADMOB_BANNER_ANDROID_ID}")
fi

if [[ "$BUILD_TARGET" == "appbundle" ]]; then
  echo "==> Building Play Store AAB (ads on, donations off)"
  "$FLUTTER_BIN" build appbundle --flavor "$FLAVOR" --release "${DEFINES[@]}" \
    --obfuscate --split-debug-info=build/symbols
  echo "==> Output: build/app/outputs/bundle/release/app-release.aab"
else
  echo "==> Building Play Store APK (ads on, donations off)"
  "$FLUTTER_BIN" build apk --flavor "$FLAVOR" --release "${DEFINES[@]}" \
    --obfuscate --split-debug-info=build/symbols
  echo "==> Output: build/app/outputs/flutter-apk/app-release.apk"
fi
