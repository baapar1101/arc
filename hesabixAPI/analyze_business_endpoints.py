#!/usr/bin/env python3
"""
اسکریپت برای بررسی endpoint های سطح کسب و کار و دسترسی‌های آنها
"""
import os
import re
import ast
from pathlib import Path
from typing import List, Dict, Any

API_V1_PATH = Path(__file__).parent / "adapters" / "api" / "v1"

def extract_endpoints_from_file(file_path: Path) -> List[Dict[str, Any]]:
    """استخراج endpoint ها از یک فایل Python"""
    endpoints = []
    
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"خطا در خواندن فایل {file_path}: {e}")
        return endpoints
    
    # جستجوی تمام @router decorator ها
    router_pattern = r'@router\.(get|post|put|delete|patch)\(([^)]*)\)'
    decorator_pattern = r'@(\w+)\(([^)]*)\)'
    
    lines = content.split('\n')
    
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        
        # بررسی @router decorator
        router_match = re.match(router_pattern, line)
        if router_match:
            method = router_match.group(1).upper()
            path_args = router_match.group(2)
            
            # استخراج path از آرگومان‌ها
            path_match = re.search(r'["\']([^"\']+)["\']', path_args)
            path = path_match.group(1) if path_match else ""
            
            # بررسی وجود business_id در path
            has_business_id = '{business_id' in path or 'business_id' in path
            
            # خواندن decorator های بعدی تا رسیدن به تابع
            decorators = []
            j = i + 1
            while j < len(lines):
                next_line = lines[j].strip()
                if next_line.startswith('@'):
                    decorator_match = re.match(decorator_pattern, next_line)
                    if decorator_match:
                        decorator_name = decorator_match.group(1)
                        decorator_args = decorator_match.group(2)
                        decorators.append((decorator_name, decorator_args))
                    j += 1
                elif next_line.startswith('def ') or next_line.startswith('async def '):
                    # پیدا کردن نام تابع
                    func_match = re.match(r'(?:async\s+)?def\s+(\w+)', next_line)
                    func_name = func_match.group(1) if func_match else ""
                    
                    # بررسی دسترسی‌ها
                    has_require_business_access = any(
                        'require_business_access' in d[0] for d in decorators
                    )
                    has_require_business_permission_dep = any(
                        'require_business_permission_dep' in d[1] for d in decorators
                    )
                    has_require_business_permission_by_entity_dep = any(
                        'require_business_permission_by_entity_dep' in d[1] for d in decorators
                    )
                    
                    # بررسی در بدنه تابع
                    body_lines = lines[j:min(j+50, len(lines))]
                    body_content = '\n'.join(body_lines)
                    
                    has_depends_permission = 'Depends(require_business_permission_dep' in body_content
                    has_manual_check = 'has_business_permission' in body_content or 'can_access_business' in body_content
                    
                    endpoint_info = {
                        'file': str(file_path.relative_to(API_V1_PATH.parent.parent.parent)),
                        'method': method,
                        'path': path,
                        'function': func_name,
                        'has_business_id': has_business_id,
                        'has_require_business_access': has_require_business_access,
                        'has_require_business_permission_dep': has_require_business_permission_dep or has_depends_permission,
                        'has_require_business_permission_by_entity_dep': has_require_business_permission_by_entity_dep,
                        'has_manual_check': has_manual_check,
                        'line': i + 1,
                        'decorators': [d[0] for d in decorators],
                    }
                    
                    endpoints.append(endpoint_info)
                    break
                else:
                    break
            i = j
        else:
            i += 1
    
    return endpoints

def main():
    """تابع اصلی"""
    all_endpoints = []
    
    # لیست فایل‌های API (به جز admin و support که در پوشه جداگانه‌اند)
    excluded_dirs = {'admin', 'support', '__pycache__', 'schema_models', 'schemas'}
    
    for root, dirs, files in os.walk(API_V1_PATH):
        # حذف پوشه‌های غیرضروری
        dirs[:] = [d for d in dirs if d not in excluded_dirs]
        
        # بررسی فایل‌های Python
        for file in files:
            if file.endswith('.py') and file != '__init__.py':
                file_path = Path(root) / file
                endpoints = extract_endpoints_from_file(file_path)
                all_endpoints.extend(endpoints)
    
    # فیلتر endpoint هایی که business_id دارند
    business_endpoints = [
        ep for ep in all_endpoints 
        if ep['has_business_id']
    ]
    
    # گروه‌بندی بر اساس وضعیت دسترسی
    endpoints_with_access = []
    endpoints_without_access = []
    endpoints_with_permission = []
    
    for ep in business_endpoints:
        has_access = (
            ep['has_require_business_access'] or 
            ep['has_require_business_permission_dep'] or
            ep['has_require_business_permission_by_entity_dep'] or
            ep['has_manual_check']
        )
        
        has_permission = (
            ep['has_require_business_permission_dep'] or
            ep['has_require_business_permission_by_entity_dep']
        )
        
        if has_permission:
            endpoints_with_permission.append(ep)
        elif has_access:
            endpoints_with_access.append(ep)
        else:
            endpoints_without_access.append(ep)
    
    # نمایش نتایج
    print("=" * 100)
    print("📊 گزارش endpoint های سطح کسب و کار")
    print("=" * 100)
    print(f"\n📈 آمار کلی:")
    print(f"  - کل endpoint های سطح کسب و کار: {len(business_endpoints)}")
    print(f"  - با دسترسی مناسب (require_business_access): {len(endpoints_with_access)}")
    print(f"  - با permission مناسب: {len(endpoints_with_permission)}")
    print(f"  - بدون دسترسی مناسب: {len(endpoints_without_access)}")
    
    if endpoints_with_permission:
        print(f"\n✅ endpoint های با permission مناسب ({len(endpoints_with_permission)}):")
        print("-" * 100)
        for ep in sorted(endpoints_with_permission, key=lambda x: x['file']):
            permission_type = "permission_dep" if ep['has_require_business_permission_dep'] else "permission_by_entity_dep"
            print(f"  {ep['method']:6} {ep['path']:60} | {ep['file']:40} | {ep['function']}")
    
    if endpoints_with_access:
        print(f"\n⚠️  endpoint های فقط با دسترسی کسب و کار ({len(endpoints_with_access)}):")
        print("-" * 100)
        for ep in sorted(endpoints_with_access, key=lambda x: x['file']):
            access_type = "require_business_access" if ep['has_require_business_access'] else "manual_check"
            print(f"  {ep['method']:6} {ep['path']:60} | {ep['file']:40} | {ep['function']} ({access_type})")
    
    if endpoints_without_access:
        print(f"\n❌ endpoint های بدون دسترسی مناسب ({len(endpoints_without_access)}):")
        print("-" * 100)
        for ep in sorted(endpoints_without_access, key=lambda x: x['file']):
            print(f"  {ep['method']:6} {ep['path']:60} | {ep['file']:40} | {ep['function']} (خط {ep['line']})")
    
    print("\n" + "=" * 100)
    print("\n📋 لیست کامل endpoint های سطح کسب و کار:")
    print("-" * 100)
    for ep in sorted(business_endpoints, key=lambda x: (x['file'], x['path'])):
        status = "✅" if ep['has_require_business_permission_dep'] or ep['has_require_business_permission_by_entity_dep'] else \
                 "⚠️" if ep['has_require_business_access'] or ep['has_manual_check'] else "❌"
        print(f"  {status} {ep['method']:6} {ep['path']:60} | {ep['file']:40} | {ep['function']}")

if __name__ == '__main__':
    main()

