@echo off
REM Forcefully delete build folder
rmdir /s /q build 2>nul

REM Configure wireless debugging endpoint (IP:PORT)
set "WIRELESS_ENDPOINT=192.168.0.244:40183"
REM Forcefully delete .dart_tool folder
rmdir /s /q .dart_tool 2>nul

REM Try to connect to wireless device via ADB (ignore errors if adb missing)
echo Attempting ADB connect to %WIRELESS_ENDPOINT% ...
adb connect %WIRELESS_ENDPOINT% >nul 2>nul

REM Forcefully delete iOS ephemeral folder
rmdir /s /q ios\Flutter\ephemeral 2>nul

set "DEVICE_ID="
REM Forcefully delete Linux ephemeral folder
rmdir /s /q linux\flutter\ephemeral 2>nul

REM Forcefully delete macOS ephemeral folder
rmdir /s /q macos\Flutter\ephemeral 2>nul

REM Forcefully delete Windows ephemeral folder
rmdir /s /q windows\flutter\ephemeral 2>nul
REM Prefer the explicit wireless endpoint if present in devices
flutter devices | findstr /i /c:"%WIRELESS_ENDPOINT%" >nul
if not errorlevel 1 set "WIRELESS_FOUND=1"
if defined WIRELESS_FOUND set "DEVICE_ID=%WIRELESS_ENDPOINT%"

if defined WIRELESS_FOUND (
    echo Installing APK on wireless device %DEVICE_ID% ...
    cmd /c flutter install -d %DEVICE_ID%
    goto :end
)

echo Folders deleted. Running flutter clean...
cmd /c flutter clean

echo Running flutter pub get...
cmd /c flutter pub get

echo Building release APK...
cmd /c flutter build apk --release

REM Check for wireless and USB devices (avoid parsing issues with parentheses)
set "WIRELESS_FOUND="
set "USB_FOUND="

flutter devices | findstr /i /c:"wireless" >nul && set "WIRELESS_FOUND=1"
if defined WIRELESS_FOUND (
    echo Installing APK on wireless device...
    cmd /c flutter install
    goto :end
)

flutter devices | findstr /i /c:"usb" >nul && set "USB_FOUND=1"
if defined USB_FOUND (
    echo Installing APK on USB device...
    cmd /c flutter install
    goto :end
)

echo No wireless or USB device connected. Please connect a device.
:end
echo Done!
pause