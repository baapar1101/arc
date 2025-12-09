#!/usr/bin/env python3
"""
اسکریپت انتقال اشخاص از hesabixOld به hesabixpy

این اسکریپت:
- اشخاص را از hesabixOld منتقل می‌کند
- person_types را از جدول person_person_type به JSON array تبدیل می‌کند
- نام را به first_name و last_name تقسیم می‌کند
"""

import sys
import os
import argparse
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime
import json

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session


def split_name(name: str | None) -> Tuple[str | None, str | None]:
	"""
	تبدیل name به first_name و last_name
	
	Args:
		name: نام کامل (مثل "علی زیوری" یا "صادق احمدیان")
	
	Returns:
		(first_name, last_name)
	"""
	if not name or not name.strip():
		return (None, None)
	
	name = name.strip()
	parts = name.split()
	
	if len(parts) == 0:
		return (None, None)
	elif len(parts) == 1:
		return (parts[0], None)
	else:
		# اولین کلمه = نام، بقیه = نام خانوادگی
		first_name = parts[0]
		last_name = ' '.join(parts[1:])
		return (first_name, last_name)


def get_alias_name(nikename: str | None, name: str | None) -> str:
	"""
	دریافت alias_name از nikename یا name
	
	Args:
		nikename: نام مستعار
		name: نام کامل
	
	Returns:
		alias_name (الزامی)
	"""
	if nikename and nikename.strip():
		return nikename.strip()
	elif name and name.strip():
		return name.strip()
	else:
		# اگر هیچکدام نبود، از "شخص بدون نام" استفاده می‌کنیم
		return "شخص بدون نام"


def convert_code(code: int | None) -> int | None:
	"""تبدیل code از bigint به integer (با بررسی محدوده)"""
	if code is None:
		return None
	
	# محدود کردن به محدوده integer
	if code > 2147483647:
		return None  # خارج از محدوده
	
	return int(code)


def get_person_types(old_person_id: int, person_type_mapping: Dict[int, str], old_db: Session) -> List[str]:
	"""
	دریافت انواع شخص از دیتابیس قدیمی
	
	Args:
		old_person_id: شناسه شخص قدیمی
		person_type_mapping: mapping {person_type_id: label}
		old_db: session دیتابیس قدیمی
	
	Returns:
		لیست انواع شخص (مثل ["مشتری", "تامین‌کننده"])
	"""
	query = text("""
		SELECT person_type_id
		FROM hesabixOld.person_person_type
		WHERE person_id = :person_id
	""")
	results = old_db.execute(query, {"person_id": old_person_id}).fetchall()
	
	types = []
	for row in results:
		type_label = person_type_mapping.get(row.person_type_id)
		if type_label:
			types.append(type_label)
	
	# اگر نوعی نداشت، پیش‌فرض مشتری
	if not types:
		types = ["مشتری"]
	
	return types


def convert_person_types_to_json(types: List[str]) -> str:
	"""تبدیل لیست انواع به JSON"""
	return json.dumps(types, ensure_ascii=False)


