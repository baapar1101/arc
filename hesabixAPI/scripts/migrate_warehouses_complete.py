#!/usr/bin/env python3
"""
اسکریپت انتقال انبارها از hesabixOld به hesabixpy

این اسکریپت:
- انبارها را از storeroom منتقل می‌کند
- اسناد انبار را از storeroom_ticket منتقل می‌کند
- خطوط سند را از storeroom_item منتقل می‌کند
"""

import sys
import os
import argparse
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime, date
from decimal import Decimal, InvalidOperation
import json
import re

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session


def convert_persian_date_to_date(date_str: str | None) -> date | None:
	"""تبدیل تاریخ شمسی string به date"""
	if not date_str or not date_str.strip():
		return None
	
	date_str = date_str.strip()
	
	# فرمت: 1402/08/27
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


def convert_timestamp_to_datetime(timestamp_str: str | None) -> datetime | None:
	"""تبدیل timestamp string به datetime"""
	if not timestamp_str:
		return None
	
	try:
		if str(timestamp_str).strip().isdigit():
			return datetime.fromtimestamp(int(timestamp_str))
	except (ValueError, TypeError, OSError):
		pass
	
	return None


def convert_doc_type(old_type: str, type_string: str | None) -> str:
	"""
	تبدیل type قدیمی به doc_type جدید
	
	Args:
		old_type: 'input' یا 'output'
		type_string: نوع سند به فارسی (مثل "حواله ورود")
	
	Returns:
		doc_type جدید: 'receipt'|'issue'|'transfer'|'production_in'|'production_out'|'adjustment'
	"""
	if not old_type:
		return "adjustment"
	
	type_string_lower = (type_string or "").lower()
	
	if old_type == "input":
		if "انتقال" in type_string_lower:
			return "transfer"
		elif "تولید" in type_string_lower:
			return "production_in"
		else:
			return "receipt"
	elif old_type == "output":
		if "انتقال" in type_string_lower:
			return "transfer"
		elif "تولید" in type_string_lower:
			return "production_out"
		else:
			return "issue"
	else:
		return "adjustment"


def convert_status(completed: int | None, is_approved: int | None) -> str:
	"""
	تبدیل وضعیت قدیمی به status جدید
	
	Returns:
		'draft'|'posted'|'cancelled'
	"""
	if completed == 1:
		return "posted"
	elif is_approved == 0:
		return "cancelled"
	else:
		return "draft"


def convert_quantity(count_str: str | None) -> Decimal | None:
	"""تبدیل count از varchar به decimal"""
	if not count_str or not count_str.strip():
		return None
	
	try:
		cleaned = str(count_str).strip().replace(',', '').replace(' ', '').replace('،', '')
		if not cleaned or cleaned == '0' or cleaned == '':
			return None
		return Decimal(cleaned)
	except (ValueError, InvalidOperation, TypeError):
		return None


def truncate_string(value: str | None, max_length: int) -> str | None:
	"""محدود کردن طول رشته به حداکثر طول مجاز"""
	if not value:
		return None
	
	value_str = str(value).strip()
	if len(value_str) > max_length:
		return value_str[:max_length]
	return value_str


def generate_warehouse_code(name: str, existing_codes: set) -> str:
	"""تولید کد یکتا برای انبار"""
	base_code = truncate_string(name, 64) or "warehouse"
	base_code = base_code.strip()
	
	code = base_code
	counter = 1
	while code in existing_codes:
		suffix = f"_{counter}"
		max_base_len = 64 - len(suffix)
		code = (base_code[:max_base_len] + suffix)
		counter += 1
		if counter > 1000:  # جلوگیری از حلقه بی‌نهایت
			code = f"{base_code[:50]}_{counter}"
			break
	
	return code


