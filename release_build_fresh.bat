@echo off
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

echo Building release APK...
cmd /c flutter build apk --release

REM Check for wireless and USB devices
set WIRELESS_FOUND=
set USB_FOUND=
for /f "tokens=*" %%i in ('flutter devices') do (
    echo %%i | findstr /i /c:"wireless" >nul && set WIRELESS_FOUND=1
)

if defined WIRELESS_FOUND (
    echo Installing APK on wireless device...
    cmd /c flutter install
    goto :end
)

REM If no wireless, check for USB
for /f "tokens=*" %%i in ('flutter devices') do (
    echo %%i | findstr /i /c:"usb" >nul && set USB_FOUND=1
)

if defined USB_FOUND (
    echo Installing APK on USB device...
    cmd /c flutter install
    goto :end
)

echo No wireless or USB device connected. Please connect a device.
:end
echo Done!
pause