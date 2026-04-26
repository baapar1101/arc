#!/bin/sh
# تولید فایل .mo از .po — ابتدا msgfmt، در نبود آن اسکریپت Python
set -e
cd "$(dirname "$0")/.."
PY="$PWD/bin/po2mo.py"
for po in languages/*.po; do
  [ -e "$po" ] || continue
  mo="${po%.po}.mo"
  if command -v msgfmt >/dev/null 2>&1; then
    msgfmt -o "$mo" "$po"
  else
    python3 "$PY" "$po" "$mo"
  fi
  echo "Compiled: $mo"
done
