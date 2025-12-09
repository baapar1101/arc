#!/usr/bin/env python3
"""
اسکریپت تحلیل و بررسی جدول حساب‌ها برای انتقال از hesabixOld به hesabixpy

این اسکریپت:
- ساختار جدول hesabdari_table در دیتابیس قدیمی را بررسی می‌کند
- ساختار جدول accounts در دیتابیس جدید را بررسی می‌کند
- حساب‌های عمومی (NULL business_id) را در هر دو مقایسه می‌کند
- حساب‌های مخصوص کسب و کار را در هر دو بررسی می‌کند
- راهنمای انتقال ارائه می‌دهد
"""

import sys
import os
import argparse
from typing import List, Dict, Any, Optional, Set, Tuple
from collections import defaultdict

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session


class AccountsAnalyzer:
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
	
	def get_old_accounts_structure(self) -> Dict[str, Any]:
		"""دریافت ساختار و آمار حساب‌ها از دیتابیس قدیمی"""
		query = text("""
			SELECT 
				id, upper_id, name, type, code, entity, bid_id
			FROM hesabdari_table
			ORDER BY bid_id, id ASC
		""")
		results = self.old_db.execute(query).fetchall()
		
		accounts = []
		for row in results:
			accounts.append({
				"id": row[0],
				"parent_id": row[1],
				"name": row[2],
				"account_type": row[3],
				"code": row[4],
				"entity": row[5],
				"business_id": row[6]
			})
		
		# آمار
		public_accounts = [a for a in accounts if a["business_id"] is None]
		business_accounts = [a for a in accounts if a["business_id"] is not None]
		
		business_ids = set(a["business_id"] for a in business_accounts)
		
		stats = {
			"total": len(accounts),
			"public": len(public_accounts),
			"business": len(business_accounts),
			"business_count": len(business_ids),
			"by_type": defaultdict(int),
			"by_business": defaultdict(int)
		}
		
		for acc in accounts:
			stats["by_type"][acc["account_type"]] += 1
			if acc["business_id"]:
				stats["by_business"][acc["business_id"]] += 1
		
		return {
			"accounts": accounts,
			"stats": stats
		}
	
	def get_new_accounts_structure(self) -> Dict[str, Any]:
		"""دریافت ساختار و آمار حساب‌ها از دیتابیس جدید"""
		query = text("""
			SELECT 
				id, name, business_id, account_type, code, parent_id, created_at, updated_at
			FROM accounts
			ORDER BY business_id, id ASC
		""")
		results = self.new_db.execute(query).fetchall()
		
		accounts = []
		for row in results:
			accounts.append({
				"id": row[0],
				"name": row[1],
				"business_id": row[2],
				"account_type": row[3],
				"code": row[4],
				"parent_id": row[5],
				"created_at": row[6],
				"updated_at": row[7]
			})
		
		# آمار
		public_accounts = [a for a in accounts if a["business_id"] is None]
		business_accounts = [a for a in accounts if a["business_id"] is not None]
		
		business_ids = set(a["business_id"] for a in business_accounts)
		
		stats = {
			"total": len(accounts),
			"public": len(public_accounts),
			"business": len(business_accounts),
			"business_count": len(business_ids),
			"by_type": defaultdict(int),
			"by_business": defaultdict(int)
		}
		
		for acc in accounts:
			stats["by_type"][acc["account_type"]] += 1
			if acc["business_id"]:
				stats["by_business"][acc["business_id"]] += 1
		
		return {
			"accounts": accounts,
			"stats": stats
		}
	
	def map_old_type_to_new(self, old_type: str) -> str:
		"""نقشه‌برداری نوع حساب از قدیمی به جدید"""
		type_mapping = {
			"calc": "accounting_document",
			"bank": "bank",
			"cashdesk": "cash_register",
			"salary": "petty_cash",
			"cheque": "check",
			"person": "person",
			"commodity": "product"
		}
		return type_mapping.get(old_type, "accounting_document")
	
	def build_tree_structure(self, accounts: List[Dict[str, Any]]) -> Dict[str, Any]:
		"""ساخت ساختار درختی از لیست حساب‌ها"""
		# ساخت دیکشنری با id به عنوان کلید
		accounts_dict = {acc["id"]: acc.copy() for acc in accounts}
		
		# اضافه کردن children به هر حساب
		for acc in accounts_dict.values():
			acc["children"] = []
		
		# ساختن درخت
		roots = []
		for acc in accounts:
			if acc["parent_id"] is None:
				roots.append(accounts_dict[acc["id"]])
			else:
				parent = accounts_dict.get(acc["parent_id"])
				if parent:
					parent["children"].append(accounts_dict[acc["id"]])
				else:
					# parent وجود ندارد، پس root است
					roots.append(accounts_dict[acc["id"]])
		
		return {
			"roots": roots,
			"flat": accounts_dict
		}
	
	def find_similar_accounts_by_content(self, old_acc: Dict[str, Any], 
	                                    new_accounts: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
		"""پیدا کردن حساب‌های مشابه بر اساس محتوا (نه کد)"""
		similar = []
		new_type = self.map_old_type_to_new(old_acc["account_type"])
		
		for new_acc in new_accounts:
			# مقایسه بر اساس نام و نوع
			if (new_acc["account_type"] == new_type and 
			    new_acc["name"].strip() == old_acc["name"].strip() and
			    new_acc["business_id"] == old_acc["business_id"]):
				similar.append(new_acc)
		
		return similar
	
	def analyze_public_accounts(self, old_data: Dict, new_data: Dict) -> Dict[str, Any]:
		"""تحلیل حساب‌های عمومی"""
		old_public = [a for a in old_data["accounts"] if a["business_id"] is None]
		new_public = [a for a in new_data["accounts"] if a["business_id"] is None]
		
		# ساخت درخت
		old_tree = self.build_tree_structure(old_public)
		new_tree = self.build_tree_structure(new_public)
		
		# پیدا کردن حساب‌های مشابه بر اساس محتوا
		matched_by_content = []
		unmatched_old = []
		unmatched_new = []
		
		for old_acc in old_public:
			similar = self.find_similar_accounts_by_content(old_acc, new_public)
			if similar:
				matched_by_content.append({
					"old": old_acc,
					"new": similar
				})
			else:
				unmatched_old.append(old_acc)
		
		for new_acc in new_public:
			similar = self.find_similar_accounts_by_content(new_acc, old_public)
			if not similar:
				unmatched_new.append(new_acc)
		
		return {
			"old_count": len(old_public),
			"new_count": len(new_public),
			"matched_by_content": matched_by_content,
			"unmatched_old": unmatched_old,
			"unmatched_new": unmatched_new,
			"old_tree": old_tree,
			"new_tree": new_tree
		}
	
	def analyze_business_accounts(self, old_data: Dict, new_data: Dict) -> Dict[str, Any]:
		"""تحلیل حساب‌های مخصوص کسب و کار"""
		old_business = [a for a in old_data["accounts"] if a["business_id"] is not None]
		new_business = [a for a in new_data["accounts"] if a["business_id"] is not None]
		
		# گروه‌بندی بر اساس business_id
		old_by_business = defaultdict(list)
		new_by_business = defaultdict(list)
		
		for acc in old_business:
			old_by_business[acc["business_id"]].append(acc)
		
		for acc in new_business:
			new_by_business[acc["business_id"]].append(acc)
		
		business_analysis = {}
		all_business_ids = set(old_by_business.keys()) | set(new_by_business.keys())
		
		for bid in all_business_ids:
			old_accs = old_by_business.get(bid, [])
			new_accs = new_by_business.get(bid, [])
			
			# پیدا کردن مشابه‌ها
			matched = []
			unmatched_old = []
			
			for old_acc in old_accs:
				similar = self.find_similar_accounts_by_content(old_acc, new_accs)
				if similar:
					matched.append({"old": old_acc, "new": similar})
				else:
					unmatched_old.append(old_acc)
			
			business_analysis[bid] = {
				"old_count": len(old_accs),
				"new_count": len(new_accs),
				"matched": matched,
				"unmatched_old": unmatched_old
			}
		
		return {
			"old_count": len(old_business),
			"new_count": len(new_business),
			"old_business_count": len(old_by_business),
			"new_business_count": len(new_by_business),
			"by_business": business_analysis
		}
	
	def print_tree(self, node: Dict[str, Any], level: int = 0, max_level: int = 3):
		"""چاپ درخت به صورت بازگشتی"""
		if level > max_level:
			return
		
		indent = "  " * level
		print(f"{indent}├─ {node['code']:10s} | {node['name']:50s} | {node['account_type']:20s}")
		
		for child in node.get("children", [])[:5]:  # فقط 5 فرزند اول
			self.print_tree(child, level + 1, max_level)
		
		if len(node.get("children", [])) > 5:
			print(f"{'  ' * (level + 1)}... ({len(node['children']) - 5} بیشتر)")
	
	def run_analysis(self):
		"""اجرای تحلیل کامل"""
		print("=" * 100)
		print("🔍 تحلیل و بررسی جدول حساب‌ها برای انتقال")
		print("=" * 100)
		
		# دریافت داده‌ها
		print("\n📊 دریافت داده‌ها از دیتابیس قدیمی...")
		old_data = self.get_old_accounts_structure()
		print(f"✅ {old_data['stats']['total']} حساب در دیتابیس قدیمی یافت شد")
		
		print("\n📊 دریافت داده‌ها از دیتابیس جدید...")
		new_data = self.get_new_accounts_structure()
		print(f"✅ {new_data['stats']['total']} حساب در دیتابیس جدید یافت شد")
		
		# آمار کلی
		print("\n" + "=" * 100)
		print("📈 آمار کلی")
		print("=" * 100)
		print(f"\n🔹 دیتابیس قدیمی (hesabdari_table):")
		print(f"   - تعداد کل حساب‌ها: {old_data['stats']['total']}")
		print(f"   - حساب‌های عمومی (bid_id IS NULL): {old_data['stats']['public']}")
		print(f"   - حساب‌های مخصوص کسب و کار: {old_data['stats']['business']}")
		print(f"   - تعداد کسب و کارهای دارای حساب: {old_data['stats']['business_count']}")
		print(f"\n   توزیع بر اساس نوع:")
		for acc_type, count in sorted(old_data['stats']['by_type'].items()):
			print(f"     - {acc_type:15s}: {count:4d}")
		
		print(f"\n🔹 دیتابیس جدید (accounts):")
		print(f"   - تعداد کل حساب‌ها: {new_data['stats']['total']}")
		print(f"   - حساب‌های عمومی (business_id IS NULL): {new_data['stats']['public']}")
		print(f"   - حساب‌های مخصوص کسب و کار: {new_data['stats']['business']}")
		print(f"   - تعداد کسب و کارهای دارای حساب: {new_data['stats']['business_count']}")
		print(f"\n   توزیع بر اساس نوع:")
		for acc_type, count in sorted(new_data['stats']['by_type'].items()):
			print(f"     - {acc_type:15s}: {count:4d}")
		
		# تحلیل حساب‌های عمومی
		print("\n" + "=" * 100)
		print("🌐 تحلیل حساب‌های عمومی")
		print("=" * 100)
		public_analysis = self.analyze_public_accounts(old_data, new_data)
		
		print(f"\n📊 آمار حساب‌های عمومی:")
		print(f"   - دیتابیس قدیمی: {public_analysis['old_count']} حساب")
		print(f"   - دیتابیس جدید: {public_analysis['new_count']} حساب")
		print(f"   - حساب‌های مشابه (بر اساس نام و نوع): {len(public_analysis['matched_by_content'])}")
		print(f"   - حساب‌های قدیمی بدون مشابه: {len(public_analysis['unmatched_old'])}")
		print(f"   - حساب‌های جدید بدون مشابه: {len(public_analysis['unmatched_new'])}")
		
		# نمایش نمونه حساب‌های مشابه
		if public_analysis['matched_by_content']:
			print(f"\n✅ نمونه حساب‌های مشابه (نام و نوع یکسان، کد متفاوت):")
			for i, match in enumerate(public_analysis['matched_by_content'][:5]):
				old = match['old']
				new_list = match['new']
				for new in new_list[:1]:  # فقط اولین مشابه
					print(f"   {i+1}. نام: '{old['name']}' | نوع قدیمی: {old['account_type']:10s} -> نوع جدید: {new['account_type']:20s}")
					print(f"      کد قدیمی: {old['code']:10s} | کد جدید: {new['code']:10s}")
		
		# نمایش حساب‌های قدیمی بدون مشابه
		if public_analysis['unmatched_old']:
			print(f"\n⚠️  نمونه حساب‌های عمومی قدیمی که در دیتابیس جدید مشابه ندارند:")
			for i, acc in enumerate(public_analysis['unmatched_old'][:10]):
				print(f"   {i+1}. کد: {acc['code']:10s} | نام: {acc['name']:50s} | نوع: {acc['account_type']:10s}")
		
		# نمایش ساختار درختی (نمونه)
		print(f"\n🌳 ساختار درختی حساب‌های عمومی - دیتابیس قدیمی (نمونه):")
		for root in public_analysis['old_tree']['roots'][:3]:
			self.print_tree(root, max_level=2)
		
		print(f"\n🌳 ساختار درختی حساب‌های عمومی - دیتابیس جدید (نمونه):")
		for root in public_analysis['new_tree']['roots'][:3]:
			self.print_tree(root, max_level=2)
		
		# تحلیل حساب‌های مخصوص کسب و کار
		print("\n" + "=" * 100)
		print("🏢 تحلیل حساب‌های مخصوص کسب و کار")
		print("=" * 100)
		business_analysis = self.analyze_business_accounts(old_data, new_data)
		
		print(f"\n📊 آمار حساب‌های مخصوص کسب و کار:")
		print(f"   - دیتابیس قدیمی: {business_analysis['old_count']} حساب در {business_analysis['old_business_count']} کسب و کار")
		print(f"   - دیتابیس جدید: {business_analysis['new_count']} حساب در {business_analysis['new_business_count']} کسب و کار")
		
		# نمایش آمار برای هر کسب و کار
		print(f"\n📋 جزئیات بر اساس کسب و کار:")
		for bid, analysis in sorted(business_analysis['by_business'].items())[:10]:
			print(f"\n   🔹 Business ID: {bid}")
			print(f"      - حساب‌های قدیمی: {analysis['old_count']}")
			print(f"      - حساب‌های جدید: {analysis['new_count']}")
			print(f"      - حساب‌های مشابه: {len(analysis['matched'])}")
			print(f"      - حساب‌های قدیمی بدون مشابه: {len(analysis['unmatched_old'])}")
		
		# راهنمای انتقال
		print("\n" + "=" * 100)
		print("📝 راهنمای انتقال")
		print("=" * 100)
		
		print("""
🔹 نکات مهم برای انتقال:

1. حساب‌های عمومی:
   - در حال حاضر {old_public} حساب عمومی در دیتابیس قدیمی وجود دارد
   - در دیتابیس جدید {new_public} حساب عمومی وجود دارد
   - باید بررسی شود که آیا حساب‌های عمومی قدیمی باید به دیتابیس جدید منتقل شوند یا نه
   - چون کد حساب‌ها متفاوت است، باید از نام و نوع برای تطبیق استفاده شود
   - بهتر است قبل از انتقال، حساب‌های عمومی جدید را بررسی کنیم تا از تکرار جلوگیری شود

2. حساب‌های مخصوص کسب و کار:
   - هر کسب و کار ممکن است ساختار حساب‌های متفاوتی داشته باشد
   - باید business_id قدیمی به business_id جدید نگاشت شود
   - قبل از انتقال، باید business_id های منتقل شده را بررسی کنیم
   - حساب‌های مخصوص کسب و کار باید فقط برای کسب و کارهای منتقل شده منتقل شوند

3. نگاشت نوع حساب:
   - calc -> accounting_document
   - bank -> bank
   - cashdesk -> cash_register
   - salary -> petty_cash
   - cheque -> check
   - person -> person
   - commodity -> product

4. ساختار درختی:
   - در دیتابیس قدیمی: upper_id برای parent
   - در دیتابیس جدید: parent_id برای parent
   - باید ساختار درختی حفظ شود
   - هنگام انتقال، باید parent_id جدید را بر اساس mapping محاسبه کنیم

5. بررسی تکراری:
   - قبل از درج، باید بررسی کنیم که آیا حساب با همان نام و نوع و business_id وجود دارد یا نه
   - اگر وجود داشت، نباید دوباره اضافه کنیم
   - بهتر است از name + account_type + business_id به عنوان unique identifier استفاده کنیم

6. پیشنهاد:
   - ابتدا حساب‌های عمومی را بررسی و تطبیق دهیم
   - سپس برای هر کسب و کار منتقل شده، حساب‌های مخصوص آن را منتقل کنیم
   - از business_id mapping استفاده کنیم تا business_id قدیمی به جدید تبدیل شود
   - قبل از انتقال، backup بگیریم
   - از transaction استفاده کنیم تا در صورت خطا، rollback شود
		""".format(
			old_public=public_analysis['old_count'],
			new_public=public_analysis['new_count']
		))
		
		print("\n" + "=" * 100)
		print("✅ تحلیل کامل شد")
		print("=" * 100)
		
		return {
			"old_data": old_data,
			"new_data": new_data,
			"public_analysis": public_analysis,
			"business_analysis": business_analysis
		}
	
	def close(self):
		"""بستن اتصالات"""
		self.old_db.close()
		self.new_db.close()


def main():
	parser = argparse.ArgumentParser(description="تحلیل و بررسی جدول حساب‌ها برای انتقال")
	parser.add_argument("--old-db", default="hesabixOld", help="نام دیتابیس قدیمی")
	parser.add_argument("--new-db", default="hesabixpy", help="نام دیتابیس جدید")
	parser.add_argument("--db-user", default="root", help="نام کاربری دیتابیس")
	parser.add_argument("--db-password", default="136431", help="رمز عبور دیتابیس")
	parser.add_argument("--db-host", default="localhost", help="آدرس دیتابیس")
	parser.add_argument("--db-port", type=int, default=3306, help="پورت دیتابیس")
	
	args = parser.parse_args()
	
	analyzer = AccountsAnalyzer(
		old_db_name=args.old_db,
		new_db_name=args.new_db,
		db_user=args.db_user,
		db_password=args.db_password,
		db_host=args.db_host,
		db_port=args.db_port
	)
	
	try:
		analyzer.run_analysis()
	finally:
		analyzer.close()


if __name__ == "__main__":
	main()

