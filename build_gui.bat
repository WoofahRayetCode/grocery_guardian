@echo off
REM ============================================================================
REM Grocery Guardian - Consolidated Build GUI Script for Windows
REM ============================================================================
REM This script provides a unified GUI menu for all build options:
REM - Debug builds (Android run/install)
REM - Release builds (APK/AAB)
REM - Play Store builds
REM - Multi-platform builds
REM - Platform-specific targets (Linux, Web, macOS, Windows)
REM ============================================================================

setlocal enabledelayedexpansion

REM Optimize for Intel Core Ultra 9 275HX (24 cores)
set FLUTTER_BUILD_PARALLELISM=24
set NUMBER_OF_PROCESSORS=24

cls

:menu
cls
echo.
echo ╔══════════════════════════════════════════════════════════════════════╗
echo ║           GROCERY GUARDIAN - BUILD SYSTEM                           ║
echo ║                  Consolidated Build Script                          ║
echo ╚══════════════════════════════════════════════════════════════════════╝
echo.
echo Choose a build option:
echo.
echo ANDROID BUILDS:
echo   1. Debug Build - Fresh Run (clean build + run on device)
echo   2. Release Build - Fresh (clean build + APK)
echo   3. Release Build - Install on Device
echo   4. Play Store Build (AAB with ads, no donations)
echo.
echo DESKTOP BUILDS:
echo   5. Linux Desktop Build
echo   6. macOS Desktop Build
echo   7. Windows Desktop Build
echo   8. Web Build
echo.
echo MULTI-PLATFORM:
echo   9. Build All Platforms (Linux, Web, Android)
echo  10. Build Android Only (all variants)
echo.
echo UTILITIES:
echo  11. Flutter Clean ^& Pub Get
echo  12. Configure Wireless Device (192.168.0.244:40183)
echo  13. Show Connected Devices
echo  14. Exit
echo.
set /p choice="Enter your choice (1-14): "

if "%choice%"=="1" goto debug_build
if "%choice%"=="2" goto release_build
if "%choice%"=="3" goto release_install
if "%choice%"=="4" goto play_build
if "%choice%"=="5" goto linux_build
if "%choice%"=="6" goto macos_build
if "%choice%"=="7" goto windows_build
if "%choice%"=="8" goto web_build
if "%choice%"=="9" goto all_platforms
if "%choice%"=="10" goto android_only
if "%choice%"=="11" goto clean_and_get
if "%choice%"=="12" goto configure_wireless
if "%choice%"=="13" goto show_devices
if "%choice%"=="14" exit /b 0
echo Invalid choice. Please try again.
timeout /t 2 /nobreak >nul
goto menu

:debug_build
cls
echo.
echo [*] Starting DEBUG BUILD - Fresh Run
echo.
echo Checking for Flutter installation...
where flutter >nul 2>&1
if errorlevel 1 (
    echo.
    echo [ERROR] Flutter not found in system PATH!
    echo.
    echo Please install Flutter:
    echo   1. Visit: https://flutter.dev/docs/get-started/install/windows
    echo   2. Download and extract Flutter SDK
    echo   3. Add Flutter\bin to your system PATH
    echo   4. Restart terminal and run: flutter doctor
    echo.
    echo Quick install:
    echo   See FLUTTER_SETUP.md for detailed instructions
    echo.
    pause
    goto menu
)
call :clean_build_artifacts
echo Running flutter clean...
call flutter clean
echo Running flutter pub get...
call flutter pub get
echo.
echo Attempting to connect wireless device (192.168.0.244:40183)...
call adb connect 192.168.0.244:40183 >nul 2>nul
echo.
echo Checking for devices...
call flutter devices
echo.
echo Running flutter run with oss flavor (press q or Ctrl+C to quit)...
call flutter run --flavor oss
echo.
echo Debug build completed. Press any key to return to menu...
pause >nul
goto menu

:release_build
cls
echo.
echo [*] Starting RELEASE BUILD - Fresh APK
echo.
call :clean_build_artifacts
echo Running flutter clean...
call flutter clean
echo Running flutter pub get...
call flutter pub get
echo.
echo Building release APK...
call flutter build apk --release
echo.
if exist "build\app\outputs\flutter-apk\app-oss-release.apk" (
    echo [+] APK built successfully!
    echo Location: build\app\outputs\flutter-apk\app-oss-release.apk
) else (
    echo [-] APK build may have failed. Check output above.
)
echo.
echo Release build completed. Press any key to return to menu...
pause >nul
goto menu

:release_install
cls
echo.
echo [*] Starting RELEASE BUILD - Install on Device
echo.
call :clean_build_artifacts
echo Running flutter clean...
call flutter clean
echo Running flutter pub get...
call flutter pub get
echo.
echo Building release APK (oss flavor)...
call flutter build apk --release --flavor oss
echo.
echo Installing on device...
call flutter install --flavor oss
echo.
echo Installation completed. Press any key to return to menu...
pause >nul
goto menu

:play_build
cls
echo.
echo [*] Starting PLAY STORE BUILD (AAB)
echo    Features: Ads enabled, Donations disabled
echo.
call :clean_build_artifacts
echo Running flutter clean...
call flutter clean
echo Running flutter pub get...
call flutter pub get
echo.
echo Building Play Store AAB...
call flutter build appbundle --release --flavor play ^
    --dart-define=DONATIONS=false ^
    --dart-define=ADS=true ^
    --obfuscate --split-debug-info=build\symbols
