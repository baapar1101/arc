#!/usr/bin/env python3
"""
اسکریپت نهایی برای اصلاح همه مشکلات میگریشن
"""

import re
import ast


def fix_specific_issues(file_path: str):
    """اصلاح مشکلات خاص شناسایی شده"""
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    fixes = 0
    
    # 1. اصلاح try block خالی در خط 254
    # پیدا کردن try: که فقط except بعدش دارد
    pattern1 = r"(try:\s*\n\s*)except Exception:"
    replacement1 = r"try:\n        pass  # Empty try block\n    except Exception:"
    if re.search(pattern1, content):
        content = re.sub(pattern1, replacement1, content)
        fixes += 1
    
    # 2. حذف op.create_table تکراری
    # پیدا کردن op.create_table('table' که تکراری است
    lines = content.split('\n')
    new_lines = []
    i = 0
    seen_create_table = False
    
    while i < len(lines):
        line = lines[i]
        
        # اگر op.create_table('table' دیدیم
        if "op.create_table('table'," in line:
            if seen_create_table:
                # این تکراری است، بپر
                i += 1
                fixes += 1
                continue
            seen_create_table = True
        
        new_lines.append(line)
        i += 1
    
    content = '\n'.join(new_lines)
    
    # 3. اصلاح try block در خط 254 - اضافه کردن op.alter_column
    # پیدا کردن try: که بعدش فقط except است
    lines = content.split('\n')
    new_lines = []
    i = 0
    
    while i < len(lines):
        line = lines[i]
        
        # اگر try: دیدیم و بعدش فقط except است
        if line.strip() == 'try:' and i + 1 < len(lines):
            next_line = lines[i + 1].strip()
            if next_line.startswith('except'):
                # بررسی کنتکست - اگر برای tax_types است
                context = ''.join(lines[max(0, i-5):i])
                if 'tax_types' in context and 'code' in context:
                    # اضافه کردن op.alter_column
                    new_lines.append(line)
                    indent = ' ' * (len(line) - len(line.lstrip()) + 4)
                    new_lines.append(indent + "op.alter_column('tax_types', 'code',")
                    new_lines.append(indent + "                   existing_type=sa.String(length=64),")
                    new_lines.append(indent + "                   nullable=False)")
                    fixes += 1
                    i += 1
                    continue
        
        new_lines.append(line)
        i += 1
    
    content = '\n'.join(new_lines)
    
    # 4. حذف try blocks تکراری
    lines = content.split('\n')
    new_lines = []
    i = 0
    
    while i < len(lines):
        line = lines[i]
        
        # اگر try: تکراری دیدیم
        if line.strip() == 'try:' and i > 0:
            prev_line = lines[i-1].strip()
            if prev_line == 'try:':
                # تکراری است، بپر
                i += 1
                fixes += 1
                continue
        
        new_lines.append(line)
        i += 1
    
    content = '\n'.join(new_lines)
    
    # نوشتن فایل
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    return fixes


def fix_missing_content(file_path: str):
    """اصلاح محتوای ناقص در try blocks"""
    
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    new_lines = []
    i = 0
    fixes = 0
    
    while i < len(lines):
        line = lines[i]
        
        # اگر try: دیدیم
        if line.strip() == 'try:':
            new_lines.append(line)
            i += 1
            
            # بررسی خط بعدی
            if i < len(lines):
                next_line = lines[i]
                next_stripped = next_line.strip()
                
                # اگر خط بعدی except است
                if next_stripped.startswith('except'):
                    # بررسی کنتکست برای پیدا کردن چه چیزی باید اضافه شود
                    context = ''.join(lines[max(0, i-10):i])
                    
                    # اگر برای tax_types code column است
                    if 'tax_types' in context and 'code' in context and 'NOT NULL' in context:
                        indent = ' ' * (len(line) - len(line.lstrip()) + 4)
                        new_lines.append(indent + "op.alter_column('tax_types', 'code',")
                        new_lines.append(indent + "                   existing_type=sa.String(length=64),")
                        new_lines.append(indent + "                   nullable=False)")
                        fixes += 1
                    # اگر برای constraint است
                    elif 'constraint' in context.lower() or 'unique' in context.lower():
                        indent = ' ' * (len(line) - len(line.lstrip()) + 4)
                        new_lines.append(indent + "op.create_unique_constraint('uq_tax_types_code', 'tax_types', ['code'])")
                        fixes += 1
                    else:
                        # یک pass اضافه کن
                        indent = ' ' * (len(line) - len(line.lstrip()) + 4)
                        new_lines.append(indent + 'pass  # Empty try block')
                        fixes += 1
                
                # اضافه کردن خط بعدی
                new_lines.append(next_line)
                i += 1
                continue
        
        new_lines.append(line)
        i += 1
    
    # نوشتن فایل
    with open(file_path, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)
    
    return fixes


def main():
    file_path = 'hesabixAPI/migrations/versions/20251202_000000_init_complete_schema.py'
    
    print("🔧 شروع اصلاح نهایی فایل میگریشن...")
    print(f"📁 فایل: {file_path}\n")
    
    # اصلاح مشکلات خاص
    fixes1 = fix_specific_issues(file_path)
    print(f"✓ اصلاح مشکلات خاص: {fixes1} مورد")
    
    # اصلاح محتوای ناقص
    fixes2 = fix_missing_content(file_path)
    print(f"✓ اصلاح محتوای ناقص: {fixes2} مورد")
    
    # بررسی نهایی
    print("\n🔍 بررسی نهایی syntax...")
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            ast.parse(f.read())
        print("✅ فایل میگریشن با موفقیت اصلاح شد و syntax معتبر است!")
        return True
    except SyntaxError as e:
        print(f"✗ Syntax error at line {e.lineno}: {e.msg}")
        if e.text:
            print(f"  Line: {e.text.strip()}")
        
        # نمایش context
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        
        start = max(0, e.lineno - 3)
        end = min(len(lines), e.lineno + 2)
        print("\n  Context:")
        for i in range(start, end):
            marker = ">>> " if i == e.lineno - 1 else "    "
            print(f"  {marker}{i+1}: {lines[i].rstrip()}")
        
        return False


if __name__ == '__main__':
    main()

