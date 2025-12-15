#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="/var/www/ark/hesabixUI/hesabix_ui"
cd "$PROJECT_ROOT"

FLUTTER_SDK_PATH="${FLUTTER_SDK_PATH:-/root/flutter}"
FLUTTER_BIN="$FLUTTER_SDK_PATH/bin/flutter"

if [[ ! -x "$FLUTTER_BIN" ]]; then
  echo "Flutter binary not found at $FLUTTER_BIN"
  echo "Set FLUTTER_SDK_PATH to your Flutter SDK path and retry."
  exit 1
fi

echo "Flutter SDK: $("$FLUTTER_BIN" --version | head -n 1)"
echo "Running flutter pub get..."
"$FLUTTER_BIN" pub get

echo "Building Android App Bundle (release)..."
"$FLUTTER_BIN" build appbundle --release "$@"

echo "Building split APKs (release)..."
"$FLUTTER_BIN" build apk --release --split-per-abi "$@"

echo "Outputs:"
echo " - AAB: $PROJECT_ROOT/build/app/outputs/bundle/release/app-release.aab"
echo " - APKs: $PROJECT_ROOT/build/app/outputs/flutter-apk/"


