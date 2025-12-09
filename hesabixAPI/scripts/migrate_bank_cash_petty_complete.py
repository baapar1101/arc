#!/usr/bin/env python3
"""
اسکریپت انتقال بانک، صندوق و تنخواه از hesabixOld به hesabixpy

این اسکریپت:
- حساب‌های بانکی را از bank_account منتقل می‌کند
- صندوق‌ها را از cashdesk منتقل می‌کند
- تنخواه گردان‌ها را از salary منتقل می‌کند
"""

import sys
import os
import argparse
from typing import List, Dict, Any, Optional
from datetime import datetime

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session


def truncate_string(value: str | None, max_length: int) -> str | None:
	"""محدود کردن طول رشته به حداکثر طول مجاز"""
	if not value:
		return None
	
	value_str = str(value).strip()
	if len(value_str) > max_length:
		return value_str[:max_length]
	return value_str


class BankCashPettyMigration:
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
			"bank_accounts_processed": 0,
			"bank_accounts_migrated": 0,
			"bank_accounts_skipped": 0,
			"cash_registers_processed": 0,
			"cash_registers_migrated": 0,
			"cash_registers_skipped": 0,
			"petty_cash_processed": 0,
			"petty_cash_migrated": 0,
			"petty_cash_skipped": 0,
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
		# از تحلیل قبلی می‌دانیم:
		# money_id = 1 → currency_id = 1 (IRR)
		# money_id = 2 → currency_id = 2 (USD)
		# money_id = 3 → currency_id = 20 (AFN)
		# money_id = 4 → currency_id = 19 (IQD)
		mapping = {
			1: 1,   # IRR
			2: 2,   # USD
			3: 20,  # AFN
			4: 19   # IQD
		}
		
		print(f"✅ Currency mapping ایجاد شد: {len(mapping)} ارز")
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
	
	def migrate_bank_account(self, old_account: Dict[str, Any], business_id_mapping: Dict[int, int],
	                        currency_mapping: Dict[int, int]) -> Optional[int]:
		"""انتقال یک حساب بانکی"""
		try:
			# نگاشت business_id
			old_business_id = old_account.get('bid_id')
			new_business_id = business_id_mapping.get(old_business_id)
			
			if not new_business_id:
				self.stats["bank_accounts_skipped"] += 1
				return None
			
			# تبدیل code
			old_code = old_account.get('code')
			new_code = truncate_string(old_code, 50)
			
			# بررسی وجود در دیتابیس جدید
			if new_code:
				query = text("""
					SELECT COUNT(*) FROM bank_accounts
					WHERE business_id = :business_id AND code = :code
				""")
				result = self.new_db.execute(query, {
					"business_id": new_business_id,
					"code": new_code
				}).scalar()
				
				if result > 0:
					self.stats["bank_accounts_skipped"] += 1
					return None
			
			# تبدیل currency_id
			old_money_id = old_account.get('money_id')
			if old_money_id and old_money_id in currency_mapping:
				new_currency_id = currency_mapping[old_money_id]
			else:
				# استفاده از ارز پیش‌فرض کسب و کار
				new_currency_id = self.get_default_currency_id(new_business_id)
			
			# درج حساب بانکی
			query = text("""
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
			
			self.new_db.execute(query, {
				"business_id": new_business_id,
				"code": new_code,
				"name": old_account.get('name'),
				"description": truncate_string(old_account.get('des'), 500),
				"branch": truncate_string(old_account.get('shobe'), 255),
				"account_number": truncate_string(old_account.get('account_num'), 50),
				"sheba_number": truncate_string(old_account.get('shaba'), 30),
				"card_number": truncate_string(old_account.get('card_num'), 20),
				"owner_name": truncate_string(old_account.get('owner'), 255),
				"pos_number": truncate_string(old_account.get('pos_num'), 50),
				"payment_id": truncate_string(old_account.get('mobile_internet_bank'), 100),
				"currency_id": new_currency_id,
				"is_active": True,
				"is_default": False,
				"created_at": datetime.utcnow(),
				"updated_at": datetime.utcnow()
			})
			
			self.new_db.commit()
			
			# دریافت new_account_id
			if new_code:
				query = text("""
					SELECT id FROM bank_accounts
					WHERE business_id = :business_id AND code = :code
					LIMIT 1
				""")
				result = self.new_db.execute(query, {
					"business_id": new_business_id,
					"code": new_code
				}).fetchone()
			else:
				# اگر code نداشت، از name استفاده می‌کنیم
				query = text("""
					SELECT id FROM bank_accounts
					WHERE business_id = :business_id AND name = :name
					ORDER BY id DESC
					LIMIT 1
				""")
				result = self.new_db.execute(query, {
					"business_id": new_business_id,
					"name": old_account.get('name')
				}).fetchone()
			
			if result:
				self.stats["bank_accounts_migrated"] += 1
				return result[0]
			else:
				raise Exception("Failed to get new bank account ID after insert")
		
		except Exception as e:
			self.new_db.rollback()
			self.stats["errors"] += 1
			self.stats["error_details"].append({
				"type": "bank_account",
				"old_id": old_account.get('id'),
				"old_business_id": old_account.get('bid_id'),
				"code": old_account.get('code'),
				"name": old_account.get('name'),
				"error": str(e)
			})
			return None
	
	def migrate_cash_register(self, old_cashdesk: Dict[str, Any], business_id_mapping: Dict[int, int],
	                          currency_mapping: Dict[int, int]) -> Optional[int]:
		"""انتقال یک صندوق"""
		try:
			# نگاشت business_id
			old_business_id = old_cashdesk.get('bid_id')
			new_business_id = business_id_mapping.get(old_business_id)
			
			if not new_business_id:
				self.stats["cash_registers_skipped"] += 1
				return None
			
			# تبدیل code
			old_code = old_cashdesk.get('code')
			new_code = truncate_string(old_code, 50)
			
			# بررسی وجود در دیتابیس جدید
			if new_code:
				query = text("""
					SELECT COUNT(*) FROM cash_registers
					WHERE business_id = :business_id AND code = :code
				""")
				result = self.new_db.execute(query, {
					"business_id": new_business_id,
					"code": new_code
				}).scalar()
				
				if result > 0:
					self.stats["cash_registers_skipped"] += 1
					return None
			
			# تبدیل currency_id
			old_money_id = old_cashdesk.get('money_id')
			if old_money_id and old_money_id in currency_mapping:
				new_currency_id = currency_mapping[old_money_id]
			else:
				# استفاده از ارز پیش‌فرض کسب و کار
				new_currency_id = self.get_default_currency_id(new_business_id)
			
			# درج صندوق
			query = text("""
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
			
			self.new_db.execute(query, {
				"business_id": new_business_id,
				"code": new_code,
				"name": old_cashdesk.get('name'),
				"description": truncate_string(old_cashdesk.get('des'), 500),
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
			
			# دریافت new_cash_register_id
			if new_code:
				query = text("""
					SELECT id FROM cash_registers
					WHERE business_id = :business_id AND code = :code
					LIMIT 1
				""")
				result = self.new_db.execute(query, {
					"business_id": new_business_id,
					"code": new_code
				}).fetchone()
			else:
				# اگر code نداشت، از name استفاده می‌کنیم
				query = text("""
					SELECT id FROM cash_registers
					WHERE business_id = :business_id AND name = :name
					ORDER BY id DESC
					LIMIT 1
				""")
				result = self.new_db.execute(query, {
					"business_id": new_business_id,
					"name": old_cashdesk.get('name')
				}).fetchone()
			
			if result:
				self.stats["cash_registers_migrated"] += 1
				return result[0]
			else:
				raise Exception("Failed to get new cash register ID after insert")
		
		except Exception as e:
			self.new_db.rollback()
			self.stats["errors"] += 1
			self.stats["error_details"].append({
				"type": "cash_register",
				"old_id": old_cashdesk.get('id'),
				"old_business_id": old_cashdesk.get('bid_id'),
				"code": old_cashdesk.get('code'),
				"name": old_cashdesk.get('name'),
				"error": str(e)
			})
			return None
	
	def migrate_petty_cash(self, old_salary: Dict[str, Any], business_id_mapping: Dict[int, int],
	                      currency_mapping: Dict[int, int]) -> Optional[int]:
		"""انتقال یک تنخواه گردان"""
		try:
			# نگاشت business_id
			old_business_id = old_salary.get('bid_id')
			new_business_id = business_id_mapping.get(old_business_id)
			
			if not new_business_id:
				self.stats["petty_cash_skipped"] += 1
				return None
			
			# تبدیل code
			old_code = old_salary.get('code')
			new_code = truncate_string(old_code, 50)
			
			# بررسی وجود در دیتابیس جدید
			if new_code:
				query = text("""
					SELECT COUNT(*) FROM petty_cash
					WHERE business_id = :business_id AND code = :code
				""")
				result = self.new_db.execute(query, {
					"business_id": new_business_id,
					"code": new_code
				}).scalar()
				
				if result > 0:
					self.stats["petty_cash_skipped"] += 1
					return None
			
			# تبدیل currency_id
			old_money_id = old_salary.get('money_id')
			if old_money_id and old_money_id in currency_mapping:
				new_currency_id = currency_mapping[old_money_id]
			else:
				# استفاده از ارز پیش‌فرض کسب و کار
				new_currency_id = self.get_default_currency_id(new_business_id)
			
			# درج تنخواه گردان
			query = text("""
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
			
			self.new_db.execute(query, {
				"business_id": new_business_id,
				"code": new_code,
				"name": old_salary.get('name'),
				"description": truncate_string(old_salary.get('des'), 500),
				"currency_id": new_currency_id,
				"is_active": True,
				"is_default": False,
				"created_at": datetime.utcnow(),
				"updated_at": datetime.utcnow()
			})
			
			self.new_db.commit()
			
			# دریافت new_petty_cash_id
			if new_code:
				query = text("""
					SELECT id FROM petty_cash
					WHERE business_id = :business_id AND code = :code
					LIMIT 1
				""")
				result = self.new_db.execute(query, {
					"business_id": new_business_id,
					"code": new_code
				}).fetchone()
			else:
				# اگر code نداشت، از name استفاده می‌کنیم
				query = text("""
					SELECT id FROM petty_cash
					WHERE business_id = :business_id AND name = :name
					ORDER BY id DESC
					LIMIT 1
				""")
				result = self.new_db.execute(query, {
					"business_id": new_business_id,
					"name": old_salary.get('name')
				}).fetchone()
			
			if result:
				self.stats["petty_cash_migrated"] += 1
				return result[0]
			else:
				raise Exception("Failed to get new petty cash ID after insert")
		
		except Exception as e:
			self.new_db.rollback()
			self.stats["errors"] += 1
			self.stats["error_details"].append({
				"type": "petty_cash",
				"old_id": old_salary.get('id'),
				"old_business_id": old_salary.get('bid_id'),
				"code": old_salary.get('code'),
				"name": old_salary.get('name'),
				"error": str(e)
			})
			return None
	
	def get_old_bank_accounts(self, start_id: Optional[int] = None, limit: Optional[int] = None,
	                         business_ids: Optional[List[int]] = None) -> List[Dict[str, Any]]:
		"""دریافت حساب‌های بانکی از دیتابیس قدیمی"""
		query = f"""
			SELECT 
				id, bid_id, name, card_num, shaba, account_num,
				owner, shobe, pos_num, des, mobile_internet_bank, code, money_id
			FROM {self.old_db_name}.bank_account
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
		
		accounts = []
		for row in results:
			accounts.append({
				"id": row[0],
				"bid_id": row[1],
				"name": row[2],
				"card_num": row[3],
				"shaba": row[4],
				"account_num": row[5],
				"owner": row[6],
				"shobe": row[7],
				"pos_num": row[8],
				"des": row[9],
				"mobile_internet_bank": row[10],
				"code": row[11],
				"money_id": row[12]
			})
		
		return accounts
	
	def get_old_cashdesk(self, start_id: Optional[int] = None, limit: Optional[int] = None,
	                    business_ids: Optional[List[int]] = None) -> List[Dict[str, Any]]:
		"""دریافت صندوق‌ها از دیتابیس قدیمی"""
		query = f"""
			SELECT 
				id, bid_id, name, des, code, money_id
			FROM {self.old_db_name}.cashdesk
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
		
		cashdesks = []
		for row in results:
			cashdesks.append({
				"id": row[0],
				"bid_id": row[1],
				"name": row[2],
				"des": row[3],
				"code": row[4],
				"money_id": row[5]
			})
		
		return cashdesks
	
	def get_old_salary(self, start_id: Optional[int] = None, limit: Optional[int] = None,
	                 business_ids: Optional[List[int]] = None) -> List[Dict[str, Any]]:
		"""دریافت تنخواه گردان‌ها از دیتابیس قدیمی"""
		query = f"""
			SELECT 
				id, bid_id, name, des, code, money_id
			FROM {self.old_db_name}.salary
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
		
		salaries = []
		for row in results:
			salaries.append({
				"id": row[0],
				"bid_id": row[1],
				"name": row[2],
				"des": row[3],
				"code": row[4],
				"money_id": row[5]
			})
		
		return salaries
	
	def run_migration(self, dry_run: bool = False, batch_size: int = 500,
	                 start_id: Optional[int] = None, limit: Optional[int] = None):
		"""اجرای انتقال"""
		print(f"{'='*60}")
		print(f"شروع انتقال بانک، صندوق و تنخواه")
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
		
		# دریافت کسب و کارهای منتقل شده
		old_business_ids = list(business_id_mapping.keys())
		
		if not old_business_ids:
			print("هیچ کسب و کاری برای انتقال یافت نشد.")
			return
		
		# ========== انتقال حساب‌های بانکی ==========
		print(f"\n{'='*60}")
		print("انتقال حساب‌های بانکی")
		print(f"{'='*60}")
		
		old_bank_accounts = self.get_old_bank_accounts(
			start_id=start_id,
			limit=limit,
			business_ids=old_business_ids
		)
		total_bank_accounts = len(old_bank_accounts)
		print(f"تعداد حساب‌های بانکی برای انتقال: {total_bank_accounts}\n")
		
		if total_bank_accounts > 0:
			for i in range(0, total_bank_accounts, batch_size):
				batch = old_bank_accounts[i:i+batch_size]
				batch_num = (i // batch_size) + 1
				total_batches = (total_bank_accounts + batch_size - 1) // batch_size
				
				print(f"\nپردازش batch {batch_num}/{total_batches} ({len(batch)} حساب بانکی)...")
				
				for old_account in batch:
					self.stats["bank_accounts_processed"] += 1
					
					if not dry_run:
						self.migrate_bank_account(
							old_account, business_id_mapping, currency_mapping
						)
					else:
						# در حالت dry-run فقط بررسی می‌کنیم
						old_business_id = old_account.get('bid_id')
						if old_business_id in business_id_mapping:
							self.stats["bank_accounts_migrated"] += 1
						else:
							self.stats["bank_accounts_skipped"] += 1
					
					if self.stats["bank_accounts_processed"] % 50 == 0:
						print(f"  پردازش شده: {self.stats['bank_accounts_processed']}/{total_bank_accounts}", end='\r')
				
				print(f"\n  Batch {batch_num} تکمیل شد")
		
		# ========== انتقال صندوق‌ها ==========
		print(f"\n{'='*60}")
		print("انتقال صندوق‌ها")
		print(f"{'='*60}")
		
		old_cashdesks = self.get_old_cashdesk(
			start_id=start_id,
			limit=limit,
			business_ids=old_business_ids
		)
		total_cashdesks = len(old_cashdesks)
		print(f"تعداد صندوق‌ها برای انتقال: {total_cashdesks}\n")
		
		if total_cashdesks > 0:
			for i in range(0, total_cashdesks, batch_size):
				batch = old_cashdesks[i:i+batch_size]
				batch_num = (i // batch_size) + 1
				total_batches = (total_cashdesks + batch_size - 1) // batch_size
				
				print(f"\nپردازش batch {batch_num}/{total_batches} ({len(batch)} صندوق)...")
				
				for old_cashdesk in batch:
					self.stats["cash_registers_processed"] += 1
					
					if not dry_run:
						self.migrate_cash_register(
							old_cashdesk, business_id_mapping, currency_mapping
						)
					else:
						# در حالت dry-run فقط بررسی می‌کنیم
						old_business_id = old_cashdesk.get('bid_id')
						if old_business_id in business_id_mapping:
							self.stats["cash_registers_migrated"] += 1
						else:
							self.stats["cash_registers_skipped"] += 1
					
					if self.stats["cash_registers_processed"] % 50 == 0:
						print(f"  پردازش شده: {self.stats['cash_registers_processed']}/{total_cashdesks}", end='\r')
				
				print(f"\n  Batch {batch_num} تکمیل شد")
		
		# ========== انتقال تنخواه گردان‌ها ==========
		print(f"\n{'='*60}")
		print("انتقال تنخواه گردان‌ها")
		print(f"{'='*60}")
		
		old_salaries = self.get_old_salary(
			start_id=start_id,
			limit=limit,
			business_ids=old_business_ids
		)
		total_salaries = len(old_salaries)
		print(f"تعداد تنخواه گردان‌ها برای انتقال: {total_salaries}\n")
		
		if total_salaries > 0:
			for i in range(0, total_salaries, batch_size):
				batch = old_salaries[i:i+batch_size]
				batch_num = (i // batch_size) + 1
				total_batches = (total_salaries + batch_size - 1) // batch_size
				
				print(f"\nپردازش batch {batch_num}/{total_batches} ({len(batch)} تنخواه گردان)...")
				
				for old_salary in batch:
					self.stats["petty_cash_processed"] += 1
					
					if not dry_run:
						self.migrate_petty_cash(
							old_salary, business_id_mapping, currency_mapping
						)
					else:
						# در حالت dry-run فقط بررسی می‌کنیم
						old_business_id = old_salary.get('bid_id')
						if old_business_id in business_id_mapping:
							self.stats["petty_cash_migrated"] += 1
						else:
							self.stats["petty_cash_skipped"] += 1
					
					if self.stats["petty_cash_processed"] % 50 == 0:
						print(f"  پردازش شده: {self.stats['petty_cash_processed']}/{total_salaries}", end='\r')
				
				print(f"\n  Batch {batch_num} تکمیل شد")
		
		# نمایش آمار نهایی
		print(f"\n{'='*60}")
		print("آمار نهایی:")
		print(f"{'='*60}")
		print(f"حساب‌های بانکی:")
		print(f"  پردازش شده: {self.stats['bank_accounts_processed']}")
		print(f"  منتقل شده: {self.stats['bank_accounts_migrated']}")
		print(f"  رد شده: {self.stats['bank_accounts_skipped']}")
		print(f"\nصندوق‌ها:")
		print(f"  پردازش شده: {self.stats['cash_registers_processed']}")
		print(f"  منتقل شده: {self.stats['cash_registers_migrated']}")
		print(f"  رد شده: {self.stats['cash_registers_skipped']}")
		print(f"\nتنخواه گردان‌ها:")
		print(f"  پردازش شده: {self.stats['petty_cash_processed']}")
		print(f"  منتقل شده: {self.stats['petty_cash_migrated']}")
		print(f"  رد شده: {self.stats['petty_cash_skipped']}")
		print(f"\nخطاها: {self.stats['errors']}")
		
		if self.stats['error_details']:
			print(f"\nجزئیات خطاها:")
			for error in self.stats['error_details'][:10]:
				print(f"  - {error.get('type')} ID {error.get('old_id')} (Code: {error.get('code')}, Name: {error.get('name')}): {error.get('error')}")
			if len(self.stats['error_details']) > 10:
				print(f"  ... و {len(self.stats['error_details']) - 10} خطای دیگر")
	
	def close(self):
		"""بستن اتصالات"""
		self.old_db.close()
		self.new_db.close()


def main():
	parser = argparse.ArgumentParser(description="انتقال بانک، صندوق و تنخواه")
	parser.add_argument("--dry-run", action="store_true", help="اجرای تست بدون تغییر در دیتابیس")
	parser.add_argument("--batch-size", type=int, default=500, help="تعداد رکوردها در هر batch")
	parser.add_argument("--start-id", type=int, help="شروع از شناسه خاص")
	parser.add_argument("--limit", type=int, help="محدود کردن تعداد رکوردها")
	parser.add_argument("--old-db", default="hesabixOld", help="نام دیتابیس قدیمی")
	parser.add_argument("--new-db", default="hesabixpy", help="نام دیتابیس جدید")
	parser.add_argument("--db-user", default="root", help="نام کاربری دیتابیس")
	parser.add_argument("--db-password", default="136431", help="رمز عبور دیتابیس")
	parser.add_argument("--db-host", default="localhost", help="آدرس دیتابیس")
	parser.add_argument("--db-port", type=int, default=3306, help="پورت دیتابیس")
	
	args = parser.parse_args()
	
	migration = BankCashPettyMigration(
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

