#!/usr/bin/env bash
# به‌روزرسانی فقط دامنه‌های Nginx (بدون دست زدن به دیتابیس یا سرویس‌های دیگر)
# اجرا: sudo bash scripts/update_nginx_domains.sh
# دامنه‌ها از .deploy_env خوانده می‌شوند

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

echo ">> به‌روزرسانی Nginx با API_DOMAIN=${API_DOMAIN} و UI_DOMAIN=${UI_DOMAIN}"

# همان کانفیگ deploy.sh
if [[ -d /etc/nginx/conf.d ]]; then
  cat > /etc/nginx/conf.d/rate-limit-api.conf <<RATELIMIT
limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=10r/s;
RATELIMIT
fi

cat > /etc/nginx/sites-available/hesabix-api.conf <<NGINX
# Backend API
server {
  listen 80;
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

  # وقتی API و UI روی یک دامنه هستند: مسیرهای /public/ را از روت UI سرو کن (SPA)
  location /public/ {
    root /var/www/${UI_DOMAIN};
    try_files \$uri \$uri/ /index.html;
  }

  location / {
    return 404;
  }

  location ~ ^/(docs|docs-custom|redoc|openapi\.json|assets/) {
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

  location /api/ {
    limit_req zone=api_limit burst=20 nodelay;
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

  # SPA: مسیرهای عمومی (لینک اشتراک و غیره) → index.html
  location /public/ {
    try_files \$uri \$uri/ /index.html;
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