echo.
if exist "build\app\outputs\bundle\playRelease\app-play-release.aab" (
    echo [+] AAB built successfully!
    echo Location: build\app\outputs\bundle\playRelease\app-play-release.aab
) else (
    echo [-] AAB build may have failed. Check output above.
)
echo.
echo Play Store build completed. Press any key to return to menu...
pause >nul
goto menu

:linux_build
cls
echo.
echo [*] Starting LINUX DESKTOP BUILD
echo.
echo Running flutter clean...
call flutter clean
echo Running flutter pub get...
call flutter pub get
echo.
echo Building for Linux...
call flutter build linux --release
echo.
if exist "build\linux\x64\release\bundle" (
    echo [+] Linux build completed successfully!
    echo Location: build\linux\x64\release\bundle
) else (
    echo [-] Linux build may have failed. Check output above.
)
echo.
echo Linux build completed. Press any key to return to menu...
pause >nul
goto menu

:macos_build
cls
echo.
echo [*] Starting macOS DESKTOP BUILD
echo.
echo Running flutter clean...
call flutter clean
echo Running flutter pub get...
call flutter pub get
echo.
echo Building for macOS...
call flutter build macos --release
echo.
if exist "build\macos\Build\Products\Release" (
    echo [+] macOS build completed successfully!
    echo Location: build\macos\Build\Products\Release
) else (
    echo [-] macOS build may have failed. Check output above.
)
echo.
echo macOS build completed. Press any key to return to menu...
pause >nul
goto menu

:windows_build
cls
echo.
echo [*] Starting WINDOWS DESKTOP BUILD
echo.
echo Running flutter clean...
call flutter clean
echo Running flutter pub get...
call flutter pub get
echo.
echo Building for Windows...
call flutter build windows --release
echo.
if exist "build\windows\x64\runner\Release" (
    echo [+] Windows build completed successfully!
    echo Location: build\windows\x64\runner\Release
) else (
    echo [-] Windows build may have failed. Check output above.
)
echo.
echo Windows build completed. Press any key to return to menu...
pause >nul
goto menu

:web_build
cls
echo.
echo [*] Starting WEB BUILD
echo.
echo Running flutter clean...
call flutter clean
echo Running flutter pub get...
call flutter pub get
echo.
echo Building for web...
call flutter build web --release
echo.
if exist "build\web" (
    echo [+] Web build completed successfully!
    echo Location: build\web
) else (
    echo [-] Web build may have failed. Check output above.
)
echo.
echo Web build completed. Press any key to return to menu...
pause >nul
goto menu

:all_platforms
cls
echo.
echo [*] Building ALL PLATFORMS: Linux, Web, Android
echo.
call :clean_build_artifacts
echo Running flutter clean...
call flutter clean
echo Running flutter pub get...
call flutter pub get
echo.
echo Building for Linux...
call flutter build linux --release
echo [+] Linux build completed
echo.
echo Building for Web...
call flutter build web --release
echo [+] Web build completed
echo.
echo Building for Android (APK - oss flavor)...
call flutter build apk --release --flavor oss
echo [+] Android build completed
echo.
echo All platform builds completed. Press any key to return to menu...
pause >nul
goto menu

:android_only
cls
echo.
echo [*] Building ANDROID VARIANTS
echo.
call :clean_build_artifacts
echo Running flutter clean...
call flutter clean
echo Running flutter pub get...
call flutter pub get
echo.
echo 1. Building OSS release APK...
call flutter build apk --release --flavor oss
echo [+] OSS APK completed
echo.
echo 2. Building Play Store AAB (ads on, donations off)...
call flutter build appbundle --release --flavor play ^
    --dart-define=DONATIONS=false ^
    --dart-define=ADS=true ^
    --obfuscate --split-debug-info=build\symbols
echo [+] Play Store AAB completed
echo.
echo Android variants build completed. Press any key to return to menu...
pause >nul
goto menu

:clean_and_get
cls
echo.
echo [*] Cleaning project and fetching dependencies
echo.
echo Removing build artifacts...
rmdir /s /q build 2>nul
rmdir /s /q .dart_tool 2>nul
rmdir /s /q ios\Flutter\ephemeral 2>nul
rmdir /s /q linux\flutter\ephemeral 2>nul
rmdir /s /q macos\Flutter\ephemeral 2>nul
rmdir /s /q windows\flutter\ephemeral 2>nul
echo.
echo Running flutter clean...
call flutter clean
echo.
echo Running flutter pub get...
call flutter pub get
echo.
echo [+] Clean and pub get completed. Press any key to return to menu...
pause >nul
goto menu

:configure_wireless
cls
echo.
echo [*] Configuring Wireless Device
echo.
set "WIRELESS_ENDPOINT=192.168.0.244:40183"
echo Attempting to connect to %WIRELESS_ENDPOINT%...
call adb connect %WIRELESS_ENDPOINT%
echo.
echo [+] Connection attempt completed. Press any key to return to menu...
pause >nul
goto menu

:show_devices
cls
echo.
echo [*] Connected Devices
echo.
call flutter devices
echo.
echo Press any key to return to menu...
pause >nul
goto menu

:clean_build_artifacts
echo Cleaning build artifacts...
rmdir /s /q build 2>nul
rmdir /s /q .dart_tool 2>nul
rmdir /s /q ios\Flutter\ephemeral 2>nul
rmdir /s /q linux\flutter\ephemeral 2>nul
rmdir /s /q macos\Flutter\ephemeral 2>nul
rmdir /s /q windows\flutter\ephemeral 2>nul
goto :eof
