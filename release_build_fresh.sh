#!/usr/bin/env bash
set -euo pipefail

# Fresh release build & install script for Linux
# - Cleans build artifacts and ephemeral folders
# - Runs flutter clean and pub get
# - Builds Android release APK
# - If an Android device is connected (wireless/USB/android), installs APK on it

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
# Prefer existing user SDK dir
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
# If SDK dir doesn't exist, try to infer from adb or common system path
if [[ ! -d "$ANDROID_SDK_ROOT" ]]; then
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
  if [[ ! -d "$ANDROID_SDK_ROOT" && -d "/opt/android-sdk" ]]; then
    export ANDROID_SDK_ROOT="/opt/android-sdk"
    export ANDROID_HOME="/opt/android-sdk"
  fi
fi
echo "==> Using Android SDK: $ANDROID_SDK_ROOT"
# Define required NDK version to match AGP
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
  mkdir -p "$CT_DIR"
  if [[ -d "$TMP_DIR/cmdline-tools" ]]; then
    cp -a "$TMP_DIR/cmdline-tools/." "$CT_DIR/" || true
  else
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
    if [[ -z "$SDKM_BIN" ]]; then
      ensure_cmdline_tools "$USER" || true
      if [[ -x "$USER/cmdline-tools/latest/bin/sdkmanager" ]]; then
        SDKM_BIN="$USER/cmdline-tools/latest/bin/sdkmanager"
      fi
    fi
    if [[ -n "$SDKM_BIN" ]]; then
      echo "==> Installing minimal Android SDK components into $USER"
      "$SDKM_BIN" --sdk_root="$USER" --install "platform-tools" || true
      "$SDKM_BIN" --sdk_root="$USER" --install "platforms;android-36" || true
      "$SDKM_BIN" --sdk_root="$USER" --install "build-tools;36.0.0" || true
      "$SDKM_BIN" --sdk_root="$USER" --install "$REQUIRED_NDK" || true
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
# Configure Flutter to use this Android SDK
echo "==> Configuring Flutter Android SDK"
"$FLUTTER_BIN" config --android-sdk "$ANDROID_SDK_ROOT" || true

