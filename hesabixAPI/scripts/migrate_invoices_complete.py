#!/usr/bin/env python3
"""
اسکریپت انتقال فاکتورهای فروش، خرید، برگشت از فروش و برگشت از خرید از hesabixOld به hesabixpy

این اسکریپت:
- فاکتورهای sell, buy, rfsell, rfbuy را منتقل می‌کند
- از سرویس invoice_service.create_invoice() استفاده می‌کند
- ثبت‌های حسابداری به صورت خودکار انجام می‌شود
"""

import sys
import os
import argparse
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime, date
from decimal import Decimal, InvalidOperation
import re

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session


def convert_timestamp_to_datetime(timestamp_str: str | None) -> datetime | None:
	"""تبدیل timestamp string به datetime"""
	if not timestamp_str:
		return None
	
	try:
		if timestamp_str.strip().isdigit():
			return datetime.fromtimestamp(int(timestamp_str))
	except (ValueError, TypeError, OSError):
		pass
	
	return None


def convert_persian_date_to_date(date_str: str | None) -> date | None:
	"""تبدیل تاریخ شمسی string به date"""
	if not date_str or not date_str.strip():
		return None
	
	date_str = date_str.strip()
	
	# فرمت: 1403/10/05
	match = re.match(r'^(\d{4})/(\d{1,2})/(\d{1,2})$', date_str)
	if match:
		year, month, day = match.groups()
		try:
			import jdatetime
			jd = jdatetime.date(int(year), int(month), int(day))
			gd = jd.togregorian()
			return gd
		except ImportError:
			# تبدیل تقریبی
			gregorian_year = int(year) + 621
			try:
				return date(gregorian_year, int(month), int(day))
			except (ValueError, TypeError):
				pass
	
	return None


def convert_amount(amount_str: str | None) -> Decimal:
	"""تبدیل amount از string به decimal"""
	if not amount_str:
		return Decimal(0)
	
	try:
		cleaned = str(amount_str).strip().replace(',', '').replace(' ', '').replace('،', '')
		if not cleaned or cleaned == '0' or cleaned == '':
			return Decimal(0)
		return Decimal(cleaned)
	except (ValueError, InvalidOperation, TypeError):
		return Decimal(0)


