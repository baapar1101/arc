#!/usr/bin/env python3
"""
اسکریپت انتقال کاربران عضو کسب و کار از hesabixOld به hesabixpy

این اسکریپت:
- کاربران عضو کسب و کار را از permission منتقل می‌کند
- فقط کاربران با owner = 0 را منتقل می‌کند (کاربران owner نیازی به رکورد ندارند)
- فیلدهای boolean را به ساختار JSON جدید تبدیل می‌کند
"""

import sys
import os
import argparse
from typing import List, Dict, Any, Optional
from datetime import datetime
import json

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session


def convert_permissions_to_json(old_permission: Dict[str, Any]) -> Dict[str, Any]:
	"""
	تبدیل فیلدهای boolean قدیمی به ساختار JSON جدید
	
	Args:
		old_permission: دیکشنری شامل فیلدهای boolean از دیتابیس قدیمی
	
	Returns:
		دیکشنری JSON با ساختار جدید
	"""
	permissions = {
		"join": True  # همه کاربران عضو هستند
	}
	
	# تبدیل فیلدهای boolean به ساختار JSON
	# invoices (فروش)
	if old_permission.get('sell') == 1:
		permissions["invoices"] = {
			"add": True,
			"edit": old_permission.get('sell') == 1,
			"view": True,
			"draft": True,
			"delete": old_permission.get('sell') == 1,
			"export": old_permission.get('report') == 1
		}
	
	# transfers (خرید)
	if old_permission.get('buy') == 1:
		permissions["transfers"] = {
			"add": True,
			"edit": old_permission.get('buy') == 1,
			"view": True,
			"draft": True,
			"delete": old_permission.get('buy') == 1
		}
	
	# people (اشخاص)
	if old_permission.get('person') == 1:
		permissions["people"] = {
			"add": True,
			"edit": old_permission.get('person') == 1,
			"view": True,
			"delete": old_permission.get('person') == 1
		}
	
	# products (کالا)
	if old_permission.get('commodity') == 1:
		permissions["products"] = {
			"add": True,
			"edit": old_permission.get('commodity') == 1,
			"view": True,
			"delete": old_permission.get('commodity') == 1,
			"export": old_permission.get('report') == 1
		}
	
	# categories (دسته‌بندی)
	if old_permission.get('commodity') == 1:
		permissions["categories"] = {
			"add": True,
			"edit": old_permission.get('commodity') == 1,
			"view": True,
			"delete": old_permission.get('commodity') == 1
		}
	
	# bank_accounts (حساب‌های بانکی)
	if old_permission.get('banks') == 1:
		permissions["bank_accounts"] = {
			"add": True,
			"edit": old_permission.get('banks') == 1,
			"view": True,
			"delete": old_permission.get('banks') == 1
		}
	
	# cash (صندوق)
	if old_permission.get('cashdesk') == 1:
		permissions["cash"] = {
			"add": True,
			"edit": old_permission.get('cashdesk') == 1,
			"view": True,
			"delete": old_permission.get('cashdesk') == 1
		}
		permissions["petty_cash"] = {
			"add": True,
			"edit": old_permission.get('cashdesk') == 1,
			"view": True,
			"delete": old_permission.get('cashdesk') == 1
		}
	
	# checks (چک‌ها)
	if old_permission.get('cheque') == 1:
		permissions["checks"] = {
			"add": True,
			"edit": old_permission.get('cheque') == 1,
			"view": True,
			"delete": old_permission.get('cheque') == 1,
			"return": True,
			"collect": True,
			"transfer": True
		}
	
	# settings (تنظیمات)
	if old_permission.get('settings') == 1:
		permissions["settings"] = {
			"view": True,
			"print": True,
			"users": old_permission.get('permission') == 1,
			"history": old_permission.get('log') == 1,
			"business": old_permission.get('settings') == 1
		}
	
	# reports (گزارش‌ها)
	if old_permission.get('report') == 1:
		permissions["reports"] = {
			"view": True,
			"export": old_permission.get('report') == 1
		}
	
	# expenses_income (هزینه و درآمد)
	if old_permission.get('cost') == 1 or old_permission.get('income') == 1:
		permissions["expenses_income"] = {
			"add": True,
			"edit": (old_permission.get('cost') == 1 or old_permission.get('income') == 1),
			"view": True,
			"draft": True,
			"delete": (old_permission.get('cost') == 1 or old_permission.get('income') == 1)
		}
	
	# accounting (حسابداری)
	if old_permission.get('accounting') == 1:
		permissions["chart_of_accounts"] = {
			"add": True,
			"edit": old_permission.get('accounting') == 1,
			"view": True,
			"delete": old_permission.get('accounting') == 1
		}
		permissions["accounting_documents"] = {
			"add": True,
			"edit": old_permission.get('accounting') == 1,
			"view": True,
			"draft": True,
			"delete": old_permission.get('accounting') == 1
		}
		permissions["opening_balance"] = {
			"edit": old_permission.get('accounting') == 1,
			"view": True
		}
	
	# fiscal_years (سال‌های مالی)
	if old_permission.get('accounting') == 1:
		permissions["fiscal_years"] = {
			"view": True
		}
	
	# wallet (کیف پول)
	if old_permission.get('wallet') == 1:
		permissions["wallet"] = {
			"view": True,
			"charge": old_permission.get('wallet') == 1
		}
	
	# storage (آرشیو)
	if old_permission.get('archive_view') == 1:
		permissions["storage"] = {
			"view": True,
			"delete": old_permission.get('archive_delete') == 1
		}
	
	# people_transactions (تراکنش‌های اشخاص)
	if old_permission.get('getpay') == 1:
		permissions["people_transactions"] = {
			"add": True,
			"edit": old_permission.get('getpay') == 1,
			"view": True,
			"draft": True,
			"delete": old_permission.get('getpay') == 1
		}
	
	# bank_transfer (انتقالات بانکی)
	if old_permission.get('bank_transfer') == 1:
		permissions["bank_transfer"] = {
			"add": True,
			"edit": old_permission.get('bank_transfer') == 1,
			"view": True,
			"delete": old_permission.get('bank_transfer') == 1
		}
	
	# price_lists (لیست قیمت)
	if old_permission.get('commodity') == 1:
		permissions["price_lists"] = {
			"add": True,
			"edit": old_permission.get('commodity') == 1,
			"view": True,
			"delete": old_permission.get('commodity') == 1
		}
	
	# warehouses (انبار)
	if old_permission.get('commodity') == 1:
		permissions["warehouses"] = {
			"add": True,
			"edit": old_permission.get('commodity') == 1,
			"view": True,
			"delete": old_permission.get('commodity') == 1
		}
		permissions["warehouse_transfers"] = {
			"add": True,
			"edit": old_permission.get('commodity') == 1,
			"view": True,
			"draft": True,
			"delete": old_permission.get('commodity') == 1
		}
	
	# marketplace (بازار)
	if old_permission.get('store') == 1:
		permissions["marketplace"] = {
			"buy": True,
			"view": True,
			"invoices": True
		}
	
	# warranty (گارانتی)
	if old_permission.get('plug_warranty_manager') == 1:
		permissions["warranty"] = {
			"read": False,
			"view": True,
			"write": old_permission.get('plug_warranty_manager') == 1,
			"delete": old_permission.get('plug_warranty_manager') == 1,
			"manage": old_permission.get('plug_warranty_manager') == 1
		}
	
	# sms
	if old_permission.get('settings') == 1:
		permissions["sms"] = {
			"view": old_permission.get('settings') == 1,
			"history": False,
			"templates": old_permission.get('settings') == 1
		}
	
	return permissions


