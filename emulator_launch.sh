#!/usr/bin/env bash
set -euo pipefail

# Android Emulator helper
# - Detects Android SDK path
# - Lists AVDs, optionally creates a default AVD
# - Launches selected AVD
#
# Usage:
#   ./emulator_launch.sh                 # launch first available AVD
#   ./emulator_launch.sh --list          # list AVDs
#   ./emulator_launch.sh <AVD_NAME>      # launch by name
#   ./emulator_launch.sh --create        # create default Pixel_API_35 (API 35, google_apis, x86_64)
#   ./emulator_launch.sh --create --name MyAVD --image "system-images;android-35;google_apis;x86_64" --device pixel_7

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve Android SDK root: prefer android/local.properties sdk.dir, then env, then ~/Android/Sdk
LOCAL_PROPERTIES="$SCRIPT_DIR/android/local.properties"
USER_SDK="$HOME/Android/Sdk"
if [[ -f "$LOCAL_PROPERTIES" ]]; then
  SDK_DIR_LINE=$(grep -E '^[[:space:]]*sdk\.dir=' "$LOCAL_PROPERTIES" | head -n1 | sed 's/\r$//' || true)
  if [[ -n "${SDK_DIR_LINE:-}" ]]; then
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

EMULATOR_BIN="$ANDROID_SDK_ROOT/emulator/emulator"
SDKM="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
AVDM="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/avdmanager"

# Prefer a supported JDK for avdmanager/sdkmanager if needed
detect_java() {
  for c in /usr/lib/jvm/java-21-openjdk /usr/lib/jvm/java-17-openjdk; do
    if [[ -x "$c/bin/java" ]]; then
      echo "$c"
      return
    fi
  done
}
JH=$(detect_java || true)
if [[ -n "${JH:-}" ]]; then
  export JAVA_HOME="$JH"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

print_help() {
  sed -n '2,24p' "$0" | sed -E 's/^# ?//'
}

NAME=""
CREATE_AVD="false"
DEVICE="pixel_7"
IMAGE="system-images;android-35;google_apis;x86_64"
CLI_SDK_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      print_help; exit 0 ;;
    --list)
      ACTION="list"; shift ;;
    --create)
      CREATE_AVD="true"; shift ;;
    --name)
      NAME="${2:-}"; shift 2 ;;
    --image)
      IMAGE="${2:-}"; shift 2 ;;
    --device)
      DEVICE="${2:-}"; shift 2 ;;
    --sdk-root)
      CLI_SDK_ROOT="${2:-}"; shift 2 ;;
    --)
      shift; break ;;
    -*)
      echo "Unknown option: $1"; print_help; exit 1 ;;
    *)
      # Positional: treat as AVD name
      NAME="$1"; shift ;;
  esac
done

# Apply explicit --sdk-root override if provided
if [[ -n "$CLI_SDK_ROOT" ]]; then
  export ANDROID_SDK_ROOT="$CLI_SDK_ROOT"
  export ANDROID_HOME="$CLI_SDK_ROOT"
  EMULATOR_BIN="$ANDROID_SDK_ROOT/emulator/emulator"
  SDKM="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
  AVDM="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/avdmanager"
fi

if [[ ! -x "$EMULATOR_BIN" ]]; then
  # Fallback to system-wide location (Arch/CachyOS packaging)
  if [[ -x "/opt/android-sdk/emulator/emulator" ]]; then
    EMULATOR_BIN="/opt/android-sdk/emulator/emulator"
  elif command -v emulator >/dev/null 2>&1; then
    EMULATOR_BIN="$(command -v emulator)"
  else
    echo "Error: emulator binary not found. Looked in:"
    echo "  - $ANDROID_SDK_ROOT/emulator/emulator"
    echo "  - /opt/android-sdk/emulator/emulator"
    echo "  - PATH (emulator)"
    echo "Install Android SDK emulator and platform-tools, or ensure ANDROID_SDK_ROOT is correct."
    echo "Hint (Arch/CachyOS): sudo pacman -S --needed android-sdk-emulator android-sdk-platform-tools"
    echo "Or install into your user SDK (no sudo):"
    echo "  sdkmanager --sdk_root=$ANDROID_SDK_ROOT --install 'emulator'"
    exit 1
  fi
fi

if [[ "${ACTION:-}" == "list" ]]; then
  "$EMULATOR_BIN" -list-avds || true
  exit 0
fi

# Optionally create an AVD if requested
if [[ "$CREATE_AVD" == "true" ]]; then
  # Fallback to system-wide cmdline-tools if not present in selected SDK root
  if [[ ! -x "$AVDM" || ! -x "$SDKM" ]]; then
    if [[ -x "/opt/android-sdk/cmdline-tools/latest/bin/avdmanager" && -x "/opt/android-sdk/cmdline-tools/latest/bin/sdkmanager" ]]; then
      AVDM="/opt/android-sdk/cmdline-tools/latest/bin/avdmanager"
      SDKM="/opt/android-sdk/cmdline-tools/latest/bin/sdkmanager"
    else
      echo "Error: cmdline-tools not found at: $ANDROID_SDK_ROOT/cmdline-tools/latest/bin"
      echo "Install Android SDK Command-line Tools (latest) into your SDK, or ensure /opt/android-sdk/... exists."
      echo "Hint (Arch/CachyOS): sudo pacman -S --needed android-sdk-cmdline-tools-latest"
      exit 1
    fi
  fi
  if [[ -z "$NAME" ]]; then
    NAME="Pixel_API_35"
  fi
  echo "==> Accepting licenses (if any)"
  yes | "$SDKM" --sdk_root="$ANDROID_SDK_ROOT" --licenses >/dev/null || true
  echo "==> Ensuring system image present: $IMAGE"
  "$SDKM" --sdk_root="$ANDROID_SDK_ROOT" --install "$IMAGE" >/dev/null
  echo "==> Creating AVD: $NAME (device=$DEVICE, image=$IMAGE)"
  "$AVDM" create avd --name "$NAME" --package "$IMAGE" --device "$DEVICE" --force
fi

# If no AVD name provided, pick the first available
if [[ -z "$NAME" ]]; then
  if ! AVD_LIST=$("$EMULATOR_BIN" -list-avds); then
    echo "Error: No AVDs found. Create one with: $0 --create --name Pixel_API_35"
    exit 1
  fi
  NAME=$(echo "$AVD_LIST" | head -n1)
  if [[ -z "$NAME" ]]; then
    echo "Error: No AVDs available. Create one with: $0 --create --name Pixel_API_35"
    exit 1
  fi
fi

echo "==> Launching emulator: $NAME"
"$EMULATOR_BIN" -avd "$NAME" -netdelay none -netspeed full -no-snapshot