class InvoiceMigration:
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
			pool_size=10,
			max_overflow=20,
			pool_recycle=3600,
			connect_args={
				"connect_timeout": 60,
				"read_timeout": 300,
				"write_timeout": 300,
				"charset": "utf8mb4",
				"init_command": "SET sql_mode='STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO'"
			}
		)
		self.old_db = sessionmaker(bind=old_engine)()
		
		# اتصال به دیتابیس جدید
		new_dsn = f"mysql+pymysql://{db_user}:{db_password}@{db_host}:{db_port}/{new_db_name}"
		new_engine = create_engine(
			new_dsn, 
			echo=False, 
			pool_pre_ping=True,
			pool_size=10,
			max_overflow=20,
			pool_recycle=3600,
			connect_args={
				"connect_timeout": 60,
				"read_timeout": 300,
				"write_timeout": 300,
				"charset": "utf8mb4",
				"init_command": "SET sql_mode='STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO'"
			}
		)
		self.new_db = sessionmaker(bind=new_engine)()
		
		# Cache ها برای بهینه‌سازی
		self.default_currency_cache: Dict[int, int] = {}  # {business_id: currency_id}
		self.default_fiscal_year_cache: Dict[int, int] = {}  # {business_id: fiscal_year_id}
		self.migrated_old_doc_ids: set[int] = set()  # Cache برای migrated documents
		self.migrated_codes_cache: Dict[Tuple[int, str], bool] = {}  # {(business_id, code): True}
		
		# آمار
		self.stats = {
			"invoices_processed": 0,
			"invoices_migrated": 0,
			"invoices_skipped": 0,
			"errors": 0,
			"error_details": []
		}
	
	def create_business_id_mapping(self) -> Dict[int, int]:
		"""ایجاد mapping بین business_id قدیمی و جدید با case-insensitive"""
		query = text("""
			SELECT 
				old_business.id as old_business_id,
				new_business.id as new_business_id
			FROM hesabixOld.business old_business
			INNER JOIN hesabixOld.user old_user ON old_business.owner_id = old_user.id
			INNER JOIN hesabixpy.users new_user ON (
				(old_user.email IS NOT NULL AND new_user.email IS NOT NULL AND LOWER(TRIM(old_user.email)) = LOWER(TRIM(new_user.email))) OR
				(old_user.mobile IS NOT NULL AND new_user.mobile IS NOT NULL AND REPLACE(REPLACE(REPLACE(old_user.mobile, '+', ''), ' ', ''), '-', '') = REPLACE(REPLACE(REPLACE(new_user.mobile, '+', ''), ' ', ''), '-', ''))
			)
			INNER JOIN hesabixpy.businesses new_business ON (
				new_business.owner_id = new_user.id 
				AND new_business.name = old_business.name
			)
			WHERE old_user.active = 1
		""")
		
		results = self.old_db.execute(query).fetchall()
		mapping = {}
		for row in results:
			mapping[row.old_business_id] = row.new_business_id
		
		print(f"✅ Business ID mapping ایجاد شد: {len(mapping)} کسب و کار")
		return mapping
	
	def create_user_id_mapping(self) -> Dict[int, int]:
		"""ایجاد mapping بین user_id قدیمی و جدید با case-insensitive"""
		query = text("""
			SELECT 
				old.id as old_user_id,
				new.id as new_user_id
			FROM hesabixOld.user old
			INNER JOIN hesabixpy.users new ON (
				(old.email IS NOT NULL AND new.email IS NOT NULL AND LOWER(TRIM(old.email)) = LOWER(TRIM(new.email))) OR
				(old.mobile IS NOT NULL AND new.mobile IS NOT NULL AND REPLACE(REPLACE(REPLACE(old.mobile, '+', ''), ' ', ''), '-', '') = REPLACE(REPLACE(REPLACE(new.mobile, '+', ''), ' ', ''), '-', ''))
			)
			WHERE old.active = 1
		""")
		
		results = self.old_db.execute(query).fetchall()
		mapping = {}
		for row in results:
			mapping[row.old_user_id] = row.new_user_id
		
		print(f"✅ User ID mapping ایجاد شد: {len(mapping)} کاربر")
		return mapping
	
	def create_fiscal_year_mapping(self, business_id_mapping: Dict[int, int]) -> Dict[Tuple[int, int], int]:
		"""ایجاد mapping بین fiscal_year_id قدیمی و جدید"""
		# mapping: (old_business_id, old_year_id) -> new_year_id
		mapping = {}
		
		for old_bid, new_bid in business_id_mapping.items():
			# در جدول قدیمی start و end به صورت timestamp (varchar) هستند
			# باید آنها را به date تبدیل کنیم
			query = text("""
				SELECT 
					old.id as old_year_id,
					new.id as new_year_id
				FROM {}.year old
				INNER JOIN {}.fiscal_years new ON (
					new.business_id = :new_bid
					AND new.start_date = DATE(FROM_UNIXTIME(CAST(old.start AS UNSIGNED)))
					AND new.end_date = DATE(FROM_UNIXTIME(CAST(old.end AS UNSIGNED)))
				)
				WHERE old.bid_id = :old_bid
			""".format(self.old_db_name, self.new_db_name))
			
			try:
				results = self.old_db.execute(query, {
					"old_bid": old_bid,
					"new_bid": new_bid
				}).fetchall()
				
				for row in results:
					mapping[(old_bid, row.old_year_id)] = row.new_year_id
			except Exception as e:
				# اگر تبدیل تاریخ با مشکل مواجه شد، فقط بر اساس business_id و label (یا label) جستجو کنیم
				query2 = text("""
					SELECT 
						old.id as old_year_id,
						new.id as new_year_id
					FROM {}.year old
					INNER JOIN {}.fiscal_years new ON (
						new.business_id = :new_bid
						AND new.title = old.label
					)
					WHERE old.bid_id = :old_bid
					LIMIT 1
				""".format(self.old_db_name, self.new_db_name))
				
				try:
					results = self.old_db.execute(query2, {
						"old_bid": old_bid,
						"new_bid": new_bid
					}).fetchall()
					
					for row in results:
						mapping[(old_bid, row.old_year_id)] = row.new_year_id
				except Exception:
					pass  # اگر پیدا نشد، skip می‌کنیم
		
		print(f"✅ Fiscal Year mapping ایجاد شد: {len(mapping)} سال مالی")
		return mapping
	
	def create_currency_mapping(self) -> Dict[int, int]:
		"""ایجاد mapping بین currency_id قدیمی و جدید"""
		query = text("""
			SELECT 
				old.id as old_currency_id,
				new.id as new_currency_id
			FROM {}.money old
			INNER JOIN {}.currencies new ON (
				BINARY new.code = BINARY old.name
				AND BINARY new.symbol = BINARY old.symbol
			)
		""".format(self.old_db_name, self.new_db_name))
		
		results = self.old_db.execute(query).fetchall()
		mapping = {}
		for row in results:
			mapping[row.old_currency_id] = row.new_currency_id
		
		print(f"✅ Currency mapping ایجاد شد: {len(mapping)} ارز")
		return mapping
	
	def create_person_id_mapping(self, business_id_mapping: Dict[int, int]) -> Dict[Tuple[int, int], int]:
		"""ایجاد mapping بین person_id قدیمی و جدید"""
		# mapping: (old_business_id, old_person_id) -> new_person_id
		mapping = {}
		
		for old_bid, new_bid in business_id_mapping.items():
			query = text("""
				SELECT 
					old.id as old_person_id,
					new.id as new_person_id
				FROM {}.person old
				INNER JOIN {}.persons new ON (
					new.business_id = :new_bid
					AND BINARY new.code = BINARY old.code
				)
				WHERE old.bid_id = :old_bid
			""".format(self.old_db_name, self.new_db_name))
			
			results = self.old_db.execute(query, {
				"old_bid": old_bid,
				"new_bid": new_bid
			}).fetchall()
			
			for row in results:
				mapping[(old_bid, row.old_person_id)] = row.new_person_id
		
		print(f"✅ Person ID mapping ایجاد شد: {len(mapping)} شخص")
		return mapping
	
	def create_product_id_mapping(self, business_id_mapping: Dict[int, int]) -> Dict[Tuple[int, int], int]:
		"""ایجاد mapping بین product_id قدیمی و جدید"""
		# mapping: (old_business_id, old_commodity_id) -> new_product_id
		mapping = {}
		
		for old_bid, new_bid in business_id_mapping.items():
			query = text("""
				SELECT 
					old.id as old_commodity_id,
					new.id as new_product_id
				FROM {}.commodity old
				INNER JOIN {}.products new ON (
					new.business_id = :new_bid
					AND BINARY new.code = BINARY old.code
				)
				WHERE old.bid_id = :old_bid
			""".format(self.old_db_name, self.new_db_name))
			
			results = self.old_db.execute(query, {
				"old_bid": old_bid,
				"new_bid": new_bid
			}).fetchall()
			
			for row in results:
				mapping[(old_bid, row.old_commodity_id)] = row.new_product_id
		
		print(f"✅ Product ID mapping ایجاد شد: {len(mapping)} کالا")
		return mapping
	
	def ensure_policy_exists(self, business_id: int):
		"""اطمینان از وجود سیاست درآمدزایی برای کسب‌وکار"""
		# بررسی وجود سیاست
		query = text("""
			SELECT COUNT(*) FROM document_usage_policies
			WHERE business_id = :business_id AND is_active = 1
		""")
		result = self.new_db.execute(query, {"business_id": business_id}).scalar()
		
		if result == 0:
			# ایجاد سیاست free
			query_insert = text("""
				INSERT INTO document_usage_policies 
				(business_id, policy_type, title, priority, is_active, config, created_at, updated_at)
				VALUES 
				(:business_id, 'free', 'سیاست رایگان برای انتقال', 100, 1, NULL, NOW(), NOW())
			""")
			self.new_db.execute(query_insert, {"business_id": business_id})
			self.new_db.commit()
	
	def get_old_invoices(self, invoice_type: str, start_id: Optional[int] = None, 
	                     limit: Optional[int] = None, offset: Optional[int] = None,
	                     business_ids: Optional[List[int]] = None) -> List[Dict[str, Any]]:
		"""دریافت فاکتورها از دیتابیس قدیمی"""
		query_str = """
			SELECT 
				d.id, d.bid_id, d.submitter_id, d.year_id, d.money_id,
				d.date_submit, d.date, d.type, d.code, d.des, d.amount,
				d.is_preview, d.is_approved, d.project_id, d.tax_percent,
				d.discount_type, d.discount_percent
			FROM {}.hesabdari_doc d
			WHERE d.type = :invoice_type
		""".format(self.old_db_name)
		
		params = {"invoice_type": invoice_type}
		
		if business_ids:
			placeholders = ','.join([f':bid_{i}' for i in range(len(business_ids))])
			query_str += f" AND d.bid_id IN ({placeholders})"
			for i, bid in enumerate(business_ids):
				params[f'bid_{i}'] = bid
		elif start_id:
			query_str += " AND d.id >= :start_id"
			params["start_id"] = start_id
		
		# فقط اسناد تایید شده
		query_str += " AND d.is_approved = 1"
		
		query_str += " ORDER BY d.bid_id, d.id ASC"
		
		if limit:
			query_str += " LIMIT :limit"
			params["limit"] = limit
			# فقط زمانی از offset استفاده می‌کنیم که start_id استفاده نشده باشد
			if offset and offset > 0 and not start_id:
				query_str += " OFFSET :offset"
				params["offset"] = offset
		
		results = self.old_db.execute(text(query_str), params).fetchall()
		
		invoices = []
		for row in results:
			invoices.append({
				"id": row[0],
				"business_id": row[1],
				"submitter_id": row[2],
				"year_id": row[3],
				"currency_id": row[4],
				"date_submit": row[5],
				"date": row[6],
				"type": row[7],
				"code": row[8],
				"description": row[9],
				"amount": row[10],
				"is_preview": row[11],
				"is_approved": row[12],
				"project_id": row[13],
				"tax_percent": row[14],
				"discount_type": row[15],
				"discount_percent": row[16]
			})
		
		return invoices
	
	def get_invoice_rows(self, doc_id: int) -> List[Dict[str, Any]]:
		"""دریافت سطرهای فاکتور از دیتابیس قدیمی"""
		query = text("""
			SELECT 
				r.id, r.ref_id, r.person_id, r.commodity_id, r.bs, r.bd, r.des,
				r.commdity_count, r.discount, r.tax, r.bank_id, r.cashdesk_id,
				r.salary_id, r.cheque_id, t.name as account_name, t.type as account_type
			FROM {}.hesabdari_row r
			LEFT JOIN {}.hesabdari_table t ON r.ref_id = t.id
			WHERE r.doc_id = :doc_id
			ORDER BY r.id ASC
		""".format(self.old_db_name, self.old_db_name))
		
		results = self.old_db.execute(query, {"doc_id": doc_id}).fetchall()
	
	def get_invoice_rows_bulk(self, doc_ids: List[int]) -> Dict[int, List[Dict[str, Any]]]:
		"""دریافت سطرهای چند فاکتور به صورت bulk"""
		if not doc_ids:
			return {}
		
		placeholders = ','.join([f':doc_id_{i}' for i in range(len(doc_ids))])
		query = text(f"""
			SELECT 
				r.doc_id, r.id, r.ref_id, r.person_id, r.commodity_id, r.bs, r.bd, r.des,
				r.commdity_count, r.discount, r.tax, r.bank_id, r.cashdesk_id,
				r.salary_id, r.cheque_id, t.name as account_name, t.type as account_type
			FROM {self.old_db_name}.hesabdari_row r
			LEFT JOIN {self.old_db_name}.hesabdari_table t ON r.ref_id = t.id
			WHERE r.doc_id IN ({placeholders})
			ORDER BY r.doc_id, r.id ASC
		""")
		
		params = {f'doc_id_{i}': doc_id for i, doc_id in enumerate(doc_ids)}
		results = self.old_db.execute(query, params).fetchall()
		
		rows_dict: Dict[int, List[Dict[str, Any]]] = {}
		for row in results:
			doc_id = row[0]
			if doc_id not in rows_dict:
				rows_dict[doc_id] = []
			
			rows_dict[doc_id].append({
				"id": row[1],
				"ref_id": row[2],
				"person_id": row[3],
				"commodity_id": row[4],
				"debit": row[5],
				"credit": row[6],
				"description": row[7],
				"quantity": row[8],
				"discount": row[9],
				"tax": row[10],
				"bank_id": row[11],
				"cashdesk_id": row[12],
				"salary_id": row[13],
				"cheque_id": row[14],
				"account_name": row[15],
				"account_type": row[16]
			})
		
		return rows_dict
	
	def _load_migrated_documents_cache(self, business_id_mapping: Dict[int, int]):
		"""بارگذاری cache اسناد منتقل شده از دیتابیس"""
		if not business_id_mapping:
			return
		
		new_business_ids = list(business_id_mapping.values())
		if not new_business_ids:
			return
		
		placeholders = ','.join([f':bid_{i}' for i in range(len(new_business_ids))])
		
		# Load migrated old_document_ids
		query1 = text(f"""
			SELECT JSON_EXTRACT(extra_info, '$.old_document_id') as old_doc_id
			FROM documents
			WHERE business_id IN ({placeholders})
			AND extra_info LIKE '%migration%'
			AND JSON_EXTRACT(extra_info, '$.old_document_id') IS NOT NULL
		""")
		params1 = {f'bid_{i}': bid for i, bid in enumerate(new_business_ids)}
		results1 = self.new_db.execute(query1, params1).fetchall()
		
		for row in results1:
			try:
				old_doc_id = int(row[0])
				self.migrated_old_doc_ids.add(old_doc_id)
			except (ValueError, TypeError):
				pass
		
		# Load migrated codes
		query2 = text(f"""
			SELECT business_id, code
			FROM documents
			WHERE business_id IN ({placeholders})
			AND code IS NOT NULL
		""")
		results2 = self.new_db.execute(query2, params1).fetchall()
		
		for row in results2:
			business_id = row[0]
			code = row[1]
			if business_id and code:
				self.migrated_codes_cache[(business_id, code)] = True
		
		print(f"   📋 Cache بارگذاری شد: {len(self.migrated_old_doc_ids)} سند منتقل شده، {len(self.migrated_codes_cache)} کد")
	
	def _batch_duplicate_check(self, invoices: List[Dict[str, Any]], business_id_mapping: Dict[int, int]):
		"""بررسی تکراری بودن فاکتورها به صورت batch"""
		if not invoices:
			return
		
		# جمع‌آوری business_id و code ها
		business_codes: Dict[int, List[str]] = {}
		for invoice in invoices:
			old_bid = invoice.get('business_id')
			new_bid = business_id_mapping.get(old_bid)
			code = invoice.get('code')
			
			if new_bid and code:
				if new_bid not in business_codes:
					business_codes[new_bid] = []
				business_codes[new_bid].append(code)
		
		# Query batch برای یافتن کدهای تکراری
		for new_bid, codes in business_codes.items():
			if not codes:
				continue
			
			placeholders = ','.join([f':code_{i}' for i in range(len(codes))])
			query = text(f"""
				SELECT code
				FROM documents
				WHERE business_id = :business_id
				AND BINARY code IN ({placeholders})
			""")
			params = {"business_id": new_bid}
			for i, code in enumerate(codes):
				params[f'code_{i}'] = code
			
			results = self.new_db.execute(query, params).fetchall()
			
			# اضافه کردن به cache
			for row in results:
				if row[0]:
					self.migrated_codes_cache[(new_bid, row[0])] = True
	
	def extract_invoice_lines(self, rows: List[Dict[str, Any]], invoice_type: str,
	                         business_id_mapping: Dict[int, int],
	                         product_mapping: Dict[Tuple[int, int], int]) -> List[Dict[str, Any]]:
		"""استخراج و تبدیل سطرهای فاکتور به فرمت جدید"""
		lines = []
		
		# شناسایی ref_id برای کالاها (معمولاً 59 برای فروش کالا)
		# و ref_id برای شخص (معمولاً 3 برای حساب‌های دریافتی)
		
		for row in rows:
			ref_id = row.get("ref_id")
			commodity_id = row.get("commodity_id")
			person_id = row.get("person_id")
			
			# اگر commodity_id وجود دارد، این یک سطر کالا است
			if commodity_id:
				# پیدا کردن business_id قدیمی از rows (از اولین row می‌توانیم استفاده کنیم)
				# یا باید از invoice استفاده کنیم - در اینجا فرض می‌کنیم که در invoice موجود است
				
				# محاسبه unit_price
				debit = convert_amount(row.get("debit"))
				credit = convert_amount(row.get("credit"))
				quantity = convert_amount(row.get("quantity") or 1)
				
				if quantity == 0:
					quantity = Decimal(1)
				
				# unit_price = (بدهکار یا بستانکار) / quantity
				unit_price = (debit + credit) / quantity if quantity > 0 else Decimal(0)
				
				# تخفیف
				discount_amount = convert_amount(row.get("discount") or 0)
				line_discount = discount_amount
				
				# مالیات
				tax_amount = convert_amount(row.get("tax") or 0)
				
				# محاسبه tax_percent
				taxable_amount = (quantity * unit_price) - line_discount
				tax_percent = Decimal(0)
				if taxable_amount > 0 and tax_amount > 0:
					tax_percent = (tax_amount / taxable_amount) * 100
				
				line = {
					"product_id": None,  # باید بعداً set شود
					"quantity": float(quantity),
					"extra_info": {
						"unit_price": float(unit_price),
						"line_discount": float(line_discount),
						"tax_amount": float(tax_amount),
						"tax_rate": float(tax_percent)
					},
					"description": row.get("description"),
					"_old_commodity_id": commodity_id,  # برای mapping بعدی
					"_old_business_id": None  # باید set شود
				}
				
				lines.append(line)
		
		return lines
	
	def migrate_invoice(self, old_invoice: Dict[str, Any],
	                   business_id_mapping: Dict[int, int],
	                   user_id_mapping: Dict[int, int],
	                   fiscal_year_mapping: Dict[Tuple[int, int], int],
	                   currency_mapping: Dict[int, int],
	                   person_mapping: Dict[Tuple[int, int], int],
	                   product_mapping: Dict[Tuple[int, int], int],
	                   dry_run: bool = False) -> Optional[int]:
		"""انتقال یک فاکتور"""
		try:
			# تعریف متغیرهای اولیه
			old_code = old_invoice.get('code')
			old_document_id = old_invoice.get('id')
			
			# نگاشت شناسه‌ها
			old_business_id = old_invoice.get('business_id')
			new_business_id = business_id_mapping.get(old_business_id)
			
			if not new_business_id:
				self.stats["invoices_skipped"] += 1
				return None
			
			# بررسی اینکه آیا این سند قبلاً منتقل شده یا نه (با cache)
			if old_document_id in self.migrated_old_doc_ids:
				# سند قبلاً منتقل شده، skip می‌کنیم
				return None
			
			old_user_id = old_invoice.get('submitter_id')
			new_user_id = user_id_mapping.get(old_user_id)
			
			if not new_user_id:
				self.stats["invoices_skipped"] += 1
				return None
			
			old_currency_id = old_invoice.get('currency_id')
			new_currency_id = currency_mapping.get(old_currency_id)
			
			# اگر ارز پیدا نشد، از ارز پیش‌فرض کسب‌وکار استفاده می‌کنیم (با cache)
			if not new_currency_id:
				if new_business_id in self.default_currency_cache:
					new_currency_id = self.default_currency_cache[new_business_id]
				else:
					query = text("""
						SELECT default_currency_id FROM businesses
						WHERE id = :business_id
					""")
					result = self.new_db.execute(query, {"business_id": new_business_id}).first()
					if result and result[0]:
						new_currency_id = result[0]
						self.default_currency_cache[new_business_id] = new_currency_id
					else:
						if self.stats["invoices_skipped"] < 5:
							print(f"   ⚠️  فاکتور {old_invoice.get('code')} رد شد: ارز پیدا نشد و ارز پیش‌فرض کسب‌وکار هم نیست")
						self.stats["invoices_skipped"] += 1
						return None
			
			old_year_id = old_invoice.get('year_id')
			fiscal_year_id = fiscal_year_mapping.get((old_business_id, old_year_id))
			
			# اگر سال مالی پیدا نشد، از سال مالی پیش‌فرض (جاری) کسب‌وکار استفاده می‌کنیم (با cache)
			if not fiscal_year_id:
				if new_business_id in self.default_fiscal_year_cache:
					fiscal_year_id = self.default_fiscal_year_cache[new_business_id]
				else:
					# ابتدا سعی می‌کنیم سال مالی جاری (is_last = True) را پیدا کنیم
					query = text("""
						SELECT id FROM fiscal_years
						WHERE business_id = :business_id AND is_last = 1
						LIMIT 1
					""")
					result = self.new_db.execute(query, {"business_id": new_business_id}).first()
					if result:
						fiscal_year_id = result[0]
						self.default_fiscal_year_cache[new_business_id] = fiscal_year_id
					else:
						# اگر سال مالی جاری پیدا نشد، آخرین سال مالی را برمی‌گردانیم
						query2 = text("""
							SELECT id FROM fiscal_years
							WHERE business_id = :business_id 
							ORDER BY start_date DESC
							LIMIT 1
						""")
						result2 = self.new_db.execute(query2, {"business_id": new_business_id}).first()
						if result2:
							fiscal_year_id = result2[0]
							self.default_fiscal_year_cache[new_business_id] = fiscal_year_id
						else:
							if self.stats["invoices_skipped"] < 5:
								print(f"   ⚠️  فاکتور {old_invoice.get('code')} رد شد: سال مالی پیدا نشد (old_year_id: {old_year_id})")
							self.stats["invoices_skipped"] += 1
							return None
			
			# تبدیل تاریخ
			doc_date = convert_persian_date_to_date(old_invoice.get('date'))
			if not doc_date:
				date_submit = convert_timestamp_to_datetime(old_invoice.get('date_submit'))
				if date_submit:
					doc_date = date_submit.date()
				else:
					doc_date = date.today()
			
			# تشخیص نوع فاکتور
			old_type = old_invoice.get('type')
			type_mapping = {
				"sell": "invoice_sales",
				"buy": "invoice_purchase",
				"rfsell": "invoice_sales_return",
				"rfbuy": "invoice_purchase_return"
			}
			new_invoice_type = type_mapping.get(old_type)
			
			if not new_invoice_type:
				self.stats["invoices_skipped"] += 1
				return None
			
			# دریافت سطرهای فاکتور (استفاده از cache اگر موجود باشد)
			if '_cached_rows' in old_invoice:
				old_rows = old_invoice['_cached_rows']
			else:
				old_rows = self.get_invoice_rows(old_invoice.get('id'))
			
			if not old_rows:
				self.stats["invoices_skipped"] += 1
				return None
			
			# استخراج person_id از سطرها
			person_id = None
			person_ids_found = []
			for row in old_rows:
				row_person_id = row.get('person_id')
				if row_person_id is not None:
					try:
						row_person_id_int = int(row_person_id)
						person_ids_found.append(row_person_id_int)
						mapped_person_id = person_mapping.get((old_business_id, row_person_id_int))
						if mapped_person_id:
							person_id = mapped_person_id
							break
					except (ValueError, TypeError):
						pass
			
			# اگر person_id پیدا نشد، لاگ می‌کنیم
			if not person_id and person_ids_found:
				if self.stats["errors"] < 3:
					print(f"   ⚠️  فاکتور {old_code}: person_id در mapping پیدا نشد (old_person_ids: {person_ids_found[:3]}, old_business_id: {old_business_id})")
			
			if not person_id:
				# برای فاکتورهای فروش/خرید person_id الزامی است
				if new_invoice_type in ["invoice_sales", "invoice_purchase", 
				                        "invoice_sales_return", "invoice_purchase_return"]:
					# لاگ برای دیباگ
					if self.stats["invoices_skipped"] < 5:
						old_person_ids_str = ", ".join([str(pid) for pid in person_ids_found[:3]])
						print(f"   ⚠️  فاکتور {old_code} رد شد: person_id پیدا نشد (doc_id: {old_invoice.get('id')}, old_person_ids: {old_person_ids_str})")
					self.stats["invoices_skipped"] += 1
					return None
			
			# استخراج سطرهای کالا
			invoice_lines = []
			skipped_commodities = []
			for row in old_rows:
				commodity_id = row.get('commodity_id')
				if commodity_id:
					product_id = product_mapping.get((old_business_id, commodity_id))
					if not product_id:
						skipped_commodities.append(commodity_id)
						continue
					
					# محاسبه مقادیر
					debit = convert_amount(row.get('debit'))
					credit = convert_amount(row.get('credit'))
					quantity = convert_amount(row.get('quantity') or 1)
					
					if quantity == 0:
						quantity = Decimal(1)
					
					# unit_price
					unit_price = (debit + credit) / quantity if quantity > 0 else Decimal(0)
					
					# تخفیف و مالیات
					discount_amount = convert_amount(row.get('discount') or 0)
					tax_amount = convert_amount(row.get('tax') or 0)
					
					# محاسبه tax_percent
					taxable_amount = (quantity * unit_price) - discount_amount
					tax_rate = Decimal(0)
					if taxable_amount > 0 and tax_amount > 0:
						tax_rate = (tax_amount / taxable_amount) * 100
					
					line = {
						"product_id": product_id,
						"quantity": float(quantity),
						"extra_info": {
							"unit_price": float(unit_price),
							"line_discount": float(discount_amount),
							"tax_amount": float(tax_amount),
							"tax_rate": float(tax_rate)
						},
						"description": row.get('description')
					}
					
					invoice_lines.append(line)
			
			if not invoice_lines:
				# لاگ برای دیباگ
				if self.stats["invoices_skipped"] < 5:
					skipped_str = ", ".join([str(cid) for cid in skipped_commodities[:3]])
					print(f"   ⚠️  فاکتور {old_code} رد شد: هیچ سطر کالایی پیدا نشد (doc_id: {old_invoice.get('id')}, skipped_commodities: {skipped_str})")
				self.stats["invoices_skipped"] += 1
				return None
			
			if dry_run:
				self.stats["invoices_migrated"] += 1
				return None
			
			# استفاده از سرویس create_invoice
			try:
				# Import سرویس
				from app.services.invoice_service import create_invoice
				
				# اطمینان از وجود سیاست درآمدزایی
				self.ensure_policy_exists(new_business_id)
				
				# ایجاد فاکتور
				# person_id باید در extra_info قرار بگیرد یا مستقیماً در data
				extra_info_data = {
					"source": "migration",
					"old_document_id": old_invoice.get('id'),
					"old_code": old_code,
					"person_id": int(person_id)  # اضافه کردن person_id به extra_info
				}
				
				result = create_invoice(
					db=self.new_db,
					business_id=new_business_id,
					user_id=new_user_id,
					data={
						"invoice_type": new_invoice_type,
						"document_date": doc_date.isoformat(),
						"currency_id": new_currency_id,
						"person_id": int(person_id),  # همچنین در data هم قرار می‌دهیم
						"lines": invoice_lines,
						"description": old_invoice.get('description'),
						"is_proforma": old_invoice.get('is_preview') == 1,
						"extra_info": extra_info_data
					}
				)
				
				# commit در batch انجام می‌شود (در run_migration)
				# فقط ID را برمی‌گردانیم
				new_invoice_id = result.get("id")
				if new_invoice_id:
					# اضافه کردن به cache
					self.migrated_old_doc_ids.add(old_document_id)
					if old_code:
						cache_key = (new_business_id, old_code)
						self.migrated_codes_cache[cache_key] = True
				
				self.stats["invoices_migrated"] += 1
				
				return new_invoice_id
				
			except Exception as e:
				# rollback و ایجاد session جدید
				try:
					self.new_db.rollback()
				except Exception:
					pass
				
				# ایجاد session جدید برای ادامه کار
				try:
					from sqlalchemy import create_engine
					from sqlalchemy.orm import sessionmaker
					dsn = f"mysql+pymysql://root:136431@localhost:3306/{self.new_db_name}"
					engine = create_engine(dsn, echo=False, pool_pre_ping=True)
					self.new_db = sessionmaker(bind=engine)()
				except Exception:
					pass
				
				self.stats["errors"] += 1
				
				# استخراج جزئیات خطا از ApiError
				error_msg = str(e)
				error_code = None
				if hasattr(e, 'code'):
					error_code = e.code
				if hasattr(e, 'message'):
					error_msg = e.message
				
				# بررسی خطای duplicate
				if "Duplicate entry" in error_msg or "1062" in error_msg:
					error_msg = "کد تکراری در warehouse_documents"
				
				error_detail = {
					"old_invoice_id": old_invoice.get('id'),
					"old_code": old_code,
					"error": error_msg,
					"error_code": error_code
				}
				
				# فقط خطاهای اولیه را در لاگ نمایش می‌دهیم
				if len(self.stats["error_details"]) < 10:
					short_error = error_msg[:200] if len(error_msg) > 200 else error_msg
					print(f"   ❌ خطا در فاکتور {old_code} (ID: {old_invoice.get('id')}): {short_error}")
				
				self.stats["error_details"].append(error_detail)
				return None
				
		except Exception as e:
			self.stats["errors"] += 1
			
			import traceback
			error_trace = traceback.format_exc()
			
			# فقط خطاهای اولیه را در لاگ نمایش می‌دهیم
			if len(self.stats["error_details"]) < 10:
				print(f"   ❌ خطای عمومی در فاکتور {old_invoice.get('id', 'unknown')}: {str(e)}")
				if "PERSON_REQUIRED" in str(e) or "person_id" in str(e).lower():
					print(f"      -> مشکل در person_id")
			
			self.stats["error_details"].append({
				"old_invoice_id": old_invoice.get('id'),
				"error": str(e),
				"traceback": error_trace[:500] if len(error_trace) > 500 else error_trace
			})
			return None
	
	def run_migration(self, invoice_types: List[str] = None, dry_run: bool = False,
	                 batch_size: int = 100, start_id: Optional[int] = None,
	                 limit: Optional[int] = None, business_ids: Optional[List[int]] = None):
		"""اجرای انتقال"""
		if invoice_types is None:
			invoice_types = ["sell", "buy", "rfsell", "rfbuy"]
		
		print("=" * 100)
		print("🚀 شروع انتقال فاکتورها")
		print("=" * 100)
		
		if dry_run:
			print("\n⚠️  حالت DRY RUN - هیچ تغییری اعمال نمی‌شود")
		
		# ایجاد mapping ها
		print("\n📊 ایجاد mapping ها...")
		business_id_mapping = self.create_business_id_mapping()
		if not business_id_mapping:
			print("❌ هیچ mapping کسب و کاری یافت نشد!")
			return
		
		user_id_mapping = self.create_user_id_mapping()
		fiscal_year_mapping = self.create_fiscal_year_mapping(business_id_mapping)
		currency_mapping = self.create_currency_mapping()
		person_mapping = self.create_person_id_mapping(business_id_mapping)
		product_mapping = self.create_product_id_mapping(business_id_mapping)
		
		# انتقال برای هر نوع
		for invoice_type in invoice_types:
			print(f"\n{'='*100}")
			print(f"📦 انتقال فاکتورهای نوع: {invoice_type}")
			print(f"{'='*100}")
			
			offset = 0
			batch_commit_size = 10  # Commit هر 10 فاکتور
			processed_in_batch = 0
			
			# Load migrated documents cache در ابتدای هر نوع
			self._load_migrated_documents_cache(business_id_mapping)
			
			while True:
				invoices = self.get_old_invoices(
					invoice_type=invoice_type,
					start_id=start_id if offset == 0 else None,
					limit=batch_size,
					offset=offset if offset > 0 else None,
					business_ids=list(business_id_mapping.keys()) if not business_ids else business_ids
				)
				
				if not invoices:
					break
				
				print(f"\n📄 پردازش batch {offset // batch_size + 1}: {len(invoices)} فاکتور")
				
				# Bulk load invoice rows
				doc_ids = [inv.get('id') for inv in invoices]
				rows_dict = self.get_invoice_rows_bulk(doc_ids) if not dry_run else {}
				
				# Bulk duplicate check
				if not dry_run:
					self._batch_duplicate_check(invoices, business_id_mapping)
				
				for invoice in invoices:
					self.stats["invoices_processed"] += 1
					
					# استفاده از rows از cache
					if not dry_run and invoice.get('id') in rows_dict:
						invoice['_cached_rows'] = rows_dict[invoice.get('id')]
					
					if self.stats["invoices_processed"] % 10 == 0:
						print(f"   پردازش شده: {self.stats['invoices_processed']}, منتقل شده: {self.stats['invoices_migrated']}, رد شده: {self.stats['invoices_skipped']}, خطا: {self.stats['errors']}")
					
					result = self.migrate_invoice(
						old_invoice=invoice,
						business_id_mapping=business_id_mapping,
						user_id_mapping=user_id_mapping,
						fiscal_year_mapping=fiscal_year_mapping,
						currency_mapping=currency_mapping,
						person_mapping=person_mapping,
						product_mapping=product_mapping,
						dry_run=dry_run
					)
					
					if result and not dry_run:
						processed_in_batch += 1
						# Batch commit
						if processed_in_batch >= batch_commit_size:
							try:
								self.new_db.commit()
								processed_in_batch = 0
							except Exception as e:
								self.new_db.rollback()
								print(f"   ⚠️  خطا در commit batch: {str(e)}")
				
				# Commit نهایی batch
				if not dry_run and processed_in_batch > 0:
					try:
						self.new_db.commit()
						processed_in_batch = 0
					except Exception as e:
						self.new_db.rollback()
						print(f"   ⚠️  خطا در commit نهایی batch: {str(e)}")
				
				offset += batch_size
				
				if limit and self.stats["invoices_processed"] >= limit:
					break
				
				if len(invoices) < batch_size:
					break
		
		# نمایش آمار نهایی
		print("\n" + "=" * 100)
		print("📊 آمار نهایی")
		print("=" * 100)
		print(f"✅ فاکتورهای پردازش شده: {self.stats['invoices_processed']:,}")
		print(f"✅ فاکتورهای منتقل شده: {self.stats['invoices_migrated']:,}")
		print(f"⚠️  فاکتورهای رد شده: {self.stats['invoices_skipped']:,}")
		print(f"❌ خطاها: {self.stats['errors']:,}")
		
		if self.stats['error_details']:
			print(f"\n⚠️  جزئیات خطاها (نمونه 10 مورد اول):")
			for error in self.stats['error_details'][:10]:
				print(f"   - Invoice ID: {error.get('old_invoice_id')}, Code: {error.get('old_code')}")
				print(f"     Error: {error.get('error')}")
	
	def close(self):
		"""بستن اتصالات"""
		self.old_db.close()
		self.new_db.close()


