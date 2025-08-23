#!/usr/bin/env bash
set -euo pipefail

# Setup a default Android Virtual Device (AVD) and required SDK components
# - Ensures Android SDK cmdline-tools (sdkmanager/avdmanager) are available
# - Installs system image, emulator, platform-tools
# - Creates an AVD if not present
#
# Defaults:
#   NAME=Pixel_API_35
#   IMAGE="system-images;android-35;google_apis;x86_64"
#   DEVICE=pixel_7
#
# Usage:
#   tools/setup_default_avd.sh                  # create default AVD
#   tools/setup_default_avd.sh --list           # list AVDs
#   tools/setup_default_avd.sh --name MyAVD     # custom name
#   tools/setup_default_avd.sh --image "system-images;android-35;google_apis;x86_64"
#   tools/setup_default_avd.sh --device pixel_7
#   tools/setup_default_avd.sh --sdk-root /path/to/Sdk

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

NAME="Pixel_API_35"
IMAGE="system-images;android-35;google_apis;x86_64"
DEVICE="pixel_7"
CLI_SDK_ROOT=""
ACTION="create"

print_help() {
  sed -n '1,40p' "$0" | sed -E 's/^# ?//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) print_help; exit 0 ;;
    --list) ACTION="list"; shift ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --image) IMAGE="${2:-}"; shift 2 ;;
    --device) DEVICE="${2:-}"; shift 2 ;;
    --sdk-root) CLI_SDK_ROOT="${2:-}"; shift 2 ;;
    *) echo "Unknown option: $1"; print_help; exit 1 ;;
  esac
done

# Resolve Android SDK root
LOCAL_PROPERTIES="$ROOT_DIR/android/local.properties"
USER_SDK="$HOME/Android/Sdk"
if [[ -f "$LOCAL_PROPERTIES" ]]; then
  SDK_DIR_LINE=$(grep -E '^[[:space:]]*sdk\.dir=' "$LOCAL_PROPERTIES" | head -n1 | sed 's/\r$//' || true)
  if [[ -n "${SDK_DIR_LINE:-}" ]]; then
    SDK_ROOT_RAW="${SDK_DIR_LINE#*=}"
    SDK_ROOT_TRIMMED="${SDK_ROOT_RAW%%[[:space:]]*}"
  fi
fi
if [[ -n "$CLI_SDK_ROOT" ]]; then
  SDK_ROOT="$CLI_SDK_ROOT"
elif [[ -d "$USER_SDK" ]]; then
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

EMULATOR_BIN="$ANDROID_SDK_ROOT/emulator/emulator"
SDKM="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
AVDM="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/avdmanager"

# Prefer a supported JDK for cmdline-tools
choose_java() {
  for c in /usr/lib/jvm/java-21-openjdk /usr/lib/jvm/java-17-openjdk; do
    if [[ -x "$c/bin/java" ]]; then
      echo "$c"; return
    fi
  done
}
JH=$(choose_java || true)
if [[ -n "${JH:-}" ]]; then
  export JAVA_HOME="$JH"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

ensure_cmdline_tools() {
  local TARGET_SDK="$1"
  local CT_DIR="$TARGET_SDK/cmdline-tools/latest"
  if [[ -x "$CT_DIR/bin/sdkmanager" ]]; then return 0; fi
  echo "==> Installing Android cmdline-tools into $TARGET_SDK"
  mkdir -p "$CT_DIR"
  local ZIP_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  local TMP_ZIP
  TMP_ZIP="$(mktemp -t cmdline-tools-XXXXXX.zip)"
  if command -v curl >/dev/null 2>&1; then
    curl -L --fail -o "$TMP_ZIP" "$ZIP_URL"
  else
    wget -O "$TMP_ZIP" "$ZIP_URL"
  fi
  local TMP_DIR
  TMP_DIR="$(mktemp -d -t cmdline-tools-XXXXXX)"
  unzip -q "$TMP_ZIP" -d "$TMP_DIR"
  if [[ -d "$TMP_DIR/cmdline-tools" ]]; then
    cp -a "$TMP_DIR/cmdline-tools/." "$CT_DIR/"
  else
    cp -a "$TMP_DIR/." "$CT_DIR/"
  fi
  rm -rf "$TMP_ZIP" "$TMP_DIR"
}

ensure_components() {
  local ROOT="$1"
  ensure_cmdline_tools "$ROOT" || true
  if [[ -x "$ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
    echo "==> Installing emulator, platform-tools, and system image"
    yes | "$ROOT/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ROOT" --licenses >/dev/null || true
    "$ROOT/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ROOT" --install "platform-tools" "emulator" "$IMAGE"
  else
    echo "ERROR: sdkmanager not found under $ROOT"
    exit 1
  fi
}

if [[ "$ACTION" == "list" ]]; then
  if [[ -x "$EMULATOR_BIN" ]]; then
    "$EMULATOR_BIN" -list-avds || true
  else
    echo "No emulator binary found at $EMULATOR_BIN"
  fi
  exit 0
fi

ensure_components "$ANDROID_SDK_ROOT"

# Create AVD if it does not exist
EXISTS=$("$ANDROID_SDK_ROOT/emulator/emulator" -list-avds | grep -Fx "$NAME" || true)
if [[ -z "$EXISTS" ]]; then
  echo "==> Creating AVD: $NAME (device=$DEVICE, image=$IMAGE)"
  "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/avdmanager" create avd --name "$NAME" --package "$IMAGE" --device "$DEVICE" --force
else
  echo "==> AVD already exists: $NAME"
fi

echo "==> Done. Launch with: ./emulator_launch.sh --name $NAME"
