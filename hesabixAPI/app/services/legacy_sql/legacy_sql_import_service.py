from __future__ import annotations

import secrets
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Callable, Dict, List, Optional, Tuple

from sqlalchemy import select, and_
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.person import PersonCreateRequest, PersonType
from adapters.api.v1.schema_models.product import ProductCreateRequest
from adapters.db.models.business import Business, BusinessCurrency
from adapters.db.models.currency import Currency
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from adapters.db.models.user import User
from adapters.db.repositories.business_repo import BusinessRepository
from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository
from adapters.db.repositories.user_repo import UserRepository
from app.services.auth_service import _normalize_email, _normalize_mobile
from app.services.legacy_sql.business_purge import purge_business_operational_data
from app.services.legacy_sql.expense_income_importer import LegacyExpenseIncomeImporter
from app.services.legacy_sql.invoice_importer import LegacyInvoiceImporter
from app.services.legacy_sql.receipt_payment_importer import LegacyReceiptPaymentImporter
from app.services.legacy_sql.check_importer import LegacyCheckImporter
from app.services.legacy_sql.opening_balance_importer import LegacyOpeningBalanceImporter
from app.services.legacy_sql.transfer_importer import LegacyTransferImporter
from app.services.legacy_sql.warehouse_importer import LegacyWarehouseImporter
from app.services.legacy_sql.mappers import (
	convert_timestamp_to_datetime,
	map_business_field,
	map_business_type,
	split_full_name,
	unix_ts_to_date,
)
from app.services.legacy_sql.hs60_loader import LegacyImportFileError, materialize_legacy_sql_path
from app.services.legacy_sql.sql_dump_reader import (
	LegacySqlData,
	load_legacy_sql_dump,
	validate_legacy_dump,
)
from app.services.person_service import create_person
from app.services.product_service import create_product


ProgressCb = Optional[Callable[[int, str], None]]


LEGACY_REWRITE_CONFIRMATION_FA = "بازنویسی"
LEGACY_REWRITE_CONFIRMATION_EN = "REWRITE"


@dataclass
class LegacyImportOptions:
	import_mode: str = "new_business"  # new_business | merge_into_business | rewrite_business
	target_business_id: Optional[int] = None
	owner_user_id: Optional[int] = None
	dry_run: bool = False
	import_users: bool = True
	import_master_data: bool = True
	import_invoices: bool = True
	import_receipts_payments: bool = True
	import_expense_income: bool = True
	import_warehouses: bool = True
	import_transfers: bool = True
	import_opening_balance: bool = True
	import_checks: bool = True
	conflict_policy: str = "skip"  # skip | link
	rewrite_confirmation: Optional[str] = None


@dataclass
class LegacyImportResult:
	ok: bool
	dry_run: bool
	stats: Dict[str, Any] = field(default_factory=dict)
	errors: List[str] = field(default_factory=list)
	mappings: Dict[str, Any] = field(default_factory=dict)


