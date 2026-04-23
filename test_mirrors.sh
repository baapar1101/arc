#!/usr/bin/env bash
# بررسی در دسترس بودن آینهٔ واحد pub/storage — f.mirror.hesabix.ir

set -euo pipefail

PUB="https://f.mirror.hesabix.ir/pub"
STORAGE="https://f.mirror.hesabix.ir/gcs"

echo "=========================================="
echo "Hesabix Flutter mirror: $PUB + $STORAGE"
echo "=========================================="
echo ""

check_one() {
  local name="$1" url="$2"
  echo -n "🔍 $name ... "
  if timeout 12 curl -kfsS --connect-timeout 5 --max-time 10 -o /dev/null -I "$url" 2>/dev/null; then
    echo "OK"
    return 0
  fi
  if timeout 12 curl -fsS --connect-timeout 5 --max-time 10 -o /dev/null -I "$url" 2>/dev/null; then
    echo "OK (TLS)"
    return 0
  fi
  echo "FAIL"
  return 1
}

pub_ok=0
gcs_ok=0
check_one "Pub (health)" "$PUB" && pub_ok=1
check_one "GCS (health)" "$STORAGE" && gcs_ok=1

echo ""
if [[ "$pub_ok" -eq 1 && "$gcs_ok" -eq 1 ]]; then
  echo "export PUB_HOSTED_URL=\"$PUB\""
  echo "export FLUTTER_STORAGE_BASE_URL=\"$STORAGE\""
  echo ""
  exit 0
fi
echo "آینه در دسترس نیست — فایروال، DNS و Nginx (hesabixAPI/f.mirror.hesabix.ir.conf) را بررسی کنید."
exit 1
