#!/usr/bin/env python3
"""
اسکریپت ایجاد اسناد حسابداری برای چک‌های ایمپورت شده

این اسکریپت:
- چک‌هایی که سند حسابداری ندارند را پیدا می‌کند
- برای هر چک یک سند حسابداری با کدهای مناسب ایجاد می‌کند
- برای چک دریافتی: بدهکار 10403، بستانکار 10401
- برای چک واگذار شده: بدهکار 20201، بستانکار 20202
"""

import sys
import os
import argparse
from typing import List, Dict, Any, Optional
from datetime import datetime, date
from decimal import Decimal

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text, and_, or_, func
from sqlalchemy.orm import sessionmaker, Session

from adapters.db.models.check import Check, CheckType, CheckStatus
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.user import User


def _get_fixed_account_by_code(db: Session, account_code: str) -> Account:
    """دریافت حساب با کد مشخص"""
    account = db.query(Account).filter(Account.code == str(account_code)).first()
    if not account:
        raise Exception(f"Account with code {account_code} not found")
    return account


def _get_business_fiscal_year(db: Session, business_id: int) -> FiscalYear:
    """دریافت سال مالی جاری کسب‌وکار"""
    from sqlalchemy import and_
    fy = (
        db.query(FiscalYear)
        .filter(
            and_(
                FiscalYear.business_id == business_id,
                FiscalYear.is_last == True,  # noqa: E712
            )
        )
        .order_by(FiscalYear.start_date.desc())
        .first()
    )
    if not fy:
        raise Exception(f"Active fiscal year not found for business {business_id}")
    return fy


def _get_system_user(db: Session) -> User:
    """دریافت یک کاربر سیستم برای ایجاد اسناد"""
    # اول سعی می‌کنیم superadmin پیدا کنیم
    user = db.query(User).filter(
        and_(
            User.is_superadmin == True,  # noqa: E712
            User.is_active == True  # noqa: E712
        )
    ).first()
    
    if not user:
        # اگر superadmin نبود، اولین کاربر فعال را برمی‌گردانیم
        user = db.query(User).filter(User.is_active == True).first()  # noqa: E712
    
    if not user:
        raise Exception("No active user found in database")
    
    return user


def _check_has_accounting_document(db: Session, check_id: int) -> bool:
    """بررسی اینکه آیا چک سند حسابداری دارد یا نه"""
    # بررسی از طریق DocumentLine
    line_count = db.query(func.count(DocumentLine.id)).filter(
        DocumentLine.check_id == check_id
    ).scalar()
    
    if line_count and line_count > 0:
        return True
    
    # بررسی از طریق extra_info در Document
    try:
        docs = db.query(Document).filter(
            and_(
                Document.extra_info.isnot(None),
                or_(
                    Document.extra_info['source'].astext == 'check_create',
                    Document.extra_info['source'].astext == 'check_action'
                )
            )
        ).all()
        
        for doc in docs:
            extra_info = doc.extra_info or {}
            if extra_info.get("check_id") == check_id:
                return True
    except Exception:
        # اگر query JSONB خطا داد، از روش جایگزین استفاده می‌کنیم
        docs = db.query(Document).filter(
            Document.extra_info.isnot(None)
        ).all()
        
        for doc in docs:
            if doc.extra_info:
                extra_info = doc.extra_info
                if isinstance(extra_info, dict):
                    if extra_info.get("check_id") == check_id:
                        return True
    
    return False


def _generate_document_code(db: Session, business_id: int, document_date: date) -> str:
    """تولید کد یکتا برای سند"""
    prefix = f"CHK-{document_date.strftime('%Y%m%d')}"
    
    # پیدا کردن آخرین سند با این prefix
    last_doc = (
        db.query(Document)
        .filter(
            and_(
                Document.business_id == business_id,
                Document.code.like(f"{prefix}-%")
            )
        )
        .order_by(Document.code.desc())
        .first()
    )
    
    if last_doc:
        try:
            # استخراج شماره از کد
            last_num_str = str(last_doc.code).split("-")[-1]
            last_num = int(last_num_str)
            next_num = last_num + 1
        except (ValueError, IndexError):
            next_num = 1
    else:
        next_num = 1
    
    # استفاده از timestamp برای اطمینان از یکتایی
    timestamp_suffix = int(datetime.utcnow().timestamp()) % 100000
    return f"{prefix}-{timestamp_suffix:05d}"


