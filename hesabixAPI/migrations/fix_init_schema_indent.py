#!/usr/bin/env python3
"""
اصلاح جامع مشکلات indentation در init_schema
"""

from pathlib import Path
import re

file_path = Path(__file__).parent / "versions" / "20250101_000000_init_schema.py"
content = file_path.read_text(encoding='utf-8')

lines = content.split('\n')
fixed_lines = []
in_function = False
indent_stack = [0]  # Stack to track indentation levels

for i, line in enumerate(lines):
    stripped = line.lstrip()
    
    # Track function boundaries
    if 'def upgrade()' in line or 'def downgrade()' in line:
        in_function = True
        indent_stack = [4]  # Function body starts at 4 spaces
        fixed_lines.append(line)
        continue
    
    if not in_function:
        fixed_lines.append(line)
        continue
    
    # Inside function
    if not stripped:
        fixed_lines.append('')
        continue
    
    # Calculate current indentation
    current_indent = len(line) - len(stripped)
    
    # Check for control flow statements
    control_keywords = ['for ', 'if ', 'while ', 'try:', 'with ', 'except', 'else:', 'elif ', 'finally:']
    is_control = any(stripped.startswith(kw) for kw in control_keywords)
    
    if is_control:
        # Control statement - should be at function level (4) or nested
        if current_indent < 4:
            fixed_lines.append('    ' + stripped)
            indent_stack.append(8)  # Next line should be indented
        elif current_indent == 4:
            fixed_lines.append(line)
            indent_stack.append(8)  # Next line should be indented
        elif current_indent == 8:
            fixed_lines.append(line)
            indent_stack.append(12)  # Nested block
        else:
            fixed_lines.append(line)
            indent_stack.append(current_indent + 4)
    else:
        # Regular statement
        expected_indent = indent_stack[-1] if indent_stack else 4
        
        if current_indent == 0 and stripped and not stripped.startswith('#'):
            # Should be indented
            fixed_lines.append('    ' + stripped)
        elif current_indent == 8 and expected_indent == 4:
            # Wrong indentation - should be 4
            if i > 0 and any(kw in lines[i-1] for kw in control_keywords):
                fixed_lines.append('        ' + stripped)  # Keep 8 for nested
            else:
                fixed_lines.append('    ' + stripped)  # Fix to 4
        elif current_indent == 4 and expected_indent == 8:
            # Should be 8
            fixed_lines.append('        ' + stripped)
        elif current_indent < expected_indent:
            # Too little indentation
            fixed_lines.append(' ' * expected_indent + stripped)
        else:
            fixed_lines.append(line)
        
        # Pop indent stack if we're ending a block
        if stripped and not any(stripped.startswith(kw) for kw in ['if ', 'for ', 'while ', 'try:', 'with ']):
            if len(indent_stack) > 1:
                indent_stack.pop()

file_path.write_text('\n'.join(fixed_lines), encoding='utf-8')
print("✅ Fixed indentation")