class PersonMigration:
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
			"persons_processed": 0,
			"persons_migrated": 0,
			"persons_skipped": 0,
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
	
	def create_person_type_mapping(self) -> Dict[int, str]:
		"""ایجاد mapping بین person_type_id و person_type label"""
		query = text("SELECT id, label FROM hesabixOld.person_type")
		results = self.old_db.execute(query).fetchall()
		
		mapping = {}
		for row in results:
			mapping[row.id] = row.label
		
		print(f"✅ Person type mapping ایجاد شد: {len(mapping)} نوع")
		return mapping
	
	def migrate_person(self, old_person: Dict[str, Any], business_id_mapping: Dict[int, int],
	                 person_type_mapping: Dict[int, str]) -> Optional[int]:
		"""انتقال یک شخص"""
		try:
			# نگاشت business_id
			old_business_id = old_person.get('bid_id')
			new_business_id = business_id_mapping.get(old_business_id)
			
			if not new_business_id:
				self.stats["persons_skipped"] += 1
				return None
			
			# تبدیل code
			old_code = old_person.get('code')
			new_code = convert_code(old_code)
			
			# بررسی وجود در دیتابیس جدید
			if new_code is not None:
				query = text("""
					SELECT COUNT(*) FROM persons
					WHERE business_id = :business_id AND code = :code
				""")
				result = self.new_db.execute(query, {
					"business_id": new_business_id,
					"code": new_code
				}).scalar()
				
				if result > 0:
					self.stats["persons_skipped"] += 1
					return None
			
			# تبدیل alias_name
			alias_name = get_alias_name(
				old_person.get('nikename'),
				old_person.get('name')
			)
			
			# تقسیم name به first_name و last_name
			first_name, last_name = split_name(old_person.get('name'))
			
			# تبدیل person_types
			old_person_id = old_person.get('id')
			person_types_list = get_person_types(old_person_id, person_type_mapping, self.old_db)
			person_types_json = convert_person_types_to_json(person_types_list)
			
			# درج شخص
			query = text("""
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
			
			# محدود کردن national_id به 20 کاراکتر
			national_id = old_person.get('shenasemeli')
			if national_id and len(str(national_id)) > 20:
				national_id = None  # اگر خیلی طولانی است، NULL می‌کنیم
			
			# محدود کردن سایر فیلدها به طول مجاز
			registration_number = old_person.get('sabt')
			if registration_number and len(str(registration_number)) > 50:
				registration_number = str(registration_number)[:50]
			
			economic_id = old_person.get('codeeghtesadi')
			if economic_id and len(str(economic_id)) > 50:
				economic_id = str(economic_id)[:50]
			
			postal_code = old_person.get('postalcode')
			if postal_code and len(str(postal_code)) > 20:
				postal_code = str(postal_code)[:20]
			
			self.new_db.execute(query, {
				"business_id": new_business_id,
				"code": new_code,
				"alias_name": alias_name,
				"first_name": first_name,
				"last_name": last_name,
				"person_types": person_types_json,
				"company_name": old_person.get('company'),
				"payment_id": old_person.get('payment_id'),
				"national_id": national_id,
				"registration_number": registration_number,
				"economic_id": economic_id,
				"country": old_person.get('keshvar'),
				"province": old_person.get('ostan'),
				"city": old_person.get('shahr'),
				"address": old_person.get('address'),
				"postal_code": postal_code,
				"phone": old_person.get('tel'),
				"mobile": old_person.get('mobile'),
				"fax": old_person.get('fax'),
				"email": old_person.get('email'),
				"website": old_person.get('website'),
				"created_at": datetime.utcnow(),
				"updated_at": datetime.utcnow()
			})
			
			self.new_db.commit()
			
			# دریافت new_person_id
			if new_code is not None:
				query = text("""
					SELECT id FROM persons
					WHERE business_id = :business_id AND code = :code
					LIMIT 1
				""")
				result = self.new_db.execute(query, {
					"business_id": new_business_id,
					"code": new_code
				}).fetchone()
			else:
				# اگر code نداشت، از alias_name استفاده می‌کنیم
				query = text("""
					SELECT id FROM persons
					WHERE business_id = :business_id AND alias_name = :alias_name
					ORDER BY id DESC
					LIMIT 1
				""")
				result = self.new_db.execute(query, {
					"business_id": new_business_id,
					"alias_name": alias_name
				}).fetchone()
			
			if result:
				self.stats["persons_migrated"] += 1
				return result[0]
			else:
				raise Exception("Failed to get new person ID after insert")
		
		except Exception as e:
			self.new_db.rollback()
			self.stats["errors"] += 1
			self.stats["error_details"].append({
				"old_person_id": old_person.get('id'),
				"old_business_id": old_person.get('bid_id'),
				"code": old_person.get('code'),
				"alias_name": old_person.get('nikename') or old_person.get('name'),
				"error": str(e)
			})
			return None
	
	def get_old_persons(self, start_id: Optional[int] = None, limit: Optional[int] = None,
	                   business_ids: Optional[List[int]] = None) -> List[Dict[str, Any]]:
		"""دریافت اشخاص از دیتابیس قدیمی"""
		query = f"""
			SELECT 
				id, bid_id, code, nikename, name,
				tel, mobile, mobile2, address, des,
				company, shenasemeli, codeeghtesadi, sabt,
				keshvar, ostan, shahr, postalcode,
				email, website, fax, birthday, payment_id
			FROM {self.old_db_name}.person
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
		
		persons = []
		for row in results:
			persons.append({
				"id": row[0],
				"bid_id": row[1],
				"code": row[2],
				"nikename": row[3],
				"name": row[4],
				"tel": row[5],
				"mobile": row[6],
				"mobile2": row[7],
				"address": row[8],
				"des": row[9],
				"company": row[10],
				"shenasemeli": row[11],
				"codeeghtesadi": row[12],
				"sabt": row[13],
				"keshvar": row[14],
				"ostan": row[15],
				"shahr": row[16],
				"postalcode": row[17],
				"email": row[18],
				"website": row[19],
				"fax": row[20],
				"birthday": row[21],
				"payment_id": row[22]
			})
		
		return persons
	
	def run_migration(self, dry_run: bool = False, batch_size: int = 500,
	                 start_id: Optional[int] = None, limit: Optional[int] = None):
		"""اجرای انتقال"""
		print(f"{'='*60}")
		print(f"شروع انتقال اشخاص")
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
		person_type_mapping = self.create_person_type_mapping()
		
		# دریافت کسب و کارهای منتقل شده
		old_business_ids = list(business_id_mapping.keys())
		
		if not old_business_ids:
			print("هیچ کسب و کاری برای انتقال یافت نشد.")
			return
		
		# دریافت اشخاص
		old_persons = self.get_old_persons(
			start_id=start_id,
			limit=limit,
			business_ids=old_business_ids
		)
		total_persons = len(old_persons)
		print(f"تعداد اشخاص برای انتقال: {total_persons}\n")
		
		if total_persons == 0:
			print("هیچ شخصی برای انتقال یافت نشد.")
			return
		
		# پردازش batch به batch
		for i in range(0, total_persons, batch_size):
			batch = old_persons[i:i+batch_size]
			batch_num = (i // batch_size) + 1
			total_batches = (total_persons + batch_size - 1) // batch_size
			
			print(f"\nپردازش batch {batch_num}/{total_batches} ({len(batch)} شخص)...")
			
			for old_person in batch:
				self.stats["persons_processed"] += 1
				
				if not dry_run:
					self.migrate_person(
						old_person, business_id_mapping, person_type_mapping
					)
				else:
					# در حالت dry-run فقط بررسی می‌کنیم
					old_business_id = old_person.get('bid_id')
					if old_business_id in business_id_mapping:
						self.stats["persons_migrated"] += 1
					else:
						self.stats["persons_skipped"] += 1
				
				if self.stats["persons_processed"] % 50 == 0:
					print(f"  پردازش شده: {self.stats['persons_processed']}/{total_persons}", end='\r')
			
			print(f"\n  Batch {batch_num} تکمیل شد")
		
		# نمایش آمار نهایی
		print(f"\n{'='*60}")
		print("آمار نهایی:")
		print(f"{'='*60}")
		print(f"اشخاص:")
		print(f"  پردازش شده: {self.stats['persons_processed']}")
		print(f"  منتقل شده: {self.stats['persons_migrated']}")
		print(f"  رد شده: {self.stats['persons_skipped']}")
		print(f"\nخطاها: {self.stats['errors']}")
		
		if self.stats['error_details']:
			print(f"\nجزئیات خطاها:")
			for error in self.stats['error_details'][:10]:
				print(f"  - Person ID {error.get('old_person_id')} (Code: {error.get('code')}, Alias: {error.get('alias_name')}): {error.get('error')}")
			if len(self.stats['error_details']) > 10:
				print(f"  ... و {len(self.stats['error_details']) - 10} خطای دیگر")
	
	def close(self):
		"""بستن اتصالات"""
		self.old_db.close()
		self.new_db.close()


def main():
	parser = argparse.ArgumentParser(description="انتقال اشخاص")
	parser.add_argument("--dry-run", action="store_true", help="اجرای تست بدون تغییر در دیتابیس")
	parser.add_argument("--batch-size", type=int, default=500, help="تعداد اشخاص در هر batch")
	parser.add_argument("--start-id", type=int, help="شروع از شناسه خاص")
	parser.add_argument("--limit", type=int, help="محدود کردن تعداد اشخاص")
	parser.add_argument("--old-db", default="hesabixOld", help="نام دیتابیس قدیمی")
	parser.add_argument("--new-db", default="hesabixpy", help="نام دیتابیس جدید")
	parser.add_argument("--db-user", default="root", help="نام کاربری دیتابیس")
	parser.add_argument("--db-password", default="136431", help="رمز عبور دیتابیس")
	parser.add_argument("--db-host", default="localhost", help="آدرس دیتابیس")
	parser.add_argument("--db-port", type=int, default=3306, help="پورت دیتابیس")
	
	args = parser.parse_args()
	
	migration = PersonMigration(
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

