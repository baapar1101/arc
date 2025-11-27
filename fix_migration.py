#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys

file_path = 'hesabixAPI/migrations/versions/20251202_000000_init_complete_schema.py'

print("شروع پردازش...", flush=True)

# خواندن فایل
print("خواندن فایل...", flush=True)
with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

total = len(lines)
print(f"تعداد خطوط: {total}", flush=True)

# پردازش
print("پردازش خطوط...", flush=True)
fixed = []
i = 0
removed = 0

while i < total:
    if i % 200 == 0:
        print(f"خط {i}/{total} ({int(i*100/total)}%)", flush=True)
    
    line = lines[i]
    indent = len(line) - len(line.lstrip())
    
    # حذف خطوط با indentation >= 12 که بخشی از کد ناقص هستند
    if indent >= 12 and line.strip() and not line.strip().startswith('#'):
        # پیدا کردن انتهای بلوک
        start = i
        j = i + 1
        while j < total and j < i + 500:
            next_line = lines[j]
            next_indent = len(next_line) - len(next_line.lstrip())
            if next_indent <= 8 and next_line.strip():
                if next_line.strip().startswith('#') or (
                    not any(next_line.strip().startswith(p) for p in [
                        'sa.', 'op.', '"', ')', 'nullable', 'server_default',
                        'primary_key', 'autoincrement', 'ondelete', 'length', 'name='
                    ])
                ):
                    size = j - start
                    removed += size
                    print(f"  حذف {size} خط از خط {start+1}", flush=True)
                    i = j
                    break
            j += 1
        else:
            i = j
        continue
    
    fixed.append(line)
    i += 1

print(f"\nحذف شد: {removed} خط")
print(f"باقی ماند: {len(fixed)} خط")
print("ذخیره فایل...", flush=True)

with open(file_path, 'w', encoding='utf-8') as f:
    f.writelines(fixed)

print("تمام شد!", flush=True)
