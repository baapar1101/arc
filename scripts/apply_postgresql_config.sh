#!/bin/bash
# اسکریپت اعمال تنظیمات بهینه‌سازی PostgreSQL برای Hesabix
# اجرا: sudo bash scripts/apply_postgresql_config.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_SOURCE="${APP_ROOT}/config/postgresql-hesabix.conf"
CONFIG_DEST_NAME="hesabix-optimization.conf"

echo -e "${GREEN}تنظیمات بهینه‌سازی PostgreSQL Hesabix${NC}"

if [[ ! -f "${CONFIG_SOURCE}" ]]; then
  echo -e "${RED}فایل پیکربندی یافت نشد: ${CONFIG_SOURCE}${NC}"
  exit 1
fi

# تشخیص نسخه PostgreSQL
PG_VERSION=$(sudo -u postgres psql -tAc "SELECT version();" 2>/dev/null | grep -oE '[0-9]+' | head -1)
if [[ -z "${PG_VERSION}" ]]; then
  echo -e "${RED}اتصال به PostgreSQL ناموفق بود.${NC}"
  exit 1
fi

CONFIG_DIR="/etc/postgresql/${PG_VERSION}/main/conf.d"
CONFIG_DEST="${CONFIG_DIR}/${CONFIG_DEST_NAME}"

echo -e "${YELLOW}PostgreSQL نسخه: ${PG_VERSION}${NC}"
echo -e "${YELLOW}مقصد: ${CONFIG_DEST}${NC}"

# کپی فایل
sudo cp "${CONFIG_SOURCE}" "${CONFIG_DEST}"
sudo chown postgres:postgres "${CONFIG_DEST}"
sudo chmod 644 "${CONFIG_DEST}"

echo -e "${GREEN}فایل پیکربندی کپی شد.${NC}"

# Restart لازم است چون max_connections و shared_buffers تغییر کرده‌اند
echo -e "${YELLOW}ریستارت PostgreSQL...${NC}"
if systemctl list-unit-files 2>/dev/null | grep -qE "^postgresql\.service"; then
  sudo systemctl restart postgresql
elif systemctl list-units --type=service 2>/dev/null | grep -qE "postgresql@"; then
  PG_SVC=$(systemctl list-units --type=service --state=active 2>/dev/null | grep -oE "postgresql@[0-9]+-main" | head -1 || echo "postgresql")
  sudo systemctl restart "${PG_SVC}"
else
  sudo systemctl restart postgresql 2>/dev/null || sudo -u postgres pg_ctlcluster "${PG_VERSION}" main restart
fi

echo -e "${GREEN}PostgreSQL ریستارت شد.${NC}"
echo ""
echo -e "${GREEN}تنظیمات اعمال شده:${NC}"
sudo -u postgres psql -tAc "SHOW max_connections;"
sudo -u postgres psql -tAc "SHOW shared_buffers;"
sudo -u postgres psql -tAc "SHOW work_mem;"
echo -e "${GREEN}تمام.${NC}"
