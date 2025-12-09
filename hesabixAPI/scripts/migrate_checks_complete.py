#!/usr/bin/env python3
"""
اسکریپت انتقال چک‌ها از hesabixOld به hesabixpy

این اسکریپت:
- چک‌ها را از cheque منتقل می‌کند
- type و status را تبدیل می‌کند
- تاریخ‌ها را از timestamp/string به datetime تبدیل می‌کند
- amount را از string به numeric تبدیل می‌کند
"""

import sys
import os
import argparse
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime
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
		# اگر عدد است، timestamp است
		if timestamp_str.strip().isdigit():
			return datetime.fromtimestamp(int(timestamp_str))
	except (ValueError, TypeError, OSError):
		pass
	
	return None


def convert_persian_date_to_datetime(date_str: str | None) -> datetime | None:
	"""تبدیل تاریخ شمسی string به datetime"""
	if not date_str or not date_str.strip():
		return None
	
	date_str = date_str.strip()
	
	# فرمت: 1403/10/05
	match = re.match(r'^(\d{4})/(\d{1,2})/(\d{1,2})$', date_str)
	if match:
		year, month, day = match.groups()
		try:
			# استفاده از کتابخانه jdatetime برای تبدیل
			# اگر jdatetime نصب نباشد، از یک تبدیل ساده استفاده می‌کنیم
			try:
				import jdatetime
				jd = jdatetime.date(int(year), int(month), int(day))
				gd = jd.togregorian()
				return datetime(gd.year, gd.month, gd.day)
			except ImportError:
				# اگر jdatetime نصب نباشد، از یک تبدیل تقریبی استفاده می‌کنیم
				# 1403 شمسی ≈ 2024 میلادی
				# این تبدیل دقیق نیست اما برای موارد ضروری استفاده می‌شود
				gregorian_year = int(year) + 621
				return datetime(gregorian_year, int(month), int(day))
		except (ValueError, TypeError):
			pass
	
	return None


def convert_type(old_type: str) -> str:
	"""تبدیل type از قدیمی به جدید"""
	if old_type == "input":
		return "RECEIVED"
	elif old_type == "output":
		return "TRANSFERRED"
	else:
		raise ValueError(f"Unknown type: {old_type}")


def convert_status(old_status: str, old_type: str) -> str:
	"""تبدیل status از فارسی به ENUM انگلیسی"""
	if not old_status:
		return None
	
	status_map = {
		"وصول نشده": {
			"input": "RECEIVED_ON_HAND",
			"output": "TRANSFERRED_ISSUED"
		},
		"واگذار شده": "ENDORSED",
		"وصول": "CLEARED",
		"پاس نشده": "DEPOSITED",
		"پاس شده": "CLEARED",
		"برگشت خورده": "BOUNCED"
	}
	
	if old_status in status_map:
		mapping = status_map[old_status]
		if isinstance(mapping, dict):
			return mapping.get(old_type)
		return mapping
	
	return None


def convert_amount(amount_str: str | None) -> Decimal | None:
	"""تبدیل amount از string به decimal"""
	if not amount_str or not amount_str.strip():
		return None
	
	try:
		# حذف فاصله و کاما
		cleaned = amount_str.strip().replace(',', '').replace(' ', '').replace('،', '')
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


def calculate_holder(old_cheque: Dict[str, Any], new_bank_account_id: Optional[int],
                    new_person_id: Optional[int], new_business_id: int) -> Tuple[str | None, int | None]:
	"""محاسبه current_holder_type و current_holder_id"""
	transfered = old_cheque.get('transfered')
	
	if transfered == 1:
		if new_bank_account_id:
			return ('BANK', new_bank_account_id)
		elif new_person_id:
			return ('PERSON', new_person_id)
		else:
			return ('BUSINESS', new_business_id)
	else:
		# اگر transfered نباشد، در دست کسب و کار است
		return ('BUSINESS', new_business_id)


