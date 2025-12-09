#!/usr/bin/env python3
"""
اسکریپت تحلیل و بررسی تیکت‌های پشتیبانی برای انتقال از hesabixOld به hesabixpy

این اسکریپت:
- ساختار جداول تیکت‌ها در دیتابیس قدیمی را بررسی می‌کند
- ساختار جداول تیکت‌ها در دیتابیس جدید را بررسی می‌کند
- جداول مرتبط (categories, priorities, statuses, messages) را بررسی می‌کند
- آمار و تفاوت‌ها را نشان می‌دهد
- راهنمای انتقال ارائه می‌دهد
"""

import sys
import os
import argparse
from typing import List, Dict, Any, Optional, Set, Tuple
from collections import defaultdict
from datetime import datetime

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text, inspect
from sqlalchemy.orm import sessionmaker, Session


class SupportTicketsAnalyzer:
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
		self.old_inspector = inspect(old_engine)
		
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
		self.new_inspector = inspect(new_engine)
	
	def get_table_structure(self, inspector, table_name: str) -> Dict[str, Any]:
		"""دریافت ساختار یک جدول"""
		if table_name not in inspector.get_table_names():
			return None
		
		columns = inspector.get_columns(table_name)
		foreign_keys = inspector.get_foreign_keys(table_name)
		indexes = inspector.get_indexes(table_name)
		
		return {
			"exists": True,
			"columns": {col["name"]: col for col in columns},
			"foreign_keys": foreign_keys,
			"indexes": indexes
		}
	
	def analyze_old_database(self) -> Dict[str, Any]:
		"""تحلیل دیتابیس قدیمی"""
		print("\n" + "="*80)
		print("تحلیل دیتابیس قدیمی (hesabixOld)")
		print("="*80)
		
		# بررسی وجود جداول
		old_tables = self.old_inspector.get_table_names()
		print(f"\nتعداد کل جداول: {len(old_tables)}")
		
		# جستجوی جداول مرتبط با support/ticket
		support_tables = [t for t in old_tables if 'support' in t.lower() or 'ticket' in t.lower()]
		
		print(f"\nجداول مرتبط با support/ticket:")
		for table in support_tables:
			print(f"  - {table}")
		
		# بررسی ساختار جداول
		old_structure = {}
		
		# بررسی جدول support (که در نسخه قدیمی وجود دارد)
		if 'support' in old_tables:
			print(f"\n✓ جدول support پیدا شد!")
			old_structure['tickets'] = self.get_table_structure(self.old_inspector, 'support')
			
			# آمار
			try:
				# تعداد کل رکوردها
				total_count = self.old_db.execute(text("SELECT COUNT(*) FROM support")).scalar()
				print(f"\n📊 تعداد کل رکوردها در جدول support: {total_count}")
				
				# تعداد تیکت‌های اصلی (main=0 یا NULL)
				tickets_count = self.old_db.execute(text("SELECT COUNT(*) FROM support WHERE main = 0 OR main IS NULL")).scalar()
				print(f"📊 تعداد تیکت‌های اصلی (main=0 یا NULL): {tickets_count}")
				
				# تعداد پاسخ‌ها (main!=0)
				replies_count = self.old_db.execute(text("SELECT COUNT(*) FROM support WHERE main != 0 AND main IS NOT NULL")).scalar()
				print(f"📊 تعداد پاسخ‌ها (main!=0): {replies_count}")
				
				# بررسی state ها
				states = self.old_db.execute(text("SELECT DISTINCT state FROM support WHERE state IS NOT NULL ORDER BY state")).fetchall()
				print(f"\n📊 مقادیر state:")
				for state in states:
					count = self.old_db.execute(text("SELECT COUNT(*) FROM support WHERE state = :state"), {'state': state[0]}).scalar()
					print(f"  - '{state[0]}': {count} رکورد")
				
				# نمونه داده
				sample_query = text("SELECT * FROM support WHERE (main = 0 OR main IS NULL) LIMIT 2")
				samples = self.old_db.execute(sample_query).fetchall()
				if samples:
					print(f"\n📋 نمونه تیکت‌های اصلی (2 مورد اول):")
					columns = [col['name'] for col in old_structure['tickets']['columns'].values()]
					for i, row in enumerate(samples, 1):
						print(f"\n  نمونه {i}:")
						for col, val in zip(columns, row):
							print(f"    {col}: {val}")
						
						# بررسی پاسخ‌های این تیکت
						if row[0]:  # id
							replies = self.old_db.execute(text("SELECT id, submitter_id, body, state FROM support WHERE main = :ticket_id LIMIT 3"), {'ticket_id': row[0]}).fetchall()
							if replies:
								print(f"    پاسخ‌ها ({len(replies)} مورد اول):")
								for reply in replies:
									print(f"      - id={reply[0]}, submitter_id={reply[1]}, state={reply[3]}")
			except Exception as e:
				print(f"⚠ خطا در دریافت آمار: {e}")
		
		# بررسی جدول پیام‌ها
		for table_name in ['support_messages', 'messages', 'support_message', 'ticket_messages']:
			if table_name in old_tables:
				print(f"✓ جدول {table_name} پیدا شد!")
				old_structure['messages'] = self.get_table_structure(self.old_inspector, table_name)
				break
		
		# بررسی جداول categories, priorities, statuses
		for table_type in ['categories', 'priorities', 'statuses']:
			for table_name in [f'support_{table_type}', f'ticket_{table_type}', table_type]:
				if table_name in old_tables:
					print(f"✓ جدول {table_name} پیدا شد!")
					old_structure[table_type] = self.get_table_structure(self.old_inspector, table_name)
					break
		
		return old_structure
	
	def analyze_new_database(self) -> Dict[str, Any]:
		"""تحلیل دیتابیس جدید"""
		print("\n" + "="*80)
		print("تحلیل دیتابیس جدید (hesabixpy)")
		print("="*80)
		
		# بررسی وجود جداول
		new_tables = self.new_inspector.get_table_names()
		print(f"\nتعداد کل جداول: {len(new_tables)}")
		
		# بررسی جداول support
		support_tables = [t for t in new_tables if 'support' in t.lower()]
		
		print(f"\nجداول مرتبط با support:")
		for table in sorted(support_tables):
			print(f"  - {table}")
		
		# بررسی ساختار جداول
		new_structure = {}
		
		# جدول تیکت‌ها
		if 'support_tickets' in new_tables:
			print(f"\n✓ جدول support_tickets پیدا شد!")
			new_structure['tickets'] = self.get_table_structure(self.new_inspector, 'support_tickets')
		
		# جدول پیام‌ها
		if 'support_messages' in new_tables:
			print(f"✓ جدول support_messages پیدا شد!")
			new_structure['messages'] = self.get_table_structure(self.new_inspector, 'support_messages')
		
		# جداول categories, priorities, statuses
		for table_type in ['categories', 'priorities', 'statuses']:
			table_name = f'support_{table_type}'
			if table_name in new_tables:
				print(f"✓ جدول {table_name} پیدا شد!")
				new_structure[table_type] = self.get_table_structure(self.new_inspector, table_name)
		
		# آمار
		if 'tickets' in new_structure and new_structure['tickets']:
			try:
				count_query = text("SELECT COUNT(*) FROM support_tickets")
				count = self.new_db.execute(count_query).scalar()
				print(f"\n📊 تعداد تیکت‌ها در دیتابیس جدید: {count}")
			except Exception as e:
				print(f"⚠ خطا در دریافت آمار: {e}")
		
		return new_structure
	
	def compare_structures(self, old_structure: Dict[str, Any], new_structure: Dict[str, Any]):
		"""مقایسه ساختار جداول"""
		print("\n" + "="*80)
		print("مقایسه ساختار جداول")
		print("="*80)
		
		# مقایسه جدول تیکت‌ها
		print("\n📋 مقایسه جدول تیکت‌ها:")
		if 'tickets' not in old_structure:
			print("  ⚠ جدول تیکت در دیتابیس قدیمی پیدا نشد!")
		elif 'tickets' not in new_structure:
			print("  ⚠ جدول تیکت در دیتابیس جدید پیدا نشد!")
		else:
			old_cols = set(old_structure['tickets']['columns'].keys())
			new_cols = set(new_structure['tickets']['columns'].keys())
			
			print(f"  فیلدهای دیتابیس قدیمی (support): {len(old_cols)}")
			print(f"  فیلدهای دیتابیس جدید (support_tickets): {len(new_cols)}")
			
			only_old = old_cols - new_cols
			only_new = new_cols - old_cols
			common = old_cols & new_cols
			
			if only_old:
				print(f"\n  ⚠ فیلدهای فقط در قدیمی: {only_old}")
				print("     (این فیلدها باید map شوند یا نادیده گرفته شوند)")
			if only_new:
				print(f"\n  ✓ فیلدهای جدید: {only_new}")
				print("     (این فیلدها باید با مقادیر پیش‌فرض یا محاسبه شده پر شوند)")
			if common:
				print(f"\n  ✓ فیلدهای مشترک: {len(common)} فیلد")
				print(f"     {common}")
			
			# Mapping پیشنهادی
			print("\n  📝 Mapping پیشنهادی:")
			print("     قدیمی -> جدید")
			print("     id -> id (اگر autoincrement نباشد)")
			print("     submitter_id -> user_id")
			print("     title -> title")
			print("     body -> description")
			print("     date_submit -> created_at (تبدیل timestamp string به datetime)")
			print("     state -> status_id (نیاز به mapping)")
			print("     main -> (تیکت اصلی: main=0, پاسخ‌ها: main=id تیکت)")
			print("     bid_id -> (اختیاری، در ساختار جدید نیست)")
			print("     code -> (اختیاری، در ساختار جدید نیست)")
			print("     file_name -> (اختیاری، در ساختار جدید نیست)")
		
		# مقایسه جدول پیام‌ها
		print("\n💬 مقایسه جدول پیام‌ها:")
		if 'messages' not in old_structure:
			print("  ⚠ جدول پیام در دیتابیس قدیمی پیدا نشد!")
			print("     در نسخه قدیمی، پاسخ‌ها در همان جدول support با main=id تیکت ذخیره می‌شوند")
			print("     باید این رکوردها را به جدول support_messages منتقل کنیم")
		elif 'messages' not in new_structure:
			print("  ⚠ جدول پیام در دیتابیس جدید پیدا نشد!")
		else:
			old_cols = set(old_structure['messages']['columns'].keys())
			new_cols = set(new_structure['messages']['columns'].keys())
			
			print(f"  فیلدهای دیتابیس قدیمی: {len(old_cols)}")
			print(f"  فیلدهای دیتابیس جدید: {len(new_cols)}")
			
			only_old = old_cols - new_cols
			only_new = new_cols - old_cols
			
			if only_old:
				print(f"\n  ⚠ فیلدهای فقط در قدیمی: {only_old}")
			if only_new:
				print(f"\n  ✓ فیلدهای جدید: {only_new}")
	
	def get_migration_recommendations(self, old_structure: Dict[str, Any], new_structure: Dict[str, Any]):
		"""ارائه توصیه‌های انتقال"""
		print("\n" + "="*80)
		print("توصیه‌های انتقال")
		print("="*80)
		
		if 'tickets' not in old_structure:
			print("\n⚠ جدول تیکت در دیتابیس قدیمی پیدا نشد!")
			print("  ممکن است:")
			print("    - نام جدول متفاوت باشد")
			print("    - تیکت‌ها در جدول دیگری ذخیره شده باشند")
			print("    - سیستم پشتیبانی در نسخه قدیمی وجود نداشته باشد")
			return
		
		if 'tickets' not in new_structure:
			print("\n⚠ جدول تیکت در دیتابیس جدید پیدا نشد!")
			print("  باید ابتدا migration را اجرا کنید تا جداول ایجاد شوند.")
			return
		
		print("\n✅ مراحل پیشنهادی برای انتقال:")
		
		print("\n1. آماده‌سازی جداول مرجع:")
		print("   - support_categories: ایجاد دسته‌بندی پیش‌فرض (مثلاً 'عمومی')")
		print("   - support_priorities: ایجاد اولویت‌های پیش‌فرض (کم، متوسط، بالا)")
		print("   - support_statuses: ایجاد وضعیت‌ها و mapping با state های قدیمی:")
		print("     * '0' یا 'در حال پیگیری' -> status 'در حال بررسی'")
		print("     * 'پاسخ داده شده' -> status 'پاسخ داده شده'")
		print("     * 'خاتمه یافته' -> status 'بسته شده' (is_final=True)")
		print("     * 'بسته شده' -> status 'بسته شده' (is_final=True)")
		
		print("\n2. Mapping کاربران:")
		print("   - submitter_id (قدیمی) -> user_id (جدید)")
		print("   - باید mapping table از user_id قدیمی به جدید داشته باشیم")
		print("   - assigned_operator_id: در نسخه قدیمی وجود ندارد، می‌توان NULL بگذاریم")
		
		print("\n3. انتقال تیکت‌های اصلی:")
		print("   - فقط رکوردهایی که main=0 یا main IS NULL هستند")
		print("   - تبدیل date_submit (string timestamp) به created_at (datetime)")
		print("   - تبدیل state (string) به status_id (integer)")
		print("   - category_id: استفاده از دسته‌بندی پیش‌فرض")
		print("   - priority_id: استفاده از اولویت پیش‌فرض (مثلاً متوسط)")
		print("   - is_internal: False (پیش‌فرض)")
		print("   - closed_at: اگر state='خاتمه یافته' یا 'بسته شده'، از updated_at استفاده کنیم")
		
		print("\n4. انتقال پاسخ‌ها (پیام‌ها):")
		print("   - رکوردهایی که main!=0 و main IS NOT NULL هستند")
		print("   - اینها را به جدول support_messages منتقل کنیم")
		print("   - ticket_id: id تیکت اصلی در دیتابیس جدید")
		print("   - sender_id: submitter_id (باید map شود)")
		print("   - sender_type: تعیین بر اساس submitter_id (user یا operator)")
		print("   - content: body از جدول قدیمی")
		print("   - is_internal: False (پیش‌فرض)")
		print("   - created_at: تبدیل date_submit به datetime")
		
		print("\n5. نکات مهم:")
		print("   - حفظ ترتیب زمانی: پاسخ‌ها باید بر اساس date_submit مرتب شوند")
		print("   - Foreign Keys: اطمینان از وجود تمام user_id های مورد نیاز")
		print("   - Transaction: استفاده از transaction برای اطمینان از یکپارچگی")
		print("   - Duplicate Check: بررسی تیکت‌های تکراری قبل از انتقال")
		
		print("\n6. داده‌های از دست رفته:")
		print("   - bid_id: در ساختار جدید وجود ندارد (می‌توان نادیده گرفت)")
		print("   - code: در ساختار جدید وجود ندارد")
		print("   - file_name: در ساختار جدید وجود ندارد (اگر نیاز باشد باید جدول جداگانه ایجاد شود)")
	
	def print_detailed_structure(self, structure: Dict[str, Any], db_name: str):
		"""چاپ جزئیات ساختار"""
		print("\n" + "="*80)
		print(f"جزئیات ساختار - {db_name}")
		print("="*80)
		
		for table_type, table_info in structure.items():
			if not table_info:
				continue
			
			print(f"\n📋 جدول {table_type}:")
			print(f"  ستون‌ها:")
			for col_name, col_info in table_info['columns'].items():
				col_type = str(col_info['type'])
				nullable = "NULL" if col_info['nullable'] else "NOT NULL"
				default = f" DEFAULT {col_info['default']}" if col_info.get('default') else ""
				print(f"    - {col_name}: {col_type} {nullable}{default}")
			
			if table_info.get('foreign_keys'):
				print(f"\n  Foreign Keys:")
				for fk in table_info['foreign_keys']:
					print(f"    - {fk['name']}: {fk['constrained_columns']} -> {fk['referred_table']}.{fk['referred_columns']}")
	
	def run(self):
		"""اجرای تحلیل کامل"""
		print("\n" + "🔍"*40)
		print("تحلیل تیکت‌های پشتیبانی برای انتقال")
		print("🔍"*40)
		
		# تحلیل دیتابیس قدیمی
		old_structure = self.analyze_old_database()
		
		# تحلیل دیتابیس جدید
		new_structure = self.analyze_new_database()
		
		# چاپ جزئیات ساختار
		if old_structure:
			self.print_detailed_structure(old_structure, "hesabixOld")
		if new_structure:
			self.print_detailed_structure(new_structure, "hesabixpy")
		
		# مقایسه
		self.compare_structures(old_structure, new_structure)
		
		# توصیه‌ها
		self.get_migration_recommendations(old_structure, new_structure)
		
		print("\n" + "="*80)
		print("تحلیل کامل شد!")
		print("="*80 + "\n")
	
	def close(self):
		"""بستن اتصالات"""
		self.old_db.close()
		self.new_db.close()


def main():
	parser = argparse.ArgumentParser(description="تحلیل تیکت‌های پشتیبانی برای انتقال")
	parser.add_argument("--old-db", default="hesabixOld", help="نام دیتابیس قدیمی")
	parser.add_argument("--new-db", default="hesabixpy", help="نام دیتابیس جدید")
	parser.add_argument("--user", default="root", help="نام کاربری دیتابیس")
	parser.add_argument("--password", default="136431", help="رمز دیتابیس")
	parser.add_argument("--host", default="localhost", help="هاست دیتابیس")
	parser.add_argument("--port", type=int, default=3306, help="پورت دیتابیس")
	
	args = parser.parse_args()
	
	analyzer = SupportTicketsAnalyzer(
		old_db_name=args.old_db,
		new_db_name=args.new_db,
		db_user=args.user,
		db_password=args.password,
		db_host=args.host,
		db_port=args.port
	)
	
	try:
		analyzer.run()
	finally:
		analyzer.close()


if __name__ == "__main__":
	main()

