#!/usr/bin/env python3
"""
اسکریپت Python برای بررسی تنظیمات MySQL
این اسکریپت تنظیمات MySQL را بررسی می‌کند و گزارش می‌دهد
"""

import sys
import os
from sqlalchemy import create_engine, text
from app.core.settings import get_settings

def check_mysql_config():
    """بررسی تنظیمات MySQL"""
    settings = get_settings()
    
    print("🔍 بررسی تنظیمات MySQL...")
    print(f"   Host: {settings.db_host}")
    print(f"   Port: {settings.db_port}")
    print(f"   Database: {settings.db_name}\n")
    
    # ایجاد اتصال
    try:
        engine = create_engine(
            settings.mysql_dsn,
            pool_pre_ping=True,
            connect_args={"connect_timeout": 5}
        )
        
        with engine.connect() as conn:
            # بررسی تنظیمات مهم
            checks = {
                "max_connections": {
                    "query": "SHOW VARIABLES LIKE 'max_connections'",
                    "recommended": 2000,
                    "type": "number"
                },
                "innodb_buffer_pool_size": {
                    "query": "SHOW VARIABLES LIKE 'innodb_buffer_pool_size'",
                    "recommended": None,  # وابسته به RAM
                    "type": "bytes"
                },
                "wait_timeout": {
                    "query": "SHOW VARIABLES LIKE 'wait_timeout'",
                    "recommended": 600,
                    "type": "number"
                },
                "slow_query_log": {
                    "query": "SHOW VARIABLES LIKE 'slow_query_log'",
                    "recommended": "ON",
                    "type": "string"
                },
                "long_query_time": {
                    "query": "SHOW VARIABLES LIKE 'long_query_time'",
                    "recommended": 2,
                    "type": "number"
                },
                "performance_schema": {
                    "query": "SHOW VARIABLES LIKE 'performance_schema'",
                    "recommended": "ON",
                    "type": "string"
                },
            }
            
            results = {}
            
            print("📊 نتایج بررسی:\n")
            for key, config in checks.items():
                result = conn.execute(text(config["query"]))
                row = result.fetchone()
                if row:
                    current_value = row[1]
                    
                    # تبدیل به فرمت مناسب
                    if config["type"] == "bytes":
                        current_mb = int(current_value) / 1024 / 1024
                        display_value = f"{current_mb:.0f} MB"
                        results[key] = {"current": current_value, "display": display_value}
                    else:
                        display_value = str(current_value)
                        results[key] = {"current": current_value, "display": display_value}
                    
                    # بررسی با مقدار پیشنهادی
                    status = "✅"
                    if config["recommended"]:
                        if config["type"] == "number":
                            if int(current_value) < config["recommended"]:
                                status = "⚠️"
                        elif config["type"] == "string":
                            if str(current_value).upper() != str(config["recommended"]).upper():
                                status = "⚠️"
                    
                    print(f"{status} {key}:")
                    print(f"   فعلی: {display_value}")
                    if config["recommended"]:
                        if config["type"] == "bytes":
                            print(f"   پیشنهادی: {config['recommended']} (وابسته به RAM)")
                        else:
                            print(f"   پیشنهادی: {config['recommended']}")
                    
                    # توصیه برای innodb_buffer_pool_size
                    if key == "innodb_buffer_pool_size":
                        try:
                            # تلاش برای دریافت RAM (اگر امکان‌پذیر باشد)
                            import psutil
                            total_ram_mb = psutil.virtual_memory().total / 1024 / 1024
                            recommended_mb = int(total_ram_mb * 0.7)
                            current_mb = int(current_value) / 1024 / 1024
                            
                            if current_mb < recommended_mb:
                                print(f"   💡 توصیه: innodb_buffer_pool_size را به {recommended_mb}M (70% RAM) افزایش دهید")
                        except ImportError:
                            pass
                    
                    print()
            
            # بررسی اتصالات فعلی
            print("📊 وضعیت اتصالات:\n")
            result = conn.execute(text("""
                SELECT 
                    COUNT(*) as total_connections,
                    SUM(CASE WHEN command != 'Sleep' THEN 1 ELSE 0 END) as active_queries,
                    SUM(CASE WHEN command = 'Sleep' THEN 1 ELSE 0 END) as sleeping_connections
                FROM information_schema.processlist
            """))
            conn_stats = result.fetchone()
            
            if conn_stats:
                print(f"   کل اتصالات: {conn_stats[0]}")
                print(f"   Query های فعال: {conn_stats[1]}")
                print(f"   اتصالات خواب: {conn_stats[2]}")
                
                # بررسی max_connections
                max_conn = results.get("max_connections", {}).get("current", 0)
                if max_conn:
                    usage_percent = (conn_stats[0] / int(max_conn)) * 100
                    print(f"   استفاده از max_connections: {usage_percent:.1f}%")
                    
                    if usage_percent > 80:
                        print("   ⚠️  استفاده از اتصالات بالاست! در نظر بگیرید max_connections را افزایش دهید")
                    elif usage_percent > 50:
                        print("   💡 استفاده از اتصالات متوسط است")
                    else:
                        print("   ✅ استفاده از اتصالات در حد نرمال است")
            
            print("\n✅ بررسی تکمیل شد!")
            
    except Exception as e:
        print(f"❌ خطا در اتصال به MySQL: {e}")
        sys.exit(1)

if __name__ == "__main__":
    check_mysql_config()

