#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p build/releases

flutter clean
flutter pub get

flutter build apk --release --target-platform android-arm64
flutter build appbundle --release
flutter build ios --release --no-codesign
flutter build macos --release
flutter build windows --release

echo "Builds completed. Outputs are under build/"