def main():
	parser = argparse.ArgumentParser(description="انتقال فاکتورهای فروش، خرید و برگشت")
	parser.add_argument("--dry-run", action="store_true", help="اجرای تست بدون تغییر در دیتابیس")
	parser.add_argument("--batch-size", type=int, default=100, help="تعداد فاکتورها در هر batch")
	parser.add_argument("--start-id", type=int, help="شروع از شناسه خاص")
	parser.add_argument("--limit", type=int, help="محدود کردن تعداد فاکتورها")
	parser.add_argument("--invoice-types", nargs="+", 
	                   choices=["sell", "buy", "rfsell", "rfbuy"],
	                   default=["sell", "buy", "rfsell", "rfbuy"],
	                   help="انواع فاکتور برای انتقال")
	parser.add_argument("--old-db", default="hesabixOld", help="نام دیتابیس قدیمی")
	parser.add_argument("--new-db", default="hesabixpy", help="نام دیتابیس جدید")
	parser.add_argument("--db-user", default="root", help="نام کاربری دیتابیس")
	parser.add_argument("--db-password", default="136431", help="رمز عبور دیتابیس")
	parser.add_argument("--db-host", default="localhost", help="آدرس دیتابیس")
	parser.add_argument("--db-port", type=int, default=3306, help="پورت دیتابیس")
	
	args = parser.parse_args()
	
	migration = InvoiceMigration(
		old_db_name=args.old_db,
		new_db_name=args.new_db,
		db_user=args.db_user,
		db_password=args.db_password,
		db_host=args.db_host,
		db_port=args.db_port
	)
	
	try:
		migration.run_migration(
			invoice_types=args.invoice_types,
			dry_run=args.dry_run,
			batch_size=args.batch_size,
			start_id=args.start_id,
			limit=args.limit
		)
	finally:
		migration.close()


if __name__ == "__main__":
	main()

