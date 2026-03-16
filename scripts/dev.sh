#!/usr/bin/env bash
# ABOUTME: Development convenience script for Factory Floor.
# ABOUTME: Usage: ./scripts/dev.sh [build|run|test|clean]

set -e

PROJECT="FactoryFloor.xcodeproj"
SCHEME="FactoryFloor"
TEST_SCHEME="FactoryFloorTests"
APP_NAME="Factory Floor"
URL_SCHEME="factoryfloor"

case "${1:-build}" in
  build)
    xcodegen generate
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug build
    ;;
  run)
    shift 2>/dev/null || true
    DIR=$(cd "${1:-.}" 2>/dev/null && pwd)
    pkill -f "$APP_NAME.app/Contents/MacOS" 2>/dev/null || true
    sleep 0.5
    open "$URL_SCHEME://$DIR"
    ;;
  br)
    shift 2>/dev/null || true
    DIR=$(cd "${1:-.}" 2>/dev/null && pwd)
    xcodegen generate
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug build
    pkill -f "$APP_NAME.app/Contents/MacOS" 2>/dev/null || true
    sleep 0.5
    open "$URL_SCHEME://$DIR"
    ;;
  test)
    xcodegen generate
    xcodebuild -project "$PROJECT" -scheme "$TEST_SCHEME" -configuration Debug test
    ;;
  clean)
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug clean 2>/dev/null || true
    rm -rf ~/Library/Developer/Xcode/DerivedData/FactoryFloor-*
    ;;
  *)
    echo "Usage: ./scripts/dev.sh [command] [directory]"
    echo ""
    echo "  build    Build (debug)"
    echo "  run      Kill and relaunch (optionally with a directory)"
    echo "  br       Build and run"
    echo "  test     Run tests"
    echo "  clean    Clean build artifacts"
    ;;
esac