def _create_accounting_document_for_check(
    db: Session,
    check: Check,
    user_id: int
) -> Optional[int]:
    """ایجاد سند حسابداری برای یک چک"""
    try:
        # بررسی اینکه آیا قبلاً سند ایجاد شده است
        if _check_has_accounting_document(db, check.id):
            print(f"  ⚠️  چک {check.id} (شماره: {check.check_number}) قبلاً سند حسابداری دارد - رد می‌شود")
            return None
        
        # دریافت سال مالی
        fiscal_year = _get_business_fiscal_year(db, check.business_id)
        
        # تعیین تاریخ سند (از issue_date چک)
        document_date = check.issue_date.date() if isinstance(check.issue_date, datetime) else check.issue_date
        
        # تولید کد سند
        document_code = _generate_document_code(db, check.business_id, document_date)
        
        # تعیین حساب‌ها و سطرها بر اساس نوع چک
        amount_dec = Decimal(str(check.amount))
        lines: List[Dict[str, Any]] = []
        
        if check.type == CheckType.RECEIVED:
            # چک دریافتی
            if not check.person_id:
                print(f"  ⚠️  چک {check.id} (شماره: {check.check_number}) person_id ندارد - رد می‌شود")
                return None
            
            # بدهکار: اسناد دریافتنی 10403
            acc_notes_recv = _get_fixed_account_by_code(db, "10403")
            lines.append({
                "account_id": acc_notes_recv.id,
                "debit": amount_dec,
                "credit": Decimal(0),
                "description": "ثبت چک دریافتی",
                "check_id": check.id,
            })
            
            # بستانکار: حساب دریافتنی شخص 10401
            acc_ar = _get_fixed_account_by_code(db, "10401")
            lines.append({
                "account_id": acc_ar.id,
                "person_id": check.person_id,
                "debit": Decimal(0),
                "credit": amount_dec,
                "description": "ثبت چک دریافتی",
                "check_id": check.id,
            })
            
            check_type_str = "received"
            description = "ثبت چک دریافتی"
            
        elif check.type == CheckType.TRANSFERRED:
            # چک واگذار شده
            if not check.person_id:
                print(f"  ⚠️  چک {check.id} (شماره: {check.check_number}) person_id ندارد - رد می‌شود")
                return None
            
            # بدهکار: حساب پرداختنی شخص 20201
            acc_ap = _get_fixed_account_by_code(db, "20201")
            lines.append({
                "account_id": acc_ap.id,
                "person_id": check.person_id,
                "debit": amount_dec,
                "credit": Decimal(0),
                "description": "ثبت چک واگذار شده",
                "check_id": check.id,
            })
            
            # بستانکار: اسناد پرداختنی 20202
            acc_notes_pay = _get_fixed_account_by_code(db, "20202")
            lines.append({
                "account_id": acc_notes_pay.id,
                "debit": Decimal(0),
                "credit": amount_dec,
                "description": "ثبت چک واگذار شده",
                "check_id": check.id,
            })
            
            check_type_str = "transferred"
            description = "ثبت چک واگذار شده"
        else:
            print(f"  ⚠️  چک {check.id} (شماره: {check.check_number}) نوع نامعتبر دارد: {check.type}")
            return None
        
        # بررسی تراز سند
        debit_total = Decimal(0)
        credit_total = Decimal(0)
        for line in lines:
            debit_total += Decimal(str(line.get("debit") or 0))
            credit_total += Decimal(str(line.get("credit") or 0))
        
        if debit_total != credit_total:
            raise Exception(f"Document is not balanced: debit={debit_total}, credit={credit_total}")
        
        # ایجاد سند
        document = Document(
            code=document_code,
            business_id=check.business_id,
            fiscal_year_id=fiscal_year.id,
            currency_id=check.currency_id,
            created_by_user_id=user_id,
            document_date=document_date,
            document_type="check",
            is_proforma=False,
            description=description,
            extra_info={
                "source": "check_create",
                "check_id": check.id,
                "check_type": check_type_str,
                "created_by_script": True,
                "script_name": "create_accounting_documents_for_imported_checks"
            },
        )
        db.add(document)
        db.flush()
        
        # ایجاد سطرهای سند
        for line in lines:
            db.add(DocumentLine(document_id=document.id, **line))
        
        db.commit()
        db.refresh(document)
        
        print(f"  ✅ سند {document.code} (ID: {document.id}) برای چک {check.id} ایجاد شد")
        return document.id
        
    except Exception as e:
        db.rollback()
        print(f"  ❌ خطا در ایجاد سند برای چک {check.id}: {str(e)}")
        raise


