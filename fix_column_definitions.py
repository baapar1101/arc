#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import re

file_path = 'hesabixAPI/migrations/versions/20251202_000000_init_complete_schema.py'

print("خواندن فایل...", flush=True)
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

print("اصلاح تعاریف sa.Column ناقص...", flush=True)

# الگو برای پیدا کردن تعاریف ناقص sa.Column
# مثال: 'column_name',\n    sa.String(\n        length=255),\n        nullable=False,

# پیدا کردن همه موارد op.create_table که بعد از آن تعاریف ناقص دارند
lines = content.split('\n')
fixed_lines = []
i = 0
fixed_count = 0

while i < len(lines):
    line = lines[i]
    
    # اگر خط با op.create_table شروع می‌شود
    if "op.create_table(" in line and i + 1 < len(lines):
        # بررسی خط بعدی
        next_line = lines[i + 1] if i + 1 < len(lines) else ""
        # اگر خط بعدی یک string literal است (نام ستون) اما sa.Column ندارد
        if next_line.strip().startswith("'") and "sa.Column" not in line:
            # پیدا کردن انتهای این تعریف ناقص
            j = i + 1
            col_parts = []
            found_sa = False
            
            while j < len(lines) and j < i + 20:
                current = lines[j]
                stripped = current.strip()
                
                if stripped.startswith("sa."):
                    found_sa = True
                    col_parts.append(current)
                elif found_sa and (stripped.startswith("nullable") or stripped.startswith("comment") or stripped.startswith("server_default")):
                    col_parts.append(current)
                elif found_sa and stripped.endswith("),"):
                    col_parts.append(current)
                    # ساخت sa.Column صحیح
                    col_name = lines[i + 1].strip().strip("',\"")
                    fixed_col = f"            sa.Column('{col_name}', " + " ".join([p.strip() for p in col_parts[1:] if p.strip()])
                    # جایگزینی
                    fixed_lines.append(line)
                    fixed_lines.append(fixed_col)
                    i = j + 1
                    fixed_count += 1
                    print(f"  اصلاح ستون {col_name} در خط {i}", flush=True)
                    break
                elif found_sa:
                    col_parts.append(current)
                
                j += 1
            else:
                fixed_lines.append(line)
                i += 1
            continue
    
    fixed_lines.append(line)
    i += 1

print(f"اصلاح شد: {fixed_count} تعریف", flush=True)
print("ذخیره فایل...", flush=True)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(fixed_lines))

print("تمام شد!", flush=True)

