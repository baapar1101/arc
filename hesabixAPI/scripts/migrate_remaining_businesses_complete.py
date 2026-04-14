#!/usr/bin/env python3
"""
اسکریپت انتقال کسب و کارهای منتقل نشده و تمام موارد مرتبط

این اسکریپت:
- کسب و کارهای منتقل نشده را با query mapping اصلاح شده منتقل می‌کند
- برای هر کسب و کار جدید، موارد زیر را منتقل می‌کند:
  - اشخاص
  - حساب‌های بانکی
  - صندوق
  - تنخواه
  - کالاها
  - چک‌ها
  - کاربران عضو
"""

import sys
import os
import argparse
from typing import List, Dict, Any, Optional
from datetime import datetime, date
import json
from decimal import Decimal, InvalidOperation

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session

# Import helper functions
from migrate_businesses_complete import (
	convert_timestamp_to_date, convert_business_type, convert_business_field
)
from migrate_bank_cash_petty_complete import truncate_string
from migrate_persons_complete import (
	split_name, get_alias_name, convert_code, get_person_types,
	convert_person_types_to_json
)
from migrate_products_complete import (
	convert_price, convert_khadamat_to_item_type, convert_order_point,
	convert_track_inventory, convert_taxable
)
from migrate_checks_complete import (
	convert_timestamp_to_datetime, convert_persian_date_to_datetime,
	convert_type as convert_check_type, convert_status, convert_amount,
	calculate_holder
)
from migrate_business_users_complete import convert_permissions_to_json

def normalize_email(email: str | None) -> str | None:
	"""نرمال‌سازی ایمیل"""
	return email.lower().strip() if email else None

def normalize_mobile(mobile: str | None) -> str | None:
	"""نرمال‌سازی موبایل"""
	if not mobile:
		return None
	# Clean input: keep digits and leading plus
	raw = mobile.strip()
	raw = ''.join(ch for ch in raw if ch.isdigit() or ch == '+')
	try:
		import phonenumbers
		region = None if raw.startswith('+') else "IR"
		num = phonenumbers.parse(raw, region)
		if not phonenumbers.is_valid_number(num):
			return None
		return phonenumbers.format_number(num, phonenumbers.PhoneNumberFormat.E164)
	except Exception:
		return None

def split_full_name(full_name: Optional[str]) -> tuple[Optional[str], Optional[str]]:
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