class CheckAccountingDocumentCreator:
    """کلاس اصلی برای ایجاد اسناد حسابداری چک‌ها"""
    
    def __init__(self, db_name: str = "hesabixpy",
                 db_user: str = "root", db_password: str = "136431",
                 db_host: str = "localhost", db_port: int = 3306):
        """ایجاد اتصال به دیتابیس"""
        self.db_name = db_name
        
        # اتصال به دیتابیس
        dsn = f"mysql+pymysql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}"
        engine = create_engine(
            dsn,
            echo=False,
            pool_pre_ping=True,
            connect_args={
                "connect_timeout": 60,
                "read_timeout": 300,
                "write_timeout": 300,
                "charset": "utf8mb4"
            }
        )
        self.db = sessionmaker(bind=engine)()
        
        # آمار
        self.stats = {
            "checks_processed": 0,
            "documents_created": 0,
            "checks_skipped": 0,
            "errors": 0,
            "error_details": []
        }
    
    def find_checks_without_documents(self, business_id: Optional[int] = None) -> List[Check]:
        """پیدا کردن چک‌هایی که سند حسابداری ندارند"""
        query = self.db.query(Check)
        
        if business_id:
            query = query.filter(Check.business_id == business_id)
        
        all_checks = query.all()
        checks_without_docs = []
        
        print(f"🔍 بررسی {len(all_checks)} چک...")
        
        for check in all_checks:
            if not _check_has_accounting_document(self.db, check.id):
                checks_without_docs.append(check)
        
        return checks_without_docs
    
    def create_documents_for_checks(
        self,
        checks: List[Check],
        dry_run: bool = False
    ) -> None:
        """ایجاد اسناد حسابداری برای لیست چک‌ها"""
        if not checks:
            print("✅ هیچ چکی برای پردازش یافت نشد")
            return
        
        # دریافت کاربر سیستم
        system_user = _get_system_user(self.db)
        print(f"👤 استفاده از کاربر سیستم: {system_user.id} ({system_user.email or system_user.username})")
        
        if dry_run:
            print("\n🔍 حالت DRY RUN - هیچ تغییری اعمال نمی‌شود\n")
        
        print(f"\n📝 شروع ایجاد اسناد برای {len(checks)} چک...\n")
        
        for idx, check in enumerate(checks, 1):
            self.stats["checks_processed"] += 1
            
            print(f"[{idx}/{len(checks)}] پردازش چک {check.id} (شماره: {check.check_number}, نوع: {check.type.name})")
            
            try:
                if not dry_run:
                    document_id = _create_accounting_document_for_check(
                        self.db,
                        check,
                        system_user.id
                    )
                    
                    if document_id:
                        self.stats["documents_created"] += 1
                    else:
                        self.stats["checks_skipped"] += 1
                else:
                    # در حالت dry run فقط بررسی می‌کنیم
                    if _check_has_accounting_document(self.db, check.id):
                        print(f"  ⚠️  چک {check.id} قبلاً سند دارد")
                        self.stats["checks_skipped"] += 1
                    else:
                        print(f"  ✅ چک {check.id} آماده ایجاد سند است")
                        self.stats["documents_created"] += 1
                        
            except Exception as e:
                self.stats["errors"] += 1
                error_detail = {
                    "check_id": check.id,
                    "check_number": check.check_number,
                    "error": str(e)
                }
                self.stats["error_details"].append(error_detail)
                print(f"  ❌ خطا: {str(e)}")
        
        print("\n" + "="*80)
        print("📊 خلاصه نتایج:")
        print(f"  - چک‌های پردازش شده: {self.stats['checks_processed']}")
        print(f"  - اسناد ایجاد شده: {self.stats['documents_created']}")
        print(f"  - چک‌های رد شده: {self.stats['checks_skipped']}")
        print(f"  - خطاها: {self.stats['errors']}")
        
        if self.stats["error_details"]:
            print("\n❌ جزئیات خطاها:")
            for error in self.stats["error_details"][:10]:  # نمایش حداکثر 10 خطا
                print(f"  - چک {error['check_id']} ({error['check_number']}): {error['error']}")
            if len(self.stats["error_details"]) > 10:
                print(f"  ... و {len(self.stats['error_details']) - 10} خطای دیگر")
    
    def run(self, business_id: Optional[int] = None, dry_run: bool = False) -> None:
        """اجرای کامل اسکریپت"""
        print("="*80)
        print("🚀 شروع اسکریپت ایجاد اسناد حسابداری برای چک‌های ایمپورت شده")
        print("="*80)
        
        # پیدا کردن چک‌های بدون سند
        checks = self.find_checks_without_documents(business_id)
        
        # ایجاد اسناد
        self.create_documents_for_checks(checks, dry_run)
        
        print("\n" + "="*80)
        print("✅ اسکریپت با موفقیت به پایان رسید")
        print("="*80)
    
    def close(self):
        """بستن اتصال دیتابیس"""
        if self.db:
            self.db.close()