class CheckMigration:
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
			"checks_processed": 0,
			"checks_migrated": 0,
			"checks_skipped": 0,
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
				(old_user.email IS NOT NULL AND new_user.email IS NOT NULL AND BINARY old_user.email = BINARY new_user.email) OR
				(old_user.mobile IS NOT NULL AND new_user.mobile IS NOT NULL AND BINARY old_user.mobile = BINARY new_user.mobile)
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
	
	def create_currency_mapping(self) -> Dict[int, int]:
		"""ایجاد mapping بین money_id قدیمی و currency_id جدید"""
		mapping = {
			1: 1,   # IRR
			2: 2,   # USD
			3: 20,  # AFN
			4: 19   # IQD
		}
		
		print(f"✅ Currency mapping ایجاد شد: {len(mapping)} ارز")
		return mapping
	
	def create_person_id_mapping(self, business_id_mapping: Dict[int, int]) -> Dict[int, int]:
		"""ایجاد mapping بین person_id قدیمی و جدید"""
		if not business_id_mapping:
			return {}
		
		# استفاده از business_id_mapping برای بهینه‌سازی
		old_business_ids = list(business_id_mapping.keys())
		placeholders = ','.join([str(bid) for bid in old_business_ids])
		
		query = text(f"""
			SELECT 
				old_person.id as old_person_id,
				old_person.bid_id as old_business_id,
				old_person.code as old_code,
				old_person.nikename as old_nikename
			FROM hesabixOld.person old_person
			WHERE old_person.bid_id IN ({placeholders})
		""")
		
		results = self.old_db.execute(query).fetchall()
		mapping = {}
		
		# برای هر person، business_id جدید را پیدا می‌کنیم و سپس person جدید را
		for row in results:
			old_person_id = row.old_person_id
			old_business_id = row.old_business_id
			new_business_id = business_id_mapping.get(old_business_id)
			
			if not new_business_id:
				continue
			
			old_code = row.old_code
			old_nikename = row.old_nikename
			
			# جستجوی person جدید
			if old_code:
				query_person = text("""
					SELECT id FROM persons
					WHERE business_id = :business_id AND code = :code
					LIMIT 1
				""")
				result = self.new_db.execute(query_person, {
					"business_id": new_business_id,
					"code": old_code
				}).fetchone()
				if result:
					mapping[old_person_id] = result[0]
					continue
			
			if old_nikename:
				query_person = text("""
					SELECT id FROM persons
					WHERE business_id = :business_id AND alias_name = :alias_name
					LIMIT 1
				""")
				result = self.new_db.execute(query_person, {
					"business_id": new_business_id,
					"alias_name": old_nikename
				}).fetchone()
				if result:
					mapping[old_person_id] = result[0]
		
		print(f"✅ Person ID mapping ایجاد شد: {len(mapping)} شخص")
		return mapping
	
	def create_bank_account_id_mapping(self, business_id_mapping: Dict[int, int]) -> Dict[int, int]:
		"""ایجاد mapping بین bank_id قدیمی (bank_account) و جدید (bank_accounts)"""
		if not business_id_mapping:
			return {}
		
		# استفاده از business_id_mapping برای بهینه‌سازی
		old_business_ids = list(business_id_mapping.keys())
		placeholders = ','.join([str(bid) for bid in old_business_ids])
		
		query = text(f"""
			SELECT 
				old_bank.id as old_bank_id,
				old_bank.bid_id as old_business_id,
				old_bank.code as old_code
			FROM hesabixOld.bank_account old_bank
			WHERE old_bank.bid_id IN ({placeholders})
		""")
		
		results = self.old_db.execute(query).fetchall()
		mapping = {}
		
		# برای هر bank_account، business_id جدید را پیدا می‌کنیم و سپس bank_account جدید را
		for row in results:
			old_bank_id = row.old_bank_id
			old_business_id = row.old_business_id
			new_business_id = business_id_mapping.get(old_business_id)
			
			if not new_business_id:
				continue
			
			old_code = row.old_code
			
			if old_code:
				query_bank = text("""
					SELECT id FROM bank_accounts
					WHERE business_id = :business_id AND code = :code
					LIMIT 1
				""")
				result = self.new_db.execute(query_bank, {
					"business_id": new_business_id,
					"code": old_code
				}).fetchone()
				if result:
					mapping[old_bank_id] = result[0]
		
		print(f"✅ Bank Account ID mapping ایجاد شد: {len(mapping)} حساب بانکی")
		return mapping
	
	def get_default_currency_id(self, business_id: int) -> int:
		"""دریافت ارز پیش‌فرض کسب و کار"""
		query = text("""
			SELECT default_currency_id FROM businesses WHERE id = :business_id
		""")
		result = self.new_db.execute(query, {"business_id": business_id}).fetchone()
		
		if result and result[0]:
			return result[0]
		
		# اگر پیش‌فرض نداشت، IRR استفاده می‌کنیم
		return 1
	
	def migrate_check(self, old_cheque: Dict[str, Any], business_id_mapping: Dict[int, int],
	                 currency_mapping: Dict[int, int], person_id_mapping: Dict[int, int],
	                 bank_account_id_mapping: Dict[int, int]) -> Optional[int]:
		"""انتقال یک چک"""
		try:
			# نگاشت business_id
			old_business_id = old_cheque.get('bid_id')
			new_business_id = business_id_mapping.get(old_business_id)
			
			if not new_business_id:
				self.stats["checks_skipped"] += 1
				return None
			
			# تبدیل type
			old_type = old_cheque.get('type')
			new_type = convert_type(old_type)
			
			# تبدیل check_number
			check_number = truncate_string(old_cheque.get('number'), 50)
			if not check_number:
				self.stats["checks_skipped"] += 1
				return None
			
			# بررسی وجود در دیتابیس جدید
			query = text("""
				SELECT COUNT(*) FROM checks
				WHERE business_id = :business_id AND check_number = :check_number
			""")
			result = self.new_db.execute(query, {
				"business_id": new_business_id,
				"check_number": check_number
			}).scalar()
			
			if result > 0:
				self.stats["checks_skipped"] += 1
				return None
			
			# تبدیل sayad_code
			sayad_code = truncate_string(old_cheque.get('sayad_num'), 16)
			
			# بررسی sayad_code تکراری (اگر NULL نباشد)
			if sayad_code:
				query = text("""
					SELECT COUNT(*) FROM checks
					WHERE business_id = :business_id AND sayad_code = :sayad_code
				""")
				result = self.new_db.execute(query, {
					"business_id": new_business_id,
					"sayad_code": sayad_code
				}).scalar()
				
				if result > 0:
					# اگر تکراری بود، NULL می‌کنیم
					sayad_code = None
			
			# تبدیل issue_date
			issue_date = convert_timestamp_to_datetime(old_cheque.get('date_stamp'))
			if not issue_date:
				self.stats["checks_skipped"] += 1
				return None
			
			# تبدیل due_date
			due_date = convert_persian_date_to_datetime(old_cheque.get('pay_date'))
			if not due_date:
				# اگر pay_date معتبر نباشد، از date_stamp استفاده می‌کنیم
				due_date = issue_date
			
			# تبدیل amount
			amount = convert_amount(old_cheque.get('amount'))
			if not amount:
				self.stats["checks_skipped"] += 1
				return None
			
			# تبدیل currency_id
			old_money_id = old_cheque.get('money_id')
			if old_money_id and old_money_id in currency_mapping:
				new_currency_id = currency_mapping[old_money_id]
			else:
				# استفاده از ارز پیش‌فرض کسب و کار
				new_currency_id = self.get_default_currency_id(new_business_id)
			
			# تبدیل status
			old_status = old_cheque.get('status')
			new_status = convert_status(old_status, old_type) if old_status else None
			
			# تبدیل status_at
			status_at = convert_timestamp_to_datetime(old_cheque.get('date_submit'))
			if not status_at:
				status_at = issue_date
			
			# نگاشت person_id
			old_person_id = old_cheque.get('person_id')
			new_person_id = person_id_mapping.get(old_person_id) if old_person_id else None
			
			# نگاشت bank_id
			old_bank_id = old_cheque.get('bank_id')
			new_bank_account_id = bank_account_id_mapping.get(old_bank_id) if old_bank_id else None
			
			# محاسبه holder
			current_holder_type, current_holder_id = calculate_holder(
				old_cheque, new_bank_account_id, new_person_id, new_business_id
			)
			
			# developer_data (ذخیره des و سایر اطلاعات)
			import json
			developer_data = {}
			if old_cheque.get('des'):
				developer_data['description'] = old_cheque.get('des')
			if old_cheque.get('ref_id'):
				developer_data['ref_id'] = old_cheque.get('ref_id')
			if old_cheque.get('submitter_id'):
				developer_data['submitter_id'] = old_cheque.get('submitter_id')
			if old_cheque.get('locked'):
				developer_data['locked'] = bool(old_cheque.get('locked'))
			if old_cheque.get('rejected'):
				developer_data['rejected'] = bool(old_cheque.get('rejected'))
			if old_cheque.get('transfer_date'):
				developer_data['transfer_date'] = old_cheque.get('transfer_date')
			
			developer_data_json = None if not developer_data else json.dumps(developer_data, ensure_ascii=False)
			
			# درج چک
			query = text("""
				INSERT INTO checks (
					business_id, type, person_id,
					issue_date, due_date,
					check_number, sayad_code,
					bank_name, branch_name,
					amount, currency_id,
					status, status_at,
					current_holder_type, current_holder_id,
					developer_data,
					created_at, updated_at
				) VALUES (
					:business_id, :type, :person_id,
					:issue_date, :due_date,
					:check_number, :sayad_code,
					:bank_name, :branch_name,
					:amount, :currency_id,
					:status, :status_at,
					:current_holder_type, :current_holder_id,
					:developer_data,
					:created_at, :updated_at
				)
			""")
			
			self.new_db.execute(query, {
				"business_id": new_business_id,
				"type": new_type,
				"person_id": new_person_id,
				"issue_date": issue_date,
				"due_date": due_date,
				"check_number": check_number,
				"sayad_code": sayad_code,
				"bank_name": truncate_string(old_cheque.get('bank_oncheque'), 255),
				"branch_name": None,
				"amount": amount,
				"currency_id": new_currency_id,
				"status": new_status,
				"status_at": status_at,
				"current_holder_type": current_holder_type,
				"current_holder_id": current_holder_id,
				"developer_data": developer_data_json,
				"created_at": datetime.utcnow(),
				"updated_at": datetime.utcnow()
			})
			
			self.new_db.commit()
			
			# دریافت new_check_id
			query = text("""
				SELECT id FROM checks
				WHERE business_id = :business_id AND check_number = :check_number
				LIMIT 1
			""")
			result = self.new_db.execute(query, {
				"business_id": new_business_id,
				"check_number": check_number
			}).fetchone()
			
			if result:
				self.stats["checks_migrated"] += 1
				return result[0]
			else:
				raise Exception("Failed to get new check ID after insert")
		
		except Exception as e:
			self.new_db.rollback()
			self.stats["errors"] += 1
			self.stats["error_details"].append({
				"old_check_id": old_cheque.get('id'),
				"old_business_id": old_cheque.get('bid_id'),
				"check_number": old_cheque.get('number'),
				"type": old_cheque.get('type'),
				"error": str(e)
			})
			return None
	
	def get_old_cheques(self, start_id: Optional[int] = None, limit: Optional[int] = None,
	                   business_ids: Optional[List[int]] = None) -> List[Dict[str, Any]]:
		"""دریافت چک‌ها از دیتابیس قدیمی"""
		query = f"""
			SELECT 
				id, bid_id, submitter_id, bank_id, person_id, ref_id,
				date_submit, type, sayad_num, des, date_stamp, pay_date,
				number, bank_oncheque, amount, status, locked, date,
				rejected, money_id, transfered, transfer_date
			FROM {self.old_db_name}.cheque
			WHERE 1=1
		"""
		
		params = {}
		if business_ids:
			placeholders = ','.join([f':bid_{i}' for i in range(len(business_ids))])
			query += f" AND bid_id IN ({placeholders})"
			for i, bid in enumerate(business_ids):
				params[f'bid_{i}'] = bid
		elif start_id:
			query += " AND id >= :start_id"
			params["start_id"] = start_id
		
		query += " ORDER BY bid_id, id ASC"
		
		if limit:
			query += " LIMIT :limit"
			params["limit"] = limit
		
		results = self.old_db.execute(text(query), params).fetchall()
		
		cheques = []
		for row in results:
			cheques.append({
				"id": row[0],
				"bid_id": row[1],
				"submitter_id": row[2],
				"bank_id": row[3],
				"person_id": row[4],
				"ref_id": row[5],
				"date_submit": row[6],
				"type": row[7],
				"sayad_num": row[8],
				"des": row[9],
				"date_stamp": row[10],
				"pay_date": row[11],
				"number": row[12],
				"bank_oncheque": row[13],
				"amount": row[14],
				"status": row[15],
				"locked": row[16],
				"date": row[17],
				"rejected": row[18],
				"money_id": row[19],
				"transfered": row[20],
				"transfer_date": row[21]
			})
		
		return cheques
	
	def run_migration(self, dry_run: bool = False, batch_size: int = 500,
	                 start_id: Optional[int] = None, limit: Optional[int] = None):
		"""اجرای انتقال"""
		print(f"{'='*60}")
		print(f"شروع انتقال چک‌ها")
		print(f"{'='*60}")
		print(f"دیتابیس قدیمی: {self.old_db_name}")
		print(f"دیتابیس جدید: {self.new_db_name}")
		print(f"حالت تست (dry-run): {dry_run}")
		print(f"اندازه batch: {batch_size}")
		if start_id:
			print(f"شروع از ID: {start_id}")
		if limit:
			print(f"محدودیت تعداد: {limit}")
		print(f"{'='*60}\n")
		
		# ایجاد mapping ها
		business_id_mapping = self.create_business_id_mapping()
		currency_mapping = self.create_currency_mapping()
		person_id_mapping = self.create_person_id_mapping(business_id_mapping)
		bank_account_id_mapping = self.create_bank_account_id_mapping(business_id_mapping)
		
		# دریافت کسب و کارهای منتقل شده
		old_business_ids = list(business_id_mapping.keys())
		
		if not old_business_ids:
			print("هیچ کسب و کاری برای انتقال یافت نشد.")
			return
		
		# دریافت چک‌ها
		old_cheques = self.get_old_cheques(
			start_id=start_id,
			limit=limit,
			business_ids=old_business_ids
		)
		total_cheques = len(old_cheques)
		print(f"تعداد چک‌ها برای انتقال: {total_cheques}\n")
		
		if total_cheques == 0:
			print("هیچ چکی برای انتقال یافت نشد.")
			return
		
		# پردازش batch به batch
		for i in range(0, total_cheques, batch_size):
			batch = old_cheques[i:i+batch_size]
			batch_num = (i // batch_size) + 1
			total_batches = (total_cheques + batch_size - 1) // batch_size
			
			print(f"\nپردازش batch {batch_num}/{total_batches} ({len(batch)} چک)...")
			
			for old_cheque in batch:
				self.stats["checks_processed"] += 1
				
				if not dry_run:
					self.migrate_check(
						old_cheque, business_id_mapping, currency_mapping,
						person_id_mapping, bank_account_id_mapping
					)
				else:
					# در حالت dry-run فقط بررسی می‌کنیم
					old_business_id = old_cheque.get('bid_id')
					if old_business_id in business_id_mapping:
						self.stats["checks_migrated"] += 1
					else:
						self.stats["checks_skipped"] += 1
				
				if self.stats["checks_processed"] % 50 == 0:
					print(f"  پردازش شده: {self.stats['checks_processed']}/{total_cheques}", end='\r')
			
			print(f"\n  Batch {batch_num} تکمیل شد")
		
		# نمایش آمار نهایی
		print(f"\n{'='*60}")
		print("آمار نهایی:")
		print(f"{'='*60}")
		print(f"چک‌ها:")
		print(f"  پردازش شده: {self.stats['checks_processed']}")
		print(f"  منتقل شده: {self.stats['checks_migrated']}")
		print(f"  رد شده: {self.stats['checks_skipped']}")
		print(f"\nخطاها: {self.stats['errors']}")
		
		if self.stats['error_details']:
			print(f"\nجزئیات خطاها:")
			for error in self.stats['error_details'][:10]:
				print(f"  - Check ID {error.get('old_check_id')} (Number: {error.get('check_number')}, Type: {error.get('type')}): {error.get('error')}")
			if len(self.stats['error_details']) > 10:
				print(f"  ... و {len(self.stats['error_details']) - 10} خطای دیگر")
	
	def close(self):
		"""بستن اتصالات"""
		self.old_db.close()
		self.new_db.close()


def main():
	parser = argparse.ArgumentParser(description="انتقال چک‌ها")
	parser.add_argument("--dry-run", action="store_true", help="اجرای تست بدون تغییر در دیتابیس")
	parser.add_argument("--batch-size", type=int, default=500, help="تعداد چک‌ها در هر batch")
	parser.add_argument("--start-id", type=int, help="شروع از شناسه خاص")
	parser.add_argument("--limit", type=int, help="محدود کردن تعداد چک‌ها")
	parser.add_argument("--old-db", default="hesabixOld", help="نام دیتابیس قدیمی")
	parser.add_argument("--new-db", default="hesabixpy", help="نام دیتابیس جدید")
	parser.add_argument("--db-user", default="root", help="نام کاربری دیتابیس")
	parser.add_argument("--db-password", default="136431", help="رمز عبور دیتابیس")
	parser.add_argument("--db-host", default="localhost", help="آدرس دیتابیس")
	parser.add_argument("--db-port", type=int, default=3306, help="پورت دیتابیس")
	
	args = parser.parse_args()
	
	migration = CheckMigration(
		old_db_name=args.old_db,
		new_db_name=args.new_db,
		db_user=args.db_user,
		db_password=args.db_password,
		db_host=args.db_host,
		db_port=args.db_port
	)
	
	try:
		migration.run_migration(
			dry_run=args.dry_run,
			batch_size=args.batch_size,
			start_id=args.start_id,
			limit=args.limit
		)
	finally:
		migration.close()


if __name__ == "__main__":
	main()

