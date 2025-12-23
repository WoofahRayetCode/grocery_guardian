#!/bin/bash

# Build web version of Grocery Guardian
# Usage: ./build_web.sh [--release]

BUILD_MODE="debug"

# Check for --release flag
if [ "$1" = "--release" ]; then
  BUILD_MODE="release"
  echo "Building Grocery Guardian web (RELEASE)"
else
  echo "Building Grocery Guardian web (DEBUG)"
fi

# Clean previous build
echo ""
echo "Cleaning previous build..."
flutter clean

# Get dependencies
echo ""
echo "Getting dependencies..."
flutter pub get

# Build web app
echo ""
if [ "$BUILD_MODE" = "release" ]; then
  echo "Building web app in release mode..."
  flutter build web --release
else
  echo "Building web app in debug mode..."
  flutter build web --debug
fi

if [ $? -ne 0 ]; then
  echo ""
  echo "ERROR: Web build failed!"
  exit 1
fi

echo ""
echo ""
echo "Build completed successfully!"
echo "Web app is in: build/web/"
echo ""
echo "To serve locally, you can use:"
echo "  python3 -m http.server 8000 --directory build/web"
echo "Then open: http://localhost:8000"
echo ""
echo "Or use Flutter's built-in server:"
echo "  flutter run -d web-server"
echo ""
