#!/usr/bin/env python3
"""
اسکریپت جامع برای اصلاح مشکلات میگریشن
این اسکریپت مشکلات زیر را برطرف می‌کند:
1. مشکلات indentation
2. بلوک‌های try-except ناقص
3. شرط‌های if بدون بدنه
4. مشکلات syntax دیگر
"""

import re
import ast


def fix_migration_file(file_path: str) -> dict:
    """اصلاح همه مشکلات فایل میگریشن"""
    
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    stats = {
        'fixed_indentation': 0,
        'fixed_try_except': 0,
        'fixed_if_blocks': 0,
        'total_lines': len(lines)
    }
    
    new_lines = []
    i = 0
    
    while i < len(lines):
        line = lines[i]
        original_line = line
        
        # 1. اصلاح indentation بعد از if/for/while بدون :
        if i > 0:
            prev_line = lines[i-1].rstrip()
            prev_stripped = prev_line.strip()
            
            # اگر خط قبلی if/for/while/def/class است که : ندارد
            if prev_stripped and not prev_stripped.endswith(':') and not prev_stripped.startswith('#'):
                # اگر خط فعلی با 8 space شروع می‌شود اما نباید
                if line.startswith('        ') and not line.startswith('            '):
                    # بررسی کن که آیا خط قبلی یک statement ساده است
                    if not any(prev_stripped.startswith(kw) for kw in ['if ', 'for ', 'while ', 'def ', 'class ', 'try:', 'except', 'else:', 'elif ']):
                        new_line = '    ' + line[8:]
                        if new_line != line:
                            stats['fixed_indentation'] += 1
                            line = new_line
        
        # 2. اصلاح بلوک‌های try-except ناقص
        if line.strip() == 'try:':
            new_lines.append(line)
            i += 1
            
            # بررسی خط بعدی
            if i < len(lines):
                next_line = lines[i]
                next_stripped = next_line.strip()
                
                # اگر خط بعدی با except شروع می‌شود (بدون بدنه try)
                if next_stripped.startswith('except'):
                    # یک pass اضافه کن قبل از except
                    base_indent = len(line) - len(line.lstrip())
                    new_lines.append(' ' * (base_indent + 4) + 'pass  # Empty try block\n')
                    stats['fixed_try_except'] += 1
                    # حالا خط except را اضافه کن
                    new_lines.append(next_line)
                    i += 1
                    continue
                
                # اگر خط بعدی indentation ندارد و یک statement است
                if next_stripped and (next_stripped.startswith('op.') or next_stripped.startswith('sa.') or 
                                    next_stripped.startswith('conn.') or next_stripped.startswith('inspector.')):
                    base_indent = len(line) - len(line.lstrip())
                    if not next_line.startswith(' ' * (base_indent + 4)):
                        fixed_line = ' ' * (base_indent + 4) + next_stripped + '\n'
                        new_lines.append(fixed_line)
                        stats['fixed_try_except'] += 1
                        i += 1
                        continue
        
        # 3. اصلاح شرط‌های if بدون بدنه
        if line.strip().startswith('if ') and line.strip().endswith(':'):
            new_lines.append(line)
            i += 1
            
            # بررسی خط بعدی
            if i < len(lines):
                next_line = lines[i]
                next_stripped = next_line.strip()
                
                # اگر خط بعدی indentation ندارد یا با else/elif شروع می‌شود
                if not next_line.startswith(' ') or next_stripped.startswith('elif ') or next_stripped.startswith('else:'):
                    if next_stripped and not (next_stripped.startswith('elif ') or next_stripped.startswith('else:') or next_stripped.startswith('#')):
                        # اضافه کردن pass
                        base_indent = len(line) - len(line.lstrip())
                        new_lines.append(' ' * (base_indent + 4) + 'pass  # Empty if block\n')
                        stats['fixed_if_blocks'] += 1
                        # خط بعدی را اضافه کن
                        new_lines.append(next_line)
                        i += 1
                        continue
        
        # 4. اصلاح indentation در return statements
        if line.strip() == 'return' and i > 0:
            prev_line = lines[i-1].rstrip()
            if prev_line.strip().endswith(':'):
                # return باید داخل بلوک باشد
                base_indent = len(prev_line) - len(prev_line.lstrip())
                if not line.startswith(' ' * (base_indent + 4)):
                    new_line = ' ' * (base_indent + 4) + 'return\n'
                    if new_line != line:
                        stats['fixed_indentation'] += 1
                        line = new_line
        
        new_lines.append(line)
        i += 1
    
    # نوشتن فایل جدید
    with open(file_path, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)
    
    return stats


def validate_syntax(file_path: str) -> tuple[bool, str]:
    """بررسی صحت syntax فایل"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            code = f.read()
        ast.parse(code)
        return True, "✓ Syntax is valid!"
    except SyntaxError as e:
        return False, f"✗ Syntax error at line {e.lineno}: {e.msg}"
    except Exception as e:
        return False, f"✗ Error: {str(e)}"


def main():
    file_path = 'hesabixAPI/migrations/versions/20251202_000000_init_complete_schema.py'
    
    print("🔧 شروع اصلاح فایل میگریشن...")
    print(f"📁 فایل: {file_path}\n")
    
    # اصلاح فایل
    stats = fix_migration_file(file_path)
    
    print("📊 آمار اصلاحات:")
    print(f"  - خطوط کل: {stats['total_lines']}")
    print(f"  - اصلاحات indentation: {stats['fixed_indentation']}")
    print(f"  - اصلاحات try-except: {stats['fixed_try_except']}")
    print(f"  - اصلاحات if blocks: {stats['fixed_if_blocks']}")
    print()
    
    # بررسی syntax
    print("🔍 بررسی syntax...")
    is_valid, message = validate_syntax(file_path)
    print(message)
    
    if not is_valid:
        print("\n⚠️  هنوز مشکلات syntax وجود دارد. در حال انجام اصلاحات بیشتر...")
        
        # اصلاحات اضافی
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # اصلاح مشکلات رایج
        fixes = [
            # اصلاح indentation در except blocks
            (r'(\n    try:\n        .+\n    except Exception:)', r'\1'),
            # اصلاح indentation در return statements
            (r'(\n    if .+:\n        .+\n    return)', r'\1'),
        ]
        
        for pattern, replacement in fixes:
            content = re.sub(pattern, replacement, content)
        
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        
        # بررسی دوباره
        is_valid, message = validate_syntax(file_path)
        print(f"\n{message}")
    
    if is_valid:
        print("\n✅ فایل میگریشن با موفقیت اصلاح شد!")
    else:
        print("\n❌ هنوز مشکلاتی وجود دارد. لطفاً به صورت دستی بررسی کنید.")


if __name__ == '__main__':
    main()

