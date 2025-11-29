#!/usr/bin/env python3
"""ایجاد مستقیم جداول zohal بدون استفاده از alembic"""
import sys
from pathlib import Path

# اضافه کردن مسیر پروژه به sys.path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from sqlalchemy import create_engine, text
from app.core.settings import get_settings
from adapters.db.session import get_db

def create_tables():
    settings = get_settings()
    # ساخت connection string از تنظیمات
    db_url = f"mysql+pymysql://{settings.db_user}:{settings.db_password}@{settings.db_host}:{settings.db_port}/{settings.db_name}"
    engine = create_engine(db_url)
    
    with engine.connect() as conn:
        # بررسی وجود جدول zohal_services
        result = conn.execute(text("SHOW TABLES LIKE 'zohal_services'"))
        if result.fetchone():
            print('✓ Table zohal_services already exists')
        else:
            print('Creating zohal_services table...')
            conn.execute(text('''
            CREATE TABLE zohal_services (
                id INTEGER NOT NULL AUTO_INCREMENT,
                service_code VARCHAR(100) NOT NULL,
                service_path VARCHAR(255) NOT NULL,
                service_name VARCHAR(255) NOT NULL,
                service_category VARCHAR(50) NOT NULL,
                description TEXT,
                is_active BOOL NOT NULL DEFAULT true,
                base_price NUMERIC(18, 2) NOT NULL,
                currency_id INTEGER NOT NULL,
                request_schema JSON,
                response_schema JSON,
                created_at DATETIME NOT NULL,
                updated_at DATETIME NOT NULL,
                PRIMARY KEY (id),
                FOREIGN KEY(currency_id) REFERENCES currencies (id) ON DELETE RESTRICT,
                UNIQUE KEY uq_zohal_services_code (service_code),
                INDEX ix_zohal_services_service_code (service_code),
                INDEX ix_zohal_services_service_category (service_category),
                INDEX ix_zohal_services_currency_id (currency_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            '''))
            conn.commit()
            print('✓ zohal_services table created')
        
        # بررسی وجود جدول zohal_service_logs
        result = conn.execute(text("SHOW TABLES LIKE 'zohal_service_logs'"))
        if result.fetchone():
            print('✓ Table zohal_service_logs already exists')
        else:
            print('Creating zohal_service_logs table...')
            conn.execute(text('''
            CREATE TABLE zohal_service_logs (
                id INTEGER NOT NULL AUTO_INCREMENT,
                business_id INTEGER NOT NULL,
                service_id INTEGER NOT NULL,
                user_id INTEGER,
                request_data JSON,
                response_data JSON,
                status VARCHAR(20) NOT NULL DEFAULT 'pending',
                error_message TEXT,
                amount_charged NUMERIC(18, 2) NOT NULL,
                currency_id INTEGER NOT NULL,
                wallet_transaction_id INTEGER,
                document_id INTEGER,
                created_at DATETIME NOT NULL,
                PRIMARY KEY (id),
                FOREIGN KEY(business_id) REFERENCES businesses (id) ON DELETE CASCADE,
                FOREIGN KEY(service_id) REFERENCES zohal_services (id) ON DELETE RESTRICT,
                FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE SET NULL,
                FOREIGN KEY(currency_id) REFERENCES currencies (id) ON DELETE RESTRICT,
                FOREIGN KEY(wallet_transaction_id) REFERENCES wallet_transactions (id) ON DELETE SET NULL,
                FOREIGN KEY(document_id) REFERENCES documents (id) ON DELETE SET NULL,
                INDEX ix_zohal_service_logs_business_id (business_id),
                INDEX ix_zohal_service_logs_service_id (service_id),
                INDEX ix_zohal_service_logs_user_id (user_id),
                INDEX ix_zohal_service_logs_currency_id (currency_id),
                INDEX ix_zohal_service_logs_wallet_transaction_id (wallet_transaction_id),
                INDEX ix_zohal_service_logs_document_id (document_id),
                INDEX ix_zohal_service_logs_created_at (created_at),
                INDEX ix_zohal_service_logs_status (status)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            '''))
            conn.commit()
            print('✓ zohal_service_logs table created')
        
        print('\n✅ All tables created successfully!')

if __name__ == '__main__':
    try:
        create_tables()
    except Exception as e:
        print(f'❌ Error: {e}')
        sys.exit(1)