class RemainingBusinessMigration:
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
			"businesses_migrated": 0,
			"fiscal_years_migrated": 0,
			"persons_migrated": 0,
			"bank_accounts_migrated": 0,
			"cash_registers_migrated": 0,
			"petty_cash_migrated": 0,
			"products_migrated": 0,
			"checks_migrated": 0,
			"business_users_migrated": 0,
			"errors": 0
		}
	
	def create_user_id_mapping_case_insensitive(self) -> Dict[int, int]:
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
		
		print(f"✅ User ID mapping (case-insensitive) ایجاد شد: {len(mapping)} کاربر")
		return mapping
	
	def migrate_missing_users(self, existing_user_mapping: Dict[int, int]) -> Dict[int, int]:
		"""انتقال کاربران باقی‌مانده که کسب‌وکار دارند"""
		# پیدا کردن کاربرانی که کسب‌وکار دارند اما mapping ندارند
		query = text("""
			SELECT DISTINCT
				old_u.id, old_u.email, old_u.password, old_u.full_name, 
				old_u.mobile, old_u.active, old_u.date_register, 
				old_u.invited_by_id, old_u.invate_code
			FROM hesabixOld.user old_u
			INNER JOIN hesabixOld.business old_b ON old_u.id = old_b.owner_id
			LEFT JOIN hesabixpy.users new_u ON (
				(old_u.email IS NOT NULL AND new_u.email IS NOT NULL AND LOWER(TRIM(old_u.email)) = LOWER(TRIM(new_u.email))) OR
				(old_u.mobile IS NOT NULL AND new_u.mobile IS NOT NULL AND REPLACE(REPLACE(REPLACE(old_u.mobile, '+', ''), ' ', ''), '-', '') = REPLACE(REPLACE(REPLACE(new_u.mobile, '+', ''), ' ', ''), '-', ''))
			)
			WHERE old_u.active = 1
				AND new_u.id IS NULL
				AND (old_u.email IS NOT NULL OR old_u.mobile IS NOT NULL)
				AND old_b.id IN (
					SELECT DISTINCT bid_id FROM hesabixOld.hesabdari_doc 
					WHERE type IN ('sell', 'buy', 'rfsell', 'rfbuy') AND is_approved = 1
				)
		""")
		
		results = self.old_db.execute(query).fetchall()
		new_mappings = {}
		
		# Use local helper functions
		
		# Get existing referral codes
		query = text("SELECT referral_code FROM users WHERE referral_code IS NOT NULL")
		existing_codes = {row[0] for row in self.new_db.execute(query).fetchall()}
		
		for row in results:
			old_user_id = row[0]
			old_email = row[1]
			old_password = row[2]
			old_full_name = row[3]
			old_mobile = row[4]
			
			try:
				# Normalize email and mobile
				email = normalize_email(old_email)
				mobile = normalize_mobile(old_mobile)
				
				if not email and not mobile:
					print(f"⚠️  کاربر {old_user_id}: بدون email یا mobile، رد شد")
					continue
				
				# Check if already exists with normalized values
				check_query = text("""
					SELECT id FROM users 
					WHERE (email = :email AND :email IS NOT NULL) 
					   OR (mobile = :mobile AND :mobile IS NOT NULL)
				""")
				existing = self.new_db.execute(check_query, {
					"email": email,
					"mobile": mobile
				}).fetchone()
				
				if existing:
					print(f"✅ کاربر {old_user_id}: پیدا شد در سیستم جدید (ID: {existing[0]})")
					new_mappings[old_user_id] = existing[0]
					continue
				
				# Split full name
				first_name, last_name = split_full_name(old_full_name)
				
				# Handle password
				password_hash = old_password
				if not password_hash:
					try:
						from app.core.security import hash_password
						import secrets
						default_password = secrets.token_urlsafe(32)
						password_hash = hash_password(default_password)
					except Exception:
						import bcrypt
						import secrets
						default_password = secrets.token_urlsafe(32)
						password_hash = bcrypt.hashpw(default_password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
				
				# Generate referral code
				import secrets
				referral_code = None
				if row[8] and row[8].strip():
					old_code = row[8].strip()
					if old_code not in existing_codes:
						check_code = text("SELECT COUNT(*) FROM users WHERE referral_code = :code")
						if self.new_db.execute(check_code, {"code": old_code}).scalar() == 0:
							referral_code = old_code
							existing_codes.add(referral_code)
				
				if not referral_code:
					for _ in range(20):
						code = secrets.token_urlsafe(8).replace('-', '').replace('_', '')[:10]
						if code not in existing_codes:
							check_code = text("SELECT COUNT(*) FROM users WHERE referral_code = :code")
							if self.new_db.execute(check_code, {"code": code}).scalar() == 0:
								referral_code = code
								existing_codes.add(referral_code)
								break
					if not referral_code:
						referral_code = secrets.token_urlsafe(12).replace('-', '').replace('_', '')[:12]
				
				# Get referred_by_user_id
				referred_by_user_id = None
				if row[7] and row[7] in existing_user_mapping:
					referred_by_user_id = existing_user_mapping[row[7]]
				elif row[7] and row[7] in new_mappings:
					referred_by_user_id = new_mappings[row[7]]
				
				# Convert date
				created_at = datetime.utcnow()
				if row[6]:
					try:
						if isinstance(row[6], str) and row[6].isdigit():
							created_at = datetime.fromtimestamp(int(row[6]))
						else:
							created_at = datetime.fromisoformat(str(row[6]).replace('Z', '+00:00'))
					except:
						pass
				
				# Insert user
				insert_query = text("""
					INSERT INTO users (
						email, mobile, first_name, last_name, password_hash,
						is_active, email_verified, mobile_verified,
						referral_code, referred_by_user_id,
						created_at, updated_at
					) VALUES (
						:email, :mobile, :first_name, :last_name, :password_hash,
						:is_active, :email_verified, :mobile_verified,
						:referral_code, :referred_by_user_id,
						:created_at, :updated_at
					)
				""")
				
				self.new_db.execute(insert_query, {
					"email": email,
					"mobile": mobile,
					"first_name": first_name,
					"last_name": last_name,
					"password_hash": password_hash,
					"is_active": bool(row[5]),
					"email_verified": False,
					"mobile_verified": False,
					"referral_code": referral_code,
					"referred_by_user_id": referred_by_user_id,
					"created_at": created_at,
					"updated_at": datetime.utcnow()
				})
				self.new_db.commit()
				
				# Get new user ID
				if email:
					get_id_query = text("SELECT id FROM users WHERE email = :email")
					result = self.new_db.execute(get_id_query, {"email": email}).fetchone()
				else:
					get_id_query = text("SELECT id FROM users WHERE mobile = :mobile")
					result = self.new_db.execute(get_id_query, {"mobile": mobile}).fetchone()
				
				if result:
					new_user_id = result[0]
					new_mappings[old_user_id] = new_user_id
					print(f"✅ کاربر {old_user_id} منتقل شد -> ID جدید: {new_user_id}")
				else:
					print(f"❌ کاربر {old_user_id}: خطا در دریافت ID جدید")
				
			except Exception as e:
				self.new_db.rollback()
				print(f"❌ خطا در انتقال کاربر {old_user_id}: {str(e)}")
				continue
		
		print(f"✅ {len(new_mappings)} کاربر جدید منتقل شد")
		return new_mappings
	
	def create_currency_mapping(self) -> Dict[int, int]:
		"""ایجاد mapping بین currency_id قدیمی و جدید"""
		return {1: 1, 2: 2, 3: 20, 4: 19}  # IRR, USD, AFN, IQD
	
	def get_unmigrated_businesses(self, user_id_mapping: Dict[int, int]) -> List[Dict[str, Any]]:
		"""دریافت کسب و کارهای منتقل نشده"""
		# استفاده از JOIN مستقیم به جای IN برای پیدا کردن کسب‌وکارهای باقی‌مانده
		query = text("""
			SELECT 
				old_business.id, old_business.owner_id, old_business.name,
				old_business.legal_name, old_business.money_id, old_business.field,
				old_business.type, old_business.shenasemeli, old_business.codeeghtesadi,
				old_business.shomaresabt, old_business.country, old_business.ostan,
				old_business.shahrestan, old_business.postalcode, old_business.tel,
				old_business.mobile, old_business.address, old_business.email
			FROM hesabixOld.business old_business
			INNER JOIN hesabixOld.user old_user ON old_business.owner_id = old_user.id
			INNER JOIN hesabixpy.users new_user ON (
				(old_user.email IS NOT NULL AND new_user.email IS NOT NULL AND LOWER(TRIM(old_user.email)) = LOWER(TRIM(new_user.email))) OR
				(old_user.mobile IS NOT NULL AND new_user.mobile IS NOT NULL AND REPLACE(REPLACE(REPLACE(old_user.mobile, '+', ''), ' ', ''), '-', '') = REPLACE(REPLACE(REPLACE(new_user.mobile, '+', ''), ' ', ''), '-', ''))
			)
			LEFT JOIN hesabixpy.businesses new_business ON (
				new_business.owner_id = new_user.id 
				AND new_business.name = old_business.name
			)
			WHERE old_user.active = 1
				AND new_business.id IS NULL
				AND old_business.id IN (
					SELECT DISTINCT bid_id FROM hesabixOld.hesabdari_doc 
					WHERE type IN ('sell', 'buy', 'rfsell', 'rfbuy') AND is_approved = 1
				)
		""")
		
		results = self.old_db.execute(query).fetchall()
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
				"email": row[17]
			})
		
		return businesses
	
	def migrate_business(self, old_business: Dict[str, Any], user_id_mapping: Dict[int, int],
	                    currency_mapping: Dict[int, int]) -> Optional[int]:
		"""انتقال یک کسب و کار"""
		try:
			old_owner_id = old_business.get('owner_id')
			new_owner_id = user_id_mapping.get(old_owner_id)
			
			if not new_owner_id:
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
				return None
			
			# تبدیل currency_id
			old_money_id = old_business.get('money_id')
			if old_money_id and old_money_id in currency_mapping:
				new_currency_id = currency_mapping[old_money_id]
			else:
				new_currency_id = 1  # IRR پیش‌فرض
			
			# درج کسب و کار
			query = text("""
				INSERT INTO businesses (
					owner_id, name, business_type, business_field,
					default_currency_id, address, phone, mobile,
					national_id, registration_number, economic_id,
					country, province, city, postal_code,
					created_at, updated_at
				) VALUES (
					:owner_id, :name, :business_type, :business_field,
					:default_currency_id, :address, :phone, :mobile,
					:national_id, :registration_number, :economic_id,
					:country, :province, :city, :postal_code,
					:created_at, :updated_at
				)
			""")
			
			self.new_db.execute(query, {
				"owner_id": new_owner_id,
				"name": old_business.get('name'),
				"business_type": convert_business_type(old_business.get('type')),
				"business_field": convert_business_field(old_business.get('field')),
				"default_currency_id": new_currency_id,
				"address": truncate_string(old_business.get('address'), 1000),
				"phone": truncate_string(old_business.get('tel'), 20),
				"mobile": truncate_string(old_business.get('mobile'), 20),
				"national_id": truncate_string(old_business.get('shenasemeli'), 20),
				"registration_number": truncate_string(old_business.get('shomaresabt'), 50),
				"economic_id": truncate_string(old_business.get('codeeghtesadi'), 50),
				"country": truncate_string(old_business.get('country'), 100),
				"province": truncate_string(old_business.get('ostan'), 100),
				"city": truncate_string(old_business.get('shahrestan'), 100),
				"postal_code": truncate_string(old_business.get('postalcode'), 20),
				"created_at": datetime.utcnow(),
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
			return None
		
		except Exception as e:
			self.new_db.rollback()
			self.stats["errors"] += 1
			print(f"❌ خطا در انتقال کسب و کار {old_business.get('id')}: {e}")
			return None
	
	def migrate_fiscal_year(self, old_business_id: int, new_business_id: int):
		"""انتقال سال مالی یک کسب و کار"""
		query = text("""
			SELECT id, bid_id, label, head, start, end
			FROM hesabixOld.year
			WHERE bid_id = :bid_id
			LIMIT 1
		""")
		
		result = self.old_db.execute(query, {"bid_id": old_business_id}).fetchone()
		
		if not result:
			return
		
		try:
			# بررسی وجود
			check_query = text("""
				SELECT COUNT(*) FROM fiscal_years
				WHERE business_id = :business_id
			""")
			if self.new_db.execute(check_query, {
				"business_id": new_business_id
			}).scalar() > 0:
				return
			
			# تبدیل تاریخ‌ها
			start_date = convert_timestamp_to_date(result[4])
			end_date = convert_timestamp_to_date(result[5])
			
			# درج
			insert_query = text("""
				INSERT INTO fiscal_years (
					business_id, title, is_last,
					start_date, end_date,
					created_at, updated_at
				) VALUES (
					:business_id, :title, :is_last,
					:start_date, :end_date,
					:created_at, :updated_at
				)
			""")
			
			self.new_db.execute(insert_query, {
				"business_id": new_business_id,
				"title": result[2] or "سال مالی",
				"is_last": True,
				"start_date": start_date,
				"end_date": end_date,
				"created_at": datetime.utcnow(),
				"updated_at": datetime.utcnow()
			})
			self.new_db.commit()
			self.stats["fiscal_years_migrated"] += 1
		except Exception as e:
			self.new_db.rollback()
	
	def create_person_type_mapping(self) -> Dict[int, str]:
		"""ایجاد mapping برای person_type"""
		query = text("SELECT id, label FROM hesabixOld.person_type")
		results = self.old_db.execute(query).fetchall()
		mapping = {}
		for row in results:
			mapping[row.id] = row.label
		return mapping
	
	def migrate_persons_for_business(self, old_business_id: int, new_business_id: int,
	                                 person_type_mapping: Dict[int, str]):
		"""انتقال اشخاص یک کسب و کار"""
		query = text("""
			SELECT 
				id, bid_id, code, nikename, name,
				tel, mobile, mobile2, address, des,
				company, shenasemeli, codeeghtesadi, sabt,
				keshvar, ostan, shahr, postalcode,
				email, website, fax, birthday, payment_id
			FROM hesabixOld.person
			WHERE bid_id = :bid_id
		""")
		
		results = self.old_db.execute(query, {"bid_id": old_business_id}).fetchall()
		
		for row in results:
			try:
				old_person_id = row[0]
				old_code = row[2]
				new_code = convert_code(old_code)
				
				# بررسی وجود
				if new_code:
					check_query = text("""
						SELECT COUNT(*) FROM persons
						WHERE business_id = :business_id AND code = :code
					""")
					if self.new_db.execute(check_query, {
						"business_id": new_business_id,
						"code": new_code
					}).scalar() > 0:
						continue
				
				# تبدیل alias_name
				alias_name = get_alias_name(row[3], row[4])
				first_name, last_name = split_name(row[4])
				
				# تبدیل person_types
				person_types_list = get_person_types(old_person_id, person_type_mapping, self.old_db)
				person_types_json = convert_person_types_to_json(person_types_list)
				
				# محدود کردن national_id
				national_id = row[11]
				if national_id and len(str(national_id)) > 20:
					national_id = None
				
				# درج
				insert_query = text("""
					INSERT INTO persons (
						business_id, code, alias_name, first_name, last_name,
						person_types, company_name, payment_id,
						national_id, registration_number, economic_id,
						country, province, city, address, postal_code,
						phone, mobile, fax, email, website,
						created_at, updated_at
					) VALUES (
						:business_id, :code, :alias_name, :first_name, :last_name,
						:person_types, :company_name, :payment_id,
						:national_id, :registration_number, :economic_id,
						:country, :province, :city, :address, :postal_code,
						:phone, :mobile, :fax, :email, :website,
						:created_at, :updated_at
					)
				""")
				
				self.new_db.execute(insert_query, {
					"business_id": new_business_id,
					"code": new_code,
					"alias_name": alias_name,
					"first_name": first_name,
					"last_name": last_name,
					"person_types": person_types_json,
					"company_name": row[10],
					"payment_id": row[22],
					"national_id": national_id,
					"registration_number": row[13],
					"economic_id": row[12],
					"country": row[14],
					"province": row[15],
					"city": row[16],
					"address": row[8],
					"postal_code": truncate_string(row[17], 20),
					"phone": row[5],
					"mobile": row[6],
					"fax": row[20],
					"email": row[18],
					"website": row[19],
					"created_at": datetime.utcnow(),
					"updated_at": datetime.utcnow()
				})
				self.new_db.commit()
				self.stats["persons_migrated"] += 1
			except Exception as e:
				self.new_db.rollback()
				continue
	
	def migrate_bank_accounts_for_business(self, old_business_id: int, new_business_id: int,
	                                      currency_mapping: Dict[int, int]):
		"""انتقال حساب‌های بانکی یک کسب و کار"""
		query = text("""
			SELECT 
				id, bid_id, name, card_num, shaba, account_num,
				owner, shobe, pos_num, des, mobile_internet_bank, code, money_id
			FROM hesabixOld.bank_account
			WHERE bid_id = :bid_id
		""")
		
		results = self.old_db.execute(query, {"bid_id": old_business_id}).fetchall()
		
		for row in results:
			try:
				old_code = row[11]
				new_code = truncate_string(old_code, 50)
				
				# بررسی وجود
				if new_code:
					check_query = text("""
						SELECT COUNT(*) FROM bank_accounts
						WHERE business_id = :business_id AND code = :code
					""")
					if self.new_db.execute(check_query, {
						"business_id": new_business_id,
						"code": new_code
					}).scalar() > 0:
						continue
				
				# تبدیل currency_id
				old_money_id = row[12]
				if old_money_id and old_money_id in currency_mapping:
					new_currency_id = currency_mapping[old_money_id]
				else:
					new_currency_id = 1
				
				# درج
				insert_query = text("""
					INSERT INTO bank_accounts (
						business_id, code, name, description,
						branch, account_number, sheba_number, card_number,
						owner_name, pos_number, payment_id,
						currency_id, is_active, is_default,
						created_at, updated_at
					) VALUES (
						:business_id, :code, :name, :description,
						:branch, :account_number, :sheba_number, :card_number,
						:owner_name, :pos_number, :payment_id,
						:currency_id, :is_active, :is_default,
						:created_at, :updated_at
					)
				""")
				
				self.new_db.execute(insert_query, {
					"business_id": new_business_id,
					"code": new_code,
					"name": row[2],
					"description": truncate_string(row[9], 500),
					"branch": truncate_string(row[7], 255),
					"account_number": truncate_string(row[5], 50),
					"sheba_number": truncate_string(row[4], 30),
					"card_number": truncate_string(row[3], 20),
					"owner_name": truncate_string(row[6], 255),
					"pos_number": truncate_string(row[8], 50),
					"payment_id": truncate_string(row[10], 100),
					"currency_id": new_currency_id,
					"is_active": True,
					"is_default": False,
					"created_at": datetime.utcnow(),
					"updated_at": datetime.utcnow()
				})
				self.new_db.commit()
				self.stats["bank_accounts_migrated"] += 1
			except Exception as e:
				self.new_db.rollback()
				continue
	
	def migrate_cash_registers_for_business(self, old_business_id: int, new_business_id: int,
	                                       currency_mapping: Dict[int, int]):
		"""انتقال صندوق‌های یک کسب و کار"""
		query = text("""
			SELECT 
				id, bid_id, name, des, code, money_id
			FROM hesabixOld.cashdesk
			WHERE bid_id = :bid_id
		""")
		
		results = self.old_db.execute(query, {"bid_id": old_business_id}).fetchall()
		
		for row in results:
			try:
				old_code = row[4]
				new_code = truncate_string(old_code, 50)
				
				# بررسی وجود
				if new_code:
					check_query = text("""
						SELECT COUNT(*) FROM cash_registers
						WHERE business_id = :business_id AND code = :code
					""")
					if self.new_db.execute(check_query, {
						"business_id": new_business_id,
						"code": new_code
					}).scalar() > 0:
						continue
				
				# تبدیل currency_id
				old_money_id = row[5]
				if old_money_id and old_money_id in currency_mapping:
					new_currency_id = currency_mapping[old_money_id]
				else:
					new_currency_id = 1
				
				# درج
				insert_query = text("""
					INSERT INTO cash_registers (
						business_id, code, name, description,
						currency_id, is_active, is_default,
						payment_switch_number, payment_terminal_number, merchant_id,
						created_at, updated_at
					) VALUES (
						:business_id, :code, :name, :description,
						:currency_id, :is_active, :is_default,
						:payment_switch_number, :payment_terminal_number, :merchant_id,
						:created_at, :updated_at
					)
				""")
				
				self.new_db.execute(insert_query, {
					"business_id": new_business_id,
					"code": new_code,
					"name": row[2],
					"description": truncate_string(row[3], 500),
					"currency_id": new_currency_id,
					"is_active": True,
					"is_default": False,
					"payment_switch_number": None,
					"payment_terminal_number": None,
					"merchant_id": None,
					"created_at": datetime.utcnow(),
					"updated_at": datetime.utcnow()
				})
				self.new_db.commit()
				self.stats["cash_registers_migrated"] += 1
			except Exception as e:
				self.new_db.rollback()
				continue
	
	def migrate_petty_cash_for_business(self, old_business_id: int, new_business_id: int,
	                                   currency_mapping: Dict[int, int]):
		"""انتقال تنخواه گردان‌های یک کسب و کار"""
		query = text("""
			SELECT 
				id, bid_id, name, des, code, money_id
			FROM hesabixOld.salary
			WHERE bid_id = :bid_id
		""")
		
		results = self.old_db.execute(query, {"bid_id": old_business_id}).fetchall()
		
		for row in results:
			try:
				old_code = row[4]
				new_code = truncate_string(old_code, 50)
				
				# بررسی وجود
				if new_code:
					check_query = text("""
						SELECT COUNT(*) FROM petty_cash
						WHERE business_id = :business_id AND code = :code
					""")
					if self.new_db.execute(check_query, {
						"business_id": new_business_id,
						"code": new_code
					}).scalar() > 0:
						continue
				
				# تبدیل currency_id
				old_money_id = row[5]
				if old_money_id and old_money_id in currency_mapping:
					new_currency_id = currency_mapping[old_money_id]
				else:
					new_currency_id = 1
				
				# درج
				insert_query = text("""
					INSERT INTO petty_cash (
						business_id, code, name, description,
						currency_id, is_active, is_default,
						created_at, updated_at
					) VALUES (
						:business_id, :code, :name, :description,
						:currency_id, :is_active, :is_default,
						:created_at, :updated_at
					)
				""")
				
				self.new_db.execute(insert_query, {
					"business_id": new_business_id,
					"code": new_code,
					"name": row[2],
					"description": truncate_string(row[3], 500),
					"currency_id": new_currency_id,
					"is_active": True,
					"is_default": False,
					"created_at": datetime.utcnow(),
					"updated_at": datetime.utcnow()
				})
				self.new_db.commit()
				self.stats["petty_cash_migrated"] += 1
			except Exception as e:
				self.new_db.rollback()
				continue
	
	def create_unit_mapping(self) -> Dict[int, str]:
		"""ایجاد mapping برای واحدها"""
		query = text("SELECT id, name FROM hesabixOld.commodity_unit")
		results = self.old_db.execute(query).fetchall()
		mapping = {}
		for row in results:
			mapping[row.id] = row.name
		return mapping
	
	def create_category_mapping(self, old_business_id: int, new_business_id: int) -> Dict[int, int]:
		"""ایجاد mapping برای دسته‌بندی‌ها"""
		query = text("""
			SELECT DISTINCT cat_id
			FROM hesabixOld.commodity
			WHERE bid_id = :bid_id AND cat_id IS NOT NULL
		""")
		results = self.old_db.execute(query, {"bid_id": old_business_id}).fetchall()
		
		mapping = {}
		for row in results:
			old_cat_id = row[0]
			if old_cat_id in mapping:
				continue
			
			# دریافت نام دسته‌بندی
			cat_query = text("""
				SELECT name FROM hesabixOld.commodity_cat
				WHERE id = :cat_id
			""")
			cat_result = self.old_db.execute(cat_query, {"cat_id": old_cat_id}).fetchone()
			
			if not cat_result:
				continue
			
			cat_name = cat_result[0]
			
			# بررسی وجود در دیتابیس جدید
			check_query = text("""
				SELECT id FROM categories
				WHERE business_id = :business_id
				AND JSON_EXTRACT(title_translations, '$.fa') = :name
				LIMIT 1
			""")
			existing = self.new_db.execute(check_query, {
				"business_id": new_business_id,
				"name": cat_name
			}).fetchone()
			
			if existing:
				mapping[old_cat_id] = existing[0]
			else:
				# ایجاد دسته‌بندی جدید
				title_translations = json.dumps({"fa": cat_name, "en": cat_name})
				insert_query = text("""
					INSERT INTO categories (
						business_id, title_translations,
						sort_order, is_active,
						created_at, updated_at
					) VALUES (
						:business_id, :title_translations,
						0, 1,
						:created_at, :updated_at
					)
				""")
				self.new_db.execute(insert_query, {
					"business_id": new_business_id,
					"title_translations": title_translations,
					"created_at": datetime.utcnow(),
					"updated_at": datetime.utcnow()
				})
				self.new_db.commit()
				
				# دریافت ID جدید
				new_cat_id = self.new_db.execute(check_query, {
					"business_id": new_business_id,
					"name": cat_name
				}).fetchone()[0]
				mapping[old_cat_id] = new_cat_id
		
		return mapping
	
	def migrate_products_for_business(self, old_business_id: int, new_business_id: int,
	                                 currency_mapping: Dict[int, int], unit_mapping: Dict[int, str]):
		"""انتقال کالاها و خدمات یک کسب و کار"""
		query = text("""
			SELECT 
				id, bid_id, name, khadamat, price_buy, price_sell,
				cat_id, unit_id, order_point, commodity_count_check,
				without_tax, min_order_count, day_loading, des, code
			FROM hesabixOld.commodity
			WHERE bid_id = :bid_id
		""")
		
		results = self.old_db.execute(query, {"bid_id": old_business_id}).fetchall()
		
		# ایجاد category mapping
		category_mapping = self.create_category_mapping(old_business_id, new_business_id)
		
		for row in results:
			try:
				old_code = row[14]
				new_code = truncate_string(old_code, 50)
				
				# بررسی وجود
				if new_code:
					check_query = text("""
						SELECT COUNT(*) FROM products
						WHERE business_id = :business_id AND code = :code
					""")
					if self.new_db.execute(check_query, {
						"business_id": new_business_id,
						"code": new_code
					}).scalar() > 0:
						continue
				
				# تبدیل فیلدها
				item_type = convert_khadamat_to_item_type(row[3])
				base_purchase_price = convert_price(row[4])
				base_sales_price = convert_price(row[5])
				category_id = category_mapping.get(row[6]) if row[6] else None
				main_unit = unit_mapping.get(row[7]) if row[7] else None
				reorder_point = convert_order_point(row[8])
				track_inventory = convert_track_inventory(row[9])
				is_sales_taxable, is_purchase_taxable = convert_taxable(row[10])
				min_order_qty = convert_order_point(row[11])
				lead_time_days = convert_order_point(row[12])
				
				# درج
				insert_query = text("""
					INSERT INTO products (
						business_id, code, name, item_type,
						base_purchase_price, base_sales_price,
						category_id, main_unit,
						reorder_point, track_inventory,
						is_sales_taxable, is_purchase_taxable,
						min_order_qty, lead_time_days, description,
						created_at, updated_at
					) VALUES (
						:business_id, :code, :name, :item_type,
						:base_purchase_price, :base_sales_price,
						:category_id, :main_unit,
						:reorder_point, :track_inventory,
						:is_sales_taxable, :is_purchase_taxable,
						:min_order_qty, :lead_time_days, :description,
						:created_at, :updated_at
					)
				""")
				
				self.new_db.execute(insert_query, {
					"business_id": new_business_id,
					"code": new_code,
					"name": row[2],
					"item_type": item_type,
					"base_purchase_price": base_purchase_price,
					"base_sales_price": base_sales_price,
					"category_id": category_id,
					"main_unit": main_unit,
					"reorder_point": reorder_point,
					"track_inventory": track_inventory,
					"is_sales_taxable": is_sales_taxable,
					"is_purchase_taxable": is_purchase_taxable,
					"min_order_qty": min_order_qty,
					"lead_time_days": lead_time_days,
					"description": truncate_string(row[13], 1000),
					"created_at": datetime.utcnow(),
					"updated_at": datetime.utcnow()
				})
				self.new_db.commit()
				self.stats["products_migrated"] += 1
			except Exception as e:
				self.new_db.rollback()
				continue
	
	def create_person_id_mapping(self, old_business_id: int, new_business_id: int) -> Dict[int, int]:
		"""ایجاد mapping برای person_id"""
		# دریافت اشخاص قدیمی
		old_query = text("""
			SELECT id, code FROM hesabixOld.person
			WHERE bid_id = :bid_id
		""")
		old_results = self.old_db.execute(old_query, {"bid_id": old_business_id}).fetchall()
		
		mapping = {}
		for old_row in old_results:
			old_id = old_row[0]
			old_code = old_row[1]
			
			if old_code is None:
				continue
			
			# جستجو در دیتابیس جدید
			new_query = text("""
				SELECT id FROM persons
				WHERE business_id = :business_id AND code = :code
				LIMIT 1
			""")
			new_result = self.new_db.execute(new_query, {
				"business_id": new_business_id,
				"code": old_code
			}).fetchone()
			
			if new_result:
				mapping[old_id] = new_result[0]
		
		return mapping
	
	def create_bank_account_id_mapping(self, old_business_id: int, new_business_id: int) -> Dict[int, int]:
		"""ایجاد mapping برای bank_account_id"""
		# دریافت حساب‌های بانکی قدیمی
		old_query = text("""
			SELECT id, code FROM hesabixOld.bank_account
			WHERE bid_id = :bid_id
		""")
		old_results = self.old_db.execute(old_query, {"bid_id": old_business_id}).fetchall()
		
		mapping = {}
		for old_row in old_results:
			old_id = old_row[0]
			old_code = old_row[1]
			
			if old_code is None:
				continue
			
			# جستجو در دیتابیس جدید
			new_query = text("""
				SELECT id FROM bank_accounts
				WHERE business_id = :business_id AND code = :code
				LIMIT 1
			""")
			new_result = self.new_db.execute(new_query, {
				"business_id": new_business_id,
				"code": old_code
			}).fetchone()
			
			if new_result:
				mapping[old_id] = new_result[0]
		
		return mapping
	
	def migrate_checks_for_business(self, old_business_id: int, new_business_id: int,
	                               user_id_mapping: Dict[int, int], currency_mapping: Dict[int, int],
	                               person_id_mapping: Dict[int, int], bank_account_id_mapping: Dict[int, int]):
		"""انتقال چک‌های یک کسب و کار"""
		query = text("""
			SELECT 
				id, bid_id, type, status, date_stamp, pay_date,
				number, sayad_num, bank_oncheque, amount, money_id,
				person_id, bank_id, transfered, des
			FROM hesabixOld.cheque
			WHERE bid_id = :bid_id
		""")
		
		results = self.old_db.execute(query, {"bid_id": old_business_id}).fetchall()
		
		for row in results:
			try:
				# تبدیل type
				new_type = convert_check_type(row[2])
				
				# تبدیل status
				new_status = convert_status(row[3], row[2])
				if not new_status:
					continue
				
				# تبدیل تاریخ‌ها
				issue_date = convert_timestamp_to_datetime(row[4]) or convert_persian_date_to_datetime(row[4])
				due_date = convert_timestamp_to_datetime(row[5]) or convert_persian_date_to_datetime(row[5])
				
				# تبدیل amount
				amount = convert_amount(row[9])
				if not amount:
					continue
				
				# تبدیل currency_id
				old_money_id = row[10]
				if old_money_id and old_money_id in currency_mapping:
					new_currency_id = currency_mapping[old_money_id]
				else:
					new_currency_id = 1
				
				# تبدیل person_id و bank_account_id
				new_person_id = person_id_mapping.get(row[11]) if row[11] else None
				new_bank_account_id = bank_account_id_mapping.get(row[12]) if row[12] else None
				
				# محاسبه holder
				old_cheque = {"transfered": row[13]}
				current_holder_type, current_holder_id = calculate_holder(
					old_cheque, new_bank_account_id, new_person_id, new_business_id
				)
				
				# درج
				insert_query = text("""
					INSERT INTO checks (
						business_id, type, status,
						issue_date, due_date,
						check_number, sayad_code, bank_name,
						amount, currency_id,
						current_holder_type, current_holder_id,
						description, created_at, updated_at
					) VALUES (
						:business_id, :type, :status,
						:issue_date, :due_date,
						:check_number, :sayad_code, :bank_name,
						:amount, :currency_id,
						:current_holder_type, :current_holder_id,
						:description, :created_at, :updated_at
					)
				""")
				
				self.new_db.execute(insert_query, {
					"business_id": new_business_id,
					"type": new_type,
					"status": new_status,
					"issue_date": issue_date,
					"due_date": due_date,
					"check_number": truncate_string(row[6], 50),  # number
					"sayad_code": truncate_string(row[7], 50),  # sayad_num
					"bank_name": truncate_string(row[8], 255),  # bank_oncheque
					"amount": amount,
					"currency_id": new_currency_id,
					"current_holder_type": current_holder_type,
					"current_holder_id": current_holder_id,
					"description": truncate_string(row[14], 1000),  # des
					"created_at": datetime.utcnow(),
					"updated_at": datetime.utcnow()
				})
				self.new_db.commit()
				self.stats["checks_migrated"] += 1
			except Exception as e:
				self.new_db.rollback()
				continue
	
	def migrate_business_users_for_business(self, old_business_id: int, new_business_id: int,
	                                      user_id_mapping: Dict[int, int]):
		"""انتقال کاربران عضو یک کسب و کار"""
		query = text("""
			SELECT 
				id, user_id, bid_id, owner, settings, person, commodity,
				getpay, banks, bank_transfer, buy, sell, cost, income,
				accounting, report, log, permission, salary, cashdesk,
				store, wallet, archive_upload, archive_mod, archive_delete,
				archive_view, cheque, inquiry, ai, plug_warranty_manager
			FROM hesabixOld.permission
			WHERE bid_id = :bid_id AND owner = 0
		""")
		
		results = self.old_db.execute(query, {"bid_id": old_business_id}).fetchall()
		
		for row in results:
			try:
				old_user_id = row[1]
				new_user_id = user_id_mapping.get(old_user_id)
				
				if not new_user_id:
					continue
				
				# بررسی وجود
				check_query = text("""
					SELECT COUNT(*) FROM business_permissions
					WHERE business_id = :business_id AND user_id = :user_id
				""")
				if self.new_db.execute(check_query, {
					"business_id": new_business_id,
					"user_id": new_user_id
				}).scalar() > 0:
					continue
				
				# تبدیل permissions
				old_permission = {
					"owner": row[3],
					"settings": row[4],
					"person": row[5],
					"commodity": row[6],
					"getpay": row[7],
					"banks": row[8],
					"bank_transfer": row[9],
					"buy": row[10],
					"sell": row[11],
					"cost": row[12],
					"income": row[13],
					"accounting": row[14],
					"report": row[15],
					"log": row[16],
					"permission": row[17],
					"salary": row[18],
					"cashdesk": row[19],
					"store": row[20],
					"wallet": row[21],
					"archive_upload": row[22],
					"archive_mod": row[23],
					"archive_delete": row[24],
					"archive_view": row[25],
					"cheque": row[26],
					"inquiry": row[27],
					"ai": row[28],
					"plug_warranty_manager": row[29]
				}
				
				permissions_json = convert_permissions_to_json(old_permission)
				
				# درج
				insert_query = text("""
					INSERT INTO business_permissions (
						business_id, user_id, business_permissions,
						created_at, updated_at
					) VALUES (
						:business_id, :user_id, :business_permissions,
						:created_at, :updated_at
					)
				""")
				
				self.new_db.execute(insert_query, {
					"business_id": new_business_id,
					"user_id": new_user_id,
					"business_permissions": json.dumps(permissions_json, ensure_ascii=False),
					"created_at": datetime.utcnow(),
					"updated_at": datetime.utcnow()
				})
				self.new_db.commit()
				self.stats["business_users_migrated"] += 1
			except Exception as e:
				self.new_db.rollback()
				continue
	
	def migrate_all_for_business(self, old_business_id: int, new_business_id: int,
	                            user_id_mapping: Dict[int, int], currency_mapping: Dict[int, int]):
		"""انتقال تمام موارد مرتبط با یک کسب و کار"""
		print(f"\n  📦 انتقال موارد مرتبط برای کسب و کار {old_business_id} → {new_business_id}...")
		
		# 1. انتقال سال مالی
		self.migrate_fiscal_year(old_business_id, new_business_id)
		
		# 2. ایجاد mapping ها
		person_type_mapping = self.create_person_type_mapping()
		unit_mapping = self.create_unit_mapping()
		
		# 3. انتقال اشخاص
		print(f"    👥 انتقال اشخاص...")
		self.migrate_persons_for_business(old_business_id, new_business_id, person_type_mapping)
		
		# 4. انتقال حساب‌های بانکی
		print(f"    🏦 انتقال حساب‌های بانکی...")
		self.migrate_bank_accounts_for_business(old_business_id, new_business_id, currency_mapping)
		
		# 5. انتقال صندوق
		print(f"    💰 انتقال صندوق‌ها...")
		self.migrate_cash_registers_for_business(old_business_id, new_business_id, currency_mapping)
		
		# 6. انتقال تنخواه
		print(f"    💵 انتقال تنخواه گردان‌ها...")
		self.migrate_petty_cash_for_business(old_business_id, new_business_id, currency_mapping)
		
		# 7. انتقال کالاها
		print(f"    📦 انتقال کالاها و خدمات...")
		self.migrate_products_for_business(old_business_id, new_business_id, currency_mapping, unit_mapping)
		
		# 8. ایجاد mapping برای چک‌ها
		person_id_mapping = self.create_person_id_mapping(old_business_id, new_business_id)
		bank_account_id_mapping = self.create_bank_account_id_mapping(old_business_id, new_business_id)
		
		# 9. انتقال چک‌ها
		print(f"    📄 انتقال چک‌ها...")
		self.migrate_checks_for_business(old_business_id, new_business_id, user_id_mapping,
		                                currency_mapping, person_id_mapping, bank_account_id_mapping)
		
		# 10. انتقال کاربران عضو
		print(f"    👤 انتقال کاربران عضو...")
		self.migrate_business_users_for_business(old_business_id, new_business_id, user_id_mapping)
	
	def run_migration(self, dry_run: bool = False):
		"""اجرای انتقال"""
		print(f"{'='*60}")
		print(f"شروع انتقال کسب و کارهای منتقل نشده و موارد مرتبط")
		print(f"{'='*60}")
		print(f"دیتابیس قدیمی: {self.old_db_name}")
		print(f"دیتابیس جدید: {self.new_db_name}")
		print(f"حالت تست (dry-run): {dry_run}")
		print(f"{'='*60}\n")
		
		# ایجاد mapping اولیه
		user_id_mapping = self.create_user_id_mapping_case_insensitive()
		currency_mapping = self.create_currency_mapping()
		
		# انتقال کاربران باقی‌مانده
		print(f"\n{'='*60}")
		print("مرحله 1: انتقال کاربران باقی‌مانده")
		print(f"{'='*60}\n")
		if not dry_run:
			new_user_mappings = self.migrate_missing_users(user_id_mapping)
			# اضافه کردن mapping های جدید به mapping موجود
			user_id_mapping.update(new_user_mappings)
			print(f"\n✅ کل mapping کاربران: {len(user_id_mapping)} کاربر\n")
		
		# دریافت کسب و کارهای منتقل نشده
		unmigrated_businesses = self.get_unmigrated_businesses(user_id_mapping)
		print(f"تعداد کسب و کارهای منتقل نشده: {len(unmigrated_businesses)}\n")
		
		if len(unmigrated_businesses) == 0:
			print("✅ تمام کسب و کارها منتقل شده‌اند.")
			return
		
		# انتقال کسب و کارها
		for idx, old_business in enumerate(unmigrated_businesses, 1):
			print(f"\n[{idx}/{len(unmigrated_businesses)}] 📊 انتقال کسب و کار: {old_business.get('name')} (ID: {old_business.get('id')})")
			
			if not dry_run:
				new_business_id = self.migrate_business(
					old_business, user_id_mapping, currency_mapping
				)
				
				if new_business_id:
					# انتقال موارد مرتبط
					self.migrate_all_for_business(
						old_business.get('id'), new_business_id,
						user_id_mapping, currency_mapping
					)
		
		# نمایش آمار نهایی
		print(f"\n{'='*60}")
		print("آمار نهایی:")
		print(f"{'='*60}")
		print(f"کسب و کارها: {self.stats['businesses_migrated']}")
		print(f"سال‌های مالی: {self.stats['fiscal_years_migrated']}")
		print(f"اشخاص: {self.stats['persons_migrated']}")
		print(f"حساب‌های بانکی: {self.stats['bank_accounts_migrated']}")
		print(f"صندوق‌ها: {self.stats['cash_registers_migrated']}")
		print(f"تنخواه گردان‌ها: {self.stats['petty_cash_migrated']}")
		print(f"کالاها/خدمات: {self.stats['products_migrated']}")
		print(f"چک‌ها: {self.stats['checks_migrated']}")
		print(f"کاربران عضو: {self.stats['business_users_migrated']}")
		print(f"خطاها: {self.stats['errors']}")
	
	def close(self):
		"""بستن اتصالات"""
		self.old_db.close()
		self.new_db.close()


def main():
	parser = argparse.ArgumentParser(description="انتقال کسب و کارهای منتقل نشده و موارد مرتبط")
	parser.add_argument("--dry-run", action="store_true", help="اجرای تست بدون تغییر در دیتابیس")
	parser.add_argument("--old-db", default="hesabixOld", help="نام دیتابیس قدیمی")
	parser.add_argument("--new-db", default="hesabixpy", help="نام دیتابیس جدید")
	parser.add_argument("--db-user", default="root", help="نام کاربری دیتابیس")
	parser.add_argument("--db-password", default="136431", help="رمز عبور دیتابیس")
	parser.add_argument("--db-host", default="localhost", help="آدرس دیتابیس")
	parser.add_argument("--db-port", type=int, default=3306, help="پورت دیتابیس")
	
	args = parser.parse_args()
	
	migration = RemainingBusinessMigration(
		old_db_name=args.old_db,
		new_db_name=args.new_db,
		db_user=args.db_user,
		db_password=args.db_password,
		db_host=args.db_host,
		db_port=args.db_port
	)
	
	try:
		migration.run_migration(dry_run=args.dry_run)
	finally:
		migration.close()


if __name__ == "__main__":
	main()
