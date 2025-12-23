#!/usr/bin/env bash
################################################################################
# Grocery Guardian - Consolidated Build GUI Script for Linux/MacOS
################################################################################
# This script provides a unified interactive menu for all build options:
# - Debug builds (Android run/install)
# - Release builds (APK/AAB)
# - Play Store builds
# - Multi-platform builds
# - Platform-specific targets (Linux, Web, macOS, Windows)
################################################################################

set -euo pipefail

# Optimize for Intel Core Ultra 9 275HX (24 cores)
export FLUTTER_BUILD_PARALLELISM=24
export MAKEFLAGS="-j24"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[*]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[+]${NC} $*"
}

log_error() {
    echo -e "${RED}[-]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $*"
}

pause_menu() {
    echo ""
    read -p "Press Enter to return to menu..."
}

# Resolve Flutter binary
resolve_flutter() {
    if [[ -n "${FLUTTER_BIN:-}" && -x "$FLUTTER_BIN" ]]; then
        echo "$FLUTTER_BIN"
    elif [[ -x "$SCRIPT_DIR/flutter/bin/flutter" ]]; then
        echo "$SCRIPT_DIR/flutter/bin/flutter"
    elif command -v flutter >/dev/null 2>&1; then
        command -v flutter
    else
        log_error "Flutter not found. Please install Flutter or include a bundled SDK."
        exit 1
    fi
}

FLUTTER_BIN=$(resolve_flutter)
log_info "Using Flutter: $FLUTTER_BIN"

# Clean build artifacts
clean_build_artifacts() {
    log_info "Cleaning build artifacts..."
    rm -rf build .dart_tool
    rm -rf ios/Flutter/ephemeral
    rm -rf linux/flutter/ephemeral
    rm -rf macos/Flutter/ephemeral
    rm -rf windows/flutter/ephemeral
}

# ============================================================================
# Build Commands
# ============================================================================

debug_build() {
    clear
    log_info "DEBUG BUILD - Fresh Run"
    echo ""
    
    clean_build_artifacts
    
    log_info "Running flutter clean..."
    "$FLUTTER_BIN" clean
    
    log_info "Running flutter pub get..."
    "$FLUTTER_BIN" pub get
    
    log_info "Attempting to connect wireless device (192.168.0.244:40183)..."
    adb connect 192.168.0.244:40183 >/dev/null 2>&1 || true
    
    echo ""
    log_info "Checking for devices..."
    "$FLUTTER_BIN" devices
    echo ""
    
    log_info "Running flutter run with oss flavor (press q or Ctrl+C to quit)..."
    "$FLUTTER_BIN" run --flavor oss
    
    pause_menu
}

release_build() {
    clear
    log_info "RELEASE BUILD - Fresh APK"
    echo ""
    
    clean_build_artifacts
    
    log_info "Running flutter clean..."
    "$FLUTTER_BIN" clean
    
    log_info "Running flutter pub get..."
    "$FLUTTER_BIN" pub get
    
    log_info "Building release APK..."
    "$FLUTTER_BIN" build apk --release
    
    echo ""
    if [[ -f "build/app/outputs/flutter-apk/app-oss-release.apk" ]]; then
        log_success "APK built successfully!"
        log_info "Location: build/app/outputs/flutter-apk/app-oss-release.apk"
    else
        log_error "APK build may have failed. Check output above."
    fi
    
    pause_menu
}

release_install() {
    clear
    log_info "RELEASE BUILD - Install on Device"
    echo ""
    
    clean_build_artifacts
    
    log_info "Running flutter clean..."
    "$FLUTTER_BIN" clean
    
    log_info "Running flutter pub get..."
    "$FLUTTER_BIN" pub get
    
    log_info "Building release APK (oss flavor)..."
    "$FLUTTER_BIN" build apk --release --flavor oss
    
    echo ""
    log_info "Installing on device..."
    "$FLUTTER_BIN" install --flavor oss
    
    pause_menu
}

