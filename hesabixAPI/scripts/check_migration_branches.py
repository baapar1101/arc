#!/usr/bin/env python3
"""
اسکریپت بررسی و حل مشکل چند شاخه بودن میگریشن‌ها

این اسکریپت قبل از اجرای میگریشن‌ها بررسی می‌کند که آیا branchهای merge نشده وجود دارند یا نه.
اگر branch وجود داشته باشد، یک merge head ایجاد می‌کند.
"""

import subprocess
import sys
from pathlib import Path

# مسیر پروژه
PROJECT_ROOT = Path(__file__).parent.parent


def run_command(cmd: list[str], cwd: Path = None) -> tuple[str, str, int]:
    """اجرای یک دستور و برگرداندن خروجی"""
    result = subprocess.run(
        cmd,
        cwd=cwd or PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=False
    )
    return result.stdout, result.stderr, result.returncode


def check_branches() -> bool:
    """بررسی وجود branchهای merge نشده"""
    stdout, stderr, returncode = run_command(
        ['alembic', 'branches'],
        cwd=PROJECT_ROOT
    )
    
    if returncode != 0:
        print(f"خطا در بررسی branchها: {stderr}")
        return False
    
    # اگر خروجی خالی باشد، branch وجود ندارد
    lines = [line.strip() for line in stdout.split('\n') if line.strip()]
    
    # اگر فقط یک head وجود دارد، branch وجود ندارد
    if len(lines) == 0:
        return False
    
    # بررسی وجود branchpoint
    has_branchpoint = any('branchpoint' in line for line in lines)
    return has_branchpoint


def check_heads() -> list[str]:
    """بررسی headهای موجود"""
    stdout, stderr, returncode = run_command(
        ['alembic', 'heads'],
        cwd=PROJECT_ROOT
    )
    
    if returncode != 0:
        print(f"خطا در بررسی headها: {stderr}")
        return []
    
    # استخراج revision IDs از خروجی
    heads = []
    for line in stdout.split('\n'):
        line = line.strip()
        if line and not line.startswith('INFO'):
            # فرمت: revision_id (head)
            parts = line.split()
            if parts:
                heads.append(parts[0])
    
    return heads


def merge_heads(heads: list[str]) -> bool:
    """ایجاد merge head برای headهای موجود"""
    if len(heads) < 2:
        return True  # نیازی به merge نیست
    
    print(f"در حال merge کردن {len(heads)} head...")
    
    # ایجاد merge head
    merge_message = f"merge_{len(heads)}_heads"
    cmd = ['alembic', 'merge', '-m', merge_message] + heads
    
    stdout, stderr, returncode = run_command(cmd, cwd=PROJECT_ROOT)
    
    if returncode != 0:
        print(f"خطا در ایجاد merge head: {stderr}")
        return False
    
    print(f"Merge head با موفقیت ایجاد شد: {stdout.strip()}")
    return True


def main():
    """تابع اصلی"""
    print("بررسی وضعیت میگریشن‌ها...")
    
    # بررسی headها
    heads = check_heads()
    print(f"تعداد headهای موجود: {len(heads)}")
    
    if len(heads) == 0:
        print("هیچ headی یافت نشد!")
        return 1
    
    if len(heads) == 1:
        print("✓ فقط یک head وجود دارد. همه چیز درست است.")
        return 0
    
    # اگر چند head وجود دارد
    print(f"⚠️  {len(heads)} head یافت شد:")
    for head in heads:
        print(f"  - {head}")
    
    # بررسی branchها
    has_branches = check_branches()
    
    if has_branches:
        print("\n⚠️  Branchهای merge نشده یافت شد!")
        print("در حال ایجاد merge head...")
        
        if merge_heads(heads):
            print("✓ Merge head با موفقیت ایجاد شد.")
            print("\nلطفاً میگریشن‌ها را بررسی کنید و سپس اجرا کنید:")
            print("  alembic upgrade head")
            return 0
        else:
            print("✗ خطا در ایجاد merge head!")
            return 1
    else:
        print("\n⚠️  چند head وجود دارد اما branch point یافت نشد.")
        print("این ممکن است نشان‌دهنده مشکل در ساختار میگریشن‌ها باشد.")
        return 1


if __name__ == '__main__':
    sys.exit(main())

