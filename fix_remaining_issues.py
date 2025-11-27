#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
اصلاح مشکلات باقی‌مانده در ساختار sa.Column
"""
import re

file_path = 'hesabixAPI/migrations/versions/20251202_000000_init_complete_schema.py'

print("=" * 70)
print("اصلاح مشکلات باقی‌مانده")
print("=" * 70)

print("\n[1] خواندن فایل...", flush=True)
with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

total = len(lines)
print(f"   ✓ {total} خط", flush=True)

print("\n[2] اصلاح مشکلات...", flush=True)
fixed = []
i = 0
fixed_count = 0

while i < total:
    if i % 200 == 0 and i > 0:
        pct = int(i * 100 / total)
        print(f"   پیشرفت: {pct}%", flush=True)
    
    line = lines[i]
    stripped = line.strip()
    
    # مشکل 1: sa.Column که با پرانتز بسته شده اما محتوا ندارد
    # مثال: sa.Column('business_id',\n        sa.Integer(),)
    if "sa.Column(" in line and i + 1 < total:
        next_line = lines[i + 1] if i + 1 < total else ""
        next_stripped = next_line.strip()
        
        # اگر خط بعدی با ), تمام می‌شود
        if next_stripped.endswith("),") or next_stripped.endswith(")"):
            # بررسی اینکه آیا nullable یا comment وجود دارد
            if i + 2 < total:
                third_line = lines[i + 2].strip()
                if not (third_line.startswith("nullable") or third_line.startswith("comment") or third_line.startswith("server_default")):
                    # این یک sa.Column ناقص است
                    col_match = re.search(r"sa\.Column\(['\"]([^'\"]+)['\"]", line)
                    if col_match:
                        col_name = col_match.group(1)
                        # استخراج نوع از خط بعدی
                        type_match = re.search(r"sa\.(\w+)", next_stripped)
                        if type_match:
                            type_name = type_match.group(1)
                            # استخراج پارامترها
                            params_match = re.search(r"\(([^)]*)\)", next_stripped)
                            params = params_match.group(1) if params_match else ""
                            
                            indent = len(line) - len(line.lstrip())
                            # ساخت مجدد
                            new_line1 = f"{' ' * indent}sa.Column('{col_name}',"
                            new_line2 = f"{' ' * (indent + 4)}sa.{type_name}({params})"
                            
                            fixed.append(new_line1)
                            fixed.append(new_line2)
                            i += 2
                            fixed_count += 1
                            print(f"   ✓ اصلاح sa.Column('{col_name}') در خط {i-1}", flush=True)
                            continue
    
    # مشکل 2: sa.Column که بعد از آن خط جداگانه nullable دارد
    if stripped.startswith("nullable") and i > 0:
        prev_line = lines[i-1].strip()
        if prev_line.endswith("),") or prev_line.endswith(")"):
            # این nullable باید به خط قبل اضافه شود
            indent = len(line) - len(line.lstrip())
            # حذف خط فعلی و اضافه کردن به خط قبل
            if fixed:
                last = fixed[-1]
                if last.strip().endswith(")"):
                    # اضافه کردن nullable
                    nullable_match = re.search(r"nullable\s*=\s*(\w+)", stripped)
                    if nullable_match:
                        nullable_val = nullable_match.group(1)
                        fixed[-1] = last.rstrip()[:-1] + f",\n{' ' * indent}nullable={nullable_val})"
                        i += 1
                        fixed_count += 1
                        print(f"   ✓ اضافه کردن nullable در خط {i}", flush=True)
                        continue
    
    fixed.append(line)
    i += 1

print(f"\n   ✓ {fixed_count} مشکل اصلاح شد")

print("\n[3] ذخیره...", flush=True)
with open(file_path, 'w', encoding='utf-8') as f:
    f.writelines(fixed)

print("   ✓ ذخیره شد", flush=True)

print("\n[4] بررسی syntax...", flush=True)
import subprocess
result = subprocess.run(
    ['python3', '-m', 'py_compile', file_path],
    capture_output=True,
    text=True,
    timeout=10
)

if result.returncode == 0:
    print("   ✓ Syntax صحیح است!", flush=True)
else:
    print("   ⚠ خطاهای باقی مانده:", flush=True)
    for err in result.stderr.split('\n')[:5]:
        if err.strip():
            print(f"      {err}", flush=True)

print("\n" + "=" * 70)
print("تمام شد!")
print("=" * 70)

