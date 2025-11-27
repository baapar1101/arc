#!/usr/bin/env python3
"""
اسکریپت نهایی جامع برای اصلاح همه مشکلات میگریشن
"""

import re
import ast


def fix_all_remaining_issues(file_path: str):
    """اصلاح همه مشکلات باقیمانده"""
    
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    new_lines = []
    i = 0
    fixes = 0
    
    while i < len(lines):
        line = lines[i]
        original = line
        
        # 1. حذف if/for/def/class تکراری متوالی
        if i < len(lines) - 1:
            current_stripped = line.strip()
            next_stripped = lines[i+1].strip() if i+1 < len(lines) else ""
            
            if current_stripped and current_stripped == next_stripped:
                keywords = ['if ', 'for ', 'def ', 'class ', 'try:', 'except ', 'elif ', 'else:']
                if any(current_stripped.startswith(kw) for kw in keywords):
                    new_lines.append(line)
                    i += 2
                    fixes += 1
                    continue
        
        # 2. اصلاح if بدون بدنه
        if line.strip().endswith(':') and (line.strip().startswith('if ') or line.strip().startswith('for ') or line.strip().startswith('while ')):
            new_lines.append(line)
            i += 1
            
            if i < len(lines):
                next_line = lines[i]
                next_stripped = next_line.strip()
                
                # اگر خط بعدی indentation ندارد یا با def/class شروع می‌شود
                if (not next_line.startswith(' ') or 
                    next_line.strip().startswith('def ') or
                    next_line.strip().startswith('class ') or
                    (next_stripped and not next_stripped.startswith('#') and not next_stripped.endswith(':') and 
                     not any(next_stripped.startswith(kw) for kw in ['if ', 'for ', 'while ', 'try:', 'except', 'else:', 'elif ']))):
                    
                    # اضافه کردن بدنه
                    base_indent = len(line) - len(line.lstrip())
                    if 'return' in next_stripped or 'pass' in next_stripped:
                        # اگر خط بعدی return یا pass است، indentation را اصلاح کن
                        if not next_line.startswith(' ' * (base_indent + 4)):
                            fixed_line = ' ' * (base_indent + 4) + next_stripped + '\n'
                            new_lines.append(fixed_line)
                            fixes += 1
                            i += 1
                            continue
                    elif 'table_name' in line or 'inspector' in line:
                        new_lines.append(' ' * (base_indent + 4) + 'return False\n')
                        fixes += 1
                    else:
                        new_lines.append(' ' * (base_indent + 4) + 'pass\n')
                        fixes += 1
        
        new_lines.append(line)
        i += 1
    
    # نوشتن فایل
    with open(file_path, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)
    
    return fixes


def validate_and_fix_recursive(file_path: str, max_iter=10):
    """اعتبارسنجی و اصلاح بازگشتی تا زمانی که syntax معتبر شود"""
    
    for iteration in range(max_iter):
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                ast.parse(f.read())
            return True, f"✅ Syntax معتبر است! (بعد از {iteration} تکرار)"
        except SyntaxError as e:
            if iteration == 0:
                print(f"🔍 پیدا کردن مشکلات...")
            print(f"  تکرار {iteration + 1}: خطا در خط {e.lineno}: {e.msg}")
            
            fixes = fix_all_remaining_issues(file_path)
            if fixes == 0:
                # اگر هیچ اصلاحی انجام نشد، خطا را نمایش بده
                with open(file_path, 'r', encoding='utf-8') as f:
                    lines = f.readlines()
                
                start = max(0, e.lineno - 3)
                end = min(len(lines), e.lineno + 2)
                print(f"\n  Context خط {e.lineno}:")
                for i in range(start, end):
                    marker = ">>> " if i == e.lineno - 1 else "    "
                    print(f"  {marker}{i+1}: {lines[i].rstrip()}")
                break
            
            print(f"  ✓ {fixes} مشکل اصلاح شد")
    
    # بررسی نهایی
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            ast.parse(f.read())
        return True, "✅ Syntax معتبر است!"
    except SyntaxError as e:
        return False, f"❌ هنوز خطا در خط {e.lineno}: {e.msg}"


def main():
    file_path = 'hesabixAPI/migrations/versions/20251202_000000_init_complete_schema.py'
    
    print("🔧 شروع اصلاح جامع فایل میگریشن...")
    print(f"📁 فایل: {file_path}\n")
    
    is_valid, message = validate_and_fix_recursive(file_path)
    print(f"\n{message}")
    
    if is_valid:
        print("\n🎉 فایل میگریشن با موفقیت اصلاح شد!")
    else:
        print("\n⚠️  برخی مشکلات ممکن است نیاز به بررسی دستی داشته باشند.")


if __name__ == '__main__':
    main()

