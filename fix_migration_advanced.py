#!/usr/bin/env python3
"""
اسکریپت پیشرفته برای اصلاح همه مشکلات میگریشن
"""

import re
import ast


def fix_all_issues(file_path: str):
    """اصلاح همه مشکلات در یک فایل"""
    
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    new_lines = []
    i = 0
    fixes_count = 0
    
    while i < len(lines):
        line = lines[i]
        original = line
        
        # 1. حذف if/for/def/class تکراری متوالی
        if i < len(lines) - 1:
            current_stripped = line.strip()
            next_stripped = lines[i+1].strip() if i+1 < len(lines) else ""
            
            if current_stripped and current_stripped == next_stripped:
                if any(current_stripped.startswith(kw) for kw in ['if ', 'for ', 'def ', 'class ', 'try:', 'except ', 'elif ', 'else:']):
                    # از خط اول نگه دار
                    new_lines.append(line)
                    i += 2
                    fixes_count += 1
                    continue
        
        # 2. اصلاح if بدون بدنه
        if line.strip().startswith('if ') and line.strip().endswith(':'):
            new_lines.append(line)
            i += 1
            if i < len(lines):
                next_line = lines[i]
                next_stripped = next_line.strip()
                # اگر خط بعدی indentation ندارد یا با else/elif شروع می‌شود
                if (not next_line.startswith(' ') or 
                    next_stripped.startswith('elif ') or 
                    next_stripped.startswith('else:') or
                    next_stripped.startswith('except')):
                    if next_stripped and not (next_stripped.startswith('elif ') or 
                                            next_stripped.startswith('else:') or 
                                            next_stripped.startswith('except') or
                                            next_stripped.startswith('#')):
                        # اضافه کردن pass
                        base_indent = len(line) - len(line.lstrip())
                        new_lines.append(' ' * (base_indent + 4) + 'pass\n')
                        fixes_count += 1
                        # خط بعدی را اضافه کن
                        new_lines.append(next_line)
                        i += 1
                        continue
        
        # 3. اصلاح try-except blocks
        if line.strip() == 'try:':
            new_lines.append(line)
            i += 1
            if i < len(lines):
                next_line = lines[i]
                next_stripped = next_line.strip()
                # اگر خط بعدی except است بدون بدنه
                if next_stripped.startswith('except'):
                    base_indent = len(line) - len(line.lstrip())
                    new_lines.append(' ' * (base_indent + 4) + 'pass  # Empty try block\n')
                    fixes_count += 1
                    new_lines.append(next_line)
                    i += 1
                    continue
                # اگر خط بعدی indentation ندارد
                if next_stripped and (next_stripped.startswith('op.') or 
                                    next_stripped.startswith('sa.') or
                                    next_stripped.startswith('conn.') or
                                    next_stripped.startswith('inspector.')):
                    base_indent = len(line) - len(line.lstrip())
                    if not next_line.startswith(' ' * (base_indent + 4)):
                        fixed = ' ' * (base_indent + 4) + next_stripped + '\n'
                        new_lines.append(fixed)
                        fixes_count += 1
                        i += 1
                        continue
        
        # 4. اصلاح indentation در return
        if line.strip() == 'return' and i > 0:
            prev = lines[i-1].rstrip()
            if prev.strip().endswith(':'):
                base = len(prev) - len(prev.lstrip())
                if not line.startswith(' ' * (base + 4)):
                    line = ' ' * (base + 4) + 'return\n'
                    fixes_count += 1
        
        # 5. اصلاح indentation بعد از statements ساده
        if i > 0:
            prev = lines[i-1].rstrip()
            prev_stripped = prev.strip()
            # اگر خط قبلی statement ساده است و خط فعلی با 8 space شروع می‌شود
            if (prev_stripped and not prev_stripped.endswith(':') and 
                not prev_stripped.startswith('#') and
                line.startswith('        ') and 
                not line.startswith('            ')):
                # بررسی کن که آیا باید indentation کمتری داشته باشد
                if not any(prev_stripped.startswith(kw) for kw in ['if ', 'for ', 'while ', 'def ', 'class ', 'try:', 'except', 'else:', 'elif ']):
                    new_line = '    ' + line[8:]
                    if new_line != line:
                        line = new_line
                        fixes_count += 1
        
        # 6. اصلاح مشکل unmatched parenthesis در op.create_table
        # بررسی اگر خط با sa.Column شروع می‌شود اما op.create_table وجود ندارد
        if line.strip().startswith('sa.Column(') and i > 0:
            # بررسی خط قبلی
            prev_line_stripped = lines[i-1].strip() if i > 0 else ""
            if not prev_line_stripped.startswith('op.create_table'):
                # باید op.create_table اضافه شود
                base_indent = len(line) - len(line.lstrip()) - 8
                if base_indent >= 0:
                    # پیدا کردن نام جدول از context
                    table_name = 'table'  # fallback
                    # سعی کن از خطوط قبلی پیدا کن
                    for j in range(max(0, i-10), i):
                        if 'op.create_table' in lines[j]:
                            # استخراج نام جدول
                            match = re.search(r"op\.create_table\('([^']+)'", lines[j])
                            if match:
                                table_name = match.group(1)
                                break
                    # اضافه کردن op.create_table
                    new_lines.append(' ' * base_indent + f"op.create_table('{table_name}',\n")
                    fixes_count += 1
        
        new_lines.append(line)
        i += 1
    
    # نوشتن فایل
    with open(file_path, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)
    
    return fixes_count


