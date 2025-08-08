#!/usr/bin/env bash
set -euo pipefail

# Fresh debug run script for Linux
# - Cleans build artifacts and ephemeral folders
# - Runs flutter clean and pub get
# - If an Android device is connected (wireless/USB/android), runs on it
# - Otherwise runs on Linux desktop

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve Flutter binary: prefer env FLUTTER_BIN, then repo-bundled SDK, then system PATH
if [[ -n "${FLUTTER_BIN:-}" && -x "$FLUTTER_BIN" ]]; then
  : # use provided FLUTTER_BIN
elif [[ -x "$SCRIPT_DIR/flutter/bin/flutter" ]]; then
  FLUTTER_BIN="$SCRIPT_DIR/flutter/bin/flutter"
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN="$(command -v flutter)"
else
  echo "Error: flutter not found. Install Flutter or include a bundled SDK at ./flutter."
  exit 1
fi

echo "==> Using Flutter: $FLUTTER_BIN"

# Resolve Android SDK root: prefer android/local.properties sdk.dir, then env, then ~/Android/Sdk
LOCAL_PROPERTIES="$SCRIPT_DIR/android/local.properties"
USER_SDK="$HOME/Android/Sdk"
if [[ -f "$LOCAL_PROPERTIES" ]]; then
  SDK_DIR_LINE=$(grep -E '^[[:space:]]*sdk\.dir=' "$LOCAL_PROPERTIES" | head -n1 | sed 's/\r$//' || true)
  if [[ -n "$SDK_DIR_LINE" ]]; then
    SDK_ROOT_RAW="${SDK_DIR_LINE#*=}"
    SDK_ROOT_TRIMMED="${SDK_ROOT_RAW%%[[:space:]]*}"
  fi
fi
if [[ -d "$USER_SDK" ]]; then
  SDK_ROOT="$USER_SDK"
elif [[ -n "${SDK_ROOT_TRIMMED:-}" ]]; then
  SDK_ROOT="$SDK_ROOT_TRIMMED"
elif [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
  SDK_ROOT="$ANDROID_SDK_ROOT"
elif [[ -n "${ANDROID_HOME:-}" ]]; then
  SDK_ROOT="$ANDROID_HOME"
else
  SDK_ROOT="$USER_SDK"
fi
export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_HOME="$SDK_ROOT"
echo "==> Using Android SDK: $ANDROID_SDK_ROOT"

# Ensure a supported Java for Gradle/AGP (17 preferred, 21 acceptable)
detect_supported_java() {
  if [[ -n "${JAVA_HOME:-}" ]] && "$JAVA_HOME/bin/java" -version 2>&1 | grep -Eq 'version \"(17|21)'; then
    echo "$JAVA_HOME"
    return
  fi
  for c in /usr/lib/jvm/java-21-openjdk /usr/lib/jvm/java-17-openjdk; do
    if [[ -x "$c/bin/java" ]] && "$c/bin/java" -version 2>&1 | grep -Eq 'version \"(17|21)'; then
      echo "$c"
      return
    fi
  done
  if command -v archlinux-java >/dev/null 2>&1; then
    local current
    current=$(archlinux-java status 2>/dev/null | awk '/default/ {print $3}' | tr -d '()' || true)
    if [[ -n "$current" && -x "/usr/lib/jvm/$current/bin/java" ]] && "/usr/lib/jvm/$current/bin/java" -version 2>&1 | grep -Eq 'version \"(17|21)'; then
      echo "/usr/lib/jvm/$current"
      return
    fi
    local j
    j=$(archlinux-java status 2>/dev/null | awk '/installed/ {print $1}' | grep -Em1 'java-(17|21)' || true)
    if [[ -n "$j" && -x "/usr/lib/jvm/$j/bin/java" ]]; then
      echo "/usr/lib/jvm/$j"
      return
    fi
  fi
  for d in /usr/lib/jvm/java-17* /usr/lib/jvm/java-21* /Library/Java/JavaVirtualMachines/*/Contents/Home; do
    if [[ -x "$d/bin/java" ]] && "$d/bin/java" -version 2>&1 | grep -Eq 'version \"(17|21)'; then
      echo "$d"
      return
    fi
  done
}

JAVA_SUPPORTED_HOME=$(detect_supported_java || true)
if [[ -n "$JAVA_SUPPORTED_HOME" ]]; then
  export JAVA_HOME="$JAVA_SUPPORTED_HOME"
  export PATH="$JAVA_HOME/bin:$PATH"
  # Hint Gradle to use this JDK
  export ORG_GRADLE_JAVA_HOME="$JAVA_HOME"
  echo "==> Using Java: $JAVA_HOME ($(java -version 2>&1 | head -n1))"
else
  echo "WARN: Supported JDK (17 or 21) not found. Current is: $(java -version 2>&1 | head -n1)"
  echo "     Options on Arch/CachyOS (fish):"
  echo "       - Install JDK 21:  sudo pacman -S --needed jdk21-openjdk; and sudo archlinux-java set java-21-openjdk"
  echo "       - Or install JDK 17 (via sdkman):  curl -s https://get.sdkman.io | bash; source ~/.sdkman/bin/sdkman-init.sh; sdk install java 17.0.13-tem"
  echo "       - Or install Android Studio and point JAVA_HOME to its JBR (17)."
fi

echo "==> Cleaning build artifacts and ephemeral folders"
rm -rf build || true
rm -rf .dart_tool || true
rm -rf ios/Flutter/ephemeral || true
rm -rf linux/flutter/ephemeral || true
rm -rf macos/Flutter/ephemeral || true
rm -rf windows/flutter/ephemeral || true

echo "==> flutter clean"
"$FLUTTER_BIN" clean

echo "==> flutter pub get"
"$FLUTTER_BIN" pub get

echo "==> Checking for connected devices"
DEVICES_OUTPUT="$("$FLUTTER_BIN" devices || true)"
if echo "$DEVICES_OUTPUT" | grep -qiE "wireless"; then
  echo "==> Wireless device detected — launching flutter run (press q or Ctrl+C to quit)"
  "$FLUTTER_BIN" run
  exit $?
fi

if echo "$DEVICES_OUTPUT" | grep -qiE "usb|android"; then
  echo "==> USB/Android device detected — launching flutter run (press q or Ctrl+C to quit)"
  "$FLUTTER_BIN" run
  exit $?
fi

echo "==> No Android device detected — running on Linux desktop"
"$FLUTTER_BIN" run -d linux
