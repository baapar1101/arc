#!/usr/bin/env bash
# آزاد کردن پورت 8000 و راه‌اندازی مجدد سرویس API (در صورت خطای Address already in use)
set -e
echo "Stopping hesabix-api..."
systemctl stop hesabix-api 2>/dev/null || true
sleep 2
echo "Checking what is using port 8000..."
if command -v ss >/dev/null 2>&1; then
  ss -tlnp | grep ':8000 ' || true
elif command -v netstat >/dev/null 2>&1; then
  netstat -tlnp | grep ':8000 ' || true
fi
if command -v fuser >/dev/null 2>&1; then
  if fuser 8000/tcp 2>/dev/null; then
    echo "Killing process(es) on port 8000..."
    fuser -k 8000/tcp 2>/dev/null || true
    sleep 2
  fi
else
  echo "fuser not found. If port 8000 is in use, kill the PID manually: lsof -i :8000"
fi
echo "Starting hesabix-api..."
systemctl start hesabix-api
sleep 3
systemctl status hesabix-api --no-pager || true
echo "Done. Check: journalctl -u hesabix-api -f"