class LegacySqlImportService:
	def __init__(self, db: Session, *, on_progress: ProgressCb = None):
		self.db = db
		self.on_progress = on_progress
		self.stats: Dict[str, Any] = {}

	def _load_dump(self, path: str) -> tuple[LegacySqlData, list[str]]:
		sql_path, cleanup_paths = materialize_legacy_sql_path(path)
		try:
			return load_legacy_sql_dump(sql_path), cleanup_paths
		except Exception:
			for p in cleanup_paths:
				if p != path:
					try:
						import os
						os.unlink(p)
					except OSError:
						pass
			raise

	@staticmethod
	def _cleanup_temp_paths(original_path: str, cleanup_paths: list[str]) -> None:
		import os
		for p in cleanup_paths:
			if p != original_path:
				try:
					os.unlink(p)
				except OSError:
					pass

	def analyze_file(self, path: str) -> Dict[str, Any]:
		data, cleanup_paths = self._load_dump(path)
		try:
			errors = validate_legacy_dump(data)
			return {
				"valid": len(errors) == 0,
				"errors": errors,
				"analysis": data.analyze(),
			}
		finally:
			self._cleanup_temp_paths(path, cleanup_paths)

	def run(self, path: str, options: LegacyImportOptions) -> LegacyImportResult:
		data, cleanup_paths = self._load_dump(path)
		try:
			errors = validate_legacy_dump(data)
			if errors:
				return LegacyImportResult(ok=False, dry_run=options.dry_run, errors=errors)
			return self._run_import(data, options)
		finally:
			self._cleanup_temp_paths(path, cleanup_paths)

	def _run_import(self, data: LegacySqlData, options: LegacyImportOptions) -> LegacyImportResult:

		self.stats = {
			"users": {"linked": 0, "created": 0, "skipped": 0},
			"business": {"created": 0, "linked": 0},
			"fiscal_years": {"created": 0, "linked": 0},
			"persons": {"created": 0, "linked": 0, "skipped": 0},
			"products": {"created": 0, "linked": 0, "skipped": 0},
			"banks": {"created": 0, "linked": 0, "skipped": 0},
			"cash_registers": {"created": 0, "linked": 0},
			"petty_cash": {"created": 0, "linked": 0},
			"warehouses": {},
			"invoices": {},
			"receipts_payments": {},
			"expense_income": {},
			"transfers": {},
			"opening_balance": {},
			"checks": {},
			"purge": {},
		}
		user_map: Dict[int, int] = {}
		business_map: Dict[int, int] = {}
		person_map: Dict[Tuple[int, int], int] = {}
		product_map: Dict[Tuple[int, int], int] = {}
		bank_map: Dict[Tuple[int, int], int] = {}
		cash_map: Dict[Tuple[int, int], int] = {}
		petty_map: Dict[Tuple[int, int], int] = {}
		currency_map: Dict[int, int] = {}
		fiscal_map: Dict[Tuple[int, int], int] = {}

		try:
			if options.import_mode == "rewrite_business":
				self._validate_rewrite(options)

			self._progress(5, "نگاشت ارزها")
			currency_map = self._build_currency_map(data)

			if options.import_users:
				self._progress(10, "کاربران")
				user_map = self._import_users(data, options)

			if options.import_mode == "rewrite_business" and options.target_business_id:
				if not options.dry_run:
					self._progress(15, "پاک‌سازی داده‌های قبلی کسب‌وکار")
					self.stats["purge"] = purge_business_operational_data(
						self.db, options.target_business_id
					)
				else:
					self.stats["purge"] = {"dry_run": True}

			self._progress(25, "کسب‌وکار و سال مالی")
			business_map, fiscal_map = self._import_business(
				data, options, user_map, currency_map
			)

			if options.import_master_data:
				self._progress(40, "اشخاص")
				person_map = self._import_persons(data, options, business_map)
				self._progress(55, "کالاها")
				product_map = self._import_products(data, options, business_map)
				self._progress(62, "حساب‌های بانکی")
				bank_map = self._import_banks(data, options, business_map, currency_map)
				self._progress(64, "صندوق و تنخواه")
				cash_map = self._import_cash_registers(data, options, business_map, currency_map)
				petty_map = self._import_petty_cash(data, options, business_map, currency_map)
				if options.import_warehouses:
					wh_imp = LegacyWarehouseImporter(self.db, data, dry_run=options.dry_run)
					self.stats["warehouses"], _ = wh_imp.run(
						business_id_map=business_map,
						user_id_map=user_map,
						product_id_map=product_map,
						import_documents=True,
						on_progress=self.on_progress,
					)

			if options.import_invoices:
				self._progress(70, "فاکتورها")
				inv = LegacyInvoiceImporter(self.db, data, dry_run=options.dry_run)
				self.stats["invoices"] = inv.run(
					business_id_map=business_map,
					user_id_map=user_map,
					person_id_map=person_map,
					product_id_map=product_map,
					currency_id_map=currency_map,
					fiscal_year_map=fiscal_map,
					on_progress=self.on_progress,
				)

			if options.import_receipts_payments:
				rp = LegacyReceiptPaymentImporter(self.db, data, dry_run=options.dry_run)
				self.stats["receipts_payments"] = rp.run(
					business_id_map=business_map,
					user_id_map=user_map,
					person_id_map=person_map,
					bank_id_map=bank_map,
					cashdesk_id_map=cash_map,
					petty_id_map=petty_map,
					currency_id_map=currency_map,
					on_progress=self.on_progress,
				)

			if options.import_expense_income:
				ei = LegacyExpenseIncomeImporter(self.db, data, dry_run=options.dry_run)
				self.stats["expense_income"] = ei.run(
					business_id_map=business_map,
					user_id_map=user_map,
					person_id_map=person_map,
					bank_id_map=bank_map,
					cashdesk_id_map=cash_map,
					petty_id_map=petty_map,
					currency_id_map=currency_map,
					on_progress=self.on_progress,
				)

			if options.import_transfers:
				self._progress(93, "انتقال وجه")
				tr = LegacyTransferImporter(self.db, data, dry_run=options.dry_run)
				self.stats["transfers"] = tr.run(
					business_id_map=business_map,
					user_id_map=user_map,
					bank_id_map=bank_map,
					cashdesk_id_map=cash_map,
					petty_id_map=petty_map,
					currency_id_map=currency_map,
					on_progress=self.on_progress,
				)

			if options.import_opening_balance:
				self._progress(96, "تراز افتتاحیه")
				ob = LegacyOpeningBalanceImporter(self.db, data, dry_run=options.dry_run)
				self.stats["opening_balance"] = ob.run(
					business_id_map=business_map,
					user_id_map=user_map,
					person_id_map=person_map,
					bank_id_map=bank_map,
					cashdesk_id_map=cash_map,
					petty_id_map=petty_map,
					currency_id_map=currency_map,
					fiscal_year_map=fiscal_map,
					on_progress=self.on_progress,
				)

			if options.import_checks:
				self._progress(97, "چک‌ها")
				ch = LegacyCheckImporter(self.db, data, dry_run=options.dry_run)
				self.stats["checks"] = ch.run(
					business_id_map=business_map,
					user_id_map=user_map,
					person_id_map=person_map,
					bank_id_map=bank_map,
					currency_id_map=currency_map,
					on_progress=self.on_progress,
				)

			self._progress(100, "پایان")
			if not options.dry_run:
				self.db.commit()
			else:
				self.db.rollback()

			return LegacyImportResult(
				ok=True,
				dry_run=options.dry_run,
				stats=self.stats,
				mappings={
					"user_id": {str(k): v for k, v in user_map.items()},
					"business_id": {str(k): v for k, v in business_map.items()},
				},
			)
		except Exception as exc:
			self.db.rollback()
			return LegacyImportResult(
				ok=False,
				dry_run=options.dry_run,
				stats=self.stats,
				errors=[str(exc)],
			)

	def _progress(self, pct: int, msg: str) -> None:
		if self.on_progress:
			self.on_progress(pct, msg)

	def _validate_rewrite(self, options: LegacyImportOptions) -> None:
		if not options.target_business_id:
			raise ValueError("target_business_id برای rewrite_business الزامی است")
		conf = (options.rewrite_confirmation or "").strip()
		if conf not in (LEGACY_REWRITE_CONFIRMATION_FA, LEGACY_REWRITE_CONFIRMATION_EN):
			raise ValueError(
				f"برای بازنویسی عبارت '{LEGACY_REWRITE_CONFIRMATION_FA}' یا "
				f"'{LEGACY_REWRITE_CONFIRMATION_EN}' را وارد کنید"
			)

	def _build_currency_map(self, data: LegacySqlData) -> Dict[int, int]:
		mapping: Dict[int, int] = {}
		for row in data.rows("money"):
			code = str(row.get("name") or "").strip().upper()
			if not code:
				continue
			cur = self.db.execute(
				select(Currency).where(Currency.code == code)
			).scalars().first()
			if cur:
				mapping[int(row["id"])] = cur.id
		return mapping

	def _gen_referral(self) -> str:
		repo = UserRepository(self.db)
		for _ in range(30):
			code = secrets.token_urlsafe(8).replace("-", "").replace("_", "")[:10]
			if not repo.get_by_referral_code(code):
				return code
		return secrets.token_urlsafe(12).replace("-", "").replace("_", "")[:12]

	def _import_users(self, data: LegacySqlData, options: LegacyImportOptions) -> Dict[int, int]:
		repo = UserRepository(self.db)
		mapping: Dict[int, int] = {}
		for row in data.rows("user"):
			old_id = int(row["id"])
			if not int(row.get("active") or 0):
				self.stats["users"]["skipped"] += 1
				continue
			email = _normalize_email(row.get("email"))
			mobile = _normalize_mobile(row.get("mobile"))
			if not email and not mobile:
				self.stats["users"]["skipped"] += 1
				continue

			existing = None
			if email:
				existing = repo.get_by_email(email)
			if not existing and mobile:
				existing = repo.get_by_mobile(mobile)

			if existing:
				mapping[old_id] = existing.id
				self.stats["users"]["linked"] += 1
				continue

			if options.dry_run:
				mapping[old_id] = -old_id
				self.stats["users"]["created"] += 1
				continue

			first, last = split_full_name(row.get("full_name"))
			pw = row.get("password") or ""
			if not pw:
				from app.core.security import hash_password
				pw = hash_password(secrets.token_urlsafe(24))

			user = User(
				email=email,
				mobile=mobile,
				first_name=first,
				last_name=last,
				password_hash=pw,
				is_active=True,
				email_verified=False,
				mobile_verified=False,
				referral_code=self._gen_referral(),
				created_at=convert_timestamp_to_datetime(row.get("date_register")),
				updated_at=datetime.utcnow(),
			)
			self.db.add(user)
			self.db.flush()
			mapping[old_id] = user.id
			self.stats["users"]["created"] += 1

		return mapping

	def _import_business(
		self,
		data: LegacySqlData,
		options: LegacyImportOptions,
		user_map: Dict[int, int],
		currency_map: Dict[int, int],
	) -> Tuple[Dict[int, int], Dict[Tuple[int, int], int]]:
		business_map: Dict[int, int] = {}
		fiscal_map: Dict[Tuple[int, int], int] = {}
		brepo = BusinessRepository(self.db)
		frepo = FiscalYearRepository(self.db)

		if options.import_mode in ("merge_into_business", "rewrite_business"):
			if not options.target_business_id:
				raise ValueError("target_business_id الزامی است")
			tid = options.target_business_id
			for row in data.rows("business"):
				business_map[int(row["id"])] = tid
			self.stats["business"]["linked"] = len(business_map)
			for yrow in data.rows("year"):
				old_bid = int(yrow["bid_id"])
				if old_bid not in business_map:
					continue
				old_yid = int(yrow["id"])
				start_d = unix_ts_to_date(yrow.get("start"))
				end_d = unix_ts_to_date(yrow.get("end"))
				if options.import_mode == "rewrite_business" and start_d and end_d and not options.dry_run:
					existing_fy = [
						f for f in frepo.list_by_business(tid)
						if f.title == yrow.get("label")
					]
					if existing_fy:
						fiscal_map[(old_bid, old_yid)] = existing_fy[0].id
					else:
						fy = frepo.create_fiscal_year(
							business_id=tid,
							title=str(yrow.get("label") or "سال مالی"),
							start_date=start_d,
							end_date=end_d,
							is_last=bool(yrow.get("head")),
							commit=False,
						)
						fiscal_map[(old_bid, old_yid)] = fy.id
						self.stats["fiscal_years"]["created"] += 1
					continue
				fy = frepo.get_current_for_business(tid)
				if fy:
					fiscal_map[(old_bid, old_yid)] = fy.id
					self.stats["fiscal_years"]["linked"] += 1
			return business_map, fiscal_map

		for row in data.rows("business"):
			old_bid = int(row["id"])
			old_owner = int(row.get("owner_id") or 0)
			owner_id = options.owner_user_id or user_map.get(old_owner)
			if not owner_id or owner_id < 0:
				continue

			existing = self.db.execute(
				select(Business).where(
					and_(Business.owner_id == owner_id, Business.name == row.get("name"))
				)
			).scalars().first()
			if existing:
				business_map[old_bid] = existing.id
				self.stats["business"]["linked"] += 1
			elif options.dry_run:
				business_map[old_bid] = -old_bid
				self.stats["business"]["created"] += 1
			else:
				money_id = int(row.get("money_id") or 1)
				default_cur = currency_map.get(money_id)
				if not default_cur:
					cur = self.db.execute(
						select(Currency).where(Currency.code == "IRR")
					).scalars().first()
					default_cur = cur.id if cur else None
				biz = brepo.create_business(
					name=str(row.get("name") or "کسب‌وکار"),
					business_type=map_business_type(row.get("type")),
					business_field=map_business_field(row.get("field")),
					owner_id=owner_id,
					default_currency_id=default_cur,
					address=row.get("address"),
					phone=row.get("tel"),
					mobile=row.get("mobile"),
					national_id=row.get("shenasemeli") or None,
					registration_number=row.get("shomaresabt") or None,
					economic_id=row.get("codeeghtesadi") or None,
					country=row.get("country"),
					province=row.get("ostan"),
					city=row.get("shahrestan"),
					postal_code=row.get("postalcode"),
					commit=False,
				)
				if default_cur:
					self.db.add(BusinessCurrency(business_id=biz.id, currency_id=default_cur))
				business_map[old_bid] = biz.id
				self.stats["business"]["created"] += 1

			new_bid = business_map[old_bid]
			if new_bid < 0:
				continue

			for yrow in data.rows("year"):
				if int(yrow.get("bid_id") or 0) != old_bid:
					continue
				old_yid = int(yrow["id"])
				start_d = unix_ts_to_date(yrow.get("start"))
				end_d = unix_ts_to_date(yrow.get("end"))
				if not start_d or not end_d:
					continue
				if options.dry_run:
					fiscal_map[(old_bid, old_yid)] = -old_yid
					self.stats["fiscal_years"]["created"] += 1
					continue
				existing_fy = [
					f for f in frepo.list_by_business(new_bid)
					if f.title == yrow.get("label")
				]
				if existing_fy:
					fiscal_map[(old_bid, old_yid)] = existing_fy[0].id
					self.stats["fiscal_years"]["linked"] += 1
				else:
					fy = frepo.create_fiscal_year(
						business_id=new_bid,
						title=str(yrow.get("label") or "سال مالی"),
						start_date=start_d,
						end_date=end_d,
						is_last=bool(yrow.get("head")),
						commit=False,
					)
					fiscal_map[(old_bid, old_yid)] = fy.id
					self.stats["fiscal_years"]["created"] += 1

		self.db.flush()
		return business_map, fiscal_map

	def _import_persons(
		self,
		data: LegacySqlData,
		options: LegacyImportOptions,
		business_map: Dict[int, int],
	) -> Dict[Tuple[int, int], int]:
		mapping: Dict[Tuple[int, int], int] = {}
		type_links = data.rows("person_person_type")
		type_labels = {int(t["id"]): t.get("label") for t in data.rows("person_type") if t.get("id") is not None}
		person_types_by_old: Dict[int, List[str]] = {}
		for link in type_links:
			try:
				pid = int(link.get("person_id"))
				tid = int(link.get("person_type_id"))
			except (TypeError, ValueError):
				continue
			label = type_labels.get(tid)
			if label:
				person_types_by_old.setdefault(pid, []).append(label)

		for row in data.rows("person"):
			old_bid = int(row["bid_id"])
			new_bid = business_map.get(old_bid)
			if not new_bid or new_bid < 0:
				continue
			old_pid = int(row["id"])
			try:
				code = int(row.get("code"))
			except (TypeError, ValueError):
				code = None

			existing = None
			if code is not None:
				existing = self.db.execute(
					select(Person).where(
						and_(Person.business_id == new_bid, Person.code == code)
					)
				).scalars().first()
			if existing:
				mapping[(old_bid, old_pid)] = existing.id
				self.stats["persons"]["linked"] += 1
				continue

			if options.dry_run:
				mapping[(old_bid, old_pid)] = -old_pid
				self.stats["persons"]["created"] += 1
				continue

			labels = person_types_by_old.get(old_pid) or ["مشتری"]
			ptypes = []
			for lb in labels:
				try:
					ptypes.append(PersonType(lb))
				except ValueError:
					pass
			if not ptypes:
				ptypes = [PersonType.CUSTOMER]

			first, last = split_full_name(row.get("name"))
			req = PersonCreateRequest(
				code=code,
				alias_name=str(row.get("nikename") or row.get("name") or "شخص"),
				first_name=first,
				last_name=last,
				person_types=ptypes,
				company_name=row.get("company"),
				national_id=(str(row.get("shenasemeli"))[:20] if row.get("shenasemeli") else None),
				registration_number=row.get("sabt"),
				economic_id=row.get("codeeghtesadi"),
				country=row.get("keshvar"),
				province=row.get("ostan"),
				city=row.get("shahr"),
				address=row.get("address"),
				postal_code=row.get("postalcode"),
				phone=row.get("tel"),
				mobile=row.get("mobile"),
				email=row.get("email"),
				website=row.get("website"),
			)
			created = create_person(self.db, new_bid, req)
			mapping[(old_bid, old_pid)] = int(created["id"])
			self.stats["persons"]["created"] += 1

		return mapping

	def _import_products(
		self,
		data: LegacySqlData,
		options: LegacyImportOptions,
		business_map: Dict[int, int],
	) -> Dict[Tuple[int, int], int]:
		mapping: Dict[Tuple[int, int], int] = {}
		unit_names = {int(u["id"]): u.get("name") for u in data.rows("commodity_unit") if u.get("id") is not None}

		for row in data.rows("commodity"):
			old_bid = int(row["bid_id"])
			new_bid = business_map.get(old_bid)
			if not new_bid or new_bid < 0:
				continue
			old_cid = int(row["id"])
			code = str(row.get("code") or "").strip()
			if not code:
				continue

			existing = self.db.execute(
				select(Product).where(
					and_(Product.business_id == new_bid, Product.code == code)
				)
			).scalars().first()
			if existing:
				mapping[(old_bid, old_cid)] = existing.id
				self.stats["products"]["linked"] += 1
				continue

			if options.dry_run:
				mapping[(old_bid, old_cid)] = -old_cid
				self.stats["products"]["created"] += 1
				continue

			unit_id = row.get("unit_id")
			main_unit = "عدد"
			try:
				if unit_id is not None:
					main_unit = str(unit_names.get(int(unit_id)) or "عدد")
			except (TypeError, ValueError):
				pass

			item_type = "خدمت" if row.get("khadamat") else "کالا"
			req = ProductCreateRequest(
				code=code,
				name=str(row.get("name") or code),
				item_type=item_type,
				description=row.get("des"),
				main_unit=main_unit,
				base_purchase_price=row.get("price_buy"),
				base_sales_price=row.get("price_sell"),
			)
			created = create_product(self.db, new_bid, req)
			mapping[(old_bid, old_cid)] = int(created["id"])
			self.stats["products"]["created"] += 1

		return mapping

	def _resolve_currency_id(
		self,
		business_id: int,
		money_id: int,
		currency_map: Dict[int, int],
	) -> Optional[int]:
		cur_id = currency_map.get(money_id)
		if cur_id:
			return cur_id
		biz = self.db.get(Business, business_id)
		if biz and biz.default_currency_id:
			return biz.default_currency_id
		cur = self.db.execute(select(Currency).where(Currency.code == "IRR")).scalars().first()
		return cur.id if cur else None

	def _import_banks(
		self,
		data: LegacySqlData,
		options: LegacyImportOptions,
		business_map: Dict[int, int],
		currency_map: Dict[int, int],
	) -> Dict[Tuple[int, int], int]:
		from adapters.db.models.bank_account import BankAccount

		mapping: Dict[Tuple[int, int], int] = {}
		for row in data.rows("bank_account"):
			old_bid = int(row["bid_id"])
			new_bid = business_map.get(old_bid)
			if not new_bid or new_bid < 0:
				continue
			try:
				old_bank_id = int(row["id"])
			except (TypeError, ValueError):
				continue
			code = str(row.get("code") or "").strip()[:50]
			if not code:
				continue
			existing = self.db.execute(
				select(BankAccount).where(
					and_(BankAccount.business_id == new_bid, BankAccount.code == code)
				)
			).scalars().first()
			if existing:
				mapping[(old_bid, old_bank_id)] = existing.id
				self.stats["banks"]["linked"] += 1
				continue
			if options.dry_run:
				mapping[(old_bid, old_bank_id)] = -old_bank_id
				self.stats["banks"]["created"] += 1
				continue
			cur_id = self._resolve_currency_id(new_bid, int(row.get("money_id") or 1), currency_map)
			if not cur_id:
				self.stats["banks"]["skipped"] += 1
				continue
			ba = BankAccount(
				business_id=new_bid,
				code=code,
				name=row.get("name"),
				description=row.get("des"),
				branch=row.get("shobe"),
				account_number=row.get("account_num"),
				sheba_number=row.get("shaba"),
				card_number=row.get("card_num"),
				owner_name=row.get("owner"),
				pos_number=row.get("pos_num"),
				payment_id=row.get("mobile_internet_bank"),
				currency_id=cur_id,
				is_active=True,
				is_default=False,
			)
			self.db.add(ba)
			self.db.flush()
			mapping[(old_bid, old_bank_id)] = ba.id
			self.stats["banks"]["created"] += 1
		return mapping

	def _import_cash_registers(
		self,
		data: LegacySqlData,
		options: LegacyImportOptions,
		business_map: Dict[int, int],
		currency_map: Dict[int, int],
	) -> Dict[Tuple[int, int], int]:
		from adapters.db.models.cash_register import CashRegister

		mapping: Dict[Tuple[int, int], int] = {}
		for row in data.rows("cashdesk"):
			old_bid = int(row.get("bid_id") or 0)
			new_bid = business_map.get(old_bid)
			if not new_bid or new_bid < 0:
				continue
			try:
				old_id = int(row["id"])
			except (TypeError, ValueError):
				continue
			code = str(row.get("code") or "").strip()[:50] or str(old_id)
			existing = self.db.execute(
				select(CashRegister).where(
					and_(CashRegister.business_id == new_bid, CashRegister.code == code)
				)
			).scalars().first()
			if existing:
				mapping[(old_bid, old_id)] = existing.id
				self.stats["cash_registers"]["linked"] += 1
				continue
			if options.dry_run:
				mapping[(old_bid, old_id)] = -old_id
				self.stats["cash_registers"]["created"] += 1
				continue
			cur_id = self._resolve_currency_id(new_bid, int(row.get("money_id") or 1), currency_map)
			if not cur_id:
				continue
			cr = CashRegister(
				business_id=new_bid,
				code=code,
				name=row.get("name") or "صندوق",
				description=row.get("des"),
				currency_id=cur_id,
				is_active=True,
				is_default=False,
			)
			self.db.add(cr)
			self.db.flush()
			mapping[(old_bid, old_id)] = cr.id
			self.stats["cash_registers"]["created"] += 1
		return mapping

	def _import_petty_cash(
		self,
		data: LegacySqlData,
		options: LegacyImportOptions,
		business_map: Dict[int, int],
		currency_map: Dict[int, int],
	) -> Dict[Tuple[int, int], int]:
		from adapters.db.models.petty_cash import PettyCash

		mapping: Dict[Tuple[int, int], int] = {}
		for row in data.rows("salary"):
			old_bid = int(row.get("bid_id") or 0)
			new_bid = business_map.get(old_bid)
			if not new_bid or new_bid < 0:
				continue
			try:
				old_id = int(row["id"])
			except (TypeError, ValueError):
				continue
			code = str(row.get("code") or "").strip()[:50] or str(old_id)
			existing = self.db.execute(
				select(PettyCash).where(
					and_(PettyCash.business_id == new_bid, PettyCash.code == code)
				)
			).scalars().first()
			if existing:
				mapping[(old_bid, old_id)] = existing.id
				self.stats["petty_cash"]["linked"] += 1
				continue
			if options.dry_run:
				mapping[(old_bid, old_id)] = -old_id
				self.stats["petty_cash"]["created"] += 1
				continue
			cur_id = self._resolve_currency_id(new_bid, int(row.get("money_id") or 1), currency_map)
			if not cur_id:
				continue
			pc = PettyCash(
				business_id=new_bid,
				code=code,
				name=row.get("name") or "تنخواه",
				description=row.get("des"),
				currency_id=cur_id,
				is_active=True,
				is_default=False,
			)
			self.db.add(pc)
			self.db.flush()
			mapping[(old_bid, old_id)] = pc.id
			self.stats["petty_cash"]["created"] += 1
		return mapping
