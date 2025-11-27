#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
اصلاح خودکار ساختار sa.Column ناقص
"""
import re
import sys

file_path = 'hesabixAPI/migrations/versions/20251202_000000_init_complete_schema.py'

print("=" * 70)
print("اصلاح ساختار sa.Column ناقص")
print("=" * 70)

print("\n[1] خواندن فایل...", flush=True)
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')
total = len(lines)
print(f"   ✓ {total} خط خوانده شد", flush=True)

print("\n[2] پردازش خطوط...", flush=True)
fixed = []
i = 0
fixed_count = 0
in_table = False
table_indent = 0

while i < total:
    if i % 200 == 0 and i > 0:
        pct = int(i * 100 / total)
        print(f"   پیشرفت: {pct}% ({i}/{total})", flush=True)
    
    line = lines[i]
    stripped = line.strip()
    indent = len(line) - len(line.lstrip())
    
    # تشخیص op.create_table
    if "op.create_table(" in line:
        in_table = True
        table_indent = indent
        fixed.append(line)
        i += 1
        continue
    
    # اگر درون table هستیم و خط یک string literal است (نام ستون)
    if in_table and stripped.startswith("'") and not stripped.startswith("'''"):
        col_name = stripped.strip("',\"")
        
        # بررسی خط بعدی
        if i + 1 < total:
            next_line = lines[i + 1]
            next_stripped = next_line.strip()
            
            # اگر خط بعدی sa. دارد اما sa.Column نیست
            if next_stripped.startswith("sa.") and "sa.Column" not in line:
                print(f"   پیدا شد: '{col_name}' در خط {i+1}", flush=True)
                
                # جمع‌آوری بخش‌های ستون
                parts = []
                j = i + 1
                found_end = False
                
                while j < total and j < i + 15:
                    curr = lines[j]
                    curr_stripped = curr.strip()
                    parts.append(curr)
                    
                    if curr_stripped.endswith("),") or (curr_stripped.endswith(")") and j + 1 < total and not lines[j+1].strip().startswith("sa.")):
                        found_end = True
                        break
                    j += 1
                
                if found_end:
                    # ساخت sa.Column
                    # استخراج اطلاعات
                    sa_type_line = None
                    nullable = None
                    comment = None
                    server_default = None
                    
                    for p in parts:
                        ps = p.strip()
                        if ps.startswith("sa.") and not sa_type_line:
                            sa_type_line = ps
                        elif "nullable" in ps:
                            m = re.search(r"nullable\s*=\s*(\w+)", ps)
                            if m:
                                nullable = m.group(1)
                        elif "comment" in ps:
                            m = re.search(r"comment\s*=\s*['\"]([^'\"]+)['\"]", ps)
                            if m:
                                comment = m.group(1)
                        elif "server_default" in ps:
                            m = re.search(r"server_default\s*=\s*(.+?)(?:,|$)", ps)
                            if m:
                                server_default = m.group(1).strip()
                    
                    # ساخت خطوط جدید
                    new_lines = [f"{' ' * indent}sa.Column('{col_name}',"]
                    
                    if sa_type_line:
                        # تقسیم sa.String(length=255) به چند خط
                        if "(" in sa_type_line:
                            type_name = sa_type_line.split("(")[0]
                            params = sa_type_line.split("(")[1].rstrip(")")
                            new_lines.append(f"{' ' * (indent + 4)}{type_name}({params})")
                        else:
                            new_lines.append(f"{' ' * (indent + 4)}{sa_type_line}")
                    
                    # اضافه کردن nullable
                    if nullable:
                        new_lines.append(f"{' ' * (indent + 4)}nullable={nullable},")
                    
                    # اضافه کردن comment
                    if comment:
                        new_lines.append(f"{' ' * (indent + 4)}comment='{comment}',")
                    
                    # اضافه کردن server_default
                    if server_default:
                        new_lines.append(f"{' ' * (indent + 4)}server_default={server_default},")
                    
                    # بستن پرانتز
                    last = new_lines[-1]
                    if last.endswith(","):
                        new_lines[-1] = last[:-1] + ")"
                    else:
                        new_lines.append(f"{' ' * indent})")
                    
                    fixed.extend(new_lines)
                    i = j + 1
                    fixed_count += 1
                    print(f"      ✓ اصلاح شد ({len(parts)} خط)", flush=True)
                    continue
    
    # پایان table
    if in_table and stripped == ")" and indent <= table_indent + 4:
        in_table = False
    
    fixed.append(line)
    i += 1

print(f"\n   ✓ پردازش کامل: {fixed_count} تعریف اصلاح شد")

print("\n[3] ذخیره فایل...", flush=True)
with open(file_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(fixed))

print(f"   ✓ ذخیره شد ({len(fixed)} خط)", flush=True)

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
    for err in result.stderr.split('\n')[:3]:
        if err.strip():
            print(f"      {err}", flush=True)

print("\n" + "=" * 70)
print("تمام شد!")
print("=" * 70)