play_build() {
    clear
    log_info "PLAY STORE BUILD (AAB)"
    log_info "Features: Ads enabled, Donations disabled"
    echo ""
    
    clean_build_artifacts
    
    log_info "Running flutter clean..."
    "$FLUTTER_BIN" clean
    
    log_info "Running flutter pub get..."
    "$FLUTTER_BIN" pub get
    
    log_info "Building Play Store AAB..."
    "$FLUTTER_BIN" build appbundle --release --flavor play \
        --dart-define=DONATIONS=false \
        --dart-define=ADS=true \
        --obfuscate --split-debug-info=build/symbols
    
    echo ""
    if [[ -f "build/app/outputs/bundle/playRelease/app-play-release.aab" ]]; then
        log_success "AAB built successfully!"
        log_info "Location: build/app/outputs/bundle/playRelease/app-play-release.aab"
    else
        log_error "AAB build may have failed. Check output above."
    fi
    
    pause_menu
}

linux_build() {
    clear
    log_info "LINUX DESKTOP BUILD"
    echo ""
    
    log_info "Running flutter clean..."
    "$FLUTTER_BIN" clean
    
    log_info "Running flutter pub get..."
    "$FLUTTER_BIN" pub get
    
    log_info "Building for Linux..."
    "$FLUTTER_BIN" build linux --release
    
    echo ""
    if [[ -d "build/linux/x64/release/bundle" ]]; then
        log_success "Linux build completed successfully!"
        log_info "Location: build/linux/x64/release/bundle"
    else
        log_error "Linux build may have failed. Check output above."
    fi
    
    pause_menu
}

macos_build() {
    clear
    log_info "macOS DESKTOP BUILD"
    echo ""
    
    log_info "Running flutter clean..."
    "$FLUTTER_BIN" clean
    
    log_info "Running flutter pub get..."
    "$FLUTTER_BIN" pub get
    
    log_info "Building for macOS..."
    "$FLUTTER_BIN" build macos --release
    
    echo ""
    if [[ -d "build/macos/Build/Products/Release" ]]; then
        log_success "macOS build completed successfully!"
        log_info "Location: build/macos/Build/Products/Release"
    else
        log_error "macOS build may have failed. Check output above."
    fi
    
    pause_menu
}

windows_build() {
    clear
    log_info "WINDOWS DESKTOP BUILD"
    echo ""
    
    log_info "Running flutter clean..."
    "$FLUTTER_BIN" clean
    
    log_info "Running flutter pub get..."
    "$FLUTTER_BIN" pub get
    
    log_info "Building for Windows..."
    "$FLUTTER_BIN" build windows --release
    
    echo ""
    if [[ -d "build/windows/x64/runner/Release" ]]; then
        log_success "Windows build completed successfully!"
        log_info "Location: build/windows/x64/runner/Release"
    else
        log_error "Windows build may have failed. Check output above."
    fi
    
    pause_menu
}

web_build() {
    clear
    log_info "WEB BUILD"
    echo ""
    
    log_info "Running flutter clean..."
    "$FLUTTER_BIN" clean
    
    log_info "Running flutter pub get..."
    "$FLUTTER_BIN" pub get
    
    log_info "Building for web..."
    "$FLUTTER_BIN" build web --release
    
    echo ""
    if [[ -d "build/web" ]]; then
        log_success "Web build completed successfully!"
        log_info "Location: build/web"
    else
        log_error "Web build may have failed. Check output above."
    fi
    
    pause_menu
}

all_platforms() {
    clear
    log_info "Building ALL PLATFORMS: Linux, Web, Android"
    echo ""
    
    clean_build_artifacts
    
    log_info "Running flutter clean..."
    "$FLUTTER_BIN" clean
    
    log_info "Running flutter pub get..."
    "$FLUTTER_BIN" pub get
    
    echo ""
    log_info "Building for Linux..."
    "$FLUTTER_BIN" build linux --release
    log_success "Linux build completed"
    
    echo ""
    log_info "Building for Web..."
    "$FLUTTER_BIN" build web --release
    log_success "Web build completed"
    
    echo ""
    log_info "Building for Android (APK - oss flavor)..."
    "$FLUTTER_BIN" build apk --release --flavor oss
    log_success "Android build completed"
    
    echo ""
    log_success "All platform builds completed!"
    
    pause_menu
}