def generate_document_code(old_code: str, existing_codes: set) -> str:
	"""تولید کد یکتا برای سند انبار"""
	base_code = truncate_string(old_code, 64) or "DOC"
	base_code = base_code.strip()
	
	code = base_code
	counter = 1
	while code in existing_codes:
		suffix = f"_{counter}"
		max_base_len = 64 - len(suffix)
		code = (base_code[:max_base_len] + suffix)
		counter += 1
		if counter > 1000:
			code = f"{base_code[:50]}_{counter}"
			break
	
	return code


class WarehouseMigration:
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
		
		# آمار
		self.stats = {
			"warehouses_processed": 0,
			"warehouses_migrated": 0,
			"warehouses_skipped": 0,
			"documents_processed": 0,
			"documents_migrated": 0,
			"documents_skipped": 0,
			"lines_processed": 0,
			"lines_migrated": 0,
			"lines_skipped": 0,
			"errors": 0,
			"error_details": []
		}
	
	def create_business_id_mapping(self) -> Dict[int, int]:
		"""ایجاد mapping بین business_id قدیمی و جدید"""
		query = text("""
			SELECT 
				old_business.id as old_business_id,
				new_business.id as new_business_id
			FROM hesabixOld.business old_business
			INNER JOIN hesabixOld.user old_user ON old_business.owner_id = old_user.id
			INNER JOIN hesabixpy.users new_user ON (
				(old_user.email IS NOT NULL AND new_user.email IS NOT NULL AND LOWER(old_user.email) = LOWER(new_user.email)) OR
				(old_user.mobile IS NOT NULL AND new_user.mobile IS NOT NULL AND REPLACE(REPLACE(old_user.mobile, '+', ''), ' ', '') = REPLACE(REPLACE(new_user.mobile, '+', ''), ' ', ''))
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
		"""ایجاد mapping بین user_id قدیمی و جدید"""
		query = text("""
			SELECT 
				old.id as old_user_id,
				new.id as new_user_id
			FROM hesabixOld.user old
			INNER JOIN hesabixpy.users new ON (
				(old.email IS NOT NULL AND new.email IS NOT NULL AND LOWER(old.email) = LOWER(new.email)) OR
				(old.mobile IS NOT NULL AND new.mobile IS NOT NULL AND REPLACE(REPLACE(old.mobile, '+', ''), ' ', '') = REPLACE(REPLACE(new.mobile, '+', ''), ' ', ''))
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
		"""ایجاد mapping بین (business_id, year_id) قدیمی و fiscal_year_id جدید"""
		if not business_id_mapping:
			return {}
		
		old_business_ids = list(business_id_mapping.keys())
		placeholders = ','.join([str(bid) for bid in old_business_ids])
		
		query = text(f"""
			SELECT 
				old_year.bid_id as old_business_id,
				old_year.id as old_year_id,
				new_fy.id as new_fiscal_year_id
			FROM hesabixOld.year old_year
			INNER JOIN hesabixpy.businesses new_business ON old_year.bid_id = new_business.id
			INNER JOIN hesabixpy.fiscal_years new_fy ON (
				new_fy.business_id = new_business.id
				AND new_fy.title = old_year.label
			)
			WHERE old_year.bid_id IN ({placeholders})
		""")
		
		results = self.old_db.execute(query).fetchall()
		mapping = {}
		for row in results:
			key = (row.old_business_id, row.old_year_id)
			mapping[key] = row.new_fiscal_year_id
		
		print(f"✅ Fiscal Year mapping ایجاد شد: {len(mapping)} سال مالی")
		return mapping
	
	def create_product_id_mapping(self, business_id_mapping: Dict[int, int]) -> Dict[Tuple[int, int], int]:
		"""ایجاد mapping بین (business_id, commodity_id) قدیمی و product_id جدید"""
		if not business_id_mapping:
			return {}
		
		old_business_ids = list(business_id_mapping.keys())
		placeholders = ','.join([str(bid) for bid in old_business_ids])
		
		query = text(f"""
			SELECT 
				old_comm.bid_id as old_business_id,
				old_comm.id as old_commodity_id,
				new_product.id as new_product_id
			FROM hesabixOld.commodity old_comm
			INNER JOIN hesabixpy.businesses new_business ON old_comm.bid_id = new_business.id
			INNER JOIN hesabixpy.products new_product ON (
				new_product.business_id = new_business.id
				AND BINARY new_product.code = BINARY old_comm.code
			)
			WHERE old_comm.bid_id IN ({placeholders})
		""")
		
		results = self.old_db.execute(query).fetchall()
		mapping = {}
		for row in results:
			key = (row.old_business_id, row.old_commodity_id)
			mapping[key] = row.new_product_id
		
		print(f"✅ Product ID mapping ایجاد شد: {len(mapping)} کالا")
		return mapping
	
	def migrate_warehouse(self, old_storeroom: Dict[str, Any], business_id_mapping: Dict[int, int],
	                    existing_codes: set) -> Optional[int]:
		"""انتقال یک انبار"""
		try:
			old_business_id = old_storeroom.get('bid_id')
			new_business_id = business_id_mapping.get(old_business_id)
			
			if not new_business_id:
				return None
			
			# بررسی وجود بر اساس name و business_id (قبل از تولید کد)
			old_storeroom_id = old_storeroom.get('id')
			old_storeroom_name = old_storeroom.get('name')
			query_check = text("""
				SELECT id FROM warehouses
				WHERE business_id = :business_id 
				AND name = :name
				LIMIT 1
			""")
			result_check = self.new_db.execute(query_check, {
				"business_id": new_business_id,
				"name": old_storeroom_name
			}).fetchone()
			
			if result_check:
				return result_check[0]
			
			# تولید کد
			warehouse_code = generate_warehouse_code(
				old_storeroom.get('name'),
				existing_codes
			)
			
			# درج انبار
			query = text("""
				INSERT INTO warehouses (
					business_id, code, name, description,
					warehouse_keeper, phone, address, postal_code,
					is_default, created_at, updated_at
				) VALUES (
					:business_id, :code, :name, :description,
					:warehouse_keeper, :phone, :address, :postal_code,
					:is_default, :created_at, :updated_at
				)
			""")
			
			self.new_db.execute(query, {
				"business_id": new_business_id,
				"code": warehouse_code,
				"name": old_storeroom.get('name'),
				"description": truncate_string(old_storeroom.get('adr'), 1000),
				"warehouse_keeper": truncate_string(old_storeroom.get('manager'), 255),
				"phone": truncate_string(old_storeroom.get('tel'), 32),
				"address": truncate_string(old_storeroom.get('adr'), 1000),
				"postal_code": None,
				"is_default": False,  # بعداً تنظیم می‌شود
				"created_at": datetime.utcnow(),
				"updated_at": datetime.utcnow()
			})
			
			self.new_db.commit()
			
			# دریافت ID جدید
			query_id = text("""
				SELECT id FROM warehouses
				WHERE business_id = :business_id AND code = :code
				LIMIT 1
			""")
			result = self.new_db.execute(query_id, {
				"business_id": new_business_id,
				"code": warehouse_code
			}).fetchone()
			
			if result:
				self.stats["warehouses_migrated"] += 1
				existing_codes.add(warehouse_code)  # اضافه کردن کد جدید به لیست
				return result[0]
			return None
		
		except Exception as e:
			self.new_db.rollback()
			self.stats["errors"] += 1
			print(f"❌ خطا در انتقال انبار {old_storeroom.get('id')}: {e}")
			return None
	
	def migrate_warehouses(self, business_id_mapping: Dict[int, int], limit: Optional[int] = None):
		"""انتقال انبارها"""
		query = text("""
			SELECT 
				id, bid_id, name, manager, adr, tel, active
			FROM hesabixOld.storeroom
			WHERE active = 1
			ORDER BY id ASC
		""")
		
		if limit:
			query = text(f"""
				SELECT 
					id, bid_id, name, manager, adr, tel, active
				FROM hesabixOld.storeroom
				WHERE active = 1
				ORDER BY id ASC
				LIMIT {limit}
			""")
		
		results = self.old_db.execute(query).fetchall()
		
		# دریافت کدهای موجود برای هر کسب و کار
		warehouse_codes_by_business: Dict[int, set] = {}
		warehouse_mapping: Dict[int, int] = {}  # old_storeroom_id -> new_warehouse_id
		
		for row in results:
			old_storeroom = {
				"id": row[0],
				"bid_id": row[1],
				"name": row[2],
				"manager": row[3],
				"adr": row[4],
				"tel": row[5],
				"active": row[6]
			}
			
			self.stats["warehouses_processed"] += 1
			
			old_business_id = old_storeroom.get('bid_id')
			new_business_id = business_id_mapping.get(old_business_id)
			
			if not new_business_id:
				self.stats["warehouses_skipped"] += 1
				continue
			
			# دریافت کدهای موجود برای این کسب و کار
			if new_business_id not in warehouse_codes_by_business:
				query_codes = text("""
					SELECT code FROM warehouses
					WHERE business_id = :business_id
				""")
				codes = self.new_db.execute(query_codes, {
					"business_id": new_business_id
				}).fetchall()
				warehouse_codes_by_business[new_business_id] = {c[0] for c in codes}
			
			existing_codes = warehouse_codes_by_business[new_business_id]
			
			new_warehouse_id = self.migrate_warehouse(
				old_storeroom, business_id_mapping, existing_codes
			)
			
			if new_warehouse_id:
				warehouse_mapping[old_storeroom.get('id')] = new_warehouse_id
				# به‌روزرسانی کدهای موجود
				warehouse_code = generate_warehouse_code(
					old_storeroom.get('name'),
					existing_codes
				)
				existing_codes.add(warehouse_code)
		
		# تنظیم is_default برای اولین انبار هر کسب و کار
		for new_business_id in warehouse_codes_by_business.keys():
			query_default = text("""
				SELECT id FROM warehouses
				WHERE business_id = :business_id
				ORDER BY id ASC
				LIMIT 1
			""")
			result = self.new_db.execute(query_default, {
				"business_id": new_business_id
			}).fetchone()
			
			if result:
				update_query = text("""
					UPDATE warehouses
					SET is_default = 1
					WHERE id = :warehouse_id
				""")
				self.new_db.execute(update_query, {
					"warehouse_id": result[0]
				})
				self.new_db.commit()
		
		print(f"✅ {self.stats['warehouses_migrated']} انبار منتقل شد")
		return warehouse_mapping
	
	def migrate_document(self, old_ticket: Dict[str, Any], business_id_mapping: Dict[int, int],
	                    user_id_mapping: Dict[int, int], fiscal_year_mapping: Dict[Tuple[int, int], int],
	                    warehouse_mapping: Dict[int, int], existing_codes: set, 
	                    existing_old_ids: set) -> Optional[int]:
		"""انتقال یک سند انبار"""
		try:
			# بررسی وجود بر اساس old_id
			old_ticket_id = old_ticket.get('id')
			if old_ticket_id in existing_old_ids:
				return None
			
			old_business_id = old_ticket.get('bid_id')
			new_business_id = business_id_mapping.get(old_business_id)
			
			if not new_business_id:
				return None
			
			# تبدیل doc_type
			doc_type = convert_doc_type(
				old_ticket.get('type'),
				old_ticket.get('type_string')
			)
			
			# تبدیل تاریخ
			document_date = convert_persian_date_to_date(old_ticket.get('date'))
			if not document_date:
				date_submit = convert_timestamp_to_datetime(old_ticket.get('date_submit'))
				if date_submit:
					document_date = date_submit.date()
				else:
					document_date = date.today()
			
			# تبدیل وضعیت
			status = convert_status(
				old_ticket.get('completed'),
				old_ticket.get('is_approved')
			)
			
			# mapping warehouse
			old_storeroom_id = old_ticket.get('storeroom_id')
			new_warehouse_id = warehouse_mapping.get(old_storeroom_id)
			
			if not new_warehouse_id:
				return None
			
			# تنظیم warehouse_id_from و warehouse_id_to
			warehouse_id_from = None
			warehouse_id_to = None
			
			if doc_type == "transfer":
				# برای transfer، باید هر دو را تنظیم کنیم
				warehouse_id_from = new_warehouse_id
				warehouse_id_to = new_warehouse_id  # در صورت نیاز می‌تواند تغییر کند
			elif doc_type in ["receipt", "production_in"]:
				warehouse_id_to = new_warehouse_id
			elif doc_type in ["issue", "production_out"]:
				warehouse_id_from = new_warehouse_id
			
			# mapping fiscal_year
			old_year_id = old_ticket.get('year_id')
			fiscal_year_id = fiscal_year_mapping.get((old_business_id, old_year_id))
			
			# mapping user
			old_submitter_id = old_ticket.get('submitter_id')
			created_by_user_id = user_id_mapping.get(old_submitter_id)
			
			# mapping source_document
			old_doc_id = old_ticket.get('doc_id')
			source_document_id = None
			source_type = "manual"
			
			# بررسی وجود بر اساس old_id (قبل از تولید کد)
			query_check = text("""
				SELECT id FROM warehouse_documents
				WHERE JSON_EXTRACT(extra_info, '$.old_id') = :old_id
				LIMIT 1
			""")
			result_check = self.new_db.execute(query_check, {
				"old_id": old_ticket_id
			}).fetchone()
			
			if result_check:
				existing_old_ids.add(old_ticket_id)
				return result_check[0]
			
			# تولید کد (بعد از بررسی وجود)
			old_code = old_ticket.get('code') or f"DOC_{old_ticket.get('id')}"
			document_code = generate_document_code(old_code, existing_codes)
			existing_codes.add(document_code)  # اضافه کردن کد جدید به لیست
			
			# extra_info
			extra_info = {
				"old_id": old_ticket.get('id'),
				"type_string": old_ticket.get('type_string'),
				"description": old_ticket.get('des'),
				"transfer": old_ticket.get('transfer'),
				"receiver": old_ticket.get('receiver'),
				"sender_tel": old_ticket.get('sender_tel'),
				"referral": old_ticket.get('referral'),
				"transfer_type_id": old_ticket.get('transfer_type_id'),
				"person_id": old_ticket.get('person_id')
			}
			
			# درج سند
			query = text("""
				INSERT INTO warehouse_documents (
					business_id, fiscal_year_id, code, document_date,
					status, doc_type, warehouse_id_from, warehouse_id_to,
					source_type, source_document_id, extra_info,
					created_by_user_id, created_at, updated_at
				) VALUES (
					:business_id, :fiscal_year_id, :code, :document_date,
					:status, :doc_type, :warehouse_id_from, :warehouse_id_to,
					:source_type, :source_document_id, :extra_info,
					:created_by_user_id, :created_at, :updated_at
				)
			""")
			
			self.new_db.execute(query, {
				"business_id": new_business_id,
				"fiscal_year_id": fiscal_year_id,
				"code": document_code,
				"document_date": document_date,
				"status": status,
				"doc_type": doc_type,
				"warehouse_id_from": warehouse_id_from,
				"warehouse_id_to": warehouse_id_to,
				"source_type": source_type,
				"source_document_id": source_document_id,
				"extra_info": json.dumps(extra_info, ensure_ascii=False),
				"created_by_user_id": created_by_user_id,
				"created_at": datetime.utcnow(),
				"updated_at": datetime.utcnow()
			})
			
			self.new_db.commit()
			
			# دریافت ID جدید
			query_id = text("""
				SELECT id FROM warehouse_documents
				WHERE code = :code
				LIMIT 1
			""")
			result = self.new_db.execute(query_id, {
				"code": document_code
			}).fetchone()
			
			if result:
				self.stats["documents_migrated"] += 1
				existing_old_ids.add(old_ticket_id)  # اضافه کردن به لیست موجود
				existing_codes.add(document_code)  # اضافه کردن کد جدید
				return result[0]
			return None
		
		except Exception as e:
			self.new_db.rollback()
			self.stats["errors"] += 1
			print(f"❌ خطا در انتقال سند {old_ticket.get('id')}: {e}")
			return None
	
	def migrate_documents(self, business_id_mapping: Dict[int, int],
	                    user_id_mapping: Dict[int, int],
	                    fiscal_year_mapping: Dict[Tuple[int, int], int],
	                    warehouse_mapping: Dict[int, int],
	                    limit: Optional[int] = None):
		"""انتقال اسناد انبار"""
		query = text("""
			SELECT 
				id, bid_id, submitter_id, person_id, doc_id, year_id,
				storeroom_id, transfer_type_id, date, date_submit,
				transfer, receiver, code, type, referral, type_string,
				des, sender_tel, can_share, import_workflow_code,
				activation_code, is_preview, is_approved, completed,
				completed_at, approved_by_id, completed_by_id
			FROM hesabixOld.storeroom_ticket
			ORDER BY id ASC
		""")
		
		if limit:
			query = text(f"""
				SELECT 
					id, bid_id, submitter_id, person_id, doc_id, year_id,
					storeroom_id, transfer_type_id, date, date_submit,
					transfer, receiver, code, type, referral, type_string,
					des, sender_tel, can_share, import_workflow_code,
					activation_code, is_preview, is_approved, completed,
					completed_at, approved_by_id, completed_by_id
				FROM hesabixOld.storeroom_ticket
				ORDER BY id ASC
				LIMIT {limit}
			""")
		
		results = self.old_db.execute(query).fetchall()
		
		# دریافت کدهای موجود و old_id های موجود
		query_codes = text("SELECT code FROM warehouse_documents")
		codes = self.new_db.execute(query_codes).fetchall()
		existing_codes = {c[0] for c in codes}
		
		query_old_ids = text("""
			SELECT JSON_EXTRACT(extra_info, '$.old_id') as old_id
			FROM warehouse_documents
			WHERE extra_info IS NOT NULL
				AND JSON_EXTRACT(extra_info, '$.old_id') IS NOT NULL
		""")
		old_ids = self.new_db.execute(query_old_ids).fetchall()
		existing_old_ids = set()
		for oid in old_ids:
			try:
				if oid[0] is not None:
					existing_old_ids.add(int(oid[0]))
			except (ValueError, TypeError):
				pass
		
		document_mapping: Dict[int, int] = {}  # old_ticket_id -> new_document_id
		
		for row in results:
			old_ticket = {
				"id": row[0],
				"bid_id": row[1],
				"submitter_id": row[2],
				"person_id": row[3],
				"doc_id": row[4],
				"year_id": row[5],
				"storeroom_id": row[6],
				"transfer_type_id": row[7],
				"date": row[8],
				"date_submit": row[9],
				"transfer": row[10],
				"receiver": row[11],
				"code": row[12],
				"type": row[13],
				"referral": row[14],
				"type_string": row[15],
				"des": row[16],
				"sender_tel": row[17],
				"can_share": row[18],
				"import_workflow_code": row[19],
				"activation_code": row[20],
				"is_preview": row[21],
				"is_approved": row[22],
				"completed": row[23],
				"completed_at": row[24],
				"approved_by_id": row[25],
				"completed_by_id": row[26]
			}
			
			self.stats["documents_processed"] += 1
			
			new_document_id = self.migrate_document(
				old_ticket, business_id_mapping, user_id_mapping,
				fiscal_year_mapping, warehouse_mapping, existing_codes, existing_old_ids
			)
			
			if new_document_id:
				document_mapping[old_ticket.get('id')] = new_document_id
			else:
				self.stats["documents_skipped"] += 1
		
		print(f"✅ {self.stats['documents_migrated']} سند انبار منتقل شد")
		return document_mapping
	
	def migrate_document_line(self, old_item: Dict[str, Any], business_id_mapping: Dict[int, int],
	                         product_mapping: Dict[Tuple[int, int], int],
	                         warehouse_mapping: Dict[int, int],
	                         document_mapping: Dict[int, int]):
		"""انتقال یک خط سند"""
		try:
			old_ticket_id = old_item.get('ticket_id')
			new_document_id = document_mapping.get(old_ticket_id)
			
			if not new_document_id:
				return None
			
			# mapping product
			old_business_id = old_item.get('bid_id')
			old_commodity_id = old_item.get('commodity_id')
			new_product_id = product_mapping.get((old_business_id, old_commodity_id))
			
			if not new_product_id:
				return None
			
			# mapping warehouse
			old_storeroom_id = old_item.get('storeroom_id')
			new_warehouse_id = warehouse_mapping.get(old_storeroom_id)
			
			if not new_warehouse_id:
				return None
			
			# تبدیل movement
			old_type = old_item.get('type')
			if old_type == "input":
				movement = "in"
			elif old_type == "output":
				movement = "out"
			else:
				return None
			
			# تبدیل quantity
			quantity = convert_quantity(old_item.get('count'))
			if not quantity or quantity <= 0:
				return None
			
			# extra_info
			extra_info = {
				"old_id": old_item.get('id'),
				"description": old_item.get('des'),
				"referral": old_item.get('referal')
			}
			
			# درج خط
			query = text("""
				INSERT INTO warehouse_document_lines (
					warehouse_document_id, product_id, warehouse_id,
					movement, quantity, extra_info
				) VALUES (
					:warehouse_document_id, :product_id, :warehouse_id,
					:movement, :quantity, :extra_info
				)
			""")
			
			self.new_db.execute(query, {
				"warehouse_document_id": new_document_id,
				"product_id": new_product_id,
				"warehouse_id": new_warehouse_id,
				"movement": movement,
				"quantity": quantity,
				"extra_info": json.dumps(extra_info, ensure_ascii=False)
			})
			
			self.new_db.commit()
			self.stats["lines_migrated"] += 1
			return True
		
		except Exception as e:
			self.new_db.rollback()
			self.stats["errors"] += 1
			return None
	
	def migrate_document_lines(self, business_id_mapping: Dict[int, int],
	                          product_mapping: Dict[Tuple[int, int], int],
	                          warehouse_mapping: Dict[int, int],
	                          document_mapping: Dict[int, int],
	                          limit: Optional[int] = None):
		"""انتقال خطوط سند"""
		query = text("""
			SELECT 
				id, ticket_id, commodity_id, bid_id, storeroom_id,
				type, count, des, referal
			FROM hesabixOld.storeroom_item
			ORDER BY id ASC
		""")
		
		if limit:
			query = text(f"""
				SELECT 
					id, ticket_id, commodity_id, bid_id, storeroom_id,
					type, count, des, referal
				FROM hesabixOld.storeroom_item
				ORDER BY id ASC
				LIMIT {limit}
			""")
		
		results = self.old_db.execute(query).fetchall()
		
		for row in results:
			old_item = {
				"id": row[0],
				"ticket_id": row[1],
				"commodity_id": row[2],
				"bid_id": row[3],
				"storeroom_id": row[4],
				"type": row[5],
				"count": row[6],
				"des": row[7],
				"referal": row[8]
			}
			
			self.stats["lines_processed"] += 1
			
			result = self.migrate_document_line(
				old_item, business_id_mapping, product_mapping,
				warehouse_mapping, document_mapping
			)
			
			if not result:
				self.stats["lines_skipped"] += 1
		
		print(f"✅ {self.stats['lines_migrated']} خط سند منتقل شد")
	
	def run_migration(self, dry_run: bool = False, limit: Optional[int] = None):
		"""اجرای انتقال"""
		print(f"{'='*60}")
		print(f"شروع انتقال انبارها")
		print(f"{'='*60}")
		print(f"دیتابیس قدیمی: {self.old_db_name}")
		print(f"دیتابیس جدید: {self.new_db_name}")
		print(f"حالت تست (dry-run): {dry_run}")
		if limit:
			print(f"محدودیت: {limit} مورد")
		print(f"{'='*60}\n")
		
		if dry_run:
			print("⚠️  حالت تست - هیچ تغییری در دیتابیس ایجاد نمی‌شود\n")
			return
		
		# ایجاد mapping ها
		business_id_mapping = self.create_business_id_mapping()
		user_id_mapping = self.create_user_id_mapping()
		fiscal_year_mapping = self.create_fiscal_year_mapping(business_id_mapping)
		product_mapping = self.create_product_id_mapping(business_id_mapping)
		
		# انتقال انبارها
		print("\n📦 انتقال انبارها...")
		warehouse_mapping = self.migrate_warehouses(business_id_mapping, limit)
		
		# انتقال اسناد انبار
		print("\n📄 انتقال اسناد انبار...")
		document_mapping = self.migrate_documents(
			business_id_mapping, user_id_mapping,
			fiscal_year_mapping, warehouse_mapping, limit
		)
		
		# انتقال خطوط سند
		print("\n📋 انتقال خطوط سند...")
		self.migrate_document_lines(
			business_id_mapping, product_mapping,
			warehouse_mapping, document_mapping, limit
		)
		
		# نمایش آمار نهایی
		print(f"\n{'='*60}")
		print("آمار نهایی:")
		print(f"{'='*60}")
		print(f"انبارها:")
		print(f"  پردازش شده: {self.stats['warehouses_processed']}")
		print(f"  منتقل شده: {self.stats['warehouses_migrated']}")
		print(f"  رد شده: {self.stats['warehouses_skipped']}")
		print(f"اسناد انبار:")
		print(f"  پردازش شده: {self.stats['documents_processed']}")
		print(f"  منتقل شده: {self.stats['documents_migrated']}")
		print(f"  رد شده: {self.stats['documents_skipped']}")
		print(f"خطوط سند:")
		print(f"  پردازش شده: {self.stats['lines_processed']}")
		print(f"  منتقل شده: {self.stats['lines_migrated']}")
		print(f"  رد شده: {self.stats['lines_skipped']}")
		print(f"خطاها: {self.stats['errors']}")
	
	def close(self):
		"""بستن اتصالات"""
		self.old_db.close()
		self.new_db.close()


def main():
	parser = argparse.ArgumentParser(description="انتقال انبارها از hesabixOld به hesabixpy")
	parser.add_argument("--dry-run", action="store_true", help="اجرای تست بدون تغییر در دیتابیس")
	parser.add_argument("--limit", type=int, help="محدود کردن تعداد موارد برای تست")
	parser.add_argument("--old-db", default="hesabixOld", help="نام دیتابیس قدیمی")
	parser.add_argument("--new-db", default="hesabixpy", help="نام دیتابیس جدید")
	parser.add_argument("--db-user", default="root", help="نام کاربری دیتابیس")
	parser.add_argument("--db-password", default="136431", help="رمز عبور دیتابیس")
	parser.add_argument("--db-host", default="localhost", help="آدرس دیتابیس")
	parser.add_argument("--db-port", type=int, default=3306, help="پورت دیتابیس")
	
	args = parser.parse_args()
	
	migration = WarehouseMigration(
		old_db_name=args.old_db,
		new_db_name=args.new_db,
		db_user=args.db_user,
		db_password=args.db_password,
		db_host=args.db_host,
		db_port=args.db_port
	)
	
	try:
		migration.run_migration(dry_run=args.dry_run, limit=args.limit)
	finally:
		migration.close()


if __name__ == "__main__":
	main()

