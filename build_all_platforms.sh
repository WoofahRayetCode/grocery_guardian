#!/usr/bin/env bash
set -euo pipefail

# Multi-platform build script for Grocery Guardian
# Builds: Linux desktop, Web, and Android (APK/AAB) with automatic environment setup
# Usage: ./build_all_platforms.sh [--android-only] [--linux-only] [--web-only] [--skip-android] [--skip-tests]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse command-line flags
BUILD_LINUX=1
BUILD_WEB=1
BUILD_ANDROID=1
RUN_TESTS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --android-only)
      BUILD_LINUX=0
      BUILD_WEB=0
      shift
      ;;
    --linux-only)
      BUILD_ANDROID=0
      BUILD_WEB=0
      shift
      ;;
    --web-only)
      BUILD_ANDROID=0
      BUILD_LINUX=0
      shift
      ;;
    --skip-android)
      BUILD_ANDROID=0
      shift
      ;;
    --skip-tests)
      RUN_TESTS=0
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--android-only] [--linux-only] [--web-only] [--skip-android] [--skip-tests]"
      exit 1
      ;;
  esac
done

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Grocery Guardian Multi-Platform Build Script        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Build targets:"
echo "  - Linux Desktop: $([ $BUILD_LINUX -eq 1 ] && echo "YES" || echo "NO")"
echo "  - Web:           $([ $BUILD_WEB -eq 1 ] && echo "YES" || echo "NO")"
echo "  - Android:       $([ $BUILD_ANDROID -eq 1 ] && echo "YES" || echo "NO")"
echo "  - Run Tests:     $([ $RUN_TESTS -eq 1 ] && echo "YES" || echo "NO")"
echo ""

# Resolve Flutter binary
if [[ -n "${FLUTTER_BIN:-}" && -x "$FLUTTER_BIN" ]]; then
  : # use provided FLUTTER_BIN
elif [[ -x "$SCRIPT_DIR/flutter/bin/flutter" ]]; then
  FLUTTER_BIN="$SCRIPT_DIR/flutter/bin/flutter"
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN="$(command -v flutter)"
else
  echo "ERROR: flutter not found. Install Flutter or include a bundled SDK at ./flutter."
  exit 1
fi

echo "==> Using Flutter: $FLUTTER_BIN"
"$FLUTTER_BIN" --version
echo ""

# Clean previous builds
echo "==> Cleaning previous build artifacts"
rm -rf build || true
rm -rf .dart_tool || true
rm -rf ios/Flutter/ephemeral || true
rm -rf linux/flutter/ephemeral || true
rm -rf macos/Flutter/ephemeral || true
rm -rf windows/flutter/ephemeral || true

"$FLUTTER_BIN" clean

# Get dependencies
echo "==> Running flutter pub get"
"$FLUTTER_BIN" pub get
echo ""

# Run tests
if [[ $RUN_TESTS -eq 1 ]]; then
  echo "==> Running tests"
  if "$FLUTTER_BIN" test; then
    echo "✓ Tests passed"
  else
    echo "WARN: Tests failed, continuing with build..."
  fi
  echo ""
fi

# Track build successes
LINUX_SUCCESS=0
WEB_SUCCESS=0
ANDROID_SUCCESS=0

# ============================================================================
# BUILD LINUX DESKTOP
# ============================================================================
if [[ $BUILD_LINUX -eq 1 ]]; then
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                    Building Linux Desktop                    ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  
  "$FLUTTER_BIN" config --enable-linux-desktop
  
  if "$FLUTTER_BIN" build linux --release; then
    LINUX_SUCCESS=1
    echo ""
    echo "✓ Linux build successful!"
    echo "  Binary: build/linux/x64/release/bundle/grocery_guardian"
    echo "  To run: cd build/linux/x64/release/bundle && ./grocery_guardian"
  else
    echo ""
    echo "✗ Linux build failed"
  fi
  echo ""
fi

# ============================================================================
# BUILD WEB
# ============================================================================
if [[ $BUILD_WEB -eq 1 ]]; then
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                        Building Web                          ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  
  "$FLUTTER_BIN" config --enable-web
  
  if "$FLUTTER_BIN" build web --release; then
    WEB_SUCCESS=1
    echo ""
    echo "✓ Web build successful!"
    echo "  Output: build/web/"
    echo "  To serve: cd build/web && python3 -m http.server 8080"
  else
    echo ""
    echo "✗ Web build failed"
  fi
  echo ""
fi

