#!/usr/bin/env python3
"""
اسکریپت انتقال کالا و خدمات از hesabixOld به hesabixpy

این اسکریپت:
- دسته‌بندی‌ها را ایجاد/نگاشت می‌کند
- واحدها را نگاشت می‌کند
- کالا/خدمات را منتقل می‌کند
"""

import sys
import os
import argparse
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime
from decimal import Decimal, InvalidOperation
import json

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session


def convert_price(price_str: str | None) -> Decimal | None:
	"""تبدیل قیمت از varchar به decimal"""
	if not price_str or not price_str.strip():
		return None
	
	try:
		# حذف فاصله و کاما
		cleaned = price_str.strip().replace(',', '').replace(' ', '').replace('،', '')
		if not cleaned or cleaned == '0' or cleaned == '':
			return None
		return Decimal(cleaned)
	except (ValueError, InvalidOperation, TypeError):
		return None


def convert_khadamat_to_item_type(khadamat: int | None) -> str:
	"""تبدیل khadamat به item_type"""
	if khadamat == 1:
		return "خدمت"
	return "کالا"  # پیش‌فرض برای 0 و NULL


def convert_order_point(order_point: str | None) -> int | None:
	"""تبدیل order_point به integer (محدود به محدوده integer)"""
	if not order_point or not order_point.strip():
		return None
	try:
		value = int(float(order_point.strip()))
		# محدود کردن به محدوده integer (MAX_INT = 2147483647)
		if value > 2147483647:
			return None
		if value < -2147483648:
			return None
		return value
	except (ValueError, TypeError, OverflowError):
		return None


def convert_track_inventory(check: int | None) -> bool:
	"""تبدیل commodity_count_check به track_inventory"""
	return bool(check) if check is not None else False


def convert_taxable(without_tax: int | None) -> Tuple[bool, bool]:
	"""تبدیل without_tax به is_sales_taxable و is_purchase_taxable"""
	if without_tax == 1:
		return (False, False)  # بدون مالیات
	return (True, True)  # با مالیات (پیش‌فرض)


