#!/usr/bin/env bash
# Content-address entrypoints: Flutter's fixed filenames can retain old UI in
# HTTP caches even after version.json changes and service workers are removed.
set -euo pipefail
build_dir="${1:?Usage: stamp_web_entrypoints.sh BUILD_DIRECTORY}"
for entry in main.dart.js flutter_bootstrap.js index.html; do
  test -f "$build_dir/$entry" || { echo "Missing web entrypoint: $entry" >&2; exit 1; }
done
main_hash="$(sha256sum "$build_dir/main.dart.js" | cut -c1-16)"
main_name="main.${main_hash}.dart.js"
cp "$build_dir/main.dart.js" "$build_dir/$main_name"
# Idempotent, including a previous content-addressed filename.
sed -E -i "s/main(\.[a-f0-9]{16})?\.dart\.js/$main_name/g" "$build_dir/flutter_bootstrap.js"
bootstrap_hash="$(sha256sum "$build_dir/flutter_bootstrap.js" | cut -c1-16)"
bootstrap_name="flutter_bootstrap.${bootstrap_hash}.js"
cp "$build_dir/flutter_bootstrap.js" "$build_dir/$bootstrap_name"
sed -E -i "s/flutter_bootstrap(\.[a-f0-9]{16})?\.js/$bootstrap_name/g" "$build_dir/index.html"
echo "Web entrypoints: $bootstrap_name -> $main_name"
