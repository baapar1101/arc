#!/usr/bin/env python3
"""
اسکریپت انتقال کامل کسب و کارها، سال‌های مالی و واحدهای ارزی از hesabixOld به hesabixpy

این اسکریپت:
- کسب و کارها را از hesabixOld منتقل می‌کند
- سال‌های مالی را منتقل می‌کند
- واحدهای ارزی (business_currencies) را منتقل می‌کند
"""

import sys
import os
import argparse
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime, date
import secrets

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session
import phonenumbers


def normalize_email(email: str | None) -> str | None:
	"""نرمال‌سازی ایمیل"""
	return email.lower().strip() if email else None


def normalize_mobile(mobile: str | None) -> str | None:
	"""نرمال‌سازی موبایل"""
	if not mobile:
		return None
	raw = mobile.strip()
	raw = ''.join(ch for ch in raw if ch.isdigit() or ch == '+')
	try:
		region = None if raw.startswith('+') else "IR"
		num = phonenumbers.parse(raw, region)
		if not phonenumbers.is_valid_number(num):
			return None
		return phonenumbers.format_number(num, phonenumbers.PhoneNumberFormat.E164)
	except Exception:
		return None


def convert_timestamp_to_date(timestamp_str: str | None) -> date | None:
	"""تبدیل timestamp string به date"""
	if not timestamp_str or not timestamp_str.strip():
		return None
	try:
		timestamp = int(timestamp_str.strip())
		dt = datetime.fromtimestamp(timestamp)
		return dt.date()
	except (ValueError, TypeError, OSError):
		return None


def convert_business_type(old_type: str | None) -> str:
	"""تبدیل type به business_type (ENUM) - enum در دیتابیس به انگلیسی است"""
	mapping = {
		"فروشگاه": "STORE",
		"مغازه": "SHOP",
		"شخصی": "INDIVIDUAL",
		"شرکت": "COMPANY",
		"موسسه": "INSTITUTE",
		"باشگاه": "CLUB",
		"اتحادیه": "UNION"
	}
	if old_type and old_type in mapping:
		return mapping[old_type]
	return "SHOP"  # پیش‌فرض


def convert_business_field(old_field: str | None) -> str:
	"""تبدیل field به business_field (ENUM) - enum در دیتابیس به انگلیسی است"""
	if not old_field:
		return "OTHER"
	
	old_field_lower = old_field.lower().strip()
	
	# تولیدی
	if any(keyword in old_field_lower for keyword in ["تولید", "ساخت"]):
		return "MANUFACTURING"
	
	# بازرگانی
	if any(keyword in old_field_lower for keyword in ["بازرگانی", "فروش", "خرید", "تجارت"]):
		return "TRADING"
	
	# خدماتی
	if any(keyword in old_field_lower for keyword in ["خدمات", "خدماتی", "مشاوره", "آموزش"]):
		return "SERVICE"
	
	# سایر
	return "OTHER"


def split_full_name(full_name: Optional[str]) -> Tuple[Optional[str], Optional[str]]:
	"""تبدیل full_name به first_name و last_name"""
	if not full_name or not full_name.strip():
		return None, None
	parts = full_name.strip().split()
	if len(parts) == 0:
		return None, None
	elif len(parts) == 1:
		return parts[0], None
	else:
		return parts[0], " ".join(parts[1:])


