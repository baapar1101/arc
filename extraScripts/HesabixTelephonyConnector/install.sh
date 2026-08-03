#!/usr/bin/env bash
# Bootstrap نصب Hesabix Telephony Connector روی Issabel/Asterisk
# یک خطی:
#   curl -fsSL https://source.hesabix.ir/hesabix/arc/raw/branch/master/extraScripts/HesabixTelephonyConnector/install.sh | sudo bash
set -euo pipefail

RAW_BASE="${HESABIX_PBX_RAW_BASE:-https://source.hesabix.ir/hesabix/arc/raw/branch/master/extraScripts/HesabixTelephonyConnector}"
INSTALL_DIR="${HESABIX_PBX_DIR:-/opt/HesabixTelephonyConnector}"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "با root اجرا کنید: curl ... | sudo bash" >&2
  exit 1
fi

echo "==> نصب Hesabix PBX Connector"
mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/app" "$INSTALL_DIR/systemd"

download() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 20 --max-time 120 "$url" -o "$out"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$out" "$url"
  else
    echo "curl یا wget لازم است." >&2
    exit 1
  fi
}

# اول خود CLI را بیاور تا بقیه کار را انجام دهد
echo "==> دریافت hesabix-pbx…"
download "${RAW_BASE}/bin/hesabix-pbx" "$INSTALL_DIR/bin/hesabix-pbx"
chmod +x "$INSTALL_DIR/bin/hesabix-pbx"
ln -sfn "$INSTALL_DIR/bin/hesabix-pbx" /usr/local/bin/hesabix-pbx

export HESABIX_PBX_DIR="$INSTALL_DIR"
export HESABIX_PBX_RAW_BASE="$RAW_BASE"

# نصب کامل
exec /usr/local/bin/hesabix-pbx install
