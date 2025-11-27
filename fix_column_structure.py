#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
اسکریپت برای اصلاح خودکار ساختار sa.Column ناقص
"""
import re
import sys

file_path = 'hesabixAPI/migrations/versions/20251202_000000_init_complete_schema.py'

print("=" * 70)
print("شروع اصلاح ساختار sa.Column")
print("=" * 70)

# خواندن فایل
print("\n[1/4] خواندن فایل...", flush=True)
with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

total_lines = len(lines)
print(f"   ✓ فایل خوانده شد: {total_lines} خط", flush=True)

# پردازش خطوط
print("\n[2/4] پردازش و اصلاح ساختار...", flush=True)
fixed_lines = []
i = 0
fixed_count = 0
in_create_table = False
table_name = None
create_table_indent = None

while i < total_lines:
    # نمایش پیشرفت
    if i % 100 == 0 and i > 0:
        progress = int((i / total_lines) * 100)
        print(f"   پیشرفت: {progress}% ({i}/{total_lines} خط)", flush=True)
    
    line = lines[i]
    stripped = line.strip()
    indent = len(line) - len(line.lstrip())
    
    # تشخیص شروع op.create_table
    if "op.create_table(" in line:
        in_create_table = True
        # استخراج نام جدول
        match = re.search(r"op\.create_table\(['\"]([^'\"]+)['\"]", line)
        if match:
            table_name = match.group(1)
            create_table_indent = indent
            print(f"   پیدا شد: op.create_table('{table_name}') در خط {i+1}", flush=True)
        fixed_lines.append(line)
        i += 1
        continue
    
    # اگر درون op.create_table هستیم و خط بعدی یک string literal است (نام ستون بدون sa.Column)
    if in_create_table and stripped.startswith("'") and not stripped.startswith("'''"):
        # بررسی اینکه آیا این یک نام ستون است (نه comment یا string دیگر)
        col_name = stripped.strip("',\"")
        
        # بررسی خط بعدی برای دیدن آیا sa.Column وجود دارد
        if i + 1 < total_lines:
            next_line = lines[i + 1]
            next_stripped = next_line.strip()
            
            # اگر خط بعدی با sa. شروع می‌شود، این یک تعریف ناقص است
            if next_stripped.startswith("sa.") and "sa.Column" not in line:
                print(f"   ✗ تعریف ناقص پیدا شد: '{col_name}' در خط {i+1}", flush=True)
                
                # جمع‌آوری تمام بخش‌های این ستون
                col_parts = []
                j = i + 1
                col_indent = indent
                
                # جمع‌آوری تا زمانی که به ), برسیم
                while j < total_lines and j < i + 20:
                    current_line = lines[j]
                    current_stripped = current_line.strip()
                    
                    col_parts.append(current_line.rstrip())
                    
                    # اگر به پایان تعریف رسیدیم
                    if current_stripped.endswith("),") or current_stripped.endswith(")"):
                        # ساخت sa.Column صحیح
                        # استخراج نوع داده
                        sa_type = None
                        sa_params = []
                        nullable_val = None
                        comment_val = None
                        server_default_val = None
                        
                        for part in col_parts:
                            part_stripped = part.strip()
                            if part_stripped.startswith("sa."):
                                if not sa_type:
                                    sa_type = part_stripped
                                else:
                                    sa_params.append(part_stripped)
                            elif "nullable" in part_stripped:
                                match = re.search(r"nullable\s*=\s*(\w+)", part_stripped)
                                if match:
                                    nullable_val = match.group(1)
                            elif "comment" in part_stripped:
                                match = re.search(r"comment\s*=\s*['\"]([^'\"]+)['\"]", part_stripped)
                                if match:
                                    comment_val = match.group(1)
                            elif "server_default" in part_stripped:
                                match = re.search(r"server_default\s*=\s*(.+)", part_stripped)
                                if match:
                                    server_default_val = match.group(1).strip()
                        
                        # ساخت خط جدید
                        new_col_parts = [f"{' ' * col_indent}sa.Column('{col_name}',"]
                        if sa_type:
                            new_col_parts.append(f"{' ' * (col_indent + 4)}{sa_type}")
                        for param in sa_params:
                            new_col_parts.append(f"{' ' * (col_indent + 4)}{param}")
                        if nullable_val:
                            new_col_parts.append(f"{' ' * (col_indent + 4)}nullable={nullable_val},")
                        if comment_val:
                            new_col_parts.append(f"{' ' * (col_indent + 4)}comment='{comment_val}',")
                        if server_default_val:
                            new_col_parts.append(f"{' ' * (col_indent + 4)}server_default={server_default_val},")
                        
                        # حذف کامای آخر
                        if new_col_parts[-1].endswith(','):
                            new_col_parts[-1] = new_col_parts[-1][:-1] + ")"
                        else:
                            new_col_parts[-1] = new_col_parts[-1] + ")"
                        
                        # اضافه کردن خطوط جدید
                        fixed_lines.append(new_col_parts[0])
                        for part in new_col_parts[1:]:
                            fixed_lines.append(part)
                        
                        i = j + 1
                        fixed_count += 1
                        print(f"   ✓ اصلاح شد: sa.Column('{col_name}', ...) - {len(col_parts)} خط", flush=True)
                        break
                    
                    j += 1
                else:
                    # اگر پیدا نکردیم، خط را نگه داریم
                    fixed_lines.append(line)
                    i += 1
                continue
    
    # تشخیص پایان op.create_table
    if in_create_table and stripped == ")" and indent <= create_table_indent + 4:
        in_create_table = False
        table_name = None
        create_table_indent = None
    
    fixed_lines.append(line)
    i += 1

print(f"\n   ✓ پردازش کامل شد")

# ذخیره فایل
print(f"\n[3/4] ذخیره فایل...", flush=True)
print(f"   تعاریف اصلاح شده: {fixed_count}", flush=True)
print(f"   خطوط نهایی: {len(fixed_lines)}", flush=True)

with open(file_path, 'w', encoding='utf-8') as f:
    f.writelines(fixed_lines)

print("   ✓ فایل ذخیره شد!", flush=True)

# بررسی syntax
print(f"\n[4/4] بررسی syntax...", flush=True)
import subprocess
result = subprocess.run(
    ['python3', '-m', 'py_compile', file_path],
    capture_output=True,
    text=True
)

if result.returncode == 0:
    print("   ✓ فایل syntax صحیح است!", flush=True)
else:
    print("   ⚠ خطاهای syntax باقی مانده:", flush=True)
    error_lines = result.stderr.split('\n')[:5]
    for err in error_lines:
        if err.strip():
            print(f"      {err}", flush=True)

print("\n" + "=" * 70)
print("پردازش با موفقیت انجام شد!")
print("=" * 70)

