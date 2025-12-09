#!/usr/bin/env python3
"""
اسکریپت تحلیل و بررسی اسناد حسابداری برای انتقال از hesabixOld به hesabixpy

این اسکریپت:
- ساختار جدول hesabdari_doc و hesabdari_row در دیتابیس قدیمی را بررسی می‌کند
- ساختار جدول documents و document_lines در دیتابیس جدید را بررسی می‌کند
- نگاشت انواع سند را بررسی می‌کند
- آمار و تفاوت‌ها را نمایش می‌دهد
"""

import sys
import os
import argparse
from typing import List, Dict, Any, Optional, Set, Tuple
from collections import defaultdict
from datetime import datetime

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session


class DocumentsAnalyzer:
	def __init__(self, old_db_name: str = "hesabixOld", new_db_name: str = "hesabixpy",
	             db_user: str = "root", db_password: str = "136431",
	             db_host: str = "localhost", db_port: int = 3306):
		"""ایجاد اتصال به هر دو دیتابیس"""
		self.old_db_name = old_db_name
		self.new_db_name = new_db_name
		
		# اتصال به دیتابیس قدیمی
		old_dsn = f"mysql+pymysql://{db_user}:{db_password}@{db_host}:{db_port}/{old_db_name}"
		old_engine = create_engine(
			old_dsn, 
			echo=False, 
			pool_pre_ping=True,
			connect_args={
				"connect_timeout": 60,
				"read_timeout": 300,
				"write_timeout": 300,
				"charset": "utf8mb4"
			}
		)
		self.old_db = sessionmaker(bind=old_engine)()
		
		# اتصال به دیتابیس جدید
		new_dsn = f"mysql+pymysql://{db_user}:{db_password}@{db_host}:{db_port}/{new_db_name}"
		new_engine = create_engine(
			new_dsn, 
			echo=False, 
			pool_pre_ping=True,
			connect_args={
				"connect_timeout": 60,
				"read_timeout": 300,
				"write_timeout": 300,
				"charset": "utf8mb4"
			}
		)
		self.new_db = sessionmaker(bind=new_engine)()
	
	def map_old_document_type_to_new(self, old_type: str) -> str:
		"""نقشه‌برداری نوع سند از قدیمی به جدید"""
		type_mapping = {
			"sell": "invoice_sales",
			"sell_receive": "receipt",  # دریافت از فروش
			"buy": "invoice_purchase",
			"buy_send": "payment",  # پرداخت برای خرید
			"person_receive": "receipt",
			"person_send": "payment",
			"cost": "expense",
			"income": "income",
			"transfer": "transfer",
			"modify_cheque": "manual",  # تغییر وضعیت چک - به صورت manual منتقل می‌شود
		}
		return type_mapping.get(old_type, "manual")
	
	def get_old_documents_structure(self) -> Dict[str, Any]:
		"""دریافت ساختار و آمار اسناد از دیتابیس قدیمی"""
		# دریافت آمار کلی
		query = text("""
			SELECT 
				COUNT(*) as total,
				COUNT(DISTINCT bid_id) as business_count,
				COUNT(DISTINCT type) as type_count
			FROM hesabdari_doc
			WHERE bid_id IS NOT NULL
		""")
		result = self.old_db.execute(query).fetchone()
		
		total_docs = result[0] if result else 0
		business_count = result[1] if result else 0
		type_count = result[2] if result else 0
		
		# آمار بر اساس نوع
		query = text("""
			SELECT type, COUNT(*) as count
			FROM hesabdari_doc
			WHERE bid_id IS NOT NULL
			GROUP BY type
			ORDER BY count DESC
		""")
		results = self.old_db.execute(query).fetchall()
		
		by_type = {}
		for row in results:
			by_type[row[0]] = row[1]
		
		# آمار بر اساس کسب و کار
		query = text("""
			SELECT bid_id, COUNT(*) as count
			FROM hesabdari_doc
			WHERE bid_id IS NOT NULL
			GROUP BY bid_id
			ORDER BY count DESC
			LIMIT 20
		""")
		results = self.old_db.execute(query).fetchall()
		
		by_business = {}
		for row in results:
			by_business[row[0]] = row[1]
		
		# نمونه اسناد
		query = text("""
			SELECT 
				id, bid_id, submitter_id, year_id, money_id, 
				date_submit, date, type, code, des, amount,
				is_preview, is_approved, project_id
			FROM hesabdari_doc
			WHERE bid_id IS NOT NULL
			ORDER BY id ASC
			LIMIT 5
		""")
		results = self.old_db.execute(query).fetchall()
		
		sample_docs = []
		for row in results:
			sample_docs.append({
				"id": row[0],
				"business_id": row[1],
				"submitter_id": row[2],
				"year_id": row[3],
				"money_id": row[4],
				"date_submit": row[5],
				"date": row[6],
				"type": row[7],
				"code": row[8],
				"description": row[9],
				"amount": row[10],
				"is_preview": row[11],
				"is_approved": row[12],
				"project_id": row[13]
			})
		
		return {
			"total": total_docs,
			"business_count": business_count,
			"type_count": type_count,
			"by_type": by_type,
			"by_business": by_business,
			"sample_docs": sample_docs
		}
	
	def get_old_document_rows_structure(self) -> Dict[str, Any]:
		"""دریافت ساختار و آمار سطرهای سند از دیتابیس قدیمی"""
		# آمار کلی
		query = text("SELECT COUNT(*) FROM hesabdari_row")
		total_rows = self.old_db.execute(query).scalar()
		
		# آمار بر اساس doc_id
		query = text("""
			SELECT 
				COUNT(DISTINCT doc_id) as doc_count,
				AVG(rows_per_doc) as avg_rows
			FROM (
				SELECT doc_id, COUNT(*) as rows_per_doc
				FROM hesabdari_row
				GROUP BY doc_id
			) as subquery
		""")
		result = self.old_db.execute(query).fetchone()
		doc_count = result[0] if result else 0
		avg_rows = float(result[1]) if result and result[1] else 0
		
		# نمونه سطرها
		query = text("""
			SELECT 
				id, doc_id, ref_id, person_id, bank_id,
				bs, bd, des, bid_id, year_id,
				commodity_id, commdity_count, salary_id, cashdesk_id, cheque_id
			FROM hesabdari_row
			ORDER BY id ASC
			LIMIT 5
		""")
		results = self.old_db.execute(query).fetchall()
		
		sample_rows = []
		for row in results:
			sample_rows.append({
				"id": row[0],
				"doc_id": row[1],
				"ref_id": row[2],
				"person_id": row[3],
				"bank_id": row[4],
				"bs": row[5],  # بدهکار
				"bd": row[6],  # بستانکار
				"description": row[7],
				"business_id": row[8],
				"year_id": row[9],
				"commodity_id": row[10],
				"commodity_count": row[11],
				"salary_id": row[12],
				"cashdesk_id": row[13],
				"cheque_id": row[14]
			})
		
		return {
			"total": total_rows,
			"doc_count": doc_count,
			"avg_rows_per_doc": avg_rows,
			"sample_rows": sample_rows
		}
	
	def get_new_documents_structure(self) -> Dict[str, Any]:
		"""دریافت ساختار و آمار اسناد از دیتابیس جدید"""
		# آمار کلی
		query = text("""
			SELECT 
				COUNT(*) as total,
				COUNT(DISTINCT business_id) as business_count,
				COUNT(DISTINCT document_type) as type_count
			FROM documents
		""")
		result = self.new_db.execute(query).fetchone()
		
		total_docs = result[0] if result else 0
		business_count = result[1] if result else 0
		type_count = result[2] if result else 0
		
		# آمار بر اساس نوع
		query = text("""
			SELECT document_type, COUNT(*) as count
			FROM documents
			GROUP BY document_type
			ORDER BY count DESC
		""")
		results = self.new_db.execute(query).fetchall()
		
		by_type = {}
		for row in results:
			by_type[row[0]] = row[1]
		
		# آمار بر اساس کسب و کار
		query = text("""
			SELECT business_id, COUNT(*) as count
			FROM documents
			GROUP BY business_id
			ORDER BY count DESC
			LIMIT 20
		""")
		results = self.new_db.execute(query).fetchall()
		
		by_business = {}
		for row in results:
			by_business[row[0]] = row[1]
		
		# نمونه اسناد
		query = text("""
			SELECT 
				id, code, business_id, fiscal_year_id, currency_id,
				created_by_user_id, registered_at, document_date, 
				document_type, is_proforma, description, project_id
			FROM documents
			ORDER BY id ASC
			LIMIT 5
		""")
		results = self.new_db.execute(query).fetchall()
		
		sample_docs = []
		for row in results:
			sample_docs.append({
				"id": row[0],
				"code": row[1],
				"business_id": row[2],
				"fiscal_year_id": row[3],
				"currency_id": row[4],
				"created_by_user_id": row[5],
				"registered_at": row[6],
				"document_date": row[7],
				"document_type": row[8],
				"is_proforma": row[9],
				"description": row[10],
				"project_id": row[11]
			})
		
		return {
			"total": total_docs,
			"business_count": business_count,
			"type_count": type_count,
			"by_type": by_type,
			"by_business": by_business,
			"sample_docs": sample_docs
		}
	
	def get_new_document_lines_structure(self) -> Dict[str, Any]:
		"""دریافت ساختار و آمار سطرهای سند از دیتابیس جدید"""
		# آمار کلی
		query = text("SELECT COUNT(*) FROM document_lines")
		total_rows = self.new_db.execute(query).scalar()
		
		# آمار بر اساس document_id
		query = text("""
			SELECT 
				COUNT(DISTINCT document_id) as doc_count,
				AVG(rows_per_doc) as avg_rows
			FROM (
				SELECT document_id, COUNT(*) as rows_per_doc
				FROM document_lines
				GROUP BY document_id
			) as subquery
		""")
		result = self.new_db.execute(query).fetchone()
		doc_count = result[0] if result else 0
		avg_rows = float(result[1]) if result and result[1] else 0
		
		# نمونه سطرها
		query = text("""
			SELECT 
				id, document_id, account_id, person_id, product_id,
				bank_account_id, cash_register_id, petty_cash_id, check_id,
				debit, credit, description, quantity
			FROM document_lines
			ORDER BY id ASC
			LIMIT 5
		""")
		results = self.new_db.execute(query).fetchall()
		
		sample_rows = []
		for row in results:
			sample_rows.append({
				"id": row[0],
				"document_id": row[1],
				"account_id": row[2],
				"person_id": row[3],
				"product_id": row[4],
				"bank_account_id": row[5],
				"cash_register_id": row[6],
				"petty_cash_id": row[7],
				"check_id": row[8],
				"debit": row[9],
				"credit": row[10],
				"description": row[11],
				"quantity": row[12]
			})
		
		return {
			"total": total_rows,
			"doc_count": doc_count,
			"avg_rows_per_doc": avg_rows,
			"sample_rows": sample_rows
		}
	
	def analyze_document_type_mapping(self, old_types: Dict[str, int]) -> Dict[str, Any]:
		"""تحلیل نگاشت انواع سند"""
		mapping_analysis = {}
		unmapped_types = []
		
		for old_type, count in old_types.items():
			new_type = self.map_old_document_type_to_new(old_type)
			mapping_analysis[old_type] = {
				"old_type": old_type,
				"new_type": new_type,
				"count": count,
				"mapped": new_type != "manual" or old_type in ["transfer", "modify_cheque"]
			}
			
			if not mapping_analysis[old_type]["mapped"] and old_type not in ["transfer", "modify_cheque"]:
				unmapped_types.append(old_type)
		
		return {
			"mappings": mapping_analysis,
			"unmapped_types": unmapped_types
		}
	
	def run_analysis(self):
		"""اجرای تحلیل کامل"""
		print("=" * 100)
		print("🔍 تحلیل و بررسی اسناد حسابداری برای انتقال")
		print("=" * 100)
		
		# دریافت داده‌ها
		print("\n📊 دریافت داده‌ها از دیتابیس قدیمی...")
		old_docs = self.get_old_documents_structure()
		old_rows = self.get_old_document_rows_structure()
		print(f"✅ {old_docs['total']:,} سند و {old_rows['total']:,} سطر در دیتابیس قدیمی یافت شد")
		
		print("\n📊 دریافت داده‌ها از دیتابیس جدید...")
		new_docs = self.get_new_documents_structure()
		new_rows = self.get_new_document_lines_structure()
		print(f"✅ {new_docs['total']:,} سند و {new_rows['total']:,} سطر در دیتابیس جدید یافت شد")
		
		# آمار کلی
		print("\n" + "=" * 100)
		print("📈 آمار کلی")
		print("=" * 100)
		
		print(f"\n🔹 دیتابیس قدیمی (hesabdari_doc & hesabdari_row):")
		print(f"   - تعداد کل اسناد: {old_docs['total']:,}")
		print(f"   - تعداد کل سطرها: {old_rows['total']:,}")
		print(f"   - تعداد کسب و کارهای دارای سند: {old_docs['business_count']}")
		print(f"   - تعداد انواع مختلف سند: {old_docs['type_count']}")
		print(f"   - میانگین سطرها در هر سند: {old_rows['avg_rows_per_doc']:.2f}")
		
		print(f"\n🔹 دیتابیس جدید (documents & document_lines):")
		print(f"   - تعداد کل اسناد: {new_docs['total']:,}")
		print(f"   - تعداد کل سطرها: {new_rows['total']:,}")
		print(f"   - تعداد کسب و کارهای دارای سند: {new_docs['business_count']}")
		print(f"   - تعداد انواع مختلف سند: {new_docs['type_count']}")
		if new_rows['doc_count'] > 0:
			print(f"   - میانگین سطرها در هر سند: {new_rows['avg_rows_per_doc']:.2f}")
		
		# توزیع بر اساس نوع سند
		print("\n" + "=" * 100)
		print("📋 توزیع بر اساس نوع سند")
		print("=" * 100)
		
		print(f"\n🔹 دیتابیس قدیمی (hesabdari_doc):")
		print(f"   {'نوع سند':<30s} {'تعداد':<15s} {'نوع جدید':<30s}")
		print(f"   {'-'*75}")
		for old_type, count in sorted(old_docs['by_type'].items(), key=lambda x: x[1], reverse=True)[:15]:
			new_type = self.map_old_document_type_to_new(old_type)
			print(f"   {old_type:<30s} {count:>15,} {new_type:<30s}")
		
		print(f"\n🔹 دیتابیس جدید (documents):")
		print(f"   {'نوع سند':<30s} {'تعداد':<15s}")
		print(f"   {'-'*45}")
		for doc_type, count in sorted(new_docs['by_type'].items(), key=lambda x: x[1], reverse=True):
			print(f"   {doc_type:<30s} {count:>15,}")
		
		# تحلیل نگاشت انواع سند
		print("\n" + "=" * 100)
		print("🔄 تحلیل نگاشت انواع سند")
		print("=" * 100)
		
		mapping_analysis = self.analyze_document_type_mapping(old_docs['by_type'])
		
		print(f"\n✅ نگاشت انواع سند:")
		print(f"   {'نوع قدیمی':<30s} {'→':<5s} {'نوع جدید':<30s} {'تعداد':<15s}")
		print(f"   {'-'*80}")
		for old_type, info in sorted(mapping_analysis['mappings'].items(), 
		                              key=lambda x: x[1]['count'], reverse=True)[:15]:
			arrow = "→"
			count = info['count']
			print(f"   {old_type:<30s} {arrow:<5s} {info['new_type']:<30s} {count:>15,}")
		
		if mapping_analysis['unmapped_types']:
			print(f"\n⚠️  انواع سند بدون نگاشت مشخص:")
			for unmapped_type in mapping_analysis['unmapped_types']:
				print(f"   - {unmapped_type}")
		
		# ساختار جدول‌ها
		print("\n" + "=" * 100)
		print("🏗️  مقایسه ساختار جدول‌ها")
		print("=" * 100)
		
		print(f"\n🔹 جدول اسناد:")
		print(f"   قدیمی (hesabdari_doc):")
		print(f"     - bid_id (business_id)")
		print(f"     - submitter_id (created_by_user_id)")
		print(f"     - year_id (fiscal_year_id)")
		print(f"     - money_id (currency_id)")
		print(f"     - date_submit (registered_at)")
		print(f"     - date (document_date)")
		print(f"     - type (document_type)")
		print(f"     - code (code)")
		print(f"     - des (description)")
		print(f"     - is_preview (is_proforma)")
		print(f"     - is_approved")
		print(f"     - project_id")
		
		print(f"\n   جدید (documents):")
		print(f"     - business_id (NOT NULL)")
		print(f"     - created_by_user_id (NOT NULL)")
		print(f"     - fiscal_year_id (NOT NULL)")
		print(f"     - currency_id (NOT NULL)")
		print(f"     - registered_at (datetime)")
		print(f"     - document_date (date)")
		print(f"     - document_type (NOT NULL)")
		print(f"     - code (NOT NULL)")
		print(f"     - description (text, nullable)")
		print(f"     - is_proforma (boolean)")
		print(f"     - project_id (nullable)")
		
		print(f"\n🔹 جدول سطرهای سند:")
		print(f"   قدیمی (hesabdari_row):")
		print(f"     - doc_id → document_id")
		print(f"     - ref_id → account_id (ارجاع به hesabdari_table)")
		print(f"     - person_id → person_id")
		print(f"     - bank_id → bank_account_id")
		print(f"     - bs (بدهکار) → debit")
		print(f"     - bd (بستانکار) → credit")
		print(f"     - des → description")
		print(f"     - commodity_id → product_id")
		print(f"     - commdity_count → quantity")
		print(f"     - salary_id → petty_cash_id")
		print(f"     - cashdesk_id → cash_register_id")
		print(f"     - cheque_id → check_id")
		
		print(f"\n   جدید (document_lines):")
		print(f"     - document_id (NOT NULL)")
		print(f"     - account_id (nullable)")
		print(f"     - person_id (nullable)")
		print(f"     - product_id (nullable)")
		print(f"     - bank_account_id (nullable)")
		print(f"     - cash_register_id (nullable)")
		print(f"     - petty_cash_id (nullable)")
		print(f"     - check_id (nullable)")
		print(f"     - debit (NOT NULL, default 0)")
		print(f"     - credit (NOT NULL, default 0)")
		print(f"     - quantity (nullable, default 0)")
		print(f"     - description (text, nullable)")
		
		# نمونه داده‌ها
		print("\n" + "=" * 100)
		print("📝 نمونه داده‌ها")
		print("=" * 100)
		
		if old_docs['sample_docs']:
			print(f"\n🔹 نمونه اسناد قدیمی:")
			for i, doc in enumerate(old_docs['sample_docs'][:3], 1):
				print(f"\n   سند {i}:")
				print(f"     ID: {doc['id']}")
				print(f"     Business ID: {doc['business_id']}")
				print(f"     Type: {doc['type']}")
				print(f"     Code: {doc['code']}")
				print(f"     Date: {doc['date']}")
				print(f"     Description: {doc['description']}")
		
		if new_docs['sample_docs']:
			print(f"\n🔹 نمونه اسناد جدید:")
			for i, doc in enumerate(new_docs['sample_docs'][:3], 1):
				print(f"\n   سند {i}:")
				print(f"     ID: {doc['id']}")
				print(f"     Business ID: {doc['business_id']}")
				print(f"     Type: {doc['document_type']}")
				print(f"     Code: {doc['code']}")
				print(f"     Date: {doc['document_date']}")
				print(f"     Description: {doc['description']}")
		
		# چالش‌ها و نکات مهم
		print("\n" + "=" * 100)
		print("⚠️  چالش‌ها و نکات مهم برای انتقال")
		print("=" * 100)
		
		print("""
🔹 نگاشت داده‌ها:

1. نگاشت شناسه‌ها:
   - bid_id → business_id (نیاز به business_id mapping)
   - submitter_id → created_by_user_id (نیاز به user_id mapping)
   - year_id → fiscal_year_id (نیاز به fiscal_year_id mapping)
   - money_id → currency_id (نیاز به currency_id mapping)

2. نگاشت انواع سند:
   - sell → invoice_sales
   - sell_receive → receipt
   - buy → invoice_purchase
   - buy_send → payment
   - person_receive → receipt
   - person_send → payment
   - cost → expense
   - income → income
   - transfer → transfer
   - modify_cheque → manual (یا نوع مناسب برای چک)

3. نگاشت سطرهای سند:
   - ref_id (از hesabdari_table) → account_id (از accounts)
     ⚠️  نیاز به mapping بین hesabdari_table.id و accounts.id
   - bank_id (از bank_account) → bank_account_id (از bank_accounts)
     ⚠️  نیاز به mapping بین bank_account.id و bank_accounts.id
   - salary_id (از salary) → petty_cash_id (از petty_cash)
     ⚠️  نیاز به mapping بین salary.id و petty_cash.id
   - cashdesk_id (از cashdesk) → cash_register_id (از cash_registers)
     ⚠️  نیاز به mapping بین cashdesk.id و cash_registers.id
   - commodity_id (از commodity) → product_id (از products)
     ⚠️  نیاز به mapping بین commodity.id و products.id
   - cheque_id (از cheque) → check_id (از checks)
     ⚠️  نیاز به mapping بین cheque.id و checks.id

4. تبدیل تاریخ:
   - date_submit: varchar (timestamp) → registered_at: datetime
   - date: varchar (جلالی یا timestamp) → document_date: date
     ⚠️  نیاز به تبدیل فرمت تاریخ

5. بررسی تکراری:
   - قبل از درج، باید بررسی کنیم که آیا سند با همان business_id و code وجود دارد یا نه
   - constraint: uq_documents_business_code (business_id, code)

6. حجم داده:
   - ⚠️  حجم زیاد داده: {total_docs:,} سند و {total_rows:,} سطر
   - پیشنهاد: انتقال به صورت batch
   - پیشنهاد: فقط اسناد تایید شده (is_approved = 1) را منتقل کنیم
   - پیشنهاد: فقط اسناد غیر پیش‌نمایش (is_preview = 0) را منتقل کنیم

7. وابستگی‌ها:
   - قبل از انتقال اسناد، باید این جداول منتقل شده باشند:
     ✓ businesses
     ✓ users
     ✓ fiscal_years
     ✓ currencies
     ✓ accounts (hesabdari_table → accounts)
     ✓ persons
     ✓ products (commodity → products)
     ✓ bank_accounts
     ✓ cash_registers
     ✓ petty_cash
     ✓ checks

8. ساختار درختی:
   - در دیتابیس جدید، سطرهای سند مستقیم به document_id متصل هستند
   - باید تمام سطرهای مربوط به یک doc_id قدیمی را پیدا کرده و به document_id جدید متصل کنیم

9. محاسبات:
   - باید مطمئن شویم که مجموع بدهکار = مجموع بستانکار برای هر سند
   - می‌توانیم از این به عنوان validation استفاده کنیم

10. پیشنهادات:
    - قبل از انتقال، backup کامل بگیریم
    - از transaction استفاده کنیم تا در صورت خطا، rollback شود
    - فقط کسب و کارهای منتقل شده را بررسی کنیم
    - فقط سال‌های مالی منتقل شده را بررسی کنیم
    - لاگ کامل از عملیات انتقال نگه داریم
		""".format(
			total_docs=old_docs['total'],
			total_rows=old_rows['total']
		))
		
		print("\n" + "=" * 100)
		print("✅ تحلیل کامل شد")
		print("=" * 100)
		
		return {
			"old_docs": old_docs,
			"old_rows": old_rows,
			"new_docs": new_docs,
			"new_rows": new_rows,
			"mapping_analysis": mapping_analysis
		}
	
	def close(self):
		"""بستن اتصالات"""
		self.old_db.close()
		self.new_db.close()


def main():
	parser = argparse.ArgumentParser(description="تحلیل و بررسی اسناد حسابداری برای انتقال")
	parser.add_argument("--old-db", default="hesabixOld", help="نام دیتابیس قدیمی")
	parser.add_argument("--new-db", default="hesabixpy", help="نام دیتابیس جدید")
	parser.add_argument("--db-user", default="root", help="نام کاربری دیتابیس")
	parser.add_argument("--db-password", default="136431", help="رمز عبور دیتابیس")
	parser.add_argument("--db-host", default="localhost", help="آدرس دیتابیس")
	parser.add_argument("--db-port", type=int, default=3306, help="پورت دیتابیس")
	
	args = parser.parse_args()
	
	analyzer = DocumentsAnalyzer(
		old_db_name=args.old_db,
		new_db_name=args.new_db,
		db_user=args.db_user,
		db_password=args.db_password,
		db_host=args.db_host,
		db_port=args.db_port
	)
	
	try:
		analyzer.run_analysis()
	finally:
		analyzer.close()


if __name__ == "__main__":
	main()