android_only() {
    clear
    log_info "Building ANDROID VARIANTS"
    echo ""
    
    clean_build_artifacts
    
    log_info "Running flutter clean..."
    "$FLUTTER_BIN" clean
    
    log_info "Running flutter pub get..."
    "$FLUTTER_BIN" pub get
    
    echo ""
    log_info "Building OSS release APK..."
    "$FLUTTER_BIN" build apk --release --flavor oss
    log_success "OSS APK completed"
    
    echo ""
    log_info "Building Play Store AAB (ads on, donations off)..."
    "$FLUTTER_BIN" build appbundle --release --flavor play \
        --dart-define=DONATIONS=false \
        --dart-define=ADS=true \
        --obfuscate --split-debug-info=build/symbols
    log_success "Play Store AAB completed"
    
    echo ""
    log_success "Android variants build completed!"
    
    pause_menu
}

clean_and_get() {
    clear
    log_info "Cleaning project and fetching dependencies"
    echo ""
    
    clean_build_artifacts
    
    log_info "Running flutter clean..."
    "$FLUTTER_BIN" clean
    
    echo ""
    log_info "Running flutter pub get..."
    "$FLUTTER_BIN" pub get
    
    echo ""
    log_success "Clean and pub get completed!"
    
    pause_menu
}

configure_wireless() {
    clear
    log_info "Configuring Wireless Device"
    echo ""
    
    WIRELESS_ENDPOINT="192.168.0.244:40183"
    log_info "Attempting to connect to $WIRELESS_ENDPOINT..."
    adb connect "$WIRELESS_ENDPOINT"
    
    echo ""
    log_success "Connection attempt completed!"
    
    pause_menu
}

show_devices() {
    clear
    log_info "Connected Devices"
    echo ""
    
    "$FLUTTER_BIN" devices
    
    echo ""
    pause_menu
}

# ============================================================================
# Main Menu
# ============================================================================

show_menu() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║           GROCERY GUARDIAN - BUILD SYSTEM                           ║"
    echo "║                  Consolidated Build Script                          ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Choose a build option:"
    echo ""
    echo -e "${CYAN}ANDROID BUILDS:${NC}"
    echo "  1. Debug Build - Fresh Run (clean build + run on device)"
    echo "  2. Release Build - Fresh (clean build + APK)"
    echo "  3. Release Build - Install on Device"
    echo "  4. Play Store Build (AAB with ads, no donations)"
    echo ""
    echo -e "${CYAN}DESKTOP BUILDS:${NC}"
    echo "  5. Linux Desktop Build"
    echo "  6. macOS Desktop Build"
    echo "  7. Windows Desktop Build"
    echo "  8. Web Build"
    echo ""
    echo -e "${CYAN}MULTI-PLATFORM:${NC}"
    echo "  9. Build All Platforms (Linux, Web, Android)"
    echo " 10. Build Android Only (all variants)"
    echo ""
    echo -e "${CYAN}UTILITIES:${NC}"
    echo " 11. Flutter Clean & Pub Get"
    echo " 12. Configure Wireless Device (192.168.0.244:40183)"
    echo " 13. Show Connected Devices"
    echo " 14. Exit"
    echo ""
    read -p "Enter your choice (1-14): " choice
}

# Main loop
while true; do
    show_menu
    
    case "$choice" in
        1) debug_build ;;
        2) release_build ;;
        3) release_install ;;
        4) play_build ;;
        5) linux_build ;;
        6) macos_build ;;
        7) windows_build ;;
        8) web_build ;;
        9) all_platforms ;;
        10) android_only ;;
        11) clean_and_get ;;
        12) configure_wireless ;;
        13) show_devices ;;
        14) log_info "Exiting..."; exit 0 ;;
        *) 
            log_error "Invalid choice. Please try again."
            sleep 2
            ;;
    esac
done
