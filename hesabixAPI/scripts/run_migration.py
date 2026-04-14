#!/usr/bin/env python3
"""اسکریپت اجرای میگریشن"""
import sys
import os

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from alembic.config import Config
from alembic import command

def main():
    """اجرای میگریشن"""
    alembic_cfg = Config("alembic.ini")
    command.upgrade(alembic_cfg, "head")
    print("✓ میگریشن با موفقیت اجرا شد")

if __name__ == "__main__":
    main()

