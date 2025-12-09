#!/usr/bin/env python3
"""
اسکریپت ایجاد پیام اولیه برای تیکت‌هایی که پیام اولیه ندارند

این اسکریپت:
- تیکت‌هایی که پیام اولیه ندارند را پیدا می‌کند
- برای هر تیکت یک پیام اولیه با محتوای description تیکت ایجاد می‌کند
- sender_id را user_id تیکت قرار می‌دهد
- sender_type را "user" قرار می‌دهد
- created_at را created_at تیکت قرار می‌دهد
"""

import sys
import os
import argparse

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from datetime import datetime


class InitialMessageCreator:
	def __init__(self, db_name: str = "hesabixpy",
	             db_user: str = "root", db_password: str = "136431",
	             db_host: str = "localhost", db_port: int = 3306):
		"""ایجاد اتصال به دیتابیس"""
		dsn = f"mysql+pymysql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}"
		engine = create_engine(
			dsn, 
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
		self.db = sessionmaker(bind=engine)()
		
		# آمار
		self.stats = {
			"tickets_processed": 0,
			"messages_created": 0,
			"errors": 0,
			"error_details": []
		}
	
	def find_tickets_without_initial_message(self) -> list:
		"""پیدا کردن تیکت‌هایی که پیام اولیه ندارند"""
		# تیکت‌هایی که اصلاً پیامی ندارند
		# یا تیکت‌هایی که اولین پیامشان از کاربر نیست یا تاریخ اولین پیام بعد از ایجاد تیکت است
		query = text("""
			SELECT t.id, t.user_id, t.description, t.created_at
			FROM support_tickets t
			LEFT JOIN (
				SELECT ticket_id, MIN(created_at) as first_message_date,
					   (SELECT sender_id FROM support_messages sm 
					    WHERE sm.ticket_id = support_messages.ticket_id 
					    ORDER BY sm.created_at ASC LIMIT 1) as first_sender_id
				FROM support_messages
				GROUP BY ticket_id
			) m ON t.id = m.ticket_id
			WHERE m.ticket_id IS NULL 
			   OR (m.first_message_date > t.created_at)
			   OR (m.first_message_date = t.created_at AND m.first_sender_id != t.user_id)
			ORDER BY t.id
		""")
		
		results = self.db.execute(query).fetchall()
		tickets = []
		for row in results:
			tickets.append({
				"id": row[0],
				"user_id": row[1],
				"description": row[2] or "",
				"created_at": row[3]
			})
		
		return tickets
	
	def create_initial_message(self, ticket: dict) -> bool:
		"""ایجاد پیام اولیه برای یک تیکت"""
		try:
			# بررسی اینکه آیا پیام اولیه از قبل وجود دارد
			# پیام اولیه باید sender_id = user_id و created_at = created_at تیکت باشد
			existing_initial = self.db.execute(
				text("""
					SELECT id FROM support_messages 
					WHERE ticket_id = :ticket_id 
					  AND sender_id = :user_id
					  AND created_at = :created_at
					LIMIT 1
				"""),
				{
					"ticket_id": ticket["id"],
					"user_id": ticket["user_id"],
					"created_at": ticket["created_at"]
				}
			).fetchone()
			
			if existing_initial:
				# پیام اولیه از قبل وجود دارد، skip می‌کنیم
				return False
			
			# ایجاد پیام اولیه
			self.db.execute(text("""
				INSERT INTO support_messages (
					ticket_id, sender_id, sender_type, content, is_internal, created_at
				) VALUES (
					:ticket_id, :sender_id, :sender_type, :content, :is_internal, :created_at
				)
			"""), {
				"ticket_id": ticket["id"],
				"sender_id": ticket["user_id"],
				"sender_type": "user",
				"content": ticket["description"],
				"is_internal": False,
				"created_at": ticket["created_at"]
			})
			
			self.db.commit()
			return True
			
		except Exception as e:
			self.db.rollback()
			self.stats["errors"] += 1
			self.stats["error_details"].append({
				"ticket_id": ticket["id"],
				"error": str(e)
			})
			return False
	
	def run(self, dry_run: bool = False):
		"""اجرای اسکریپت"""
		print("\n" + "="*80)
		print("ایجاد پیام اولیه برای تیکت‌ها")
		print("="*80)
		
		if dry_run:
			print("\n⚠ حالت DRY RUN - هیچ تغییری اعمال نخواهد شد")
		
		# پیدا کردن تیکت‌هایی که پیام اولیه ندارند
		print("\n📋 در حال پیدا کردن تیکت‌هایی که پیام اولیه ندارند...")
		tickets = self.find_tickets_without_initial_message()
		print(f"✅ {len(tickets)} تیکت پیدا شد")
		
		if not tickets:
			print("\n✅ همه تیکت‌ها پیام اولیه دارند!")
			return
		
		# ایجاد پیام اولیه برای هر تیکت
		print("\n📤 شروع ایجاد پیام‌های اولیه...")
		for i, ticket in enumerate(tickets, 1):
			self.stats["tickets_processed"] += 1
			
			if i % 100 == 0:
				print(f"  در حال پردازش تیکت {i}/{len(tickets)}...")
			
			if not dry_run:
				if self.create_initial_message(ticket):
					self.stats["messages_created"] += 1
		
		# نمایش آمار نهایی
		self.print_stats()
	
	def print_stats(self):
		"""نمایش آمار نهایی"""
		print("\n" + "="*80)
		print("آمار نهایی")
		print("="*80)
		
		print(f"\n📊 تیکت‌ها:")
		print(f"  پردازش شده: {self.stats['tickets_processed']}")
		print(f"  پیام‌های ایجاد شده: {self.stats['messages_created']}")
		print(f"  خطاها: {self.stats['errors']}")
		
		if self.stats['error_details']:
			print(f"\n📋 جزئیات خطاها (10 مورد اول):")
			for error in self.stats['error_details'][:10]:
				print(f"  - تیکت id={error['ticket_id']}: {error['error']}")
		
		print("\n" + "="*80)
		print("پردازش کامل شد!")
		print("="*80 + "\n")
	
	def close(self):
		"""بستن اتصال"""
		self.db.close()


def main():
	parser = argparse.ArgumentParser(description="ایجاد پیام اولیه برای تیکت‌هایی که پیام اولیه ندارند")
	parser.add_argument("--db", default="hesabixpy", help="نام دیتابیس")
	parser.add_argument("--user", default="root", help="نام کاربری دیتابیس")
	parser.add_argument("--password", default="136431", help="رمز دیتابیس")
	parser.add_argument("--host", default="localhost", help="هاست دیتابیس")
	parser.add_argument("--port", type=int, default=3306, help="پورت دیتابیس")
	parser.add_argument("--dry-run", action="store_true", help="حالت تست بدون اعمال تغییرات")
	
	args = parser.parse_args()
	
	creator = InitialMessageCreator(
		db_name=args.db,
		db_user=args.user,
		db_password=args.password,
		db_host=args.host,
		db_port=args.port
	)
	
	try:
		creator.run(dry_run=args.dry_run)
	finally:
		creator.close()


if __name__ == "__main__":
	main()

