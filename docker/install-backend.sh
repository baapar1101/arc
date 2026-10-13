#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="${HESABIX_BACKEND_ROOT:-/opt/hesabix-backend}"
REPO_URL="${REPO_URL:-https://source.hesabix.ir/hesabix/arc.git}"
BRANCH="${BRANCH:-}"
API_PORT="${API_PORT:-8000}"

fail() { echo "Hesabix backend installer: $*" >&2; exit 1; }

[[ "${EUID:-$(id -u)}" -eq 0 ]] || fail "Run as root, for example: sudo bash install-backend.sh"
command -v git >/dev/null 2>&1 || fail "Git is required."
command -v docker >/dev/null 2>&1 || fail "Install Docker Engine before installing Hesabix."
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is required (docker compose)."
command -v openssl >/dev/null 2>&1 || fail "OpenSSL is required to generate installation secrets."
[[ "${API_PORT}" =~ ^[0-9]{1,5}$ ]] && (( API_PORT >= 1 && API_PORT <= 65535 )) || fail "API_PORT must be between 1 and 65535."

if [[ -z "${BRANCH}" ]]; then
  BRANCH="$(git ls-remote --symref "${REPO_URL}" HEAD 2>/dev/null | awk '$1 == "ref:" { sub("refs/heads/", "", $2); print $2; exit}')"
  BRANCH="${BRANCH:-main}"
fi

mkdir -p "${APP_ROOT}"
if [[ -e "${APP_ROOT}/source" && ! -d "${APP_ROOT}/source/.git" ]]; then
  fail "${APP_ROOT}/source exists but is not a Git checkout. Move it aside before installing."
fi

if [[ ! -d "${APP_ROOT}/source/.git" ]]; then
  echo "Cloning ${REPO_URL} (${BRANCH})..."
  git clone --branch "${BRANCH}" --single-branch "${REPO_URL}" "${APP_ROOT}/source"
fi

if [[ ! -f "${APP_ROOT}/.env" ]]; then
  db_password="$(openssl rand -hex 32)"
  captcha_secret="$(openssl rand -hex 32)"
  share_link_secret="$(openssl rand -hex 32)"
  encryption_key="$(openssl rand -base64 32 | tr '/+' '_-')"
  webhook_secret="$(openssl rand -hex 32)"
  cat >"${APP_ROOT}/.env" <<ENV
REPO_URL=${REPO_URL}
BRANCH=${BRANCH}
API_PORT=${API_PORT}
API_BIND_IP=0.0.0.0
DB_USER=hesabix
DB_PASSWORD=${db_password}
DB_NAME=hesabix
CAPTCHA_SECRET=${captcha_secret}
SHARE_LINK_SECRET=${share_link_secret}
ENCRYPTION_KEY=${encryption_key}
WALLET_WEBHOOK_SECRET=${webhook_secret}
REDIS_ENABLED=false
UVICORN_WORKERS=2
DB_POOL_SIZE=4
DB_MAX_OVERFLOW=2
ENV
  chmod 600 "${APP_ROOT}/.env"
else
  echo "Using existing configuration at ${APP_ROOT}/.env; secrets and selected port were preserved."
  for required_key in DB_PASSWORD CAPTCHA_SECRET SHARE_LINK_SECRET ENCRYPTION_KEY WALLET_WEBHOOK_SECRET; do
    existing_value="$(sed -n "s/^${required_key}=//p" "${APP_ROOT}/.env" | tail -n 1)"
    if [[ -z "${existing_value//[[:space:]]/}" ]]; then
      fail "${APP_ROOT}/.env is missing ${required_key}; restore the original configuration before continuing."
    fi
  done
fi

install -m 0755 "${APP_ROOT}/source/scripts/hesabix-backend" "${APP_ROOT}/hesabix-backend"
cat >/usr/local/bin/hesabix-backend <<WRAPPER
#!/bin/sh
export HESABIX_BACKEND_ROOT='${APP_ROOT}'
exec '${APP_ROOT}/hesabix-backend' "\$@"
WRAPPER
chmod 0755 /usr/local/bin/hesabix-backend

echo "Installing the Hesabix backend services..."
"${APP_ROOT}/hesabix-backend" install

echo
echo "Install directory: ${APP_ROOT}"
echo "API port: ${API_PORT}"
echo "Health endpoint: http://<server-ip>:${API_PORT}/api/v1/health"
echo "Management: sudo hesabix-backend update | status | logs | backup"
