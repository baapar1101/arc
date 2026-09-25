"""
سرویس کالای هزینه‌شده / کالای درآمدشده

جریان:
- simple: ایجاد (+ تخصیص حساب) و در صورت تنظیمات/مجوز، قطعی‌سازی یک‌مرحله‌ای
- two_step: پیش‌نویس عملیاتی → ارسال به حسابداری → تخصیص حساب → قطعی

قطعی‌سازی اتمی: حواله انبار posted + سند دفتر کل متعادل
"""

from __future__ import annotations

import logging
from datetime import date, datetime
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import and_, func, or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from adapters.db.models.account import Account
from adapters.db.models.business import Business
from adapters.db.models.currency import Currency
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.goods_expense_income import (
	GoodsExpenseIncomeDocument,
	GoodsExpenseIncomeLine,
)
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from adapters.db.models.warehouse import Warehouse
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core.responses import ApiError
from app.services.document_monetization_service import ensure_document_policy_allows_creation
from app.services.document_numbering_service import generate_document_code

logger = logging.getLogger(__name__)

DOC_KIND_EXPENSE = "goods_expense"
DOC_KIND_INCOME = "goods_income"
VALID_DOC_KINDS = frozenset({DOC_KIND_EXPENSE, DOC_KIND_INCOME})

STATUS_DRAFT_OPS = "draft_ops"
STATUS_PENDING_ACCOUNTING = "pending_accounting"
STATUS_DRAFT_ACCOUNTING = "draft_accounting"
STATUS_POSTED = "posted"
STATUS_CANCELLED = "cancelled"

EDITABLE_STATUSES = frozenset({STATUS_DRAFT_OPS, STATUS_PENDING_ACCOUNTING, STATUS_DRAFT_ACCOUNTING})
OPS_EDITABLE_STATUSES = frozenset({STATUS_DRAFT_OPS})
ACCOUNTING_EDITABLE_STATUSES = frozenset(
	{STATUS_PENDING_ACCOUNTING, STATUS_DRAFT_ACCOUNTING, STATUS_DRAFT_OPS}
)

DEFAULT_EXPENSE_ACCOUNT_CODE = "70407"
DEFAULT_INCOME_ACCOUNT_CODE = "60103"
INVENTORY_ACCOUNT_CODE = "10102"

# نوع شماره‌گذاری سند عملیاتی (جدا از سند دفتر کل goods_expense/goods_income)
VOUCHER_NUMBERING_BY_KIND = {
	DOC_KIND_EXPENSE: "goods_expense_voucher",
	DOC_KIND_INCOME: "goods_income_voucher",
}

WORKFLOW_SIMPLE = "simple"
WORKFLOW_TWO_STEP = "two_step"
STOCK_COUNT_GOODS_DOCS = "goods_docs"
STOCK_COUNT_PHYSICAL = "physical_adjustment"
STOCK_COUNT_ASK = "ask"


