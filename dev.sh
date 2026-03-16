#!/usr/bin/env bash
# ABOUTME: Dev script for building and running Factory Floor.
# ABOUTME: Usage: ./dev.sh [command] [args]

set -e

PROJECT="FactoryFloor.xcodeproj"
SCHEME="FactoryFloor"
TEST_SCHEME="FactoryFloorTests"
URL_SCHEME="factoryfloor"
APP_NAME="Factory Floor"

# Resolve a path to absolute
resolve_dir() {
  if [ -n "$1" ]; then
    cd "$1" 2>/dev/null && pwd
  fi
}

case "${1:-run}" in
  build)
    xcodegen generate
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug build
    ;;
  build-release)
    xcodegen generate
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release build
    ;;
  test)
    xcodegen generate
    xcodebuild -project "$PROJECT" -scheme "$TEST_SCHEME" -configuration Debug test
    ;;
  run)
    shift 2>/dev/null || true
    DIR=$(resolve_dir "${1:-.}")
    open "$URL_SCHEME://$DIR"
    ;;
  br)
    shift 2>/dev/null || true
    DIR=$(resolve_dir "${1:-.}")
    xcodegen generate
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug build
    pkill -f "$APP_NAME.app/Contents/MacOS" 2>/dev/null || true
    sleep 0.5
    open "$URL_SCHEME://$DIR"
    ;;
  br-release)
    shift 2>/dev/null || true
    DIR=$(resolve_dir "${1:-.}")
    xcodegen generate
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release build
    pkill -f "$APP_NAME.app/Contents/MacOS" 2>/dev/null || true
    sleep 0.5
    APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*/$SCHEME-*/Build/Products/Release/$APP_NAME.app" -type d 2>/dev/null | head -1)
    open -a "$APP" --args "$DIR"
    ;;
  clean)
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug clean 2>/dev/null || true
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release clean 2>/dev/null || true
    rm -rf ~/Library/Developer/Xcode/DerivedData/FactoryFloor-*
    ;;
  *)
    echo "Usage: ./dev.sh [command] [directory]"
    echo ""
    echo "  build          Build (debug)"
    echo "  build-release  Build (release, optimized)"
    echo "  test           Run tests"
    echo "  run            Run the app, optionally with a directory"
    echo "  br             Build (debug) and run"
    echo "  br-release     Build (release) and run"
    echo "  clean          Clean build artifacts"
    ;;
esac