# ============================================================================
# BUILD ANDROID
# ============================================================================
if [[ $BUILD_ANDROID -eq 1 ]]; then
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                      Building Android                        ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  
  # Resolve Android SDK root
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
  
  # Try to infer SDK from adb or common system path if not found
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
  
  # Ensure Java is available (17 or 21)
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
  
  if [[ -z "$JAVA_SUPPORTED_HOME" ]]; then
    echo "WARN: JDK 17 or 21 not found. Attempting to install JDK 21..."
    
    # Try to install JDK 21 on Arch-based systems
    if command -v pacman >/dev/null 2>&1; then
      echo "  Detected pacman. Installing jdk21-openjdk..."
      if sudo pacman -S --needed --noconfirm jdk21-openjdk 2>/dev/null; then
        echo "  ✓ JDK 21 installed"
        if command -v archlinux-java >/dev/null 2>&1; then
          sudo archlinux-java set java-21-openjdk || true
        fi
        JAVA_SUPPORTED_HOME=$(detect_supported_java || true)
      else
        echo "  WARN: Failed to install JDK 21 with pacman"
      fi
    elif command -v apt-get >/dev/null 2>&1; then
      echo "  Detected apt. Installing openjdk-21-jdk..."
      if sudo apt-get update && sudo apt-get install -y openjdk-21-jdk 2>/dev/null; then
        echo "  ✓ JDK 21 installed"
        JAVA_SUPPORTED_HOME=$(detect_supported_java || true)
      else
        echo "  WARN: Failed to install JDK 21 with apt"
      fi
    elif command -v dnf >/dev/null 2>&1; then
      echo "  Detected dnf. Installing java-21-openjdk..."
      if sudo dnf install -y java-21-openjdk 2>/dev/null; then
        echo "  ✓ JDK 21 installed"
        JAVA_SUPPORTED_HOME=$(detect_supported_java || true)
      else
        echo "  WARN: Failed to install JDK 21 with dnf"
      fi
    fi
  fi
  
  if [[ -n "$JAVA_SUPPORTED_HOME" ]]; then
    export JAVA_HOME="$JAVA_SUPPORTED_HOME"
    export PATH="$JAVA_HOME/bin:$PATH"
    export ORG_GRADLE_JAVA_HOME="$JAVA_HOME"
    echo "==> Using Java: $JAVA_HOME ($(java -version 2>&1 | head -n1))"
  else
    echo ""
    echo "✗ Android build skipped: JDK 17 or 21 not found and auto-install failed"
    echo ""
    echo "To install manually:"
    echo "  Arch/CachyOS: sudo pacman -S --needed jdk21-openjdk && sudo archlinux-java set java-21-openjdk"
    echo "  Ubuntu/Debian: sudo apt-get install openjdk-21-jdk"
    echo "  Fedora/RHEL: sudo dnf install java-21-openjdk"
    echo ""
    BUILD_ANDROID=0
  fi
  
  if [[ $BUILD_ANDROID -eq 1 ]]; then
    # Ensure Android SDK has necessary components
    mkdir -p "$ANDROID_SDK_ROOT"
    
    # Download cmdline-tools if missing
    ensure_cmdline_tools() {
      local TARGET_SDK="$1"
      local CT_DIR="$TARGET_SDK/cmdline-tools/latest"
      if [[ -x "$CT_DIR/bin/sdkmanager" ]]; then
        return 0
      fi
      echo "==> Installing Android cmdline-tools"
      mkdir -p "$TARGET_SDK/cmdline-tools"
      local ZIP_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
      local TMP_ZIP
      TMP_ZIP="$(mktemp -t cmdline-tools-XXXXXX.zip)"
      if command -v curl >/dev/null 2>&1; then
        curl -L --fail -o "$TMP_ZIP" "$ZIP_URL" || return 1
      elif command -v wget >/dev/null 2>&1; then
        wget -O "$TMP_ZIP" "$ZIP_URL" || return 1
      else
        echo "ERROR: Neither curl nor wget found"
        return 1
      fi
      local TMP_DIR
      TMP_DIR="$(mktemp -d -t cmdline-tools-XXXXXX)"
      unzip -q "$TMP_ZIP" -d "$TMP_DIR" || { rm -f "$TMP_ZIP"; return 1; }
      mkdir -p "$CT_DIR"
      if [[ -d "$TMP_DIR/cmdline-tools" ]]; then
        cp -a "$TMP_DIR/cmdline-tools/." "$CT_DIR/" || true
      else
        cp -a "$TMP_DIR/." "$CT_DIR/" || true
      fi
      rm -rf "$TMP_ZIP" "$TMP_DIR" || true
    }
    
    if [[ -w "$ANDROID_SDK_ROOT" ]]; then
      ensure_cmdline_tools "$ANDROID_SDK_ROOT" || true
    fi
    
    # Configure Flutter to use Android SDK
    "$FLUTTER_BIN" config --android-sdk "$ANDROID_SDK_ROOT" || true
    
    # Write local.properties
    if [[ -n "$ANDROID_SDK_ROOT" ]]; then
      {
        echo "sdk.dir=$ANDROID_SDK_ROOT"
      } > "$SCRIPT_DIR/android/local.properties"
    fi
    
    # Accept licenses if sdkmanager is available
    if [[ -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
      echo "==> Accepting Android SDK licenses"
      yes | "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_SDK_ROOT" --licenses >/dev/null 2>&1 || true
      
      # Install required components
      echo "==> Installing required Android SDK components"
      "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_SDK_ROOT" --install "platform-tools" "platforms;android-36" "build-tools;36.0.0" "ndk;27.0.12077973" || true
    fi
    
    # Add platform-tools to PATH for adb
    if [[ -d "$ANDROID_SDK_ROOT/platform-tools" ]]; then
      export PATH="$ANDROID_SDK_ROOT/platform-tools:$PATH"
    fi
    
    echo ""
    echo "==> Building Android APKs (all flavors)"
    
    # Build OSS flavor
    if "$FLUTTER_BIN" build apk --release --flavor oss 2>&1; then
      echo "  ✓ OSS APK built"
      OSS_SUCCESS=1
    else
      echo "  ✗ OSS APK failed"
      OSS_SUCCESS=0
    fi
    
    # Build Play flavor
    if "$FLUTTER_BIN" build apk --release --flavor play 2>&1; then
      echo "  ✓ Play APK built"
      PLAY_SUCCESS=1
    else
      echo "  ✗ Play APK failed"
      PLAY_SUCCESS=0
    fi
    
    # Build AAB for Play Store
    echo ""
    echo "==> Building Android App Bundle (Play Store)"
    if "$FLUTTER_BIN" build appbundle --release --flavor play 2>&1; then
      echo "  ✓ Play AAB built"
      AAB_SUCCESS=1
    else
      echo "  ✗ Play AAB failed"
      AAB_SUCCESS=0
    fi
    
    if [[ $OSS_SUCCESS -eq 1 ]] || [[ $PLAY_SUCCESS -eq 1 ]] || [[ $AAB_SUCCESS -eq 1 ]]; then
      ANDROID_SUCCESS=1
      echo ""
      echo "✓ Android builds completed"
      [[ $OSS_SUCCESS -eq 1 ]] && echo "  APK (OSS):  build/app/outputs/flutter-apk/app-oss-release.apk"
      [[ $PLAY_SUCCESS -eq 1 ]] && echo "  APK (Play): build/app/outputs/flutter-apk/app-play-release.apk"
      [[ $AAB_SUCCESS -eq 1 ]] && echo "  AAB (Play): build/app/outputs/bundle/playRelease/app-play-release.aab"
    else
      echo ""
      echo "✗ All Android builds failed"
    fi
    echo ""
  fi
fi

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                        Build Summary                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

TOTAL_REQUESTED=0
TOTAL_SUCCESS=0

if [[ $BUILD_LINUX -eq 1 ]]; then
  TOTAL_REQUESTED=$((TOTAL_REQUESTED + 1))
  if [[ $LINUX_SUCCESS -eq 1 ]]; then
    TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
    echo "✓ Linux:   build/linux/x64/release/bundle/grocery_guardian"
  else
    echo "✗ Linux:   FAILED"
  fi
fi

if [[ $BUILD_WEB -eq 1 ]]; then
  TOTAL_REQUESTED=$((TOTAL_REQUESTED + 1))
  if [[ $WEB_SUCCESS -eq 1 ]]; then
    TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
    echo "✓ Web:     build/web/"
  else
    echo "✗ Web:     FAILED"
  fi
fi

if [[ $BUILD_ANDROID -eq 1 ]]; then
  TOTAL_REQUESTED=$((TOTAL_REQUESTED + 1))
  if [[ $ANDROID_SUCCESS -eq 1 ]]; then
    TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
    echo "✓ Android: build/app/outputs/ (APK & AAB)"
  else
    echo "✗ Android: FAILED"
  fi
fi

echo ""
echo "Completed: $TOTAL_SUCCESS/$TOTAL_REQUESTED builds successful"
echo ""

if [[ $TOTAL_SUCCESS -eq $TOTAL_REQUESTED ]]; then
  exit 0
else
  exit 1
fi