def _money(value: Decimal | float | int | str | None) -> Decimal:
	return Decimal(str(value or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _qty(value: Decimal | float | int | str | None) -> Decimal:
	return Decimal(str(value or 0)).quantize(Decimal("0.000001"), rounding=ROUND_HALF_UP)


def _parse_iso_date(dt: str | datetime | date | None) -> date:
	if isinstance(dt, date) and not isinstance(dt, datetime):
		return dt
	if isinstance(dt, datetime):
		return dt.date()
	if not dt:
		return datetime.utcnow().date()
	try:
		return datetime.fromisoformat(str(dt)).date()
	except Exception:
		return datetime.utcnow().date()


def _get_business(db: Session, business_id: int) -> Business:
	biz = db.query(Business).filter(Business.id == int(business_id)).first()
	if not biz:
		raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
	return biz


def _get_business_fiscal_year(db: Session, business_id: int) -> FiscalYear:
	fy = (
		db.query(FiscalYear)
		.filter(and_(FiscalYear.business_id == business_id, FiscalYear.is_last == True))  # noqa: E712
		.order_by(FiscalYear.start_date.desc())
		.first()
	)
	if not fy:
		raise ApiError("FISCAL_YEAR_NOT_FOUND", "سال مالی فعال یافت نشد", http_status=404)
	return fy


def get_workflow_settings(biz: Business) -> Dict[str, Any]:
	mode = str(getattr(biz, "goods_expense_income_workflow_mode", None) or WORKFLOW_SIMPLE).strip().lower()
	if mode not in (WORKFLOW_SIMPLE, WORKFLOW_TWO_STEP):
		mode = WORKFLOW_SIMPLE
	stock_mode = str(
		getattr(biz, "goods_expense_income_stock_count_mode", None) or STOCK_COUNT_GOODS_DOCS
	).strip().lower()
	if stock_mode not in (STOCK_COUNT_GOODS_DOCS, STOCK_COUNT_PHYSICAL, STOCK_COUNT_ASK):
		stock_mode = STOCK_COUNT_GOODS_DOCS
	return {
		"workflow_mode": mode,
		"auto_post_in_simple_mode": bool(
			getattr(biz, "goods_expense_income_auto_post_in_simple_mode", True)
		),
		"default_expense_account_code": str(
			getattr(biz, "goods_expense_income_default_expense_account_code", None)
			or DEFAULT_EXPENSE_ACCOUNT_CODE
		),
		"default_income_account_code": str(
			getattr(biz, "goods_expense_income_default_income_account_code", None)
			or DEFAULT_INCOME_ACCOUNT_CODE
		),
		"stock_count_mode": stock_mode,
		"allow_manual_unit_cost": bool(
			getattr(biz, "goods_expense_income_allow_manual_unit_cost", False)
		),
		"require_person": bool(getattr(biz, "goods_expense_income_require_person", False)),
	}


def resolve_account_by_code(
	db: Session,
	business_id: int,
	account_code: str,
) -> Account:
	code = str(account_code or "").strip()
	if not code:
		raise ApiError("ACCOUNT_CODE_REQUIRED", "کد حساب الزامی است", http_status=400)
	acc = (
		db.query(Account)
		.filter(and_(Account.code == code, Account.business_id == business_id))
		.first()
	)
	if not acc:
		acc = (
			db.query(Account)
			.filter(and_(Account.code == code, Account.business_id.is_(None)))
			.first()
		)
	if not acc:
		raise ApiError("ACCOUNT_NOT_FOUND", f"حساب با کد {code} یافت نشد", http_status=404)
	return acc


def resolve_account_by_id(db: Session, business_id: int, account_id: int) -> Account:
	acc = db.query(Account).filter(Account.id == int(account_id)).first()
	if not acc:
		raise ApiError("ACCOUNT_NOT_FOUND", "حساب یافت نشد", http_status=404)
	if acc.business_id is not None and int(acc.business_id) != int(business_id):
		raise ApiError("ACCOUNT_NOT_FOUND", "حساب متعلق به این کسب‌وکار نیست", http_status=404)
	return acc


def _assert_leaf_account(db: Session, account: Account, business_id: Optional[int] = None) -> None:
	"""حساب گروه (دارای فرزند) نباید مقصد ثبت باشد."""
	q = db.query(Account.id).filter(Account.parent_id == account.id)
	if business_id is not None:
		# فرزندان قالب سراسری یا همین کسب‌وکار
		q = q.filter(or_(Account.business_id.is_(None), Account.business_id == int(business_id)))
	has_child = q.limit(1).first()
	if has_child:
		raise ApiError(
			"ACCOUNT_NOT_LEAF",
			f"حساب «{account.code} - {account.name}» گروه است و قابل ثبت نیست؛ یک حساب برگ انتخاب کنید",
			http_status=400,
		)


def _assert_account_kind_compatible(account: Account, doc_kind: str) -> None:
	code = str(account.code or "")
	if doc_kind == DOC_KIND_EXPENSE:
		if not (code.startswith("7") or code.startswith("4")):
			raise ApiError(
				"ACCOUNT_KIND_MISMATCH",
				"برای کالای هزینه‌شده باید حساب هزینه (شاخه ۷) انتخاب شود",
				http_status=400,
			)
	elif doc_kind == DOC_KIND_INCOME:
		if not code.startswith("6"):
			raise ApiError(
				"ACCOUNT_KIND_MISMATCH",
				"برای کالای درآمدشده باید حساب درآمد (شاخه ۶) انتخاب شود",
				http_status=400,
			)


def default_effect_account(db: Session, business_id: int, biz: Business, doc_kind: str) -> Account:
	settings = get_workflow_settings(biz)
	code = (
		settings["default_expense_account_code"]
		if doc_kind == DOC_KIND_EXPENSE
		else settings["default_income_account_code"]
	)
	acc = resolve_account_by_code(db, business_id, code)
	_assert_leaf_account(db, acc, business_id)
	_assert_account_kind_compatible(acc, doc_kind)
	return acc


def resolve_product_unit_cost(product: Product) -> Decimal:
	"""بهای واحد از قیمت خرید پایه کالا (مطابق توضیح کاربر)."""
	raw = getattr(product, "base_purchase_price", None)
	if raw is None:
		return Decimal("0")
	return _qty(raw)


def _load_document(
	db: Session,
	business_id: int,
	document_id: int,
	*,
	with_lines: bool = True,
) -> GoodsExpenseIncomeDocument:
	q = db.query(GoodsExpenseIncomeDocument).filter(
		and_(
			GoodsExpenseIncomeDocument.id == int(document_id),
			GoodsExpenseIncomeDocument.business_id == int(business_id),
		)
	)
	if with_lines:
		q = q.options(
			joinedload(GoodsExpenseIncomeDocument.lines),
			joinedload(GoodsExpenseIncomeDocument.effect_account),
			joinedload(GoodsExpenseIncomeDocument.person),
		)
	doc = q.first()
	if not doc:
		raise ApiError("NOT_FOUND", "سند کالای هزینه/درآمد یافت نشد", http_status=404)
	return doc


def _document_to_dict(doc: GoodsExpenseIncomeDocument, db: Optional[Session] = None) -> Dict[str, Any]:
	lines_out: List[Dict[str, Any]] = []
	for ln in list(doc.lines or []):
		product_name = None
		product_code = None
		warehouse_name = None
		if db is not None:
			p = db.query(Product).filter(Product.id == ln.product_id).first()
			if p:
				product_name = p.name
				product_code = getattr(p, "code", None)
			w = db.query(Warehouse).filter(Warehouse.id == ln.warehouse_id).first()
			if w:
				warehouse_name = w.name
		lines_out.append(
			{
				"id": ln.id,
				"line_no": ln.line_no,
				"product_id": ln.product_id,
				"product_name": product_name,
				"product_code": product_code,
				"warehouse_id": ln.warehouse_id,
				"warehouse_name": warehouse_name,
				"quantity": float(ln.quantity or 0),
				"unit_cost": float(ln.unit_cost or 0),
				"amount": float(ln.amount or 0),
				"description": ln.description,
				"extra_info": ln.extra_info,
			}
		)

	effect_account = None
	if doc.effect_account_id and doc.effect_account is not None:
		effect_account = {
			"id": doc.effect_account.id,
			"code": doc.effect_account.code,
			"name": doc.effect_account.name,
		}
	elif doc.effect_account_id and db is not None:
		acc = db.query(Account).filter(Account.id == doc.effect_account_id).first()
		if acc:
			effect_account = {"id": acc.id, "code": acc.code, "name": acc.name}

	person = None
	if doc.person_id and doc.person is not None:
		person = {"id": doc.person.id, "name": getattr(doc.person, "name", None)}
	elif doc.person_id and db is not None:
		p = db.query(Person).filter(Person.id == doc.person_id).first()
		if p:
			person = {"id": p.id, "name": getattr(p, "name", None)}

	return {
		"id": doc.id,
		"business_id": doc.business_id,
		"fiscal_year_id": doc.fiscal_year_id,
		"code": doc.code,
		"document_date": doc.document_date.isoformat() if doc.document_date else None,
		"doc_kind": doc.doc_kind,
		"status": doc.status,
		"effect_account_id": doc.effect_account_id,
		"effect_account": effect_account,
		"person_id": doc.person_id,
		"person": person,
		"currency_id": doc.currency_id,
		"description": doc.description,
		"warehouse_document_id": doc.warehouse_document_id,
		"accounting_document_id": doc.accounting_document_id,
		"total_amount": float(doc.total_amount or 0),
		"created_by_user_id": doc.created_by_user_id,
		"submitted_by_user_id": doc.submitted_by_user_id,
		"allocated_by_user_id": doc.allocated_by_user_id,
		"posted_by_user_id": doc.posted_by_user_id,
		"cancelled_by_user_id": doc.cancelled_by_user_id,
		"submitted_at": doc.submitted_at.isoformat() if doc.submitted_at else None,
		"allocated_at": doc.allocated_at.isoformat() if doc.allocated_at else None,
		"posted_at": doc.posted_at.isoformat() if doc.posted_at else None,
		"cancelled_at": doc.cancelled_at.isoformat() if doc.cancelled_at else None,
		"extra_info": doc.extra_info,
		"created_at": doc.created_at.isoformat() if doc.created_at else None,
		"updated_at": doc.updated_at.isoformat() if doc.updated_at else None,
		"lines": lines_out,
	}


def _validate_and_build_lines(
	db: Session,
	business_id: int,
	biz: Business,
	lines_data: List[Dict[str, Any]],
	*,
	allow_manual_unit_cost: bool,
	user_can_change_unit_cost: bool,
) -> Tuple[List[Dict[str, Any]], Decimal]:
	if not lines_data:
		raise ApiError("LINES_REQUIRED", "حداقل یک سطر کالا الزامی است", http_status=400)

	built: List[Dict[str, Any]] = []
	total = Decimal("0")
	for i, raw in enumerate(lines_data, start=1):
		product_id = raw.get("product_id")
		warehouse_id = raw.get("warehouse_id")
		if not product_id:
			raise ApiError("PRODUCT_REQUIRED", f"سطر {i}: کالا الزامی است", http_status=400)
		if not warehouse_id:
			raise ApiError("WAREHOUSE_REQUIRED", f"سطر {i}: انبار الزامی است", http_status=400)

		product = (
			db.query(Product)
			.filter(and_(Product.id == int(product_id), Product.business_id == business_id))
			.first()
		)
		if not product:
			raise ApiError("PRODUCT_NOT_FOUND", f"سطر {i}: کالا یافت نشد", http_status=404)
		if not bool(getattr(product, "track_inventory", False)):
			raise ApiError(
				"PRODUCT_NOT_TRACKED",
				f"سطر {i}: کالا «{product.name}» کنترل موجودی ندارد",
				http_status=400,
			)

		wh = (
			db.query(Warehouse)
			.filter(and_(Warehouse.id == int(warehouse_id), Warehouse.business_id == business_id))
			.first()
		)
		if not wh:
			raise ApiError("WAREHOUSE_NOT_FOUND", f"سطر {i}: انبار یافت نشد", http_status=404)

		qty = _qty(raw.get("quantity"))
		if qty <= 0:
			raise ApiError("INVALID_QUANTITY", f"سطر {i}: مقدار باید مثبت باشد", http_status=400)

		system_cost = resolve_product_unit_cost(product)
		unit_cost = system_cost
		if raw.get("unit_cost") is not None:
			requested = _qty(raw.get("unit_cost"))
			if requested != system_cost:
				if not allow_manual_unit_cost or not user_can_change_unit_cost:
					raise ApiError(
						"UNIT_COST_CHANGE_FORBIDDEN",
						f"سطر {i}: تغییر دستی بهای واحد مجاز نیست",
						http_status=403,
					)
				if requested < 0:
					raise ApiError("INVALID_UNIT_COST", f"سطر {i}: بهای واحد نامعتبر است", http_status=400)
				unit_cost = requested

		amount = _money(qty * unit_cost)
		if amount <= 0:
			raise ApiError(
				"ZERO_COST",
				f"سطر {i}: بهای کالا صفر یا نامعتبر است؛ ابتدا قیمت خرید پایه کالا را تنظیم کنید",
				http_status=400,
			)

		built.append(
			{
				"line_no": i,
				"product_id": int(product_id),
				"warehouse_id": int(warehouse_id),
				"quantity": qty,
				"unit_cost": unit_cost,
				"amount": amount,
				"description": (str(raw.get("description")).strip() if raw.get("description") else None),
				"extra_info": raw.get("extra_info") if isinstance(raw.get("extra_info"), dict) else None,
			}
		)
		total += amount

	return built, _money(total)


def _apply_header_fields(
	db: Session,
	business_id: int,
	biz: Business,
	doc: GoodsExpenseIncomeDocument,
	data: Dict[str, Any],
	*,
	allow_account_change: bool,
) -> None:
	settings = get_workflow_settings(biz)
	if "document_date" in data and data.get("document_date") is not None:
		doc.document_date = _parse_iso_date(data.get("document_date"))
		fy = _get_business_fiscal_year(db, business_id)
		if doc.document_date < fy.start_date or (fy.end_date and doc.document_date > fy.end_date):
			raise ApiError(
				"DATE_OUT_OF_RANGE",
				f"تاریخ باید در بازه سال مالی ({fy.start_date} تا {fy.end_date or 'نامحدود'}) باشد",
				http_status=400,
			)

	if "description" in data:
		doc.description = (str(data.get("description")).strip() if data.get("description") else None)

	if "person_id" in data:
		person_id = data.get("person_id")
		if person_id:
			person = (
				db.query(Person)
				.filter(and_(Person.id == int(person_id), Person.business_id == business_id))
				.first()
			)
			if not person:
				raise ApiError("PERSON_NOT_FOUND", "شخص یافت نشد", http_status=404)
			doc.person_id = int(person_id)
		else:
			doc.person_id = None

	if settings["require_person"] and not doc.person_id:
		raise ApiError("PERSON_REQUIRED", "انتخاب شخص طبق تنظیمات کسب‌وکار الزامی است", http_status=400)

	if allow_account_change and ("effect_account_id" in data or "effect_account_code" in data):
		if data.get("effect_account_id"):
			acc = resolve_account_by_id(db, business_id, int(data["effect_account_id"]))
		elif data.get("effect_account_code"):
			acc = resolve_account_by_code(db, business_id, str(data["effect_account_code"]))
		else:
			acc = None
		if acc is not None:
			_assert_leaf_account(db, acc, business_id)
			_assert_account_kind_compatible(acc, doc.doc_kind)
			doc.effect_account_id = acc.id

	if "extra_info" in data and isinstance(data.get("extra_info"), dict):
		base = dict(doc.extra_info or {})
		base.update(data["extra_info"])
		doc.extra_info = base


def create_document(
	db: Session,
	business_id: int,
	user_id: int,
	data: Dict[str, Any],
	*,
	user_can_allocate: bool = False,
	user_can_post: bool = False,
	user_can_change_unit_cost: bool = False,
	commit: bool = True,
) -> Dict[str, Any]:
	biz = _get_business(db, business_id)
	settings = get_workflow_settings(biz)
	doc_kind = str(data.get("doc_kind") or "").strip().lower()
	if doc_kind not in VALID_DOC_KINDS:
		raise ApiError(
			"INVALID_DOC_KIND",
			"doc_kind باید goods_expense یا goods_income باشد",
			http_status=400,
		)

	document_date = _parse_iso_date(data.get("document_date"))
	fy = _get_business_fiscal_year(db, business_id)
	if document_date < fy.start_date or (fy.end_date and document_date > fy.end_date):
		raise ApiError("DATE_OUT_OF_RANGE", "تاریخ خارج از سال مالی است", http_status=400)

	currency_id = data.get("currency_id") or getattr(biz, "default_currency_id", None)
	if not currency_id:
		raise ApiError("CURRENCY_REQUIRED", "ارز کسب‌وکار تنظیم نشده است", http_status=400)
	currency = db.query(Currency).filter(Currency.id == int(currency_id)).first()
	if not currency:
		raise ApiError("CURRENCY_NOT_FOUND", "ارز یافت نشد", http_status=404)

	built_lines, total_amount = _validate_and_build_lines(
		db,
		business_id,
		biz,
		list(data.get("lines") or []),
		allow_manual_unit_cost=settings["allow_manual_unit_cost"],
		user_can_change_unit_cost=user_can_change_unit_cost,
	)

	ensure_document_policy_allows_creation(
		db,
		business_id,
		document_type=doc_kind,
		document_date=document_date,
		amount=total_amount,
	)

	# تعیین حساب اثر
	effect_account: Optional[Account] = None
	if data.get("effect_account_id"):
		effect_account = resolve_account_by_id(db, business_id, int(data["effect_account_id"]))
	elif data.get("effect_account_code"):
		effect_account = resolve_account_by_code(db, business_id, str(data["effect_account_code"]))
	elif settings["workflow_mode"] == WORKFLOW_SIMPLE or user_can_allocate:
		effect_account = default_effect_account(db, business_id, biz, doc_kind)

	if effect_account is not None:
		_assert_leaf_account(db, effect_account, business_id)
		_assert_account_kind_compatible(effect_account, doc_kind)

	person_id = data.get("person_id")
	if person_id:
		person = (
			db.query(Person)
			.filter(and_(Person.id == int(person_id), Person.business_id == business_id))
			.first()
		)
		if not person:
			raise ApiError("PERSON_NOT_FOUND", "شخص یافت نشد", http_status=404)
	elif settings["require_person"]:
		raise ApiError("PERSON_REQUIRED", "انتخاب شخص طبق تنظیمات کسب‌وکار الزامی است", http_status=400)

	# وضعیت اولیه
	if settings["workflow_mode"] == WORKFLOW_SIMPLE:
		initial_status = STATUS_DRAFT_ACCOUNTING if effect_account else STATUS_DRAFT_OPS
	else:
		initial_status = STATUS_DRAFT_OPS

	# در حالت ساده بدون حساب، پیش‌فرض را اجباری کن تا سند ناقص ساخته نشود
	if settings["workflow_mode"] == WORKFLOW_SIMPLE and effect_account is None:
		effect_account = default_effect_account(db, business_id, biz, doc_kind)
		initial_status = STATUS_DRAFT_ACCOUNTING

	doc: Optional[GoodsExpenseIncomeDocument] = None
	voucher_type = VOUCHER_NUMBERING_BY_KIND[doc_kind]
	for attempt in range(8):
		code = generate_document_code(db, business_id, voucher_type, document_date)
		try:
			with db.begin_nested():
				doc = GoodsExpenseIncomeDocument(
					business_id=business_id,
					fiscal_year_id=fy.id,
					code=code,
					document_date=document_date,
					doc_kind=doc_kind,
					status=initial_status,
					effect_account_id=effect_account.id if effect_account else None,
					person_id=int(person_id) if person_id else None,
					currency_id=int(currency_id),
					description=(str(data.get("description")).strip() if data.get("description") else None),
					total_amount=total_amount,
					created_by_user_id=user_id,
					extra_info=data.get("extra_info") if isinstance(data.get("extra_info"), dict) else None,
					created_at=datetime.utcnow(),
					updated_at=datetime.utcnow(),
				)
				db.add(doc)
				db.flush()
			break
		except IntegrityError:
			if attempt >= 7:
				raise
			continue

	if doc is None:
		raise ApiError("CODE_CONFLICT", "تولید کد سند ناموفق بود", http_status=500)

	for ln in built_lines:
		db.add(
			GoodsExpenseIncomeLine(
				document_id=doc.id,
				line_no=ln["line_no"],
				product_id=ln["product_id"],
				warehouse_id=ln["warehouse_id"],
				quantity=ln["quantity"],
				unit_cost=ln["unit_cost"],
				amount=ln["amount"],
				description=ln["description"],
				extra_info=ln["extra_info"],
			)
		)
	db.flush()

	# simple + auto_post
	should_auto_post = (
		settings["workflow_mode"] == WORKFLOW_SIMPLE
		and settings["auto_post_in_simple_mode"]
		and user_can_post
		and doc.effect_account_id is not None
		and bool(data.get("auto_post", True))
	)
	if should_auto_post:
		_post_document_internal(db, business_id, user_id, doc)
	elif (
		settings["workflow_mode"] == WORKFLOW_SIMPLE
		and effect_account is not None
		and user_can_allocate
		and doc.status == STATUS_DRAFT_OPS
	):
		doc.status = STATUS_DRAFT_ACCOUNTING
		doc.allocated_by_user_id = user_id
		doc.allocated_at = datetime.utcnow()
		doc.touch()

	if commit:
		db.commit()
		db.refresh(doc)
	else:
		db.flush()

	return _document_to_dict(doc, db)


def update_document(
	db: Session,
	business_id: int,
	user_id: int,
	document_id: int,
	data: Dict[str, Any],
	*,
	user_can_allocate: bool = False,
	user_can_change_unit_cost: bool = False,
	is_ops_edit: bool = False,
	commit: bool = True,
) -> Dict[str, Any]:
	biz = _get_business(db, business_id)
	settings = get_workflow_settings(biz)
	doc = _load_document(db, business_id, document_id)

	if doc.status not in EDITABLE_STATUSES:
		raise ApiError("NOT_EDITABLE", "این سند قابل ویرایش نیست", http_status=400)

	if is_ops_edit and doc.status not in OPS_EDITABLE_STATUSES and settings["workflow_mode"] == WORKFLOW_TWO_STEP:
		raise ApiError(
			"OPS_EDIT_FORBIDDEN",
			"پس از ارسال به حسابداری، انباردار نمی‌تواند سند را ویرایش کند",
			http_status=403,
		)

	allow_account = user_can_allocate or settings["workflow_mode"] == WORKFLOW_SIMPLE
	_apply_header_fields(
		db,
		business_id,
		biz,
		doc,
		data,
		allow_account_change=allow_account,
	)

	if "lines" in data:
		built_lines, total_amount = _validate_and_build_lines(
			db,
			business_id,
			biz,
			list(data.get("lines") or []),
			allow_manual_unit_cost=settings["allow_manual_unit_cost"],
			user_can_change_unit_cost=user_can_change_unit_cost,
		)
		for old in list(doc.lines):
			db.delete(old)
		db.flush()
		for ln in built_lines:
			db.add(
				GoodsExpenseIncomeLine(
					document_id=doc.id,
					line_no=ln["line_no"],
					product_id=ln["product_id"],
					warehouse_id=ln["warehouse_id"],
					quantity=ln["quantity"],
					unit_cost=ln["unit_cost"],
					amount=ln["amount"],
					description=ln["description"],
					extra_info=ln["extra_info"],
				)
			)
		doc.total_amount = total_amount

	doc.touch()
	if commit:
		db.commit()
		doc = _load_document(db, business_id, document_id)
	else:
		db.flush()
	return _document_to_dict(doc, db)


def submit_to_accounting(
	db: Session,
	business_id: int,
	user_id: int,
	document_id: int,
	*,
	commit: bool = True,
) -> Dict[str, Any]:
	biz = _get_business(db, business_id)
	settings = get_workflow_settings(biz)
	doc = _load_document(db, business_id, document_id)

	if settings["workflow_mode"] != WORKFLOW_TWO_STEP:
		raise ApiError(
			"WORKFLOW_NOT_TWO_STEP",
			"ارسال به حسابداری فقط در حالت گردش‌کار دو مرحله‌ای فعال است",
			http_status=400,
		)
	if doc.status != STATUS_DRAFT_OPS:
		raise ApiError("INVALID_STATUS", "فقط پیش‌نویس عملیاتی قابل ارسال است", http_status=400)
	if not doc.lines:
		raise ApiError("LINES_REQUIRED", "سند بدون سطر قابل ارسال نیست", http_status=400)

	# اگر حساب هنوز ست نشده، پیش‌فرض را بگذار تا حسابدار سریع‌تر تأیید کند
	if not doc.effect_account_id:
		acc = default_effect_account(db, business_id, biz, doc.doc_kind)
		doc.effect_account_id = acc.id

	doc.status = STATUS_PENDING_ACCOUNTING
	doc.submitted_by_user_id = user_id
	doc.submitted_at = datetime.utcnow()
	doc.touch()

	if commit:
		db.commit()
		doc = _load_document(db, business_id, document_id)
	else:
		db.flush()
	return _document_to_dict(doc, db)


def allocate_account(
	db: Session,
	business_id: int,
	user_id: int,
	document_id: int,
	data: Dict[str, Any],
	*,
	commit: bool = True,
) -> Dict[str, Any]:
	biz = _get_business(db, business_id)
	doc = _load_document(db, business_id, document_id)

	if doc.status not in (STATUS_PENDING_ACCOUNTING, STATUS_DRAFT_ACCOUNTING, STATUS_DRAFT_OPS):
		raise ApiError("INVALID_STATUS", "وضعیت سند برای تخصیص حساب مناسب نیست", http_status=400)

	if data.get("effect_account_id"):
		acc = resolve_account_by_id(db, business_id, int(data["effect_account_id"]))
	elif data.get("effect_account_code"):
		acc = resolve_account_by_code(db, business_id, str(data["effect_account_code"]))
	else:
		acc = default_effect_account(db, business_id, biz, doc.doc_kind)

	_assert_leaf_account(db, acc, business_id)
	_assert_account_kind_compatible(acc, doc.doc_kind)
	doc.effect_account_id = acc.id
	doc.status = STATUS_DRAFT_ACCOUNTING
	doc.allocated_by_user_id = user_id
	doc.allocated_at = datetime.utcnow()
	doc.touch()

	if "description" in data and data.get("description") is not None:
		doc.description = str(data.get("description")).strip() or doc.description

	if commit:
		db.commit()
		doc = _load_document(db, business_id, document_id)
	else:
		db.flush()
	return _document_to_dict(doc, db)


def _create_warehouse_and_post(
	db: Session,
	business_id: int,
	user_id: int,
	doc: GoodsExpenseIncomeDocument,
) -> WarehouseDocument:
	from app.services.warehouse_service import (
		_generate_warehouse_document_code,
		_is_duplicate_warehouse_document_code_error,
		post_warehouse_document,
	)

	is_expense = doc.doc_kind == DOC_KIND_EXPENSE
	wh_doc_type = "issue" if is_expense else "receipt"
	movement = "out" if is_expense else "in"

	# انبار غالب برای هدر
	warehouse_ids = {int(ln.warehouse_id) for ln in doc.lines}
	primary_wh = next(iter(warehouse_ids))

	wh: Optional[WarehouseDocument] = None
	for attempt in range(10):
		code = _generate_warehouse_document_code(db, business_id, doc.document_date)
		try:
			with db.begin_nested():
				wh = WarehouseDocument(
					business_id=business_id,
					fiscal_year_id=doc.fiscal_year_id,
					code=code,
					document_date=doc.document_date,
					status="draft",
					doc_type=wh_doc_type,
					warehouse_id_from=primary_wh if is_expense else None,
					warehouse_id_to=None if is_expense else primary_wh,
					source_type="goods_expense_income",
					source_document_id=doc.id,
					created_by_user_id=user_id,
					extra_info={
						"goods_expense_income_id": doc.id,
						"goods_expense_income_code": doc.code,
						"doc_kind": doc.doc_kind,
						"description": doc.description,
					},
				)
				db.add(wh)
				db.flush()
			break
		except IntegrityError as e:
			if _is_duplicate_warehouse_document_code_error(e) and attempt < 9:
				continue
			raise

	if wh is None:
		raise ApiError("WAREHOUSE_CODE_CONFLICT", "تولید کد حواله ناموفق بود", http_status=500)

	for ln in doc.lines:
		db.add(
			WarehouseDocumentLine(
				warehouse_document_id=wh.id,
				product_id=ln.product_id,
				warehouse_id=ln.warehouse_id,
				movement=movement,
				quantity=ln.quantity,
				extra_info={
					"unit_cost": float(ln.unit_cost or 0),
					"amount": float(ln.amount or 0),
					"goods_expense_income_line_id": ln.id,
					"description": ln.description,
				},
			)
		)
	db.flush()
	post_warehouse_document(db, wh.id)
	return wh


def _create_accounting_document(
	db: Session,
	business_id: int,
	user_id: int,
	doc: GoodsExpenseIncomeDocument,
) -> Document:
	if not doc.effect_account_id:
		raise ApiError("ACCOUNT_REQUIRED", "حساب هزینه/درآمد برای قطعی‌سازی الزامی است", http_status=400)

	inventory_acc = resolve_account_by_code(db, business_id, INVENTORY_ACCOUNT_CODE)
	effect_acc = resolve_account_by_id(db, business_id, int(doc.effect_account_id))
	_assert_leaf_account(db, effect_acc, business_id)
	_assert_account_kind_compatible(effect_acc, doc.doc_kind)

	total = _money(doc.total_amount)
	if total <= 0:
		raise ApiError("ZERO_AMOUNT", "مبلغ سند باید بزرگ‌تر از صفر باشد", http_status=400)

	is_expense = doc.doc_kind == DOC_KIND_EXPENSE
	gl_type = DOC_KIND_EXPENSE if is_expense else DOC_KIND_INCOME
	desc = doc.description or (
		f"کالای هزینه‌شده {doc.code}" if is_expense else f"کالای درآمدشده {doc.code}"
	)

	ensure_document_policy_allows_creation(
		db,
		business_id,
		document_type=gl_type,
		document_date=doc.document_date,
		amount=total,
	)

	gl_doc: Optional[Document] = None
	for attempt in range(8):
		code = generate_document_code(db, business_id, gl_type, doc.document_date)
		try:
			with db.begin_nested():
				gl_doc = Document(
					code=code,
					business_id=business_id,
					fiscal_year_id=doc.fiscal_year_id,
					currency_id=doc.currency_id,
					created_by_user_id=user_id,
					document_date=doc.document_date,
					document_type=gl_type,
					is_proforma=False,
					description=desc,
					extra_info={
						"goods_expense_income_id": doc.id,
						"goods_expense_income_code": doc.code,
						"doc_kind": doc.doc_kind,
						"person_id": doc.person_id,
						"warehouse_document_id": doc.warehouse_document_id,
					},
				)
				db.add(gl_doc)
				db.flush()
			break
		except IntegrityError:
			if attempt >= 7:
				raise
			continue

	if gl_doc is None:
		raise ApiError("CODE_CONFLICT", "تولید کد سند حسابداری ناموفق بود", http_status=500)

	# آرتیکل اثر (هزینه یا درآمد)
	# جزئیات کالا فقط در extra_info نگهداری می‌شود تا موجودی مالی از DocumentLine.product_id دوبار شمارش نشود.
	product_snapshot = [
		{
			"line_no": ln.line_no,
			"product_id": ln.product_id,
			"warehouse_id": ln.warehouse_id,
			"quantity": float(ln.quantity or 0),
			"unit_cost": float(ln.unit_cost or 0),
			"amount": float(ln.amount or 0),
			"description": ln.description,
			"goods_expense_income_line_id": ln.id,
		}
		for ln in doc.lines
	]

	if is_expense:
		# Dr هزینه / Cr موجودی
		db.add(
			DocumentLine(
				document_id=gl_doc.id,
				account_id=effect_acc.id,
				person_id=doc.person_id,
				debit=total,
				credit=Decimal("0"),
				description=desc,
				extra_info={
					"side": "effect",
					"goods_expense_income_id": doc.id,
					"product_lines": product_snapshot,
				},
			)
		)
		db.add(
			DocumentLine(
				document_id=gl_doc.id,
				account_id=inventory_acc.id,
				debit=Decimal("0"),
				credit=total,
				description=f"خروج موجودی بابت {doc.code}",
				extra_info={
					"side": "inventory",
					"goods_expense_income_id": doc.id,
					"inventory_posted": False,
					"product_lines": product_snapshot,
				},
			)
		)
	else:
		# Dr موجودی / Cr درآمد
		db.add(
			DocumentLine(
				document_id=gl_doc.id,
				account_id=inventory_acc.id,
				debit=total,
				credit=Decimal("0"),
				description=f"ورود موجودی بابت {doc.code}",
				extra_info={
					"side": "inventory",
					"goods_expense_income_id": doc.id,
					"inventory_posted": False,
					"product_lines": product_snapshot,
				},
			)
		)
		db.add(
			DocumentLine(
				document_id=gl_doc.id,
				account_id=effect_acc.id,
				person_id=doc.person_id,
				debit=Decimal("0"),
				credit=total,
				description=desc,
				extra_info={
					"side": "effect",
					"goods_expense_income_id": doc.id,
					"product_lines": product_snapshot,
				},
			)
		)

	db.flush()
	return gl_doc


def _create_reversing_accounting_document(
	db: Session,
	business_id: int,
	user_id: int,
	doc: GoodsExpenseIncomeDocument,
	original_gl: Document,
) -> Document:
	lines = (
		db.query(DocumentLine)
		.filter(DocumentLine.document_id == original_gl.id)
		.all()
	)
	money_lines = [ln for ln in lines if (ln.debit or 0) != 0 or (ln.credit or 0) != 0]
	if not money_lines:
		raise ApiError("NO_GL_LINES", "سند حسابداری اصلی خط ریالی ندارد", http_status=400)

	gl_type = f"{doc.doc_kind}_reversal"
	desc = f"ابطال {doc.code}"
	total = _money(doc.total_amount)

	ensure_document_policy_allows_creation(
		db,
		business_id,
		document_type=doc.doc_kind,
		document_date=doc.document_date,
		amount=total,
	)

	rev: Optional[Document] = None
	for attempt in range(8):
		code = generate_document_code(db, business_id, doc.doc_kind, doc.document_date)
		try:
			with db.begin_nested():
				rev = Document(
					code=code,
					business_id=business_id,
					fiscal_year_id=doc.fiscal_year_id,
					currency_id=doc.currency_id,
					created_by_user_id=user_id,
					document_date=doc.document_date,
					document_type=doc.doc_kind,
					is_proforma=False,
					description=desc,
					extra_info={
						"goods_expense_income_id": doc.id,
						"reverses_document_id": original_gl.id,
						"is_reversal": True,
					},
				)
				db.add(rev)
				db.flush()
			break
		except IntegrityError:
			if attempt >= 7:
				raise
			continue

	if rev is None:
		raise ApiError("CODE_CONFLICT", "تولید کد سند ابطال ناموفق بود", http_status=500)

	for ln in money_lines:
		db.add(
			DocumentLine(
				document_id=rev.id,
				account_id=ln.account_id,
				person_id=ln.person_id,
				product_id=ln.product_id,
				quantity=ln.quantity,
				debit=_money(ln.credit),
				credit=_money(ln.debit),
				description=desc,
				extra_info={
					**(ln.extra_info or {}),
					"reverses_line_id": ln.id,
					"is_reversal": True,
				},
			)
		)
	db.flush()
	_ = gl_type  # reserved for future numbering split
	return rev


def _post_document_internal(
	db: Session,
	business_id: int,
	user_id: int,
	doc: GoodsExpenseIncomeDocument,
) -> None:
	if doc.status == STATUS_POSTED:
		return
	if doc.status == STATUS_CANCELLED:
		raise ApiError("ALREADY_CANCELLED", "سند ابطال‌شده قابل قطعی‌سازی نیست", http_status=400)
	if not doc.effect_account_id:
		raise ApiError("ACCOUNT_REQUIRED", "ابتدا حساب هزینه/درآمد را تخصیص دهید", http_status=400)
	if not doc.lines:
		raise ApiError("LINES_REQUIRED", "سند بدون سطر قابل قطعی‌سازی نیست", http_status=400)
	if _money(doc.total_amount) <= 0:
		raise ApiError("ZERO_AMOUNT", "مبلغ سند نامعتبر است", http_status=400)

	wh = _create_warehouse_and_post(db, business_id, user_id, doc)
	doc.warehouse_document_id = wh.id
	db.flush()

	gl = _create_accounting_document(db, business_id, user_id, doc)
	# لینک دوطرفه
	extra = dict(gl.extra_info or {})
	extra["warehouse_document_id"] = wh.id
	gl.extra_info = extra

	doc.accounting_document_id = gl.id
	doc.status = STATUS_POSTED
	doc.posted_by_user_id = user_id
	doc.posted_at = datetime.utcnow()
	doc.touch()
	db.flush()


def post_document(
	db: Session,
	business_id: int,
	user_id: int,
	document_id: int,
	*,
	commit: bool = True,
) -> Dict[str, Any]:
	doc = _load_document(db, business_id, document_id)
	if doc.status not in (
		STATUS_DRAFT_OPS,
		STATUS_PENDING_ACCOUNTING,
		STATUS_DRAFT_ACCOUNTING,
	):
		raise ApiError("INVALID_STATUS", "وضعیت سند برای قطعی‌سازی مناسب نیست", http_status=400)

	_post_document_internal(db, business_id, user_id, doc)

	if commit:
		db.commit()
		doc = _load_document(db, business_id, document_id)
	else:
		db.flush()
	return _document_to_dict(doc, db)


def cancel_document(
	db: Session,
	business_id: int,
	user_id: int,
	document_id: int,
	*,
	commit: bool = True,
) -> Dict[str, Any]:
	from app.services.warehouse_service import cancel_warehouse_document

	doc = _load_document(db, business_id, document_id)
	if doc.status != STATUS_POSTED:
		raise ApiError("NOT_CANCELLABLE", "فقط اسناد قطعی قابل ابطال هستند", http_status=400)

	if doc.warehouse_document_id:
		# seal_reversal پیش‌فرض برای source_type=goods_expense_income فعال است
		cancel_wh = cancel_warehouse_document(
			db, business_id, int(doc.warehouse_document_id), user_id
		)
		extra = dict(doc.extra_info or {})
		extra["cancelled_warehouse_document_id"] = doc.warehouse_document_id
		extra["cancel_reversal_warehouse_document_id"] = cancel_wh.id
		extra["cancel_reversal_sealed"] = bool(
			(cancel_wh.extra_info or {}).get("audit_only_reversal")
		)
		doc.extra_info = extra

	if doc.accounting_document_id:
		original_gl = (
			db.query(Document)
			.filter(
				and_(
					Document.id == int(doc.accounting_document_id),
					Document.business_id == business_id,
				)
			)
			.first()
		)
		if original_gl:
			rev = _create_reversing_accounting_document(db, business_id, user_id, doc, original_gl)
			extra = dict(doc.extra_info or {})
			extra["reversal_accounting_document_id"] = rev.id
			if "cancelled_warehouse_document_id" not in extra:
				extra["cancelled_warehouse_document_id"] = doc.warehouse_document_id
			doc.extra_info = extra

	doc.status = STATUS_CANCELLED
	doc.cancelled_by_user_id = user_id
	doc.cancelled_at = datetime.utcnow()
	doc.touch()

	if commit:
		db.commit()
		doc = _load_document(db, business_id, document_id)
	else:
		db.flush()
	return _document_to_dict(doc, db)


def delete_document(
	db: Session,
	business_id: int,
	document_id: int,
	*,
	commit: bool = True,
) -> Dict[str, Any]:
	doc = _load_document(db, business_id, document_id)
	if doc.status not in (STATUS_DRAFT_OPS, STATUS_PENDING_ACCOUNTING, STATUS_DRAFT_ACCOUNTING):
		raise ApiError("NOT_DELETABLE", "فقط اسناد غیرقطعی قابل حذف هستند", http_status=400)
	payload = _document_to_dict(doc, db)
	db.delete(doc)
	if commit:
		db.commit()
	else:
		db.flush()
	return payload


def get_document(db: Session, business_id: int, document_id: int) -> Dict[str, Any]:
	doc = _load_document(db, business_id, document_id)
	return _document_to_dict(doc, db)


def list_documents(
	db: Session,
	business_id: int,
	query: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
	query = query or {}
	q = db.query(GoodsExpenseIncomeDocument).filter(
		GoodsExpenseIncomeDocument.business_id == int(business_id)
	)

	fiscal_year_id = query.get("fiscal_year_id")
	if fiscal_year_id:
		q = q.filter(GoodsExpenseIncomeDocument.fiscal_year_id == int(fiscal_year_id))

	doc_kind = query.get("doc_kind")
	if doc_kind:
		q = q.filter(GoodsExpenseIncomeDocument.doc_kind == str(doc_kind))

	status = query.get("status")
	if status:
		q = q.filter(GoodsExpenseIncomeDocument.status == str(status))

	person_id = query.get("person_id")
	if person_id:
		q = q.filter(GoodsExpenseIncomeDocument.person_id == int(person_id))

	search = (query.get("search") or query.get("q") or "").strip()
	if search:
		like = f"%{search}%"
		q = q.filter(
			or_(
				GoodsExpenseIncomeDocument.code.ilike(like),
				GoodsExpenseIncomeDocument.description.ilike(like),
			)
		)

	date_from = query.get("date_from") or query.get("from_date")
	date_to = query.get("date_to") or query.get("to_date")
	if date_from:
		q = q.filter(GoodsExpenseIncomeDocument.document_date >= _parse_iso_date(date_from))
	if date_to:
		q = q.filter(GoodsExpenseIncomeDocument.document_date <= _parse_iso_date(date_to))

	total = q.with_entities(func.count(GoodsExpenseIncomeDocument.id)).scalar() or 0
	page = max(int(query.get("page") or 1), 1)
	page_size = min(max(int(query.get("page_size") or query.get("take") or 20), 1), 200)
	rows = (
		q.order_by(
			GoodsExpenseIncomeDocument.document_date.desc(),
			GoodsExpenseIncomeDocument.id.desc(),
		)
		.offset((page - 1) * page_size)
		.limit(page_size)
		.all()
	)

	items = [_document_to_dict(r, db) for r in rows]
	return {
		"items": items,
		"total": int(total),
		"page": page,
		"page_size": page_size,
	}


def create_from_stock_count(
	db: Session,
	business_id: int,
	user_id: int,
	*,
	stock_count_code: str,
	stock_count_date: date,
	items: List[Dict[str, Any]],
	notes: Optional[str] = None,
	user_can_allocate: bool = True,
	user_can_post: bool = False,
	commit: bool = True,
) -> Dict[str, Any]:
	"""
	از اختلافات انبارگردانی دو سند (کسری=هزینه، اضافه=درآمد) می‌سازد.
	"""
	biz = _get_business(db, business_id)
	settings = get_workflow_settings(biz)

	# فقط ردیف‌هایی که واقعاً اختلاف دارند
	diff_items = [
		item for item in items
		if Decimal(str((item or {}).get("difference") or 0)) != 0
	]
	if not diff_items:
		raise ApiError("NO_DIFFERENCES", "هیچ اختلافی برای ثبت وجود ندارد", http_status=400)

	shortage_lines: List[Dict[str, Any]] = []
	surplus_lines: List[Dict[str, Any]] = []
	for item in diff_items:
		diff = Decimal(str(item.get("difference") or 0))
		if diff == 0:
			continue
		base = {
			"product_id": item.get("product_id"),
			"warehouse_id": item.get("warehouse_id"),
			"quantity": abs(diff),
			"description": item.get("description"),
			"extra_info": {
				"system_quantity": item.get("system_quantity"),
				"physical_quantity": item.get("physical_quantity"),
				"difference": float(diff),
				"stock_count_code": stock_count_code,
			},
		}
		if diff < 0:
			shortage_lines.append(base)
		else:
			surplus_lines.append(base)

	if not shortage_lines and not surplus_lines:
		raise ApiError("NO_DIFFERENCES", "هیچ اختلافی برای ثبت وجود ندارد", http_status=400)

	created: Dict[str, Any] = {"expense": None, "income": None, "settings": settings}
	extra = {
		"stock_count_code": stock_count_code,
		"stock_count_date": stock_count_date.isoformat(),
		"notes": notes,
		"source": "stock_count",
	}

	if shortage_lines:
		created["expense"] = create_document(
			db,
			business_id,
			user_id,
			{
				"doc_kind": DOC_KIND_EXPENSE,
				"document_date": stock_count_date.isoformat(),
				"description": notes or f"کسری انبارگردانی {stock_count_code}",
				"lines": shortage_lines,
				"extra_info": extra,
				"auto_post": False,
			},
			user_can_allocate=user_can_allocate,
			user_can_post=False,
			commit=False,
		)

	if surplus_lines:
		created["income"] = create_document(
			db,
			business_id,
			user_id,
			{
				"doc_kind": DOC_KIND_INCOME,
				"document_date": stock_count_date.isoformat(),
				"description": notes or f"اضافه انبارگردانی {stock_count_code}",
				"lines": surplus_lines,
				"extra_info": extra,
				"auto_post": False,
			},
			user_can_allocate=user_can_allocate,
			user_can_post=False,
			commit=False,
		)

	if commit:
		db.commit()
	else:
		db.flush()
	return created