class BusinessUserMigration:
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
			"permissions_processed": 0,
			"permissions_migrated": 0,
			"permissions_skipped": 0,
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
	
	def create_user_id_mapping(self) -> Dict[int, int]:
		"""ایجاد mapping بین user_id قدیمی و جدید"""
		query = text("""
			SELECT 
				old_user.id as old_user_id,
				new_user.id as new_user_id
			FROM hesabixOld.user old_user
			INNER JOIN hesabixpy.users new_user ON (
				(old_user.email IS NOT NULL AND new_user.email IS NOT NULL AND BINARY old_user.email = BINARY new_user.email) OR
				(old_user.mobile IS NOT NULL AND new_user.mobile IS NOT NULL AND BINARY old_user.mobile = BINARY new_user.mobile)
			)
			WHERE old_user.active = 1
		""")
		
		results = self.old_db.execute(query).fetchall()
		mapping = {}
		for row in results:
			mapping[row.old_user_id] = row.new_user_id
		
		print(f"✅ User ID mapping ایجاد شد: {len(mapping)} کاربر")
		return mapping
	
	def migrate_business_user(self, old_permission: Dict[str, Any], business_id_mapping: Dict[int, int],
	                         user_id_mapping: Dict[int, int]) -> Optional[int]:
		"""انتقال یک کاربر عضو کسب و کار"""
		try:
			# فقط کاربران با owner = 0 را منتقل می‌کنیم
			if old_permission.get('owner') == 1:
				self.stats["permissions_skipped"] += 1
				return None
			
			# نگاشت business_id
			old_business_id = old_permission.get('bid_id')
			new_business_id = business_id_mapping.get(old_business_id)
			
			if not new_business_id:
				self.stats["permissions_skipped"] += 1
				return None
			
			# نگاشت user_id
			old_user_id = old_permission.get('user_id')
			new_user_id = user_id_mapping.get(old_user_id)
			
			if not new_user_id:
				self.stats["permissions_skipped"] += 1
				return None
			
			# بررسی وجود در دیتابیس جدید
			query = text("""
				SELECT COUNT(*) FROM business_permissions
				WHERE business_id = :business_id AND user_id = :user_id
			""")
			result = self.new_db.execute(query, {
				"business_id": new_business_id,
				"user_id": new_user_id
			}).scalar()
			
			if result > 0:
				self.stats["permissions_skipped"] += 1
				return None
			
			# تبدیل فیلدهای boolean به JSON
			permissions_json = convert_permissions_to_json(old_permission)
			
			# درج business_permission
			query = text("""
				INSERT INTO business_permissions (
					business_id, user_id, business_permissions,
					created_at, updated_at
				) VALUES (
					:business_id, :user_id, :business_permissions,
					:created_at, :updated_at
				)
			""")
			
			self.new_db.execute(query, {
				"business_id": new_business_id,
				"user_id": new_user_id,
				"business_permissions": json.dumps(permissions_json, ensure_ascii=False),
				"created_at": datetime.utcnow(),
				"updated_at": datetime.utcnow()
			})
			
			self.new_db.commit()
			
			# دریافت new_permission_id
			query = text("""
				SELECT id FROM business_permissions
				WHERE business_id = :business_id AND user_id = :user_id
				LIMIT 1
			""")
			result = self.new_db.execute(query, {
				"business_id": new_business_id,
				"user_id": new_user_id
			}).fetchone()
			
			if result:
				self.stats["permissions_migrated"] += 1
				return result[0]
			else:
				raise Exception("Failed to get new business permission ID after insert")
		
		except Exception as e:
			self.new_db.rollback()
			self.stats["errors"] += 1
			self.stats["error_details"].append({
				"old_permission_id": old_permission.get('id'),
				"old_business_id": old_permission.get('bid_id'),
				"old_user_id": old_permission.get('user_id'),
				"error": str(e)
			})
			return None
	
	def get_old_permissions(self, start_id: Optional[int] = None, limit: Optional[int] = None,
	                       business_ids: Optional[List[int]] = None) -> List[Dict[str, Any]]:
		"""دریافت دسترسی‌ها از دیتابیس قدیمی (فقط owner = 0)"""
		query = f"""
			SELECT 
				id, user_id, bid_id, owner, settings, person, commodity,
				getpay, banks, bank_transfer, buy, sell, cost, income,
				accounting, report, log, permission, salary, cashdesk,
				store, wallet, archive_upload, archive_mod, archive_delete,
				archive_view, cheque, inquiry, ai, plug_warranty_manager
			FROM {self.old_db_name}.permission
			WHERE owner = 0
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
		
		query += " ORDER BY bid_id, user_id, id ASC"
		
		if limit:
			query += " LIMIT :limit"
			params["limit"] = limit
		
		results = self.old_db.execute(text(query), params).fetchall()
		
		permissions = []
		for row in results:
			permissions.append({
				"id": row[0],
				"user_id": row[1],
				"bid_id": row[2],
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
			})
		
		return permissions
	
	def run_migration(self, dry_run: bool = False, batch_size: int = 500,
	                 start_id: Optional[int] = None, limit: Optional[int] = None):
		"""اجرای انتقال"""
		print(f"{'='*60}")
		print(f"شروع انتقال کاربران عضو کسب و کار")
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
		user_id_mapping = self.create_user_id_mapping()
		
		# دریافت کسب و کارهای منتقل شده
		old_business_ids = list(business_id_mapping.keys())
		
		if not old_business_ids:
			print("هیچ کسب و کاری برای انتقال یافت نشد.")
			return
		
		# دریافت دسترسی‌ها (فقط owner = 0)
		old_permissions = self.get_old_permissions(
			start_id=start_id,
			limit=limit,
			business_ids=old_business_ids
		)
		total_permissions = len(old_permissions)
		print(f"تعداد کاربران عضو برای انتقال: {total_permissions}\n")
		
		if total_permissions == 0:
			print("هیچ کاربر عضوی برای انتقال یافت نشد.")
			return
		
		# پردازش batch به batch
		for i in range(0, total_permissions, batch_size):
			batch = old_permissions[i:i+batch_size]
			batch_num = (i // batch_size) + 1
			total_batches = (total_permissions + batch_size - 1) // batch_size
			
			print(f"\nپردازش batch {batch_num}/{total_batches} ({len(batch)} کاربر عضو)...")
			
			for old_permission in batch:
				self.stats["permissions_processed"] += 1
				
				if not dry_run:
					self.migrate_business_user(
						old_permission, business_id_mapping, user_id_mapping
					)
				else:
					# در حالت dry-run فقط بررسی می‌کنیم
					old_business_id = old_permission.get('bid_id')
					old_user_id = old_permission.get('user_id')
					if old_business_id in business_id_mapping and old_user_id in user_id_mapping:
						self.stats["permissions_migrated"] += 1
					else:
						self.stats["permissions_skipped"] += 1
				
				if self.stats["permissions_processed"] % 50 == 0:
					print(f"  پردازش شده: {self.stats['permissions_processed']}/{total_permissions}", end='\r')
			
			print(f"\n  Batch {batch_num} تکمیل شد")
		
		# نمایش آمار نهایی
		print(f"\n{'='*60}")
		print("آمار نهایی:")
		print(f"{'='*60}")
		print(f"کاربران عضو:")
		print(f"  پردازش شده: {self.stats['permissions_processed']}")
		print(f"  منتقل شده: {self.stats['permissions_migrated']}")
		print(f"  رد شده: {self.stats['permissions_skipped']}")
		print(f"\nخطاها: {self.stats['errors']}")
		
		if self.stats['error_details']:
			print(f"\nجزئیات خطاها:")
			for error in self.stats['error_details'][:10]:
				print(f"  - Permission ID {error.get('old_permission_id')} (Business: {error.get('old_business_id')}, User: {error.get('old_user_id')}): {error.get('error')}")
			if len(self.stats['error_details']) > 10:
				print(f"  ... و {len(self.stats['error_details']) - 10} خطای دیگر")
	
	def close(self):
		"""بستن اتصالات"""
		self.old_db.close()
		self.new_db.close()


def main():
	parser = argparse.ArgumentParser(description="انتقال کاربران عضو کسب و کار")
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
	
	migration = BusinessUserMigration(
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