class BusinessMigration:
	def __init__(self, old_db_name: str = "hesabixOld", new_db_name: str = "hesabixpy",
	             db_user: str = "root", db_password: str = "136431",
	             db_host: str = "localhost", db_port: int = 3306):
		"""ایجاد اتصال به هر دو دیتابیس"""
		self.old_db_name = old_db_name
		self.new_db_name = new_db_name
		
		# اتصال به دیتابیس قدیمی
		old_dsn = f"mysql+pymysql://{db_user}:{db_password}@{db_host}:{db_port}/{old_db_name}"
		old_engine = create_engine(old_dsn, echo=False, pool_pre_ping=True)
		self.old_db = sessionmaker(bind=old_engine)()
		
		# اتصال به دیتابیس جدید
		new_dsn = f"mysql+pymysql://{db_user}:{db_password}@{db_host}:{db_port}/{new_db_name}"
		new_engine = create_engine(new_dsn, echo=False, pool_pre_ping=True)
		self.new_db = sessionmaker(bind=new_engine)()
		
		# آمار
		self.stats = {
			"businesses_processed": 0,
			"businesses_migrated": 0,
			"businesses_skipped": 0,
			"fiscal_years_migrated": 0,
			"fiscal_years_skipped": 0,
			"currencies_migrated": 0,
			"currencies_skipped": 0,
			"errors": 0,
			"error_details": []
		}
	
	def create_user_id_mapping(self) -> Dict[int, int]:
		"""ایجاد mapping بین user_id قدیمی و جدید"""
		query = text("""
			SELECT 
				old.id as old_user_id,
				new.id as new_user_id
			FROM hesabixOld.user old
			INNER JOIN hesabixpy.users new ON (
				(old.email IS NOT NULL AND new.email IS NOT NULL AND BINARY old.email = BINARY new.email) OR
				(old.mobile IS NOT NULL AND new.mobile IS NOT NULL AND BINARY old.mobile = BINARY new.mobile)
			)
			WHERE old.active = 1
		""")
		
		results = self.old_db.execute(query).fetchall()
		mapping = {}
		for row in results:
			mapping[row.old_user_id] = row.new_user_id
		
		print(f"✅ User ID mapping ایجاد شد: {len(mapping)} کاربر")
		return mapping
	
	def create_currency_mapping(self) -> Dict[int, int]:
		"""ایجاد mapping بین money_id قدیمی و currency_id جدید"""
		query = text("""
			SELECT 
				old_money.id as old_money_id,
				new_currency.id as new_currency_id
			FROM hesabixOld.money old_money
			INNER JOIN hesabixpy.currencies new_currency 
				ON BINARY old_money.name = BINARY new_currency.code
		""")
		
		results = self.old_db.execute(query).fetchall()
		mapping = {}
		for row in results:
			mapping[row.old_money_id] = row.new_currency_id
		
		print(f"✅ Currency mapping ایجاد شد: {len(mapping)} ارز")
		return mapping
	
	def get_irr_currency_id(self) -> int:
		"""دریافت شناسه ارز IRR"""
		query = text("SELECT id FROM currencies WHERE code = 'IRR' LIMIT 1")
		result = self.new_db.execute(query).fetchone()
		if result:
			return result[0]
		return 1  # پیش‌فرض
	
	def migrate_business(self, old_business: Dict[str, Any], user_id_mapping: Dict[int, int],
	                    currency_mapping: Dict[int, int], irr_currency_id: int) -> Optional[int]:
		"""انتقال یک کسب و کار"""
		try:
			# نگاشت owner_id
			old_owner_id = old_business.get('owner_id')
			new_owner_id = user_id_mapping.get(old_owner_id)
			
			if not new_owner_id:
				self.stats["businesses_skipped"] += 1
				return None
			
			# بررسی وجود در دیتابیس جدید
			query = text("""
				SELECT COUNT(*) FROM businesses 
				WHERE owner_id = :owner_id AND name = :name
			""")
			result = self.new_db.execute(query, {
				"owner_id": new_owner_id,
				"name": old_business.get('name')
			}).scalar()
			
			if result > 0:
				# کسب و کار موجود است، شناسه آن را برگردان
				query = text("""
					SELECT id FROM businesses 
					WHERE owner_id = :owner_id AND name = :name
					LIMIT 1
				""")
				result = self.new_db.execute(query, {
					"owner_id": new_owner_id,
					"name": old_business.get('name')
				}).fetchone()
				if result:
					return result[0]
				return None
			
			# تبدیل داده‌ها
			business_type = convert_business_type(old_business.get('type'))
			business_field = convert_business_field(old_business.get('field'))
			
			# تبدیل full_name (اگر legal_name وجود دارد)
			first_name, last_name = split_full_name(old_business.get('legal_name'))
			
			# نگاشت default_currency_id
			old_money_id = old_business.get('money_id')
			default_currency_id = currency_mapping.get(old_money_id, irr_currency_id) if old_money_id else irr_currency_id
			
			# تبدیل تاریخ
			date_submit = old_business.get('date_submit')
			if date_submit and date_submit.strip():
				try:
					if date_submit.isdigit():
						created_at = datetime.fromtimestamp(int(date_submit))
					else:
						created_at = datetime.utcnow()
				except:
					created_at = datetime.utcnow()
			else:
				created_at = datetime.utcnow()
			
			# درج کسب و کار
			query = text("""
				INSERT INTO businesses (
					name, business_type, business_field, owner_id,
					national_id, registration_number, economic_id,
					country, province, city, postal_code,
					phone, mobile, address,
					default_currency_id,
					created_at, updated_at
				) VALUES (
					:name, :business_type, :business_field, :owner_id,
					:national_id, :registration_number, :economic_id,
					:country, :province, :city, :postal_code,
					:phone, :mobile, :address,
					:default_currency_id,
					:created_at, :updated_at
				)
			""")
			
			self.new_db.execute(query, {
				"name": old_business.get('name'),
				"business_type": business_type,
				"business_field": business_field,
				"owner_id": new_owner_id,
				"national_id": old_business.get('shenasemeli'),
				"registration_number": old_business.get('shomaresabt'),
				"economic_id": old_business.get('codeeghtesadi'),
				"country": old_business.get('country'),
				"province": old_business.get('ostan'),
				"city": old_business.get('shahrestan'),
				"postal_code": old_business.get('postalcode'),
				"phone": old_business.get('tel'),
				"mobile": normalize_mobile(old_business.get('mobile')),
				"address": old_business.get('address'),
				"default_currency_id": default_currency_id,
				"created_at": created_at,
				"updated_at": datetime.utcnow()
			})
			
			self.new_db.commit()
			
			# دریافت new_business_id
			query = text("""
				SELECT id FROM businesses 
				WHERE owner_id = :owner_id AND name = :name
				LIMIT 1
			""")
			result = self.new_db.execute(query, {
				"owner_id": new_owner_id,
				"name": old_business.get('name')
			}).fetchone()
			
			if result:
				self.stats["businesses_migrated"] += 1
				return result[0]
			else:
				raise Exception("Failed to get new business ID after insert")
		
		except Exception as e:
			self.new_db.rollback()
			self.stats["errors"] += 1
			self.stats["error_details"].append({
				"type": "business",
				"old_business_id": old_business.get('id'),
				"error": str(e)
			})
			return None
	
	def migrate_fiscal_year(self, old_year: Dict[str, Any], business_id_mapping: Dict[int, int]) -> bool:
		"""انتقال یک سال مالی"""
		try:
			old_business_id = old_year.get('bid_id')
			new_business_id = business_id_mapping.get(old_business_id)
			
			if not new_business_id:
				self.stats["fiscal_years_skipped"] += 1
				return False
			
			# بررسی وجود
			query = text("""
				SELECT COUNT(*) FROM fiscal_years
				WHERE business_id = :business_id AND title = :title
			""")
			result = self.new_db.execute(query, {
				"business_id": new_business_id,
				"title": old_year.get('label')
			}).scalar()
			
			if result > 0:
				self.stats["fiscal_years_skipped"] += 1
				return False
			
			# تبدیل تاریخ‌ها
			start_date = convert_timestamp_to_date(old_year.get('start'))
			end_date = convert_timestamp_to_date(old_year.get('end'))
			
			if not start_date or not end_date:
				self.stats["fiscal_years_skipped"] += 1
				return False
			
			# تبدیل head به is_last
			is_last = bool(old_year.get('head', 0))
			
			# درج سال مالی
			query = text("""
				INSERT INTO fiscal_years (
					business_id, title, start_date, end_date,
					is_last, inventory_valuation_method,
					created_at, updated_at
				) VALUES (
					:business_id, :title, :start_date, :end_date,
					:is_last, :inventory_valuation_method,
					:created_at, :updated_at
				)
			""")
			
			self.new_db.execute(query, {
				"business_id": new_business_id,
				"title": old_year.get('label'),
				"start_date": start_date,
				"end_date": end_date,
				"is_last": is_last,
				"inventory_valuation_method": "FIFO",
				"created_at": datetime.utcnow(),
				"updated_at": datetime.utcnow()
			})
			
			self.new_db.commit()
			self.stats["fiscal_years_migrated"] += 1
			return True
		
		except Exception as e:
			self.new_db.rollback()
			self.stats["errors"] += 1
			self.stats["error_details"].append({
				"type": "fiscal_year",
				"old_year_id": old_year.get('id'),
				"error": str(e)
			})
			return False
	
	def migrate_business_currency(self, old_bm: Dict[str, Any], business_id_mapping: Dict[int, int],
	                             currency_mapping: Dict[int, int]) -> bool:
		"""انتقال یک واحد ارزی کسب و کار"""
		try:
			old_business_id = old_bm.get('business_id')
			new_business_id = business_id_mapping.get(old_business_id)
			
			if not new_business_id:
				self.stats["currencies_skipped"] += 1
				return False
			
			old_money_id = old_bm.get('money_id')
			new_currency_id = currency_mapping.get(old_money_id)
			
			if not new_currency_id:
				self.stats["currencies_skipped"] += 1
				return False
			
			# بررسی وجود
			query = text("""
				SELECT COUNT(*) FROM business_currencies
				WHERE business_id = :business_id AND currency_id = :currency_id
			""")
			result = self.new_db.execute(query, {
				"business_id": new_business_id,
				"currency_id": new_currency_id
			}).scalar()
			
			if result > 0:
				self.stats["currencies_skipped"] += 1
				return False
			
			# درج
			query = text("""
				INSERT INTO business_currencies (
					business_id, currency_id,
					created_at, updated_at
				) VALUES (
					:business_id, :currency_id,
					:created_at, :updated_at
				)
			""")
			
			self.new_db.execute(query, {
				"business_id": new_business_id,
				"currency_id": new_currency_id,
				"created_at": datetime.utcnow(),
				"updated_at": datetime.utcnow()
			})
			
			self.new_db.commit()
			self.stats["currencies_migrated"] += 1
			return True
		
		except Exception as e:
			self.new_db.rollback()
			self.stats["errors"] += 1
			self.stats["error_details"].append({
				"type": "business_currency",
				"old_business_id": old_bm.get('business_id'),
				"old_money_id": old_bm.get('money_id'),
				"error": str(e)
			})
			return False
	
	def get_old_businesses(self, start_id: Optional[int] = None, limit: Optional[int] = None) -> List[Dict[str, Any]]:
		"""دریافت کسب و کارها از دیتابیس قدیمی"""
		query = f"""
			SELECT 
				id, owner_id, name, legal_name, money_id,
				field, type, shenasemeli, codeeghtesadi, shomaresabt,
				country, ostan, shahrestan, postalcode,
				tel, mobile, address, date_submit
			FROM {self.old_db_name}.business
			WHERE owner_id IS NOT NULL
		"""
		
		params = {}
		if start_id:
			query += " AND id >= :start_id"
			params["start_id"] = start_id
		
		query += " ORDER BY id ASC"
		
		if limit:
			query += " LIMIT :limit"
			params["limit"] = limit
		
		results = self.old_db.execute(text(query), params).fetchall()
		
		businesses = []
		for row in results:
			businesses.append({
				"id": row[0],
				"owner_id": row[1],
				"name": row[2],
				"legal_name": row[3],
				"money_id": row[4],
				"field": row[5],
				"type": row[6],
				"shenasemeli": row[7],
				"codeeghtesadi": row[8],
				"shomaresabt": row[9],
				"country": row[10],
				"ostan": row[11],
				"shahrestan": row[12],
				"postalcode": row[13],
				"tel": row[14],
				"mobile": row[15],
				"address": row[16],
				"date_submit": row[17]
			})
		
		return businesses
	
	def get_old_fiscal_years(self, business_ids: List[int]) -> List[Dict[str, Any]]:
		"""دریافت سال‌های مالی از دیتابیس قدیمی"""
		if not business_ids:
			return []
		
		placeholders = ','.join([':id' + str(i) for i in range(len(business_ids))])
		query = f"""
			SELECT id, bid_id, label, head, start, end
			FROM {self.old_db_name}.year
			WHERE bid_id IN ({placeholders})
		"""
		
		params = {f'id{i}': bid for i, bid in enumerate(business_ids)}
		results = self.old_db.execute(text(query), params).fetchall()
		
		years = []
		for row in results:
			years.append({
				"id": row[0],
				"bid_id": row[1],
				"label": row[2],
				"head": row[3],
				"start": row[4],
				"end": row[5]
			})
		
		return years
	
	def get_old_business_currencies(self, business_ids: List[int]) -> List[Dict[str, Any]]:
		"""دریافت واحدهای ارزی از دیتابیس قدیمی"""
		if not business_ids:
			return []
		
		placeholders = ','.join([':id' + str(i) for i in range(len(business_ids))])
		query = f"""
			SELECT business_id, money_id
			FROM {self.old_db_name}.business_money
			WHERE business_id IN ({placeholders})
		"""
		
		params = {f'id{i}': bid for i, bid in enumerate(business_ids)}
		results = self.old_db.execute(text(query), params).fetchall()
		
		currencies = []
		for row in results:
			currencies.append({
				"business_id": row[0],
				"money_id": row[1]
			})
		
		return currencies
	
	def run_migration(self, dry_run: bool = False, batch_size: int = 100,
	                 start_id: Optional[int] = None, limit: Optional[int] = None):
		"""اجرای انتقال"""
		print(f"{'='*60}")
		print(f"شروع انتقال کسب و کارها، سال‌های مالی و واحدهای ارزی")
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
		user_id_mapping = self.create_user_id_mapping()
		currency_mapping = self.create_currency_mapping()
		irr_currency_id = self.get_irr_currency_id()
		
		# دریافت کسب و کارها
		old_businesses = self.get_old_businesses(start_id=start_id, limit=limit)
		total_businesses = len(old_businesses)
		print(f"تعداد کسب و کارها برای انتقال: {total_businesses}\n")
		
		if total_businesses == 0:
			print("هیچ کسب و کاری برای انتقال یافت نشد.")
			return
		
		# نگاشت old_business_id -> new_business_id
		business_id_mapping: Dict[int, int] = {}
		
		# پردازش batch به batch
		for i in range(0, total_businesses, batch_size):
			batch = old_businesses[i:i+batch_size]
			batch_num = (i // batch_size) + 1
			total_batches = (total_businesses + batch_size - 1) // batch_size
			
			print(f"\nپردازش batch {batch_num}/{total_batches} ({len(batch)} کسب و کار)...")
			
			for old_business in batch:
				self.stats["businesses_processed"] += 1
				
				if not dry_run:
					new_business_id = self.migrate_business(
						old_business, user_id_mapping, currency_mapping, irr_currency_id
					)
					if new_business_id:
						business_id_mapping[old_business['id']] = new_business_id
				else:
					# در حالت dry-run فقط بررسی می‌کنیم
					old_owner_id = old_business.get('owner_id')
					if old_owner_id in user_id_mapping:
						self.stats["businesses_migrated"] += 1
					else:
						self.stats["businesses_skipped"] += 1
				
				if self.stats["businesses_processed"] % 10 == 0:
					print(f"  پردازش شده: {self.stats['businesses_processed']}/{total_businesses}", end='\r')
			
			print(f"\n  Batch {batch_num} تکمیل شد")
		
		# انتقال سال‌های مالی و واحدهای ارزی
		if not dry_run and business_id_mapping:
			print(f"\n{'='*60}")
			print("انتقال سال‌های مالی و واحدهای ارزی...")
			print(f"{'='*60}\n")
			
			old_business_ids = list(business_id_mapping.keys())
			
			# انتقال سال‌های مالی
			old_years = self.get_old_fiscal_years(old_business_ids)
			print(f"سال‌های مالی برای انتقال: {len(old_years)}")
			for old_year in old_years:
				self.migrate_fiscal_year(old_year, business_id_mapping)
			
			# انتقال واحدهای ارزی
			old_currencies = self.get_old_business_currencies(old_business_ids)
			print(f"واحدهای ارزی برای انتقال: {len(old_currencies)}")
			for old_currency in old_currencies:
				self.migrate_business_currency(old_currency, business_id_mapping, currency_mapping)
		
		# نمایش آمار نهایی
		print(f"\n{'='*60}")
		print("آمار نهایی:")
		print(f"{'='*60}")
		print(f"کسب و کارها:")
		print(f"  پردازش شده: {self.stats['businesses_processed']}")
		print(f"  منتقل شده: {self.stats['businesses_migrated']}")
		print(f"  رد شده: {self.stats['businesses_skipped']}")
		print(f"\nسال‌های مالی:")
		print(f"  منتقل شده: {self.stats['fiscal_years_migrated']}")
		print(f"  رد شده: {self.stats['fiscal_years_skipped']}")
		print(f"\nواحدهای ارزی:")
		print(f"  منتقل شده: {self.stats['currencies_migrated']}")
		print(f"  رد شده: {self.stats['currencies_skipped']}")
		print(f"\nخطاها: {self.stats['errors']}")
		
		if self.stats['error_details']:
			print(f"\nجزئیات خطاها:")
			for error in self.stats['error_details'][:10]:
				print(f"  - {error.get('type')} (ID {error.get('old_business_id', error.get('old_year_id', 'N/A'))}): {error.get('error')}")
			if len(self.stats['error_details']) > 10:
				print(f"  ... و {len(self.stats['error_details']) - 10} خطای دیگر")
	
	def close(self):
		"""بستن اتصالات"""
		self.old_db.close()
		self.new_db.close()


def main():
	parser = argparse.ArgumentParser(description="انتقال کسب و کارها، سال‌های مالی و واحدهای ارزی")
	parser.add_argument("--dry-run", action="store_true", help="اجرای تست بدون تغییر در دیتابیس")
	parser.add_argument("--batch-size", type=int, default=100, help="تعداد کسب و کارها در هر batch")
	parser.add_argument("--start-id", type=int, help="شروع از شناسه خاص")
	parser.add_argument("--limit", type=int, help="محدود کردن تعداد کسب و کارها")
	parser.add_argument("--old-db", default="hesabixOld", help="نام دیتابیس قدیمی")
	parser.add_argument("--new-db", default="hesabixpy", help="نام دیتابیس جدید")
	parser.add_argument("--db-user", default="root", help="نام کاربری دیتابیس")
	parser.add_argument("--db-password", default="136431", help="رمز عبور دیتابیس")
	parser.add_argument("--db-host", default="localhost", help="آدرس دیتابیس")
	parser.add_argument("--db-port", type=int, default=3306, help="پورت دیتابیس")
	
	args = parser.parse_args()
	
	migration = BusinessMigration(
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

