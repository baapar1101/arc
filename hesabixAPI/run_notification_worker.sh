#!/bin/bash
set -e

# تنظیم مسیر
cd /var/www/ark/hesabixAPI

# فعال کردن virtual environment
source .venv/bin/activate

# اجرای worker
exec python -m app.workers.notification_moderation_worker