def validate_and_fix_recursive(file_path: str, max_iterations=5):
    """اعتبارسنجی و اصلاح بازگشتی"""
    
    for iteration in range(max_iterations):
        # بررسی syntax
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                ast.parse(f.read())
            return True, f"✓ Syntax is valid after {iteration} iteration(s)!"
        except SyntaxError as e:
            print(f"✗ Iteration {iteration + 1}: Syntax error at line {e.lineno}: {e.msg}")
            
            # اصلاح مشکلات
            fixes = fix_all_issues(file_path)
            if fixes == 0:
                # اگر هیچ اصلاحی انجام نشد، سعی کن مشکل خاص را برطرف کن
                with open(file_path, 'r', encoding='utf-8') as f:
                    lines = f.readlines()
                
                # اصلاح مشکل خاص در خط e.lineno
                if e.lineno - 1 < len(lines):
                    problem_line = lines[e.lineno - 1]
                    print(f"  Problem line: {problem_line.strip()}")
                    
                    # اگر مشکل unmatched parenthesis است
                    if 'unmatched' in e.msg.lower() and ')' in e.msg:
                        # بررسی کنتکست
                        context_start = max(0, e.lineno - 5)
                        context_end = min(len(lines), e.lineno + 2)
                        print(f"  Context:")
                        for j in range(context_start, context_end):
                            marker = ">>> " if j == e.lineno - 1 else "    "
                            print(f"  {marker}{j+1}: {lines[j].rstrip()}")
                
                break
            
            print(f"  Fixed {fixes} issues")
    
    # بررسی نهایی
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            ast.parse(f.read())
        return True, "✓ Syntax is valid!"
    except SyntaxError as e:
        return False, f"✗ Final syntax error at line {e.lineno}: {e.msg}"


def main():
    file_path = 'hesabixAPI/migrations/versions/20251202_000000_init_complete_schema.py'
    
    print("🔧 شروع اصلاح پیشرفته فایل میگریشن...")
    print(f"📁 فایل: {file_path}\n")
    
    is_valid, message = validate_and_fix_recursive(file_path)
    print(f"\n{message}")
    
    if is_valid:
        print("\n✅ فایل میگریشن با موفقیت اصلاح شد!")
    else:
        print("\n⚠️  برخی مشکلات ممکن است نیاز به بررسی دستی داشته باشند.")


if __name__ == '__main__':
    main()

