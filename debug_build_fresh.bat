@echo off
REM Configure wireless debugging endpoint (IP:PORT)
set "WIRELESS_ENDPOINT=192.168.0.244:40183"
REM Forcefully delete build folder
rmdir /s /q build 2>nul

REM Forcefully delete .dart_tool folder
rmdir /s /q .dart_tool 2>nul

REM Forcefully delete iOS ephemeral folder
rmdir /s /q ios\Flutter\ephemeral 2>nul

REM Forcefully delete Linux ephemeral folder
rmdir /s /q linux\flutter\ephemeral 2>nul

REM Forcefully delete macOS ephemeral folder
rmdir /s /q macos\Flutter\ephemeral 2>nul

REM Forcefully delete Windows ephemeral folder
rmdir /s /q windows\flutter\ephemeral 2>nul

echo Folders deleted. Running flutter clean...
cmd /c flutter clean

echo Running flutter pub get...
cmd /c flutter pub get

REM Try to connect to wireless device via ADB (ignore errors if adb missing)
echo Attempting ADB connect to %WIRELESS_ENDPOINT% ...
adb connect %WIRELESS_ENDPOINT% >nul 2>nul

REM Check for wireless and USB devices (avoid parsing issues with parentheses)
set "WIRELESS_FOUND="
set "USB_FOUND="
set "DEVICE_ID="

REM Prefer the explicit wireless endpoint if present in devices
flutter devices | findstr /i /c:"%WIRELESS_ENDPOINT%" >nul
if not errorlevel 1 set "WIRELESS_FOUND=1"
if defined WIRELESS_FOUND set "DEVICE_ID=%WIRELESS_ENDPOINT%"

if defined WIRELESS_FOUND (
    echo Running flutter run on wireless device ^(press q or Ctrl+C to quit^)...
    flutter run -d %DEVICE_ID%
    goto :end
)

flutter devices | findstr /i /c:"usb" >nul && set "USB_FOUND=1"
if defined USB_FOUND (
    echo Running flutter run on USB device ^(press q or Ctrl+C to quit^)...
    flutter run
    goto :end
)

echo No wireless or USB device connected. Please connect a device.
:end
cls
echo Terminal cleared. You can now run more commands.
pause