class ProductMigration:
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
			"products_processed": 0,
			"products_migrated": 0,
			"products_skipped": 0,
			"categories_created": 0,
			"categories_mapped": 0,
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
	
	def create_unit_mapping(self) -> Dict[int, str]:
		"""ایجاد mapping بین unit_id و unit name"""
		query = text("SELECT id, name FROM hesabixOld.commodity_unit")
		results = self.old_db.execute(query).fetchall()
		
		mapping = {}
		for row in results:
			mapping[row.id] = row.name
		
		print(f"✅ Unit mapping ایجاد شد: {len(mapping)} واحد")
		return mapping
	
	def get_or_create_category(self, old_cat_id: int | None, old_cat_name: str | None,
	                           new_business_id: int, category_mapping: Dict[Tuple[int, int], int]) -> int | None:
		"""
		دریافت یا ایجاد دسته‌بندی
		
		Args:
			old_cat_id: شناسه دسته‌بندی قدیمی
			old_cat_name: نام دسته‌بندی قدیمی
			new_business_id: شناسه کسب و کار جدید
			category_mapping: mapping {(old_business_id, old_cat_id): new_cat_id}
		
		Returns:
			شناسه دسته‌بندی جدید یا None
		"""
		if not old_cat_id or not old_cat_name:
			return None
		
		# بررسی mapping
		key = (new_business_id, old_cat_id)
		if key in category_mapping:
			self.stats["categories_mapped"] += 1
			return category_mapping[key]
		
		# جستجو در دیتابیس جدید
		query = text("""
			SELECT id FROM categories
			WHERE business_id = :business_id
			AND JSON_EXTRACT(title_translations, '$.fa') = :name
			LIMIT 1
		""")
		result = self.new_db.execute(query, {
			"business_id": new_business_id,
			"name": old_cat_name
		}).fetchone()
		
		if result:
			category_mapping[key] = result[0]
			self.stats["categories_mapped"] += 1
			return result[0]
		
		# ایجاد دسته‌بندی جدید
		title_translations = json.dumps({"fa": old_cat_name, "en": old_cat_name})
		query = text("""
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
		
		self.new_db.execute(query, {
			"business_id": new_business_id,
			"title_translations": title_translations,
			"created_at": datetime.utcnow(),
			"updated_at": datetime.utcnow()
		})
		self.new_db.commit()
		
		# دریافت شناسه جدید
		query = text("""
			SELECT id FROM categories
			WHERE business_id = :business_id
			AND JSON_EXTRACT(title_translations, '$.fa') = :name
			LIMIT 1
		""")
		result = self.new_db.execute(query, {
			"business_id": new_business_id,
			"name": old_cat_name
		}).fetchone()
		
		if result:
			category_mapping[key] = result[0]
			self.stats["categories_created"] += 1
			return result[0]
		
		return None
	
	def migrate_product(self, old_product: Dict[str, Any], business_id_mapping: Dict[int, int],
	                   unit_mapping: Dict[int, str], category_mapping: Dict[Tuple[int, int], int]) -> Optional[int]:
		"""انتقال یک کالا/خدمت"""
		try:
			# نگاشت business_id
			old_business_id = old_product.get('bid_id')
			new_business_id = business_id_mapping.get(old_business_id)
			
			if not new_business_id:
				self.stats["products_skipped"] += 1
				return None
			
			# بررسی وجود در دیتابیس جدید
			query = text("""
				SELECT COUNT(*) FROM products
				WHERE business_id = :business_id AND code = :code
			""")
			result = self.new_db.execute(query, {
				"business_id": new_business_id,
				"code": str(old_product.get('code', ''))
			}).scalar()
			
			if result > 0:
				self.stats["products_skipped"] += 1
				return None
			
			# تبدیل داده‌ها
			item_type = convert_khadamat_to_item_type(old_product.get('khadamat'))
			
			# تبدیل قیمت‌ها
			base_purchase_price = convert_price(old_product.get('price_buy'))
			base_sales_price = convert_price(old_product.get('price_sell'))
			
			# نگاشت category_id
			old_cat_id = old_product.get('cat_id')
			old_cat_name = old_product.get('cat_name')
			category_id = self.get_or_create_category(
				old_cat_id, old_cat_name, new_business_id, category_mapping
			)
			
			# نگاشت unit_id به main_unit
			old_unit_id = old_product.get('unit_id')
			main_unit = unit_mapping.get(old_unit_id) if old_unit_id else None
			
			# تبدیل سایر فیلدها
			reorder_point = convert_order_point(old_product.get('order_point'))
			track_inventory = convert_track_inventory(old_product.get('commodity_count_check'))
			min_order_qty = convert_order_point(old_product.get('min_order_count'))
			lead_time_days = convert_order_point(old_product.get('day_loading'))
			
			# تبدیل مالیات
			is_sales_taxable, is_purchase_taxable = convert_taxable(old_product.get('without_tax'))
			
			# درج کالا/خدمت
			query = text("""
				INSERT INTO products (
					business_id, item_type, code, name, description,
					category_id, main_unit,
					base_sales_price, base_purchase_price,
					track_inventory, reorder_point, min_order_qty, lead_time_days,
					is_sales_taxable, is_purchase_taxable,
					tax_code, inventory_mode,
					track_serial, track_barcode,
					created_at, updated_at
				) VALUES (
					:business_id, :item_type, :code, :name, :description,
					:category_id, :main_unit,
					:base_sales_price, :base_purchase_price,
					:track_inventory, :reorder_point, :min_order_qty, :lead_time_days,
					:is_sales_taxable, :is_purchase_taxable,
					:tax_code, :inventory_mode,
					:track_serial, :track_barcode,
					:created_at, :updated_at
				)
			""")
			
			# بررسی وجود بارکد
			barcodes = old_product.get('barcodes')
			track_barcode = bool(barcodes and barcodes.strip())
			
			self.new_db.execute(query, {
				"business_id": new_business_id,
				"item_type": item_type,
				"code": str(old_product.get('code', '')),
				"name": old_product.get('name', ''),
				"description": old_product.get('des'),
				"category_id": category_id,
				"main_unit": main_unit,
				"base_sales_price": base_sales_price,
				"base_purchase_price": base_purchase_price,
				"track_inventory": track_inventory,
				"reorder_point": reorder_point,
				"min_order_qty": min_order_qty,
				"lead_time_days": lead_time_days,
				"is_sales_taxable": is_sales_taxable,
				"is_purchase_taxable": is_purchase_taxable,
				"tax_code": old_product.get('tax_code'),
				"inventory_mode": "bulk",  # پیش‌فرض
				"track_serial": False,  # پیش‌فرض
				"track_barcode": track_barcode,
				"created_at": datetime.utcnow(),
				"updated_at": datetime.utcnow()
			})
			
			self.new_db.commit()
			
			# دریافت new_product_id
			query = text("""
				SELECT id FROM products
				WHERE business_id = :business_id AND code = :code
				LIMIT 1
			""")
			result = self.new_db.execute(query, {
				"business_id": new_business_id,
				"code": str(old_product.get('code', ''))
			}).fetchone()
			
			if result:
				self.stats["products_migrated"] += 1
				return result[0]
			else:
				raise Exception("Failed to get new product ID after insert")
		
		except Exception as e:
			self.new_db.rollback()
			self.stats["errors"] += 1
			self.stats["error_details"].append({
				"old_product_id": old_product.get('id'),
				"old_business_id": old_product.get('bid_id'),
				"code": old_product.get('code'),
				"error": str(e)
			})
			return None
	
	def get_old_products(self, start_id: Optional[int] = None, limit: Optional[int] = None,
	                    business_ids: Optional[List[int]] = None) -> List[Dict[str, Any]]:
		"""دریافت کالا/خدمات از دیتابیس قدیمی"""
		query = f"""
			SELECT 
				c.id, c.bid_id, c.name, c.code, c.des,
				c.price_buy, c.price_sell, c.khadamat,
				c.cat_id, cat.name as cat_name,
				c.unit_id, c.order_point, c.commodity_count_check,
				c.min_order_count, c.day_loading, c.without_tax,
				c.tax_code, c.barcodes
			FROM {self.old_db_name}.commodity c
			LEFT JOIN {self.old_db_name}.commodity_cat cat ON c.cat_id = cat.id AND c.bid_id = cat.bid_id
			WHERE 1=1
		"""
		
		params = {}
		if business_ids:
			placeholders = ','.join([f':bid_{i}' for i in range(len(business_ids))])
			query += f" AND c.bid_id IN ({placeholders})"
			for i, bid in enumerate(business_ids):
				params[f'bid_{i}'] = bid
		elif start_id:
			query += " AND c.id >= :start_id"
			params["start_id"] = start_id
		
		query += " ORDER BY c.bid_id, c.id ASC"
		
		if limit:
			query += " LIMIT :limit"
			params["limit"] = limit
		
		results = self.old_db.execute(text(query), params).fetchall()
		
		products = []
		for row in results:
			products.append({
				"id": row[0],
				"bid_id": row[1],
				"name": row[2],
				"code": row[3],
				"des": row[4],
				"price_buy": row[5],
				"price_sell": row[6],
				"khadamat": row[7],
				"cat_id": row[8],
				"cat_name": row[9],
				"unit_id": row[10],
				"order_point": row[11],
				"commodity_count_check": row[12],
				"min_order_count": row[13],
				"day_loading": row[14],
				"without_tax": row[15],
				"tax_code": row[16],
				"barcodes": row[17]
			})
		
		return products
	
	def run_migration(self, dry_run: bool = False, batch_size: int = 500,
	                 start_id: Optional[int] = None, limit: Optional[int] = None):
		"""اجرای انتقال"""
		print(f"{'='*60}")
		print(f"شروع انتقال کالا و خدمات")
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
		unit_mapping = self.create_unit_mapping()
		
		# دریافت کسب و کارهای منتقل شده
		old_business_ids = list(business_id_mapping.keys())
		
		if not old_business_ids:
			print("هیچ کسب و کاری برای انتقال یافت نشد.")
			return
		
		# دریافت کالا/خدمات
		old_products = self.get_old_products(
			start_id=start_id,
			limit=limit,
			business_ids=old_business_ids
		)
		total_products = len(old_products)
		print(f"تعداد کالا/خدمات برای انتقال: {total_products}\n")
		
		if total_products == 0:
			print("هیچ کالا/خدماتی برای انتقال یافت نشد.")
			return
		
		# نگاشت category برای هر کسب و کار
		category_mapping: Dict[Tuple[int, int], int] = {}  # {(new_business_id, old_cat_id): new_cat_id}
		
		# پردازش batch به batch
		for i in range(0, total_products, batch_size):
			batch = old_products[i:i+batch_size]
			batch_num = (i // batch_size) + 1
			total_batches = (total_products + batch_size - 1) // batch_size
			
			print(f"\nپردازش batch {batch_num}/{total_batches} ({len(batch)} کالا/خدمت)...")
			
			for old_product in batch:
				self.stats["products_processed"] += 1
				
				if not dry_run:
					self.migrate_product(
						old_product, business_id_mapping, unit_mapping, category_mapping
					)
				else:
					# در حالت dry-run فقط بررسی می‌کنیم
					old_business_id = old_product.get('bid_id')
					if old_business_id in business_id_mapping:
						self.stats["products_migrated"] += 1
					else:
						self.stats["products_skipped"] += 1
				
				if self.stats["products_processed"] % 50 == 0:
					print(f"  پردازش شده: {self.stats['products_processed']}/{total_products}", end='\r')
			
			print(f"\n  Batch {batch_num} تکمیل شد")
		
		# نمایش آمار نهایی
		print(f"\n{'='*60}")
		print("آمار نهایی:")
		print(f"{'='*60}")
		print(f"کالا/خدمات:")
		print(f"  پردازش شده: {self.stats['products_processed']}")
		print(f"  منتقل شده: {self.stats['products_migrated']}")
		print(f"  رد شده: {self.stats['products_skipped']}")
		print(f"\nدسته‌بندی‌ها:")
		print(f"  ایجاد شده: {self.stats['categories_created']}")
		print(f"  نگاشت شده: {self.stats['categories_mapped']}")
		print(f"\nخطاها: {self.stats['errors']}")
		
		if self.stats['error_details']:
			print(f"\nجزئیات خطاها:")
			for error in self.stats['error_details'][:10]:
				print(f"  - Product ID {error.get('old_product_id')} (Code: {error.get('code')}): {error.get('error')}")
			if len(self.stats['error_details']) > 10:
				print(f"  ... و {len(self.stats['error_details']) - 10} خطای دیگر")
	
	def close(self):
		"""بستن اتصالات"""
		self.old_db.close()
		self.new_db.close()


def main():
	parser = argparse.ArgumentParser(description="انتقال کالا و خدمات")
	parser.add_argument("--dry-run", action="store_true", help="اجرای تست بدون تغییر در دیتابیس")
	parser.add_argument("--batch-size", type=int, default=500, help="تعداد کالا/خدمات در هر batch")
	parser.add_argument("--start-id", type=int, help="شروع از شناسه خاص")
	parser.add_argument("--limit", type=int, help="محدود کردن تعداد کالا/خدمات")
	parser.add_argument("--old-db", default="hesabixOld", help="نام دیتابیس قدیمی")
	parser.add_argument("--new-db", default="hesabixpy", help="نام دیتابیس جدید")
	parser.add_argument("--db-user", default="root", help="نام کاربری دیتابیس")
	parser.add_argument("--db-password", default="136431", help="رمز عبور دیتابیس")
	parser.add_argument("--db-host", default="localhost", help="آدرس دیتابیس")
	parser.add_argument("--db-port", type=int, default=3306, help="پورت دیتابیس")
	
	args = parser.parse_args()
	
	migration = ProductMigration(
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

