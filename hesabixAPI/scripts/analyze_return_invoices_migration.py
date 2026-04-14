#!/usr/bin/env python3
"""
اسکریپت تحلیل و بررسی فاکتورهای برگشت از خرید و فروش برای انتقال

این اسکریپت:
- بررسی فاکتورهای rfsell و rfbuy در دیتابیس قدیمی
- بررسی نحوه ذخیره‌سازی در کد جدید (invoice_sales_return و invoice_purchase_return)
- بررسی ارتباط با جدول حساب‌ها
- شناسایی مشکلات احتمالی در ساختار داده‌ها
"""

import sys
import os
import argparse
from typing import List, Dict, Any, Optional, Set, Tuple
from collections import defaultdict
from decimal import Decimal

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session


class ReturnInvoicesAnalyzer:
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
	
	def get_return_invoices_stats(self) -> Dict[str, Any]:
		"""دریافت آمار فاکتورهای برگشت"""
		query = text("""
			SELECT 
				type,
				COUNT(*) as count,
				COUNT(DISTINCT bid_id) as business_count
			FROM hesabdari_doc
			WHERE type IN ('rfsell', 'rfbuy')
			GROUP BY type
		""")
		results = self.old_db.execute(query).fetchall()
		
		stats = {}
		for row in results:
			stats[row[0]] = {
				"count": row[1],
				"business_count": row[2]
			}
		
		return stats
	
	def analyze_return_sales_invoices(self) -> Dict[str, Any]:
		"""تحلیل فاکتورهای برگشت از فروش (rfsell)"""
		# دریافت تمام اسناد برگشت از فروش
		query = text("""
			SELECT 
				d.id, d.bid_id, d.code, d.des, d.date,
				COUNT(r.id) as row_count,
				SUM(CAST(r.bs AS DECIMAL(18,2))) as total_debit,
				SUM(CAST(r.bd AS DECIMAL(18,2))) as total_credit
			FROM hesabdari_doc d
			LEFT JOIN hesabdari_row r ON d.id = r.doc_id
			WHERE d.type = 'rfsell'
			GROUP BY d.id, d.bid_id, d.code, d.des, d.date
			ORDER BY d.id
		""")
		results = self.old_db.execute(query).fetchall()
		
		documents = []
		for row in results:
			total_debit = float(row[6] or 0)
			total_credit = float(row[7] or 0)
			balance_diff = abs(total_debit - total_credit)
			
			documents.append({
				"id": row[0],
				"business_id": row[1],
				"code": row[2],
				"description": row[3],
				"date": row[4],
				"row_count": row[5],
				"total_debit": total_debit,
				"total_credit": total_credit,
				"balance_diff": balance_diff,
				"is_balanced": balance_diff < 1.0  # اختلاف کمتر از 1 ریال
			})
		
		# تحلیل سطرها
		query = text("""
			SELECT 
				r.id, r.doc_id, r.ref_id, r.bs, r.bd, r.des, 
				r.person_id, r.commodity_id, r.bank_id,
				t.name as account_name, t.type as account_type, t.code as account_code
			FROM hesabdari_row r
			INNER JOIN hesabdari_doc d ON r.doc_id = d.id
			LEFT JOIN hesabdari_table t ON r.ref_id = t.id
			WHERE d.type = 'rfsell'
			ORDER BY r.doc_id, r.id
			LIMIT 50
		""")
		results = self.old_db.execute(query).fetchall()
		
		sample_rows = []
		for row in results:
			sample_rows.append({
				"id": row[0],
				"doc_id": row[1],
				"ref_id": row[2],
				"debit": float(row[3] or 0),
				"credit": float(row[4] or 0),
				"description": row[5],
				"person_id": row[6],
				"commodity_id": row[7],
				"bank_id": row[8],
				"account_name": row[9],
				"account_type": row[10],
				"account_code": row[11]
			})
		
		# تحلیل ref_id ها
		query = text("""
			SELECT 
				r.ref_id,
				COUNT(*) as usage_count,
				t.name as account_name,
				t.type as account_type,
				t.code as account_code
			FROM hesabdari_row r
			INNER JOIN hesabdari_doc d ON r.doc_id = d.id
			LEFT JOIN hesabdari_table t ON r.ref_id = t.id
			WHERE d.type = 'rfsell'
			GROUP BY r.ref_id, t.name, t.type, t.code
			ORDER BY usage_count DESC
		""")
		results = self.old_db.execute(query).fetchall()
		
		ref_id_usage = {}
		for row in results:
			ref_id_usage[row[0]] = {
				"usage_count": row[1],
				"account_name": row[2],
				"account_type": row[3],
				"account_code": row[4]
			}
		
		return {
			"documents": documents,
			"sample_rows": sample_rows,
			"ref_id_usage": ref_id_usage,
			"balanced_count": sum(1 for d in documents if d["is_balanced"]),
			"unbalanced_count": sum(1 for d in documents if not d["is_balanced"])
		}
	
	def analyze_return_purchase_invoices(self) -> Dict[str, Any]:
		"""تحلیل فاکتورهای برگشت از خرید (rfbuy)"""
		# دریافت تمام اسناد برگشت از خرید
		query = text("""
			SELECT 
				d.id, d.bid_id, d.code, d.des, d.date,
				COUNT(r.id) as row_count,
				SUM(CAST(r.bs AS DECIMAL(18,2))) as total_debit,
				SUM(CAST(r.bd AS DECIMAL(18,2))) as total_credit
			FROM hesabdari_doc d
			LEFT JOIN hesabdari_row r ON d.id = r.doc_id
			WHERE d.type = 'rfbuy'
			GROUP BY d.id, d.bid_id, d.code, d.des, d.date
			ORDER BY d.id
		""")
		results = self.old_db.execute(query).fetchall()
		
		documents = []
		for row in results:
			total_debit = float(row[6] or 0)
			total_credit = float(row[7] or 0)
			balance_diff = abs(total_debit - total_credit)
			
			documents.append({
				"id": row[0],
				"business_id": row[1],
				"code": row[2],
				"description": row[3],
				"date": row[4],
				"row_count": row[5],
				"total_debit": total_debit,
				"total_credit": total_credit,
				"balance_diff": balance_diff,
				"is_balanced": balance_diff < 1.0
			})
		
		# تحلیل سطرها
		query = text("""
			SELECT 
				r.id, r.doc_id, r.ref_id, r.bs, r.bd, r.des, 
				r.person_id, r.commodity_id, r.bank_id,
				t.name as account_name, t.type as account_type, t.code as account_code
			FROM hesabdari_row r
			INNER JOIN hesabdari_doc d ON r.doc_id = d.id
			LEFT JOIN hesabdari_table t ON r.ref_id = t.id
			WHERE d.type = 'rfbuy'
			ORDER BY r.doc_id, r.id
			LIMIT 50
		""")
		results = self.old_db.execute(query).fetchall()
		
		sample_rows = []
		for row in results:
			sample_rows.append({
				"id": row[0],
				"doc_id": row[1],
				"ref_id": row[2],
				"debit": float(row[3] or 0),
				"credit": float(row[4] or 0),
				"description": row[5],
				"person_id": row[6],
				"commodity_id": row[7],
				"bank_id": row[8],
				"account_name": row[9],
				"account_type": row[10],
				"account_code": row[11]
			})
		
		# تحلیل ref_id ها
		query = text("""
			SELECT 
				r.ref_id,
				COUNT(*) as usage_count,
				t.name as account_name,
				t.type as account_type,
				t.code as account_code
			FROM hesabdari_row r
			INNER JOIN hesabdari_doc d ON r.doc_id = d.id
			LEFT JOIN hesabdari_table t ON r.ref_id = t.id
			WHERE d.type = 'rfbuy'
			GROUP BY r.ref_id, t.name, t.type, t.code
			ORDER BY usage_count DESC
		""")
		results = self.old_db.execute(query).fetchall()
		
		ref_id_usage = {}
		for row in results:
			ref_id_usage[row[0]] = {
				"usage_count": row[1],
				"account_name": row[2],
				"account_type": row[3],
				"account_code": row[4]
			}
		
		return {
			"documents": documents,
			"sample_rows": sample_rows,
			"ref_id_usage": ref_id_usage,
			"balanced_count": sum(1 for d in documents if d["is_balanced"]),
			"unbalanced_count": sum(1 for d in documents if not d["is_balanced"])
		}
	
	def get_expected_accounts_for_new_system(self) -> Dict[str, Dict[str, str]]:
		"""حساب‌های مورد انتظار در سیستم جدید برای برگشت از فروش/خرید"""
		return {
			"sales_return": {
				"code": "50002",
				"name": "برگشت از فروش",
				"type": "accounting_document",
				"used_in": "invoice_sales_return"
			},
			"purchase_return_grni": {
				"code": "30101",
				"name": "GRNI",
				"type": "accounting_document",
				"used_in": "invoice_purchase_return"
			},
			"person_receivable": {
				"code": "10401",
				"name": "حساب‌های دریافتنی",
				"type": "accounting_document",
				"used_in": "invoice_sales_return"
			},
			"person_payable": {
				"code": "20201",
				"name": "حساب‌های پرداختنی",
				"type": "accounting_document",
				"used_in": "invoice_purchase_return"
			},
			"sales_discount": {
				"code": "50003",
				"name": "تخفیفات فروش",
				"type": "accounting_document",
				"used_in": "invoice_sales_return"
			},
			"purchase_discount": {
				"code": "40003",
				"name": "تخفیفات خرید",
				"type": "accounting_document",
				"used_in": "invoice_purchase_return"
			},
			"vat_out": {
				"code": "20101",
				"name": "مالیات بر ارزش افزوده خروجی",
				"type": "accounting_document",
				"used_in": "invoice_sales_return"
			},
			"vat_in": {
				"code": "10104",
				"name": "مالیات بر ارزش افزوده ورودی",
				"type": "accounting_document",
				"used_in": "invoice_purchase_return"
			}
		}
	
	def run_analysis(self):
		"""اجرای تحلیل کامل"""
		print("=" * 100)
		print("🔍 تحلیل فاکتورهای برگشت از خرید و فروش برای انتقال")
		print("=" * 100)
		
		# آمار کلی
		print("\n📊 آمار کلی فاکتورهای برگشت:")
		stats = self.get_return_invoices_stats()
		for inv_type, data in stats.items():
			old_type_name = "برگشت از فروش" if inv_type == "rfsell" else "برگشت از خرید"
			new_type_name = "invoice_sales_return" if inv_type == "rfsell" else "invoice_purchase_return"
			print(f"   - {old_type_name} ({inv_type}): {data['count']:,} فاکتور در {data['business_count']} کسب و کار")
			print(f"     → باید به {new_type_name} تبدیل شود")
		
		# تحلیل برگشت از فروش
		print("\n" + "=" * 100)
		print("📋 تحلیل برگشت از فروش (rfsell → invoice_sales_return)")
		print("=" * 100)
		
		rfsell_analysis = self.analyze_return_sales_invoices()
		print(f"\n✅ آمار اسناد برگشت از فروش:")
		print(f"   - تعداد کل اسناد: {len(rfsell_analysis['documents'])}")
		print(f"   - اسناد متعادل: {rfsell_analysis['balanced_count']}")
		print(f"   - اسناد نامتعادل: {rfsell_analysis['unbalanced_count']}")
		
		if rfsell_analysis['unbalanced_count'] > 0:
			print(f"\n⚠️  اسناد نامتعادل (اختلاف بدهکار/بستانکار):")
			unbalanced = [d for d in rfsell_analysis['documents'] if not d["is_balanced"]]
			for doc in unbalanced[:5]:
				print(f"   - سند ID: {doc['id']}, کد: {doc['code']}, اختلاف: {doc['balance_diff']:,.0f} ریال")
		
		print(f"\n📊 استفاده از حساب‌ها (ref_id) در برگشت از فروش:")
		print(f"   {'ref_id':<10s} {'نام حساب':<40s} {'نوع':<15s} {'کد':<10s} {'استفاده':<10s}")
		print(f"   {'-'*85}")
		for ref_id, info in sorted(rfsell_analysis['ref_id_usage'].items(), 
		                            key=lambda x: x[1]['usage_count'], reverse=True)[:10]:
			print(f"   {ref_id:<10d} {info['account_name'] or 'N/A':<40s} {info['account_type'] or 'N/A':<15s} {info['account_code'] or 'N/A':<10s} {info['usage_count']:>10,}")
		
		print(f"\n📝 نمونه سطرهای برگشت از فروش:")
		for i, row in enumerate(rfsell_analysis['sample_rows'][:5], 1):
			print(f"\n   سطر {i}:")
			print(f"     Doc ID: {row['doc_id']}, Ref ID: {row['ref_id']}")
			print(f"     حساب: {row['account_name']} ({row['account_code']})")
			print(f"     بدهکار: {row['debit']:,.0f}, بستانکار: {row['credit']:,.0f}")
			if row['person_id']:
				print(f"     شخص: {row['person_id']}")
			if row['commodity_id']:
				print(f"     کالا: {row['commodity_id']}")
		
		# تحلیل برگشت از خرید
		print("\n" + "=" * 100)
		print("📋 تحلیل برگشت از خرید (rfbuy → invoice_purchase_return)")
		print("=" * 100)
		
		rfbuy_analysis = self.analyze_return_purchase_invoices()
		print(f"\n✅ آمار اسناد برگشت از خرید:")
		print(f"   - تعداد کل اسناد: {len(rfbuy_analysis['documents'])}")
		print(f"   - اسناد متعادل: {rfbuy_analysis['balanced_count']}")
		print(f"   - اسناد نامتعادل: {rfbuy_analysis['unbalanced_count']}")
		
		if rfbuy_analysis['unbalanced_count'] > 0:
			print(f"\n⚠️  اسناد نامتعادل:")
			unbalanced = [d for d in rfbuy_analysis['documents'] if not d["is_balanced"]]
			for doc in unbalanced[:5]:
				print(f"   - سند ID: {doc['id']}, کد: {doc['code']}, اختلاف: {doc['balance_diff']:,.0f} ریال")
		
		print(f"\n📊 استفاده از حساب‌ها (ref_id) در برگشت از خرید:")
		print(f"   {'ref_id':<10s} {'نام حساب':<40s} {'نوع':<15s} {'کد':<10s} {'استفاده':<10s}")
		print(f"   {'-'*85}")
		for ref_id, info in sorted(rfbuy_analysis['ref_id_usage'].items(), 
		                            key=lambda x: x[1]['usage_count'], reverse=True)[:10]:
			print(f"   {ref_id:<10d} {info['account_name'] or 'N/A':<40s} {info['account_type'] or 'N/A':<15s} {info['account_code'] or 'N/A':<10s} {info['usage_count']:>10,}")
		
		print(f"\n📝 نمونه سطرهای برگشت از خرید:")
		for i, row in enumerate(rfbuy_analysis['sample_rows'][:5], 1):
			print(f"\n   سطر {i}:")
			print(f"     Doc ID: {row['doc_id']}, Ref ID: {row['ref_id']}")
			print(f"     حساب: {row['account_name']} ({row['account_code']})")
			print(f"     بدهکار: {row['debit']:,.0f}, بستانکار: {row['credit']:,.0f}")
			if row['person_id']:
				print(f"     شخص: {row['person_id']}")
			if row['commodity_id']:
				print(f"     کالا: {row['commodity_id']}")
		
		# مقایسه با سیستم جدید
		print("\n" + "=" * 100)
		print("🔄 مقایسه با سیستم جدید")
		print("=" * 100)
		
		expected_accounts = self.get_expected_accounts_for_new_system()
		
		print(f"\n✅ حساب‌های مورد نیاز در سیستم جدید:")
		for acc_key, acc_info in expected_accounts.items():
			print(f"   - {acc_key}: کد {acc_info['code']} - {acc_info['name']}")
			print(f"     استفاده در: {acc_info['used_in']}")
		
		print(f"\n📋 نحوه ثبت در سیستم جدید:")
		
		print(f"\n   🔹 برگشت از فروش (invoice_sales_return):")
		print(f"      1. حساب شخص (10401): بستانکار = مبلغ کل با مالیات")
		print(f"      2. حساب برگشت از فروش (50002): بدهکار = مبلغ ناخالص")
		print(f"      3. حساب تخفیفات فروش (50003): بستانکار = مبلغ تخفیف (اگر وجود داشته باشد)")
		print(f"      4. حساب مالیات خروجی (20101): بدهکار = مبلغ مالیات")
		
		print(f"\n   🔹 برگشت از خرید (invoice_purchase_return):")
		print(f"      1. حساب شخص (20201): بدهکار = مبلغ کل با مالیات")
		print(f"      2. حساب GRNI (30101): بستانکار = مبلغ ناخالص")
		print(f"      3. حساب تخفیفات خرید (40003): بدهکار = مبلغ تخفیف (اگر وجود داشته باشد)")
		print(f"      4. حساب مالیات ورودی (10104): بستانکار = مبلغ مالیات")
		
		# چالش‌ها و راهکارها
		print("\n" + "=" * 100)
		print("⚠️  چالش‌ها و راهکارهای انتقال")
		print("=" * 100)
		
		print("""
🔹 مشکلات احتمالی:

1. نگاشت ref_id به account_id:
   - در دیتابیس قدیمی: ref_id به hesabdari_table.id اشاره می‌کند
   - در دیتابیس جدید: account_id به accounts.id اشاره می‌کند
   - ⚠️  نیاز به mapping دقیق بین hesabdari_table و accounts
   - باید بر اساس کد حساب (code) و business_id نگاشت انجام شود

2. ساختار متفاوت ثبت‌های حسابداری:
   - در دیتابیس قدیمی ممکن است ساختار متفاوتی داشته باشد
   - در سیستم جدید، ثبت‌ها به صورت خودکار از invoice_type تولید می‌شوند
   - ⚠️  باید بررسی کنیم که آیا سطرهای قدیمی با منطق جدید سازگار هستند

3. اسناد نامتعادل:
   - اگر اسناد نامتعادل وجود دارد، باید بررسی کنیم که آیا باگ است یا منطق متفاوتی دارد
   - ممکن است نیاز به تصحیح دستی داشته باشد

4. حساب‌های مورد نیاز:
   - باید مطمئن شویم که همه حساب‌های مورد نیاز در سیستم جدید وجود دارند:
     ✓ حساب‌های دریافتنی (10401)
     ✓ حساب‌های پرداختنی (20201)
     ✓ برگشت از فروش (50002)
     ✓ GRNI (30101)
     ✓ تخفیفات فروش (50003)
     ✓ تخفیفات خرید (40003)
     ✓ مالیات خروجی (20101)
     ✓ مالیات ورودی (10104)

🔹 راهکار انتقال:

1. قبل از انتقال:
   - بررسی و تصحیح اسناد نامتعادل
   - اطمینان از وجود تمام حساب‌های مورد نیاز
   - ایجاد mapping کامل بین hesabdari_table و accounts

2. در حین انتقال:
   - تبدیل rfsell → invoice_sales_return
   - تبدیل rfbuy → invoice_purchase_return
   - نگاشت ref_id → account_id بر اساس mapping
   - تبدیل تاریخ از فرمت قدیمی به جدید
   - نگاشت person_id, commodity_id, bank_id و ...

3. پس از انتقال:
   - بررسی تعادل همه اسناد منتقل شده
   - مقایسه مانده حساب‌ها قبل و بعد از انتقال
   - تست عملکرد اسناد در سیستم جدید

4. نگاشت ref_id → account_id:
   - ابتدا باید mapping بین hesabdari_table.id و accounts.id ایجاد شود
   - این mapping باید بر اساس:
     * business_id (باید نگاشت شده باشد)
     * کد حساب (code) - باید یکسان باشد
     * نوع حساب (type → account_type) - باید نگاشت شود
   - برای حساب‌های عمومی (bid_id IS NULL)، باید از حساب‌های عمومی استفاده شود

5. نکات مهم:
   - اگر ref_id در hesabdari_table وجود ندارد، باید بررسی کنیم که آیا حساب حذف شده یا باگ است
   - اگر account_id در accounts پیدا نشد، باید تصمیم بگیریم که:
     * آیا حساب را ایجاد کنیم؟
     * آیا سطر را حذف کنیم؟
     * آیا از حساب جایگزین استفاده کنیم؟
		""")
		
		print("\n" + "=" * 100)
		print("✅ تحلیل کامل شد")
		print("=" * 100)
		
		return {
			"stats": stats,
			"rfsell_analysis": rfsell_analysis,
			"rfbuy_analysis": rfbuy_analysis,
			"expected_accounts": expected_accounts
		}
	
	def close(self):
		"""بستن اتصالات"""
		self.old_db.close()
		self.new_db.close()


def main():
	parser = argparse.ArgumentParser(description="تحلیل فاکتورهای برگشت از خرید و فروش")
	parser.add_argument("--old-db", default="hesabixOld", help="نام دیتابیس قدیمی")
	parser.add_argument("--new-db", default="hesabixpy", help="نام دیتابیس جدید")
	parser.add_argument("--db-user", default="root", help="نام کاربری دیتابیس")
	parser.add_argument("--db-password", default="136431", help="رمز عبور دیتابیس")
	parser.add_argument("--db-host", default="localhost", help="آدرس دیتابیس")
	parser.add_argument("--db-port", type=int, default=3306, help="پورت دیتابیس")
	
	args = parser.parse_args()
	
	analyzer = ReturnInvoicesAnalyzer(
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

