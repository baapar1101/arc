"""ایجاد اسناد حسابداری رایگان برای تراکنش‌های قدیمی Document Monetization

revision: 20251202_000003_backfill_document_monetization_accounting_documents
down_revision: 20251202_000002
branch_labels: None
depends_on: None

این میگریشن برای تمام DocumentUsageCharge هایی که document_id=None دارند
(یعنی سند حسابداری ندارند)، یک سند حسابداری رایگان (با amount=0) ایجاد می‌کند.

این migration فقط برای تراکنش‌های قدیمی است که قبل از اضافه شدن قابلیت ثبت سند ایجاد شده‌اند.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from datetime import datetime
import json


# revision identifiers, used by Alembic.
revision = '20251202_000003'
down_revision = '20251202_000002'
branch_labels = None
depends_on = None


def upgrade():
    """
    ایجاد اسناد حسابداری رایگان برای تراکنش‌های قدیمی
    """
    conn = op.get_bind()
    
    # 1. دریافت حساب‌های مورد نیاز
    get_70507 = sa.text("SELECT id FROM accounts WHERE code = '70507' AND business_id IS NULL LIMIT 1")
    account_70507 = conn.execute(get_70507).fetchone()
    
    get_10205 = sa.text("SELECT id FROM accounts WHERE code = '10205' AND business_id IS NULL LIMIT 1")
    account_10205 = conn.execute(get_10205).fetchone()
    
    if not account_70507 or not account_10205:
        print("⚠️  حساب‌های مورد نیاز (70507 یا 10205) یافت نشدند. از migration قبلی اطمینان حاصل کنید.")
        return
    
    account_70507_id = account_70507[0]
    account_10205_id = account_10205[0]
    
    # 2. پیدا کردن تمام DocumentUsageCharge هایی که document_id=None دارند
    get_charges = sa.text("""
        SELECT 
            id,
            business_id,
            charge_type,
            status,
            amount,
            currency_id,
            created_at,
            description
        FROM document_usage_charges
        WHERE document_id IS NULL
        ORDER BY id ASC
    """)
    charges = conn.execute(get_charges).fetchall()
    
    if not charges:
        print("✅ هیچ تراکنش قدیمی بدون سند حسابداری یافت نشد.")
        return
    
    print(f"📊 پیدا شد {len(charges)} تراکنش قدیمی بدون سند حسابداری")
    
    processed_count = 0
    error_count = 0
    
    for charge in charges:
        charge_id, business_id, charge_type, status, amount, currency_id, created_at, description = charge
        
        try:
            # 3. دریافت سال مالی جاری برای این کسب‌وکار
            get_fiscal_year = sa.text("""
                SELECT id
                FROM fiscal_years
                WHERE business_id = :business_id
                  AND start_date <= CURDATE()
                  AND end_date >= CURDATE()
                LIMIT 1
            """)
            fiscal_year_result = conn.execute(get_fiscal_year, {"business_id": business_id}).fetchone()
            
            if not fiscal_year_result:
                # تلاش برای دریافت آخرین سال مالی
                get_last_fy = sa.text("""
                    SELECT id
                    FROM fiscal_years
                    WHERE business_id = :business_id
                    ORDER BY start_date DESC
                    LIMIT 1
                """)
                fiscal_year_result = conn.execute(get_last_fy, {"business_id": business_id}).fetchone()
            
            if not fiscal_year_result:
                print(f"⚠️  سال مالی برای کسب‌وکار {business_id} یافت نشد. charge_id: {charge_id}")
                error_count += 1
                continue
            
            fiscal_year_id = fiscal_year_result[0]
            
            # 4. تولید کد سند
            doc_date = created_at.date() if created_at else datetime.now().date()
            prefix = f"PY-{doc_date.strftime('%Y%m%d')}"
            
            # دریافت آخرین سند با این prefix
            get_last_doc = sa.text("""
                SELECT code
                FROM documents
                WHERE business_id = :business_id
                  AND code LIKE :prefix
                ORDER BY code DESC
                LIMIT 1
            """)
            last_doc_result = conn.execute(get_last_doc, {
                "business_id": business_id,
                "prefix": f"{prefix}-%"
            }).fetchone()
            
            if last_doc_result:
                try:
                    last_num = int(last_doc_result[0].split("-")[-1])
                    next_num = last_num + 1
                except Exception:
                    next_num = 1
            else:
                next_num = 1
            
            doc_code = f"{prefix}-{next_num:04d}"
            
            # 5. تعیین توضیحات
            charge_type_names = {
                "subscription_fee": "هزینه اشتراک نامحدود (قدیمی - رایگان)",
                "per_document": "هزینه ثبت سند (قدیمی - رایگان)",
                "volume_cycle": "هزینه دوره حجمی (قدیمی - رایگان)",
                "manual": "هزینه دستی (قدیمی - رایگان)",
            }
            type_name = charge_type_names.get(charge_type, "هزینه خدمات سیستم (قدیمی - رایگان)")
            doc_description = description or type_name
            
            # 6. ایجاد سند (با amount=0 چون رایگان است)
            extra_info_json = json.dumps({
                "source": "document_monetization_backfill",
                "charge_id": charge_id,
                "charge_type": charge_type,
                "is_legacy": True
            })
            
            insert_document = sa.text("""
                INSERT INTO documents (
                    business_id,
                    fiscal_year_id,
                    code,
                    document_type,
                    document_date,
                    currency_id,
                    created_by_user_id,
                    registered_at,
                    is_proforma,
                    description,
                    extra_info
                ) VALUES (
                    :business_id,
                    :fiscal_year_id,
                    :code,
                    'payment',
                    :document_date,
                    :currency_id,
                    NULL,
                    NOW(),
                    0,
                    :description,
                    :extra_info
                )
            """)
            result = conn.execute(insert_document, {
                "business_id": business_id,
                "fiscal_year_id": fiscal_year_id,
                "code": doc_code,
                "document_date": doc_date,
                "currency_id": currency_id,
                "description": doc_description,
                "extra_info": extra_info_json,
            })
            document_id = result.lastrowid
            
            # 7. ایجاد ردیف‌های حسابداری (با amount=0)
            # ردیف 1: بدهکار - هزینه اشتراک و خدمات سیستم (0)
            insert_line1 = sa.text("""
                INSERT INTO document_lines (
                    document_id,
                    account_id,
                    debit,
                    credit,
                    description
                ) VALUES (
                    :document_id,
                    :account_70507_id,
                    0,
                    0,
                    :description
                )
            """)
            conn.execute(insert_line1, {
                "document_id": document_id,
                "account_70507_id": account_70507_id,
                "description": f"{type_name} - مبلغ: 0 (تراکنش قدیمی)",
            })
            
            # ردیف 2: بستانکار - کیف پول (0)
            insert_line2 = sa.text("""
                INSERT INTO document_lines (
                    document_id,
                    account_id,
                    debit,
                    credit,
                    description
                ) VALUES (
                    :document_id,
                    :account_10205_id,
                    0,
                    0,
                    'پرداخت از کیف پول (قدیمی - رایگان)'
                )
            """)
            conn.execute(insert_line2, {
                "document_id": document_id,
                "account_10205_id": account_10205_id,
            })
            
            # 8. به‌روزرسانی DocumentUsageCharge با document_id
            update_charge = sa.text("""
                UPDATE document_usage_charges
                SET document_id = :document_id,
                    updated_at = NOW()
                WHERE id = :charge_id
            """)
            conn.execute(update_charge, {
                "document_id": document_id,
                "charge_id": charge_id,
            })
            
            # 9. به‌روزرسانی WalletTransaction با document_id (اگر wallet_transaction_id وجود دارد)
            update_wallet_tx = sa.text("""
                UPDATE wallet_transactions
                SET document_id = :document_id,
                    updated_at = NOW()
                WHERE id IN (
                    SELECT wallet_transaction_id
                    FROM document_usage_charges
                    WHERE id = :charge_id
                      AND wallet_transaction_id IS NOT NULL
                )
            """)
            conn.execute(update_wallet_tx, {
                "document_id": document_id,
                "charge_id": charge_id,
            })
            
            processed_count += 1
            
            if processed_count % 100 == 0:
                print(f"📝 پردازش شد: {processed_count}/{len(charges)}")
                
        except Exception as e:
            error_count += 1
            print(f"❌ خطا در پردازش charge_id={charge_id}: {str(e)}")
            continue
    
    print(f"✅ Migration تکمیل شد:")
    print(f"   - پردازش شد: {processed_count}")
    print(f"   - خطا: {error_count}")
    print(f"   - کل: {len(charges)}")


def downgrade():
    """
    برگشت تغییرات: حذف اسناد حسابداری که با extra_info.is_legacy=true ایجاد شده‌اند
    """
    conn = op.get_bind()
    
    # پیدا کردن تمام اسناد با is_legacy=true
    # چون MySQL JSON_EXTRACT ممکن است مشکل داشته باشد، همه را می‌خوانیم و فیلتر می‌کنیم
    get_all_docs = sa.text("""
        SELECT id, extra_info
        FROM documents
        WHERE extra_info IS NOT NULL
    """)
    all_docs = conn.execute(get_all_docs).fetchall()
    
    legacy_doc_ids = []
    for doc_id, extra_info_json in all_docs:
        if extra_info_json:
            try:
                extra_info = json.loads(extra_info_json) if isinstance(extra_info_json, str) else extra_info_json
                if extra_info.get("is_legacy") and extra_info.get("source") == "document_monetization_backfill":
                    legacy_doc_ids.append(doc_id)
            except Exception:
                continue
    
    if not legacy_doc_ids:
        print("✅ هیچ سند legacy یافت نشد.")
        return
    
    legacy_docs = [(doc_id,) for doc_id in legacy_doc_ids]
    
    if not legacy_docs:
        print("✅ هیچ سند legacy یافت نشد.")
        return
    
    print(f"📊 پیدا شد {len(legacy_docs)} سند legacy")
    
    # حذف document_lines
    if legacy_doc_ids:
        placeholders = ",".join([":id" + str(i) for i in range(len(legacy_doc_ids))])
        params = {f"id{i}": doc_id for i, doc_id in enumerate(legacy_doc_ids)}
        delete_lines = sa.text(f"DELETE FROM document_lines WHERE document_id IN ({placeholders})")
        conn.execute(delete_lines, params)
        
        # به‌روزرسانی document_usage_charges (set document_id to NULL)
        update_charges = sa.text(f"UPDATE document_usage_charges SET document_id = NULL, updated_at = NOW() WHERE document_id IN ({placeholders})")
        conn.execute(update_charges, params)
        
        # به‌روزرسانی wallet_transactions (set document_id to NULL)
        update_wallet = sa.text(f"UPDATE wallet_transactions SET document_id = NULL, updated_at = NOW() WHERE document_id IN ({placeholders})")
        conn.execute(update_wallet, params)
        
        # حذف اسناد
        delete_docs = sa.text(f"DELETE FROM documents WHERE id IN ({placeholders})")
        conn.execute(delete_docs, params)
    
    print(f"✅ {len(legacy_docs)} سند legacy حذف شدند.")

