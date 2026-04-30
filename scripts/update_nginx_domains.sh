#!/usr/bin/env bash
# به‌روزرسانی فقط دامنه‌های Nginx (بدون دست زدن به دیتابیس یا سرویس‌های دیگر)
# اجرا: sudo bash scripts/update_nginx_domains.sh
# دامنه‌ها از .deploy_env خوانده می‌شوند.
# TLS: اگر برای API_DOMAIN پوشه‌ی /etc/letsencrypt/live/<domain> نبود، گواهی با SAN همان دامنه جستجو می‌شود.
#     اختیاری: SSL_LETSENCRYPT_LIVE=/etc/letsencrypt/live/arc.example.com در .deploy_env (باید SAN شامل API_DOMAIN باشد).

set -euo pipefail

APP_ROOT="${APP_ROOT:-/opt/hesabix}"
DEPLOY_ENV="${APP_ROOT}/.deploy_env"

if [[ $EUID -ne 0 ]]; then
  echo "با sudo اجرا کنید: sudo bash scripts/update_nginx_domains.sh"
  exit 1
fi

if [[ ! -f "${DEPLOY_ENV}" ]]; then
  echo "فایل ${DEPLOY_ENV} یافت نشد."
  exit 1
fi

# shellcheck source=/dev/null
source "${DEPLOY_ENV}"

if [[ -z "${API_DOMAIN:-}" ]] || [[ -z "${UI_DOMAIN:-}" ]]; then
  echo "API_DOMAIN یا UI_DOMAIN در .deploy_env خالی است."
  exit 1
fi

