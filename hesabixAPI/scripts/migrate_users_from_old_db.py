#!/usr/bin/env python3
"""
اسکریپت انتقال کاربران از دیتابیس قدیمی (hesabixOld) به دیتابیس جدید (hesabixpy)

این اسکریپت:
- کاربران فعال را از hesabixOld می‌خواند
- رمزهای bcrypt را مستقیماً نگه می‌دارد
- داده‌ها را تبدیل و در hesabixpy درج می‌کند
- کاربران تکراری را skip می‌کند
"""

import sys
import os
import argparse
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime
import secrets
import json

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
	# Clean input: keep digits and leading plus
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


class UserMigration:
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
			"total_processed": 0,
			"migrated": 0,
			"skipped_duplicate": 0,
			"skipped_existing": 0,
			"skipped_no_identifier": 0,
			"errors": 0,
			"error_details": []
		}
	
	def split_full_name(self, full_name: Optional[str]) -> Tuple[Optional[str], Optional[str]]:
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
	
	def convert_timestamp_to_datetime(self, timestamp_str: Optional[str]) -> Optional[datetime]:
		"""تبدیل timestamp string به datetime"""
		if not timestamp_str:
			return datetime.utcnow()
		
		try:
			# اگر عدد است، timestamp است
			if timestamp_str.isdigit():
				return datetime.fromtimestamp(int(timestamp_str))
			# در غیر این صورت سعی می‌کنیم parse کنیم
			return datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
		except Exception:
			return datetime.utcnow()
	
	def generate_referral_code(self, existing_codes: set) -> str:
		"""تولید کد معرف یکتا"""
		for _ in range(20):
			code = secrets.token_urlsafe(8).replace('-', '').replace('_', '')[:10]
			if code not in existing_codes:
				# بررسی در دیتابیس
				query = text("SELECT COUNT(*) FROM users WHERE referral_code = :code")
				result = self.new_db.execute(query, {"code": code}).scalar()
				if result == 0:
					existing_codes.add(code)
					return code
		# fallback
		return secrets.token_urlsafe(12).replace('-', '').replace('_', '')[:12]
	
	def check_user_exists(self, email: Optional[str], mobile: Optional[str]) -> bool:
		"""بررسی وجود کاربر در دیتابیس جدید"""
		if email:
			query = text("SELECT COUNT(*) FROM users WHERE email = :email")
			result = self.new_db.execute(query, {"email": email}).scalar()
			if result > 0:
				return True
		
		if mobile:
			query = text("SELECT COUNT(*) FROM users WHERE mobile = :mobile")
			result = self.new_db.execute(query, {"mobile": mobile}).scalar()
			if result > 0:
				return True
		
		return False
	
	def get_referred_by_user_id(self, old_invited_by_id: Optional[int], 
	                           old_to_new_mapping: Dict[int, int]) -> Optional[int]:
		"""نگاشت invited_by_id قدیمی به referred_by_user_id جدید"""
		if not old_invited_by_id:
			return None
		
		return old_to_new_mapping.get(old_invited_by_id)
	
	def migrate_user(self, old_user: Dict[str, Any], old_to_new_mapping: Dict[int, int],
	                 existing_referral_codes: set) -> Optional[int]:
		"""انتقال یک کاربر"""
		try:
			# تبدیل داده‌ها
			email = normalize_email(old_user.get('email'))
			mobile = normalize_mobile(old_user.get('mobile'))
			
			# بررسی وجود identifier
			if not email and not mobile:
				self.stats["skipped_no_identifier"] += 1
				return None
			
			# بررسی وجود در دیتابیس جدید
			if self.check_user_exists(email, mobile):
				self.stats["skipped_existing"] += 1
				return None
			
			# تبدیل full_name
			first_name, last_name = self.split_full_name(old_user.get('full_name'))
			
			# رمز عبور (مستقیماً از bcrypt نگه می‌داریم)
			password_hash = old_user.get('password')
			if not password_hash:
				# اگر password ندارند، یک hash پیش‌فرض ایجاد می‌کنیم
				# کاربر باید بعداً رمز خود را reset کند
				try:
					from app.core.security import hash_password
					# استفاده از یک رمز تصادفی برای کاربرانی که password ندارند
					# کاربر باید از طریق reset password رمز خود را تنظیم کند
					default_password = secrets.token_urlsafe(32)
					password_hash = hash_password(default_password)
				except Exception as e:
					# اگر import با مشکل مواجه شد، از bcrypt مستقیماً استفاده می‌کنیم
					import bcrypt
					default_password = secrets.token_urlsafe(32)
					password_hash = bcrypt.hashpw(default_password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
			
			# تولید referral_code
			old_invite_code = old_user.get('invate_code')
			if old_invite_code and old_invite_code.strip():
				# بررسی unique بودن
				query = text("SELECT COUNT(*) FROM users WHERE referral_code = :code")
				result = self.new_db.execute(query, {"code": old_invite_code.strip()}).scalar()
				if result == 0 and old_invite_code.strip() not in existing_referral_codes:
					referral_code = old_invite_code.strip()
					existing_referral_codes.add(referral_code)
				else:
					referral_code = self.generate_referral_code(existing_referral_codes)
			else:
				referral_code = self.generate_referral_code(existing_referral_codes)
			
			# نگاشت referred_by_user_id
			referred_by_user_id = self.get_referred_by_user_id(
				old_user.get('invited_by_id'), 
				old_to_new_mapping
			)
			
			# تبدیل تاریخ
			created_at = self.convert_timestamp_to_datetime(old_user.get('date_register'))
			
			# تبدیل active
			is_active = bool(old_user.get('active', 0))
			
			# درج در دیتابیس جدید
			query = text("""
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
			
			self.new_db.execute(query, {
				"email": email,
				"mobile": mobile,
				"first_name": first_name,
				"last_name": last_name,
				"password_hash": password_hash,
				"is_active": is_active,
				"email_verified": False,  # همه را false می‌گذاریم، کاربر باید verify کند
				"mobile_verified": False,
				"referral_code": referral_code,
				"referred_by_user_id": referred_by_user_id,
				"created_at": created_at,
				"updated_at": datetime.utcnow()
			})
			
			self.new_db.commit()
			
			# دریافت new_user_id
			if email:
				query = text("SELECT id FROM users WHERE email = :email")
			else:
				query = text("SELECT id FROM users WHERE mobile = :mobile")
			
			result = self.new_db.execute(
				query, 
				{"email": email, "mobile": mobile}
			).fetchone()
			
			if result:
				new_user_id = result[0]
				self.stats["migrated"] += 1
				return new_user_id
			else:
				raise Exception("Failed to get new user ID after insert")
		
		except Exception as e:
			self.new_db.rollback()
			self.stats["errors"] += 1
			self.stats["error_details"].append({
				"old_user_id": old_user.get('id'),
				"email": email,
				"mobile": mobile,
				"error": str(e)
			})
			return None
	
	def get_old_users(self, start_id: Optional[int] = None, limit: Optional[int] = None,
	                  skip_existing: bool = True) -> List[Dict[str, Any]]:
		"""دریافت کاربران از دیتابیس قدیمی"""
		query = f"""
			SELECT 
				id, email, password, full_name, mobile, active, 
				roles, date_register, invited_by_id, invate_code
			FROM {self.old_db_name}.user
			WHERE active = 1
				AND (email IS NOT NULL OR mobile IS NOT NULL)
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
		
		users = []
		for row in results:
			users.append({
				"id": row[0],
				"email": row[1],
				"password": row[2],
				"full_name": row[3],
				"mobile": row[4],
				"active": row[5],
				"roles": row[6],
				"date_register": row[7],
				"invited_by_id": row[8],
				"invate_code": row[9]
			})
		
		# فیلتر کردن کاربران موجود در دیتابیس جدید
		if skip_existing:
			filtered_users = []
			for user in users:
				email = normalize_email(user.get('email'))
				mobile = normalize_mobile(user.get('mobile'))
				if not self.check_user_exists(email, mobile):
					filtered_users.append(user)
			return filtered_users
		
		return users
	
	def run_migration(self, dry_run: bool = False, batch_size: int = 100,
	                 start_id: Optional[int] = None, limit: Optional[int] = None):
		"""اجرای انتقال"""
		print(f"{'='*60}")
		print(f"شروع انتقال کاربران")
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
		
		# دریافت کاربران قدیمی
		old_users = self.get_old_users(start_id=start_id, limit=limit, skip_existing=True)
		total_users = len(old_users)
		print(f"تعداد کاربران برای انتقال: {total_users}\n")
		
		if total_users == 0:
			print("هیچ کاربری برای انتقال یافت نشد.")
			return
		
		# نگاشت old_id -> new_id
		old_to_new_mapping: Dict[int, int] = {}
		
		# کدهای معرف موجود
		query = text("SELECT referral_code FROM users WHERE referral_code IS NOT NULL")
		existing_codes = {row[0] for row in self.new_db.execute(query).fetchall()}
		
		# پردازش batch به batch
		for i in range(0, total_users, batch_size):
			batch = old_users[i:i+batch_size]
			batch_num = (i // batch_size) + 1
			total_batches = (total_users + batch_size - 1) // batch_size
			
			print(f"\nپردازش batch {batch_num}/{total_batches} ({len(batch)} کاربر)...")
			
			for old_user in batch:
				self.stats["total_processed"] += 1
				
				if not dry_run:
					new_user_id = self.migrate_user(old_user, old_to_new_mapping, existing_codes)
					if new_user_id:
						old_to_new_mapping[old_user['id']] = new_user_id
				else:
					# در حالت dry-run فقط بررسی می‌کنیم
					email = normalize_email(old_user.get('email'))
					mobile = normalize_mobile(old_user.get('mobile'))
					if self.check_user_exists(email, mobile):
						self.stats["skipped_existing"] += 1
					else:
						self.stats["migrated"] += 1
				
				# نمایش پیشرفت
				if self.stats["total_processed"] % 10 == 0:
					print(f"  پردازش شده: {self.stats['total_processed']}/{total_users}", end='\r')
			
			print(f"\n  Batch {batch_num} تکمیل شد")
		
		# نمایش آمار نهایی
		print(f"\n{'='*60}")
		print("آمار نهایی:")
		print(f"{'='*60}")
		print(f"کل پردازش شده: {self.stats['total_processed']}")
		print(f"منتقل شده: {self.stats['migrated']}")
		print(f"رد شده (موجود در جدید): {self.stats['skipped_existing']}")
		print(f"رد شده (بدون identifier): {self.stats['skipped_no_identifier']}")
		print(f"خطاها: {self.stats['errors']}")
		
		if self.stats['error_details']:
			print(f"\nجزئیات خطاها:")
			for error in self.stats['error_details'][:10]:  # فقط 10 خطای اول
				print(f"  - User ID {error.get('old_user_id')}: {error.get('error')}")
			if len(self.stats['error_details']) > 10:
				print(f"  ... و {len(self.stats['error_details']) - 10} خطای دیگر")
	
	def close(self):
		"""بستن اتصالات"""
		self.old_db.close()
		self.new_db.close()


def main():
	parser = argparse.ArgumentParser(description="انتقال کاربران از دیتابیس قدیمی به جدید")
	parser.add_argument("--dry-run", action="store_true", help="اجرای تست بدون تغییر در دیتابیس")
	parser.add_argument("--batch-size", type=int, default=100, help="تعداد کاربران در هر batch")
	parser.add_argument("--start-id", type=int, help="شروع از شناسه خاص")
	parser.add_argument("--limit", type=int, help="محدود کردن تعداد کاربران")
	parser.add_argument("--old-db", default="hesabixOld", help="نام دیتابیس قدیمی")
	parser.add_argument("--new-db", default="hesabixpy", help="نام دیتابیس جدید")
	parser.add_argument("--db-user", default="root", help="نام کاربری دیتابیس")
	parser.add_argument("--db-password", default="136431", help="رمز عبور دیتابیس")
	parser.add_argument("--db-host", default="localhost", help="آدرس دیتابیس")
	parser.add_argument("--db-port", type=int, default=3306, help="پورت دیتابیس")
	
	args = parser.parse_args()
	
	migration = UserMigration(
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

