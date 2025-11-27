#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
حذف بخش‌های ناقص با indentation اشتباه از فایل migration
"""

file_path = 'hesabixAPI/migrations/versions/20251202_000000_init_complete_schema.py'

print("=" * 60)
print("شروع پردازش فایل migration")
print("=" * 60)

# خواندن فایل
print("\n1. در حال خواندن فایل...")
with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

total_lines = len(lines)
print(f"   ✓ فایل خوانده شد: {total_lines} خط")

# پردازش خطوط
print("\n2. در حال پردازش و حذف بخش‌های ناقص...")
fixed_lines = []
i = 0
skipped_blocks = 0
skipped_lines = 0

while i < total_lines:
    # نمایش پیشرفت
    if i % 500 == 0 and i > 0:
        progress = int((i / total_lines) * 100)
        print(f"   پیشرفت: {progress}% ({i}/{total_lines} خط)")
    
    line = lines[i]
    stripped = line.strip()
    indent = len(line) - len(line.lstrip())
    
    # حذف خطوط با indentation بیش از 12 space (بخش‌های ناقص)
    if indent >= 12 and stripped and not stripped.startswith('#'):
        # شروع یک بلوک ناقص
        block_start = i
        j = i + 1
        
        # پیدا کردن انتهای بلوک
        while j < total_lines:
            next_line = lines[j]
            next_stripped = next_line.strip()
            next_indent = len(next_line) - len(next_line.lstrip())
            
            # توقف وقتی به خط با indentation مناسب رسیدیم
            if next_indent <= 8:
                # بررسی اینکه آیا این خط شروع یک بخش جدید است
                if (next_stripped.startswith('#') or 
                    (next_stripped and 
                     not any(next_stripped.startswith(prefix) for prefix in [
                         'sa.Column', '"', 'op.create_index', 'op.create_table', ')',
                         'sa.ForeignKey', 'sa.PrimaryKey', 'sa.UniqueConstraint',
                         'sa.String', 'sa.Integer', 'sa.DateTime', 'sa.Boolean',
                         'sa.Numeric', 'sa.JSON', 'sa.func', 'sa.text',
                         'nullable', 'server_default', 'primary_key', 'autoincrement',
                         'ondelete', 'length', 'name=', 'autoincrement=True',
                         'primary_key=True'
                     ]))):
                    # حذف این بلوک
                    block_size = j - block_start
                    skipped_blocks += 1
                    skipped_lines += block_size
                    if block_size > 10:
                        print(f"   ✗ حذف بلوک {block_size} خطی از خط {block_start + 1}")
                    i = j
                    break
            j += 1
            if j > i + 1000:  # محدودیت امنیتی
                print(f"   ⚠ توقف در خط {i + 1} (محدودیت امنیتی)")
                i = j
                break
        continue
    
    fixed_lines.append(line)
    i += 1

print(f"   ✓ پردازش کامل شد")

# ذخیره فایل
print(f"\n3. در حال ذخیره فایل...")
print(f"   خطوط حذف شده: {skipped_lines}")
print(f"   بلوک‌های حذف شده: {skipped_blocks}")
print(f"   خطوط باقی‌مانده: {len(fixed_lines)}")

with open(file_path, 'w', encoding='utf-8') as f:
    f.writelines(fixed_lines)

print("   ✓ فایل با موفقیت ذخیره شد!")

print("\n" + "=" * 60)
print("پردازش با موفقیت انجام شد!")
print("=" * 60)

