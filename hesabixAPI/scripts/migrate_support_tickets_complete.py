#!/usr/bin/env python3
"""
اسکریپت انتقال تیکت‌های پشتیبانی از hesabixOld به hesabixpy

این اسکریپت:
- تیکت‌های اصلی (main=0 یا NULL) را به support_tickets منتقل می‌کند
- پاسخ‌ها (main!=0) را به support_messages منتقل می‌کند
- همه تیکت‌ها را به دسته‌بندی "عمومی" منتقل می‌کند
- وضعیت‌های قدیمی را به وضعیت‌های جدید map می‌کند
"""

import sys
import os
import argparse
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime

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


def map_old_state_to_new_status(state: str | None) -> int:
	"""
	Mapping وضعیت‌های قدیمی به وضعیت‌های جدید:
	- "0" یا "در حال پیگیری" -> "در حال پیگیری" (id=2)
	- "پاسخ داده شده" -> "در انتظار کاربر" (id=3)
	- "خاتمه یافته" -> "حل شده" (id=5)
	- "بسته شده" -> "بسته" (id=4)
	- پیش‌فرض: "در حال پیگیری" (id=2)
	"""
	if not state:
		return 2  # در حال پیگیری
	
	state = state.strip()
	
	if state == "0" or state == "در حال پیگیری":
		return 2  # در حال پیگیری
	elif state == "پاسخ داده شده":
		return 3  # در انتظار کاربر
	elif state == "خاتمه یافته":
		return 5  # حل شده
	elif state == "بسته شده":
		return 4  # بسته
	else:
		return 2  # پیش‌فرض: در حال پیگیری


def determine_sender_type(submitter_id: int, user_id_mapping: Dict[int, int]) -> str:
	"""
	تعیین نوع فرستنده (user/operator/system)
	در حال حاضر همه را user در نظر می‌گیریم
	می‌توان در آینده بر اساس نقش کاربر تعیین کرد
	"""
	return "user"