# مسیر live گواهی Let's Encrypt برای یک دامنه (SAN یا همان نام پوشه).
# اختیاری در .deploy_env: SSL_LETSENCRYPT_LIVE=/etc/letsencrypt/live/arc.example.com
pick_letsencrypt_live_for_domain() {
  local dom="$1"
  [[ -z "${dom}" ]] && return 1
  if [[ -n "${SSL_LETSENCRYPT_LIVE:-}" ]] && [[ -f "${SSL_LETSENCRYPT_LIVE}/fullchain.pem" ]]; then
    if openssl x509 -in "${SSL_LETSENCRYPT_LIVE}/fullchain.pem" -noout -text 2>/dev/null | grep -q "DNS:${dom}"; then
      echo "${SSL_LETSENCRYPT_LIVE}"
      return 0
    fi
  fi
  if [[ -f "/etc/letsencrypt/live/${dom}/fullchain.pem" ]]; then
    echo "/etc/letsencrypt/live/${dom}"
    return 0
  fi
  local d
  for d in /etc/letsencrypt/live/*; do
    [[ -f "${d}/fullchain.pem" ]] || continue
    if openssl x509 -in "${d}/fullchain.pem" -noout -text 2>/dev/null | grep -q "DNS:${dom}"; then
      echo "${d}"
      return 0
    fi
  done
  return 1
}

nginx_ssl_block_for_live_dir() {
  local live="$1"
  [[ -z "${live}" ]] || [[ ! -f "${live}/fullchain.pem" ]] && return 0
  echo "  listen 443 ssl;"
  echo "  ssl_certificate ${live}/fullchain.pem;"
  echo "  ssl_certificate_key ${live}/privkey.pem;"
  if [[ -f /etc/letsencrypt/options-ssl-nginx.conf ]]; then
    echo "  include /etc/letsencrypt/options-ssl-nginx.conf;"
  fi
  if [[ -f /etc/letsencrypt/ssl-dhparams.pem ]]; then
    echo "  ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;"
  fi
}

API_LETSENCRYPT_LIVE=""
if API_LETSENCRYPT_LIVE=$(pick_letsencrypt_live_for_domain "${API_DOMAIN}"); then
  :
else
  API_LETSENCRYPT_LIVE=""
fi
UI_LETSENCRYPT_LIVE=""
if UI_LETSENCRYPT_LIVE=$(pick_letsencrypt_live_for_domain "${UI_DOMAIN}"); then
  :
else
  UI_LETSENCRYPT_LIVE=""
fi

API_SSL_BLOCK=""
if [[ -n "${API_LETSENCRYPT_LIVE}" ]]; then
  API_SSL_BLOCK=$(nginx_ssl_block_for_live_dir "${API_LETSENCRYPT_LIVE}")
fi
UI_SSL_BLOCK=""
if [[ -n "${UI_LETSENCRYPT_LIVE}" ]]; then
  UI_SSL_BLOCK=$(nginx_ssl_block_for_live_dir "${UI_LETSENCRYPT_LIVE}")
fi

echo ">> به‌روزرسانی Nginx با API_DOMAIN=${API_DOMAIN} و UI_DOMAIN=${UI_DOMAIN}"
if [[ -n "${API_SSL_BLOCK}" ]]; then
  echo ">> TLS API: ${API_LETSENCRYPT_LIVE}"
else
  echo ">> هشدار: گواهی Let's Encrypt برای ${API_DOMAIN} پیدا نشد؛ فقط listen 80 برای API. در صورت نیاز SSL_LETSENCRYPT_LIVE را در .deploy_env بگذارید."
fi
if [[ -n "${UI_SSL_BLOCK}" ]]; then
  echo ">> TLS UI: ${UI_LETSENCRYPT_LIVE}"
else
  echo ">> هشدار: گواهی برای ${UI_DOMAIN} پیدا نشد؛ فقط listen 80 برای UI."
fi

# همان کانفیگ deploy.sh
if [[ -d /etc/nginx/conf.d ]]; then
  cat > /etc/nginx/conf.d/rate-limit-api.conf <<RATELIMIT
# OPTIONS (CORS preflight) را در سهمیه نمی‌گذارد؛ هر XHR معمولاً OPTIONS + METHOD است.
map \$request_method \$api_limit_key {
	default  \$binary_remote_addr;
	OPTIONS  "";
}

limit_req_zone \$api_limit_key zone=api_limit:10m rate=40r/s;
RATELIMIT
fi

cat > /etc/nginx/sites-available/hesabix-api.conf <<NGINX
# Backend API
server {
  listen 80;
${API_SSL_BLOCK}
  server_name ${API_DOMAIN};

  add_header X-Frame-Options "DENY" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-XSS-Protection "1; mode=block" always;
  add_header Referrer-Policy "strict-origin-when-cross-origin" always;

  location = / {
    proxy_pass http://127.0.0.1:8000;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
  }

  # Public share link: /p/{code} → backend (307 redirect)
  location /p/ {
    proxy_pass http://127.0.0.1:8000/p/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 30;
    proxy_connect_timeout 10;
    proxy_send_timeout 30;
  }

  # Public invoice share link: /i/{code} → backend (307 → Flutter /public/invoice-link/...)
  location /i/ {
    proxy_pass http://127.0.0.1:8000/i/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 30;
    proxy_connect_timeout 10;
    proxy_send_timeout 30;
  }

  # وقتی API و UI روی یک دامنه هستند: مسیرهای /public/ را از روت UI سرو کن (SPA)
  location /public/ {
    root /var/www/${UI_DOMAIN};
    try_files \$uri \$uri/ @hesabix_public_spa;
  }
  location @hesabix_public_spa {
    root /var/www/${UI_DOMAIN};
    rewrite ^ /index.html break;
  }

  location ^~ /docs {
    proxy_pass http://127.0.0.1:8000;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;
  }

  location = /openapi.json {
    proxy_pass http://127.0.0.1:8000;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;
  }

  location ^~ /redoc {
    proxy_pass http://127.0.0.1:8000;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;
  }

  location ^~ /assets/ {
    proxy_pass http://127.0.0.1:8000;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;
  }

  location / {
    return 404;
  }

  location /api/v1/public/crm-chat/ {
    proxy_pass http://127.0.0.1:8000/api/v1/public/crm-chat/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;
    client_max_body_size 1g;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }

  location /api/ {
    limit_req zone=api_limit burst=120 nodelay;
    proxy_pass http://127.0.0.1:8000/api/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;
    client_max_body_size 1g;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }

  # WebSocket endpoints (/ws/notifications, /ws/ai/voice, etc.)
  location /ws/ {
    proxy_pass http://127.0.0.1:8000/ws/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 86400;
    proxy_send_timeout 86400;
  }
}
NGINX

cat > /etc/nginx/sites-available/hesabix-ui.conf <<NGINX
# Frontend (Flutter Web)
server {
  listen 80;
${UI_SSL_BLOCK}
  server_name ${UI_DOMAIN};

  root /var/www/${UI_DOMAIN};
  index index.html;

  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-XSS-Protection "1; mode=block" always;
  add_header Referrer-Policy "strict-origin-when-cross-origin" always;

  # Public share link redirect: /p/{code} → backend (307 to /public/person-link/{code})
  location /p/ {
    proxy_pass http://127.0.0.1:8000/p/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 30;
    proxy_connect_timeout 10;
    proxy_send_timeout 30;
  }

  # Public invoice share: /i/{code} → backend (307 to /public/invoice-link/{code})
  location /i/ {
    proxy_pass http://127.0.0.1:8000/i/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 30;
    proxy_connect_timeout 10;
    proxy_send_timeout 30;
  }

  # Proxy /api/ and /ws/ to backend (when API and UI share same domain)
  location /api/ {
    proxy_pass http://127.0.0.1:8000/api/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_read_timeout 300;
    proxy_send_timeout 300;
    client_max_body_size 1g;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }
  location /ws/ {
    proxy_pass http://127.0.0.1:8000/ws/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_read_timeout 86400;
    proxy_send_timeout 86400;
  }

  # همان دامنهٔ UI+API: /docs و openapi و redoc و دارایی‌های swagger به بک‌اند (بدون تداخل با /assets Flutter)
  location ^~ /docs {
    proxy_pass http://127.0.0.1:8000;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;
  }

  location = /openapi.json {
    proxy_pass http://127.0.0.1:8000;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;
  }

  location ^~ /redoc {
    proxy_pass http://127.0.0.1:8000;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;
  }

  location ^~ /assets/swagger/ {
    proxy_pass http://127.0.0.1:8000;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;
  }

  location = /assets/logo-blue.png {
    proxy_pass http://127.0.0.1:8000;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
  }

  # SPA: مسیرهای عمومی (لینک اشتراک و غیره) → index.html
  location /public/ {
    try_files \$uri \$uri/ /index.html;
  }

  location = /version.json {
    add_header Cache-Control "no-store" always;
    expires off;
    try_files \$uri =404;
  }

  location = /flutter_service_worker.js {
    add_header Cache-Control "no-cache, must-revalidate" always;
    expires off;
    try_files \$uri =404;
  }

  location = /flutter_bootstrap.js {
    add_header Cache-Control "no-cache, must-revalidate" always;
    expires off;
    try_files \$uri =404;
  }

  location = /main.dart.js {
    add_header Cache-Control "no-cache, must-revalidate" always;
    expires off;
    try_files \$uri =404;
  }

  location / {
    try_files \$uri \$uri/ /index.html;
  }

  location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
  }

  gzip on;
  gzip_vary on;
  gzip_min_length 1024;
  gzip_types text/plain text/css application/javascript application/json image/svg+xml text/xml application/xml application/xml+rss;
  gzip_comp_level 6;
}
NGINX

[[ -L /etc/nginx/sites-enabled/default ]] && rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/hesabix-api.conf /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/hesabix-ui.conf /etc/nginx/sites-enabled/

if nginx -t; then
  systemctl reload nginx
  echo "✓ Nginx به‌روزرسانی شد."
else
  echo "خطا در پیکربندی Nginx."
  exit 1
fi
