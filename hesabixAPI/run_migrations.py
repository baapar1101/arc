#!/usr/bin/env python3
"""
اسکریپت اجرای migration ها بدون نیاز به alembic CLI
"""

import os
import sys
from pathlib import Path

# Set password
os.environ['DB_PASSWORD'] = '@@babaK24055'

# Add project to path
sys.path.insert(0, str(Path(__file__).parent))

from alembic import command
from alembic.config import Config
from app.core.settings import get_settings
from urllib.parse import quote_plus

def main():
    """اجرای migration ها"""
    settings = get_settings()
    settings.db_password = '@@babaK24055'  # Set password directly
    
    # Create DSN with URL-encoded password
    dsn = f"postgresql+psycopg2://{settings.db_user}:{quote_plus(settings.db_password)}@{settings.db_host}:{settings.db_port}/{settings.db_name}"
    
    # Create alembic config
    project_root = Path(__file__).parent
    migrations_dir = project_root / "migrations"
    alembic_cfg = Config()
    alembic_cfg.set_main_option("script_location", str(migrations_dir))
    alembic_cfg.set_main_option("prepend_sys_path", str(project_root))
    # Set DSN directly (bypassing config file to avoid % interpolation)
    alembic_cfg.attributes['sqlalchemy.url'] = dsn
    
    print(f"🔗 اتصال به: {settings.db_host}:{settings.db_port}/{settings.db_name}")
    print(f"👤 کاربر: {settings.db_user}\n")
    
    # Run migrations
    print("🚀 اجرای migration ها...\n")
    try:
        command.upgrade(alembic_cfg, "head")
        print("\n✅ Migration ها با موفقیت اجرا شدند!")
    except Exception as e:
        print(f"\n❌ خطا در اجرای migration: {e}")
        import traceback
        traceback.print_exc()
        return 1
    
    return 0

if __name__ == "__main__":
    sys.exit(main())

