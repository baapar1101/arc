#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.dev}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.googleapis.com}"

if ! command -v flutter >/dev/null 2>&1; then
  FLUTTER_DIR="${FLUTTER_ROOT:-/tmp/flutter}"
  rm -rf "$FLUTTER_DIR"
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
  export PATH="$FLUTTER_DIR/bin:$PATH"
fi

flutter config --enable-web

chmod +x build_web.sh
./build_web.sh   --project hesabixUI/hesabix_ui   --mode release   --clean   --install-deps   --api-base-url https://tamastore.ir

OUT="hesabixUI/hesabix_ui/build/web"
test -s "$OUT/index.html"
test -s "$OUT/version.json"

echo "Vercel Flutter build ready: $OUT"
cat "$OUT/version.json"
