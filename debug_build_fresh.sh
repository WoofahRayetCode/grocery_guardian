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
if [[ ! -d "$ANDROID_SDK_ROOT" ]]; then
  # Try to infer from adb location (e.g., /opt/android-sdk/platform-tools/adb)
  if command -v adb >/dev/null 2>&1; then
    ADB_BIN="$(command -v adb)"
    ADB_DIR="$(dirname "$ADB_BIN")"
    if [[ "$(basename "$ADB_DIR")" == "platform-tools" ]]; then
      CAND_ROOT="$(dirname "$ADB_DIR")"
      if [[ -d "$CAND_ROOT" ]]; then
        export ANDROID_SDK_ROOT="$CAND_ROOT"
        export ANDROID_HOME="$CAND_ROOT"
      fi
    fi
  fi
  # Fallback to common Arch path
  if [[ ! -d "$ANDROID_SDK_ROOT" && -d "/opt/android-sdk" ]]; then
    export ANDROID_SDK_ROOT="/opt/android-sdk"
    export ANDROID_HOME="/opt/android-sdk"
  fi
fi
echo "==> Using Android SDK: $ANDROID_SDK_ROOT"

REQUIRED_NDK="ndk;27.0.12077973"

# Download Android cmdline-tools into a given SDK if sdkmanager is missing
ensure_cmdline_tools() {
  local TARGET_SDK="$1"
  local CT_DIR="$TARGET_SDK/cmdline-tools/latest"
  if [[ -x "$CT_DIR/bin/sdkmanager" ]]; then
    return 0
  fi
  echo "==> Installing Android cmdline-tools into $TARGET_SDK"
  mkdir -p "$TARGET_SDK/cmdline-tools"
  local ZIP_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  local TMP_ZIP
  TMP_ZIP="$(mktemp -t cmdline-tools-XXXXXX.zip)"
  if command -v curl >/dev/null 2>&1; then
    curl -L --fail -o "$TMP_ZIP" "$ZIP_URL" || { echo "ERROR: Failed to download cmdline-tools"; return 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$TMP_ZIP" "$ZIP_URL" || { echo "ERROR: Failed to download cmdline-tools"; return 1; }
  else
    echo "ERROR: Neither curl nor wget found; cannot download cmdline-tools"
    return 1
  fi
  local TMP_DIR
  TMP_DIR="$(mktemp -d -t cmdline-tools-XXXXXX)"
  unzip -q "$TMP_ZIP" -d "$TMP_DIR" || { echo "ERROR: unzip failed"; rm -f "$TMP_ZIP"; return 1; }
  # The zip extracts into 'cmdline-tools' directory; move to latest/
  mkdir -p "$CT_DIR"
  if [[ -d "$TMP_DIR/cmdline-tools" ]]; then
    cp -a "$TMP_DIR/cmdline-tools/." "$CT_DIR/" || true
  else
    # Fallback: some zips may extract into 'tools'
    cp -a "$TMP_DIR/." "$CT_DIR/" || true
  fi
  rm -rf "$TMP_ZIP" "$TMP_DIR" || true
}

# If SDK root isn't writable (system SDK), bootstrap a user SDK under $HOME/Android/Sdk
ensure_user_sdk() {
  local USER SDKM_BIN
  USER="$HOME/Android/Sdk"
  # Find an sdkmanager we can use
  if [[ -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
    SDKM_BIN="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
  elif [[ -x "/opt/android-sdk/cmdline-tools/latest/bin/sdkmanager" ]]; then
    SDKM_BIN="/opt/android-sdk/cmdline-tools/latest/bin/sdkmanager"
  elif command -v sdkmanager >/dev/null 2>&1; then
    SDKM_BIN="$(command -v sdkmanager)"
  else
    SDKM_BIN=""
  fi
  if [[ ! -w "$ANDROID_SDK_ROOT" || "$ANDROID_SDK_ROOT" == "/opt/android-sdk" ]]; then
    echo "==> System SDK not writable; preparing user SDK at $USER"
    mkdir -p "$USER"
    # Ensure cmdline-tools present inside user SDK so we can use sdkmanager even if system one is missing
    if [[ -z "$SDKM_BIN" ]]; then
      ensure_cmdline_tools "$USER" || true
      if [[ -x "$USER/cmdline-tools/latest/bin/sdkmanager" ]]; then
        SDKM_BIN="$USER/cmdline-tools/latest/bin/sdkmanager"
      fi
    fi
    if [[ -n "$SDKM_BIN" ]]; then
      echo "==> Installing minimal Android SDK components into $USER"
      "$SDKM_BIN" --sdk_root="$USER" --install "platform-tools" || true
      # Install compile/target SDK and build-tools that match project
      "$SDKM_BIN" --sdk_root="$USER" --install "platforms;android-36" || true
      "$SDKM_BIN" --sdk_root="$USER" --install "build-tools;36.0.0" || true
      # Pre-install required NDK to avoid licence prompts mid-build
      "$SDKM_BIN" --sdk_root="$USER" --install "$REQUIRED_NDK" || true
      # Accept licenses for user SDK
      yes | "$SDKM_BIN" --sdk_root="$USER" --licenses || true
      export ANDROID_SDK_ROOT="$USER"
      export ANDROID_HOME="$USER"
      echo "==> Switched to user SDK: $ANDROID_SDK_ROOT"
    else
      echo "WARN: sdkmanager not found; attempted to download cmdline-tools but still unavailable."
      echo "      Please install Android Studio or 'cmdline-tools' manually and re-run."
    fi
  fi
}

ensure_user_sdk
# Ensure the active SDK has cmdline-tools and required components installed (platforms, build-tools, NDK), then accept licenses
ensure_components_for_sdk() {
  local ROOT="$1"
  local SDKM_BIN="$ROOT/cmdline-tools/latest/bin/sdkmanager"
  if [[ ! -x "$SDKM_BIN" ]]; then
    ensure_cmdline_tools "$ROOT" || true
  fi
  if [[ -x "$SDKM_BIN" ]]; then
    echo "==> Ensuring required Android components in $ROOT"
    "$SDKM_BIN" --sdk_root="$ROOT" --install "platform-tools" || true
    "$SDKM_BIN" --sdk_root="$ROOT" --install "platforms;android-36" || true
    "$SDKM_BIN" --sdk_root="$ROOT" --install "build-tools;36.0.0" || true
    "$SDKM_BIN" --sdk_root="$ROOT" --install "$REQUIRED_NDK" || true
    yes | "$SDKM_BIN" --sdk_root="$ROOT" --licenses || true
  fi
}

# Attempt to populate components if we're using a user-writable SDK
case "$ANDROID_SDK_ROOT" in
  "$HOME"/*) ensure_components_for_sdk "$ANDROID_SDK_ROOT" ;; 
  *) : ;;
esac
# Configure Flutter to use this Android SDK (persists in ~/.flutter_settings)
echo "==> Configuring Flutter Android SDK"
"$FLUTTER_BIN" config --android-sdk "$ANDROID_SDK_ROOT" || true

# Ensure android/local.properties has sdk.dir set for Gradle
if [[ -n "$ANDROID_SDK_ROOT" ]]; then
  echo "==> Writing android/local.properties sdk.dir=$ANDROID_SDK_ROOT"
  {
    echo "flutter.sdk=$HOME/.cache/flutter_sdk";
    echo "sdk.dir=$ANDROID_SDK_ROOT";
  } > "$SCRIPT_DIR/android/local.properties"
fi

# Try to accept Android SDK licenses if sdkmanager is available
if [[ -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
  echo "==> Accepting Android SDK licenses"
  yes | "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_SDK_ROOT" --licenses >/dev/null || true
else
  # Try accepting using a system sdkmanager if available
  if command -v sdkmanager >/dev/null 2>&1; then
    echo "==> Accepting Android SDK licenses (system sdkmanager)"
    yes | sdkmanager --sdk_root="$ANDROID_SDK_ROOT" --licenses >/dev/null || true
  fi
fi

# Ensure platform-tools (adb) in PATH
if [[ -d "$ANDROID_SDK_ROOT/platform-tools" ]]; then
  export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"
fi

# Attempt wireless connect; allow override via GG_WIRELESS, default to 192.168.0.244:33647
DEFAULT_WIRELESS="192.168.0.244:33647"
WIRELESS_TARGET="${GG_WIRELESS:-$DEFAULT_WIRELESS}"
if command -v adb >/dev/null 2>&1; then
  echo "==> Attempting adb connect to $WIRELESS_TARGET"
  adb connect "$WIRELESS_TARGET" || true
else
  echo "WARN: adb not found in PATH; skipping wireless connect"
fi

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

echo "==> Checking for connected Android devices (USB or wireless)"

# Default Android product flavor (can override with GG_FLAVOR)
FLAVOR="${GG_FLAVOR:-oss}"
GRADLE_FLAVOR_CAPITALIZED="${FLAVOR^}"
BASE_APP_ID="com.woofahrayetcode.groceryguardian"
APP_ID="$BASE_APP_ID.$FLAVOR"

# If user explicitly provided a device id, prefer it
SELECTED_DEVICE="${GG_DEVICE_ID:-}"

# Try to pick the first non-emulator ADB device with status 'device'
if [[ -z "$SELECTED_DEVICE" ]] && command -v adb >/dev/null 2>&1; then
  ADB_DEVICE=$(adb devices -l 2>/dev/null | awk 'NR>1 && $2=="device" && $1 !~ /^emulator-/ {print $1; exit}')
  if [[ -n "$ADB_DEVICE" ]]; then
    SELECTED_DEVICE="$ADB_DEVICE"
  fi
fi

# Fallback: try flutter devices to find an Android device id
if [[ -z "$SELECTED_DEVICE" ]]; then
  FD_OUT="$("$FLUTTER_BIN" devices 2>/dev/null || true)"
  # Grep a likely android device id from the first line containing "android" or "wireless"
  SELECTED_DEVICE=$(echo "$FD_OUT" | awk '/(android|wireless)/ && $1!="" {print $1; exit}')
fi

if [[ -n "$SELECTED_DEVICE" ]]; then
  echo "==> Launching on Android device with Flutter: $SELECTED_DEVICE (press q or Ctrl+C to quit)"
  if "$FLUTTER_BIN" run -d "$SELECTED_DEVICE" --flavor "$FLAVOR"; then
    exit 0
  fi
  echo "WARN: flutter run failed or device not recognized by Flutter. Attempting Gradle install..."
  # Fallback: use Gradle to install debug build and launch via adb
  ( cd android && ./gradlew install${GRADLE_FLAVOR_CAPITALIZED}Debug -x lint ) || {
    echo "ERROR: Gradle installDebug failed."; exit 1;
  }
  echo "==> Launching app via adb"
  adb shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
  echo "==> App installed and launched via adb."
  exit 0
fi

echo "==> No Android device detected — running on Linux desktop (hint: set GG_WIRELESS=ip:port to auto-connect)"
"$FLUTTER_BIN" run -d linux