class SupportTicketsMigration:
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
		
		# Cache ها
		self.user_id_mapping: Dict[int, int] = {}
		self.ticket_id_mapping: Dict[int, int] = {}  # {old_ticket_id: new_ticket_id}
		self.general_category_id: int = 6  # دسته‌بندی "عمومی"
		self.default_priority_id: int = 2  # اولویت "متوسط"
		
		# آمار
		self.stats = {
			"tickets_processed": 0,
			"tickets_migrated": 0,
			"tickets_skipped": 0,
			"messages_processed": 0,
			"messages_migrated": 0,
			"messages_skipped": 0,
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
	
	def get_general_category_id(self) -> int:
		"""دریافت id دسته‌بندی عمومی"""
		result = self.new_db.execute(
			text("SELECT id FROM support_categories WHERE name = 'عمومی' LIMIT 1")
		).fetchone()
		
		if result:
			return result[0]
		else:
			# ایجاد دسته‌بندی عمومی در صورت عدم وجود
			now = datetime.now()
			result = self.new_db.execute(text("""
				INSERT INTO support_categories (name, description, is_active, created_at, updated_at)
				VALUES ('عمومی', 'تیکت‌های عمومی و کلی', 1, :created_at, :updated_at)
			"""), {
				'created_at': now,
				'updated_at': now
			})
			self.new_db.commit()
			return result.lastrowid
	
	def get_old_tickets(self) -> List[Dict[str, Any]]:
		"""دریافت تیکت‌های اصلی از دیتابیس قدیمی"""
		query = text("""
			SELECT 
				id, submitter_id, title, body, date_submit, state, code, file_name, bid_id
			FROM support
			WHERE main = 0 OR main IS NULL
			ORDER BY id ASC
		""")
		
		results = self.old_db.execute(query).fetchall()
		tickets = []
		for row in results:
			tickets.append({
				"id": row[0],
				"submitter_id": row[1],
				"title": row[2] or "بدون عنوان",
				"body": row[3] or "",
				"date_submit": row[4],
				"state": row[5],
				"code": row[6],
				"file_name": row[7],
				"bid_id": row[8]
			})
		
		return tickets
	
	def get_old_replies(self, ticket_id: int) -> List[Dict[str, Any]]:
		"""دریافت پاسخ‌های یک تیکت از دیتابیس قدیمی"""
		query = text("""
			SELECT 
				id, submitter_id, body, date_submit, state
			FROM support
			WHERE main = :ticket_id
			ORDER BY date_submit ASC
		""")
		
		results = self.old_db.execute(query, {"ticket_id": ticket_id}).fetchall()
		replies = []
		for row in results:
			replies.append({
				"id": row[0],
				"submitter_id": row[1],
				"body": row[2] or "",
				"date_submit": row[3],
				"state": row[4]
			})
		
		return replies
	
	def migrate_ticket(self, old_ticket: Dict[str, Any]) -> Optional[int]:
		"""انتقال یک تیکت از دیتابیس قدیمی به جدید"""
		try:
			# بررسی mapping کاربر
			old_submitter_id = old_ticket["submitter_id"]
			if old_submitter_id not in self.user_id_mapping:
				self.stats["tickets_skipped"] += 1
				self.stats["error_details"].append({
					"type": "ticket",
					"old_id": old_ticket["id"],
					"error": f"User mapping not found for submitter_id={old_submitter_id}"
				})
				return None
			
			new_user_id = self.user_id_mapping[old_submitter_id]
			
			# تبدیل تاریخ
			created_at = convert_timestamp_to_datetime(old_ticket["date_submit"])
			if not created_at:
				created_at = datetime.now()
			
			updated_at = created_at
			
			# تبدیل وضعیت
			status_id = map_old_state_to_new_status(old_ticket["state"])
			
			# تعیین closed_at
			closed_at = None
			if old_ticket["state"] in ["خاتمه یافته", "بسته شده"]:
				closed_at = updated_at
			
			# درج تیکت جدید
			result = self.new_db.execute(text("""
				INSERT INTO support_tickets (
					title, description, user_id, category_id, priority_id, status_id,
					assigned_operator_id, is_internal, closed_at, created_at, updated_at
				) VALUES (
					:title, :description, :user_id, :category_id, :priority_id, :status_id,
					:assigned_operator_id, :is_internal, :closed_at, :created_at, :updated_at
				)
			"""), {
				"title": old_ticket["title"][:255],  # محدودیت طول
				"description": old_ticket["body"],
				"user_id": new_user_id,
				"category_id": self.general_category_id,
				"priority_id": self.default_priority_id,
				"status_id": status_id,
				"assigned_operator_id": None,
				"is_internal": False,
				"closed_at": closed_at,
				"created_at": created_at,
				"updated_at": updated_at
			})
			
			self.new_db.commit()
			new_ticket_id = result.lastrowid
			
			# ایجاد پیام اولیه برای تیکت
			# این پیام اولیه با محتوای description تیکت ایجاد می‌شود
			self.new_db.execute(text("""
				INSERT INTO support_messages (
					ticket_id, sender_id, sender_type, content, is_internal, created_at
				) VALUES (
					:ticket_id, :sender_id, :sender_type, :content, :is_internal, :created_at
				)
			"""), {
				"ticket_id": new_ticket_id,
				"sender_id": new_user_id,
				"sender_type": "user",
				"content": old_ticket["body"],
				"is_internal": False,
				"created_at": created_at
			})
			
			self.new_db.commit()
			
			# ذخیره mapping
			self.ticket_id_mapping[old_ticket["id"]] = new_ticket_id
			
			self.stats["tickets_migrated"] += 1
			return new_ticket_id
			
		except Exception as e:
			self.new_db.rollback()
			self.stats["errors"] += 1
			self.stats["error_details"].append({
				"type": "ticket",
				"old_id": old_ticket.get("id"),
				"error": str(e)
			})
			return None
	
	def migrate_message(self, old_reply: Dict[str, Any], new_ticket_id: int) -> Optional[int]:
		"""انتقال یک پیام/پاسخ از دیتابیس قدیمی به جدید"""
		try:
			# بررسی mapping کاربر
			old_submitter_id = old_reply["submitter_id"]
			if old_submitter_id not in self.user_id_mapping:
				self.stats["messages_skipped"] += 1
				return None
			
			new_sender_id = self.user_id_mapping[old_submitter_id]
			
			# تبدیل تاریخ
			created_at = convert_timestamp_to_datetime(old_reply["date_submit"])
			if not created_at:
				created_at = datetime.now()
			
			# تعیین نوع فرستنده
			sender_type = determine_sender_type(old_submitter_id, self.user_id_mapping)
			
			# درج پیام جدید
			result = self.new_db.execute(text("""
				INSERT INTO support_messages (
					ticket_id, sender_id, sender_type, content, is_internal, created_at
				) VALUES (
					:ticket_id, :sender_id, :sender_type, :content, :is_internal, :created_at
				)
			"""), {
				"ticket_id": new_ticket_id,
				"sender_id": new_sender_id,
				"sender_type": sender_type,
				"content": old_reply["body"],
				"is_internal": False,
				"created_at": created_at
			})
			
			self.new_db.commit()
			new_message_id = result.lastrowid
			
			self.stats["messages_migrated"] += 1
			return new_message_id
			
		except Exception as e:
			self.new_db.rollback()
			self.stats["errors"] += 1
			self.stats["error_details"].append({
				"type": "message",
				"old_id": old_reply.get("id"),
				"ticket_id": new_ticket_id,
				"error": str(e)
			})
			return None
	
	def migrate_all(self, dry_run: bool = False):
		"""انتقال همه تیکت‌ها و پیام‌ها"""
		print("\n" + "="*80)
		print("شروع انتقال تیکت‌های پشتیبانی")
		print("="*80)
		
		if dry_run:
			print("\n⚠ حالت DRY RUN - هیچ تغییری اعمال نخواهد شد")
		
		# ایجاد mapping کاربران
		print("\n📋 ایجاد mapping کاربران...")
		self.user_id_mapping = self.create_user_id_mapping()
		
		if not self.user_id_mapping:
			print("⚠ هیچ mapping کاربری پیدا نشد! انتقال متوقف می‌شود.")
			return
		
		# دریافت id دسته‌بندی عمومی
		print("\n📋 بررسی دسته‌بندی عمومی...")
		self.general_category_id = self.get_general_category_id()
		print(f"✅ دسته‌بندی عمومی: id={self.general_category_id}")
		
		# دریافت تیکت‌های قدیمی
		print("\n📋 دریافت تیکت‌های قدیمی...")
		old_tickets = self.get_old_tickets()
		print(f"✅ {len(old_tickets)} تیکت پیدا شد")
		
		if not old_tickets:
			print("⚠ هیچ تیکتی برای انتقال پیدا نشد!")
			return
		
		# انتقال تیکت‌ها
		print("\n📤 شروع انتقال تیکت‌ها...")
		for i, old_ticket in enumerate(old_tickets, 1):
			self.stats["tickets_processed"] += 1
			
			if i % 100 == 0:
				print(f"  در حال پردازش تیکت {i}/{len(old_tickets)}...")
			
			if not dry_run:
				new_ticket_id = self.migrate_ticket(old_ticket)
				
				# انتقال پاسخ‌های این تیکت
				if new_ticket_id:
					old_replies = self.get_old_replies(old_ticket["id"])
					for old_reply in old_replies:
						self.stats["messages_processed"] += 1
						self.migrate_message(old_reply, new_ticket_id)
			else:
				# در حالت dry run فقط آمار می‌گیریم
				if old_ticket["submitter_id"] in self.user_id_mapping:
					self.stats["tickets_migrated"] += 1
					old_replies = self.get_old_replies(old_ticket["id"])
					self.stats["messages_processed"] += len(old_replies)
					self.stats["messages_migrated"] += len(old_replies)
				else:
					self.stats["tickets_skipped"] += 1
		
		# نمایش آمار نهایی
		self.print_stats()
	
	def print_stats(self):
		"""نمایش آمار نهایی"""
		print("\n" + "="*80)
		print("آمار نهایی انتقال")
		print("="*80)
		
		print(f"\n📊 تیکت‌ها:")
		print(f"  پردازش شده: {self.stats['tickets_processed']}")
		print(f"  منتقل شده: {self.stats['tickets_migrated']}")
		print(f"  رد شده: {self.stats['tickets_skipped']}")
		
		print(f"\n💬 پیام‌ها:")
		print(f"  پردازش شده: {self.stats['messages_processed']}")
		print(f"  منتقل شده: {self.stats['messages_migrated']}")
		print(f"  رد شده: {self.stats['messages_skipped']}")
		
		print(f"\n❌ خطاها: {self.stats['errors']}")
		
		if self.stats['error_details']:
			print(f"\n📋 جزئیات خطاها (10 مورد اول):")
			for error in self.stats['error_details'][:10]:
				print(f"  - {error}")
		
		print("\n" + "="*80)
		print("انتقال کامل شد!")
		print("="*80 + "\n")
	
	def close(self):
		"""بستن اتصالات"""
		self.old_db.close()
		self.new_db.close()


def main():
	parser = argparse.ArgumentParser(description="انتقال تیکت‌های پشتیبانی از hesabixOld به hesabixpy")
	parser.add_argument("--old-db", default="hesabixOld", help="نام دیتابیس قدیمی")
	parser.add_argument("--new-db", default="hesabixpy", help="نام دیتابیس جدید")
	parser.add_argument("--user", default="root", help="نام کاربری دیتابیس")
	parser.add_argument("--password", default="136431", help="رمز دیتابیس")
	parser.add_argument("--host", default="localhost", help="هاست دیتابیس")
	parser.add_argument("--port", type=int, default=3306, help="پورت دیتابیس")
	parser.add_argument("--dry-run", action="store_true", help="حالت تست بدون اعمال تغییرات")
	
	args = parser.parse_args()
	
	migration = SupportTicketsMigration(
		old_db_name=args.old_db,
		new_db_name=args.new_db,
		db_user=args.user,
		db_password=args.password,
		db_host=args.host,
		db_port=args.port
	)
	
	try:
		migration.migrate_all(dry_run=args.dry_run)
	finally:
		migration.close()


if __name__ == "__main__":
	main()

