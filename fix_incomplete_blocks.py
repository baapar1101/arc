#!/usr/bin/env python3
"""
Fix incomplete code blocks in migration file
"""
import re

def fix_incomplete_blocks(content):
    lines = content.split('\n')
    fixed_lines = []
    i = 0
    
    while i < len(lines):
        line = lines[i]
        
        # Skip incomplete if blocks with only pass
        if re.match(r'\s+if\s+.*:\s*$', line):
            # Check if next non-empty line is just "pass"
            j = i + 1
            while j < len(lines) and lines[j].strip() == '':
                j += 1
            if j < len(lines) and lines[j].strip() == 'pass':
                # Skip this if block
                i = j + 1
                continue
        
        # Fix incomplete try-except blocks
        if 'pass  # Empty try block' in line:
            # Find the matching except
            j = i
            indent_level = len(line) - len(line.lstrip())
            while j < len(lines):
                if lines[j].strip().startswith('except Exception:'):
                    # Check if next line has wrong indentation
                    if j + 1 < len(lines):
                        next_line = lines[j + 1]
                        next_indent = len(next_line) - len(next_line.lstrip())
                        if next_indent > indent_level + 4:
                            # Fix indentation
                            lines[j + 1] = ' ' * (indent_level + 4) + next_line.lstrip()
                    break
                j += 1
        
        fixed_lines.append(line)
        i += 1
    
    return '\n'.join(fixed_lines)

if __name__ == '__main__':
    file_path = 'hesabixAPI/migrations/versions/20251202_000000_init_complete_schema.py'
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Remove incomplete if blocks
    # Pattern: if ...: followed by only pass
    content = re.sub(r'(\s+if\s+[^:]+:\s*\n\s+)pass\s*\n', r'\1# Skipped incomplete block\n', content)
    
    # Remove incomplete try-except blocks with wrong indentation
    content = re.sub(r'(\s+)try:\s*\n\s+pass\s+# Empty try block\s*\n(\s+)except Exception:\s*\n(\s{4,})pass\s+#.*\n', r'\1# Skipped incomplete try-except block\n', content)
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print("Fixed incomplete blocks")