def main():
    """تابع اصلی"""
    parser = argparse.ArgumentParser(
        description="ایجاد اسناد حسابداری برای چک‌های ایمپورت شده"
    )
    parser.add_argument(
        "--db-name",
        type=str,
        default="hesabixpy",
        help="نام دیتابیس (پیش‌فرض: hesabixpy)"
    )
    parser.add_argument(
        "--db-user",
        type=str,
        default="root",
        help="نام کاربری دیتابیس (پیش‌فرض: root)"
    )
    parser.add_argument(
        "--db-password",
        type=str,
        default="136431",
        help="رمز عبور دیتابیس (پیش‌فرض: 136431)"
    )
    parser.add_argument(
        "--db-host",
        type=str,
        default="localhost",
        help="آدرس سرور دیتابیس (پیش‌فرض: localhost)"
    )
    parser.add_argument(
        "--db-port",
        type=int,
        default=3306,
        help="پورت دیتابیس (پیش‌فرض: 3306)"
    )
    parser.add_argument(
        "--business-id",
        type=int,
        default=None,
        help="فیلتر بر اساس business_id (اختیاری)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="حالت تست - بدون ایجاد تغییرات"
    )
    
    args = parser.parse_args()
    
    creator = None
    try:
        creator = CheckAccountingDocumentCreator(
            db_name=args.db_name,
            db_user=args.db_user,
            db_password=args.db_password,
            db_host=args.db_host,
            db_port=args.db_port
        )
        
        creator.run(
            business_id=args.business_id,
            dry_run=args.dry_run
        )
        
    except KeyboardInterrupt:
        print("\n\n⚠️  عملیات توسط کاربر متوقف شد")
        sys.exit(1)
    except Exception as e:
        print(f"\n\n❌ خطای غیرمنتظره: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        if creator:
            creator.close()


if __name__ == "__main__":
    main()