# Try to accept Android SDK licenses
if [[ -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
  echo "==> Accepting Android SDK licenses"
  yes | "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_SDK_ROOT" --licenses >/dev/null || true
else
  if command -v sdkmanager >/dev/null 2>&1; then
    echo "==> Accepting Android SDK licenses (system sdkmanager)"
    yes | sdkmanager --sdk_root="$ANDROID_SDK_ROOT" --licenses >/dev/null || true
  fi
fi

# Ensure android/local.properties has sdk.dir set for Gradle
if [[ -n "$ANDROID_SDK_ROOT" ]]; then
  echo "==> Writing android/local.properties sdk.dir=$ANDROID_SDK_ROOT"
  {
    echo "flutter.sdk=$HOME/.cache/flutter_sdk";
    echo "sdk.dir=$ANDROID_SDK_ROOT";
  } > "$SCRIPT_DIR/android/local.properties"
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
  # Common Arch/CachyOS paths
  for c in /usr/lib/jvm/java-21-openjdk /usr/lib/jvm/java-17-openjdk; do
    if [[ -x "$c/bin/java" ]] && "$c/bin/java" -version 2>&1 | grep -Eq 'version \"(17|21)'; then
      echo "$c"
      return
    fi
  done
  # Try archlinux-java helper
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
  # Fallback scan
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

# Ensure required components exist for the active SDK and accept licenses
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
    yes | "$SDKM_BIN" --sdk_root="$ROOT" --licenses >/dev/null || true
  fi
}

case "$ANDROID_SDK_ROOT" in
  "$HOME"/*) ensure_components_for_sdk "$ANDROID_SDK_ROOT" ;;
  *) : ;;
esac

# Preflight: ensure Android SDK cmdline-tools (sdkmanager) are available for license acceptance and components
SDKMANAGER_BIN=""
if [[ -n "$ANDROID_SDK_ROOT" && -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
  SDKMANAGER_BIN="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
elif [[ -n "$SDK_ROOT" && -x "$SDK_ROOT/tools/bin/sdkmanager" ]]; then
  SDKMANAGER_BIN="$ANDROID_SDK_ROOT/tools/bin/sdkmanager"
fi

if [[ -z "$SDKMANAGER_BIN" ]]; then
  echo "WARN: Android SDK cmdline-tools not found."
  echo "      Needed to accept licenses and install components (NDK, build-tools)."
  echo "      Detected ANDROID_SDK_ROOT/ANDROID_HOME: '${ANDROID_SDK_ROOT:-unset}'."
  echo "\nFix options:"
  echo "  1) Install cmdline-tools to \"$SDK_ROOT/cmdline-tools/latest\" and re-run."
  echo "     On Arch/CachyOS (fish):"
  echo "       sudo pacman -S --needed jdk17-openjdk android-sdk-cmdline-tools-latest android-platform android-sdk-platform-tools"
  echo "  2) Or install Android Studio and run 'Tools > SDK Manager' to add 'Android SDK Command-line Tools (latest)'."
  echo "  3) Or set ANDROID_SDK_ROOT to a user-writable SDK with cmdline-tools installed."
  echo ""
fi

echo "==> Building release APKs (flavors)"
# Build both flavors; ignore failures individually so the second can still succeed
"$FLUTTER_BIN" build apk --release --flavor oss || true
"$FLUTTER_BIN" build apk --release --flavor play || true

# Gather all possible APKs for upload; pick one primary for install
OSS_APK="build/app/outputs/flutter-apk/app-oss-release.apk"
PLAY_APK="build/app/outputs/flutter-apk/app-play-release.apk"
GENERIC_APK="build/app/outputs/flutter-apk/app-release.apk"

APK_PATH=""
if [[ -f "$OSS_APK" ]]; then
  APK_PATH="$OSS_APK"
elif [[ -f "$PLAY_APK" ]]; then
  APK_PATH="$PLAY_APK"
elif [[ -f "$GENERIC_APK" ]]; then
  APK_PATH="$GENERIC_APK"
fi

upload_all_apks() {
  local any=0
  if [[ -x "$SCRIPT_DIR/tools/upload_to_gdrive.sh" ]]; then
    for f in "$OSS_APK" "$PLAY_APK" "$GENERIC_APK"; do
      if [[ -f "$f" ]]; then
        any=1
        echo "==> Uploading APK to Google Drive: $f"
        "$SCRIPT_DIR/tools/upload_to_gdrive.sh" "$f" || echo "WARN: Upload failed for $f"
      fi
    done
  else
    echo "INFO: Upload script not found or not executable: $SCRIPT_DIR/tools/upload_to_gdrive.sh"
  fi
  return $any
}

echo "==> Checking for connected Android devices (USB or wireless)"

# Prefer explicit device id via GG_DEVICE_ID if provided
SELECTED_DEVICE="${GG_DEVICE_ID:-}"

if [[ -z "$SELECTED_DEVICE" ]] && command -v adb >/dev/null 2>&1; then
  ADB_DEVICE=$(adb devices -l 2>/dev/null | awk 'NR>1 && $2=="device" && $1 !~ /^emulator-/ {print $1; exit}')
  if [[ -n "$ADB_DEVICE" ]]; then
    SELECTED_DEVICE="$ADB_DEVICE"
  fi
fi

if [[ -z "$SELECTED_DEVICE" ]]; then
  FD_OUT="$("$FLUTTER_BIN" devices 2>/dev/null || true)"
  SELECTED_DEVICE=$(echo "$FD_OUT" | awk '/(android|wireless)/ && $1!="" {print $1; exit}')
fi

if [[ -n "$SELECTED_DEVICE" && -n "$APK_PATH" ]]; then
  echo "==> Installing to Android device with Flutter: $SELECTED_DEVICE"
  # Prefer adb direct install for explicit APK
  if command -v adb >/dev/null 2>&1; then
    if adb -s "$SELECTED_DEVICE" install -r "$APK_PATH"; then
      echo "==> Install successful."
  upload_all_apks || true
      exit 0
    fi
  fi
  # Fallback to Gradle flavor-specific install
  if [[ "$APK_PATH" == *oss* ]]; then
    ( cd android && ./gradlew installOssRelease -x lint ) && { echo "==> App installed via Gradle (oss)."; exit 0; }
  elif [[ "$APK_PATH" == *play* ]]; then
    ( cd android && ./gradlew installPlayRelease -x lint ) && { echo "==> App installed via Gradle (play)."; exit 0; }
  fi
  # Last resort, let Flutter try generic install
  if "$FLUTTER_BIN" install -d "$SELECTED_DEVICE" -v; then
    echo "==> Install successful."
    upload_all_apks || true
    exit 0
  fi
  echo "WARN: flutter install failed or device not recognized by Flutter. Attempting Gradle install..."
  ( cd android && ./gradlew installRelease -x lint ) || { echo "ERROR: Gradle installRelease failed."; exit 1; }
  echo "==> App installed via Gradle (generic)."
  exit 0
fi

if [[ -n "$APK_PATH" ]]; then
  echo "==> No physical/wireless Android device detected — attempting to launch Android emulator"
  AVD_NAME="${GG_AVD_NAME:-Pixel_API_35}"
  EMU_STARTED=0
  if [[ -x "$SCRIPT_DIR/emulator_launch.sh" ]]; then
    nohup "$SCRIPT_DIR/emulator_launch.sh" --create --name "$AVD_NAME" >/dev/null 2>&1 &
    EMU_STARTED=1
  else
    EMULATOR_BIN="$ANDROID_SDK_ROOT/emulator/emulator"
    if [[ -x "$EMULATOR_BIN" ]]; then
      FIRST_AVD=$("$EMULATOR_BIN" -list-avds | head -n1 || true)
      if [[ -n "$FIRST_AVD" ]]; then
        nohup "$EMULATOR_BIN" -avd "$FIRST_AVD" -netdelay none -netspeed full -no-snapshot >/dev/null 2>&1 &
        EMU_STARTED=1
      fi
    fi
  fi

  if [[ "$EMU_STARTED" -eq 1 ]]; then
    echo "==> Waiting for Android emulator to boot (timeout ~300s)"
    sleep 2
    BOOTED=""
    EMU_ID=""
    for i in {1..300}; do
      EMU_ID=$(adb devices | awk '/^emulator-/{ if ($2=="device") {print $1; exit} }') || true
      if [[ -n "$EMU_ID" ]]; then
        if [[ "$(adb -s "$EMU_ID" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
          BOOTED=1
          break
        fi
      fi
      sleep 1
    done
    if [[ -n "$BOOTED" && -n "$EMU_ID" ]]; then
      echo "==> Installing APK to emulator: $EMU_ID"
      if command -v adb >/dev/null 2>&1; then
        adb -s "$EMU_ID" install -r "$APK_PATH" || true
        # Determine app id from APK filename to launch the app
        APP_ID_BASE="com.woofahrayetcode.groceryguardian"
        if [[ "$APK_PATH" == *oss* ]]; then
          APP_ID="$APP_ID_BASE.oss"
        elif [[ "$APK_PATH" == *play* ]]; then
          APP_ID="$APP_ID_BASE.play"
        else
          APP_ID="$APP_ID_BASE"
        fi
        adb -s "$EMU_ID" shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
      fi
      echo "==> APK available at: $APK_PATH"
      upload_all_apks || true
      exit 0
    else
      echo "WARN: Emulator did not become ready in time. Skipping install."
    fi
  else
    echo "INFO: Could not start emulator automatically."
  fi

  echo "==> APK built at: $APK_PATH"
  upload_all_apks || true
else
  echo "ERROR: APK not found under build/app/outputs/flutter-apk."
  exit 1
fi
