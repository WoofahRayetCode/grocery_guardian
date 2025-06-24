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

echo Installing APK on connected device...
cmd /c flutter install

echo Done!
pause