"""
SQLAlchemy Events برای لاگ‌گیری خودکار فعالیت‌ها
این فایل باید import شود تا event handlers ثبت شوند
"""
from sqlalchemy import event
from sqlalchemy.orm import Session
from datetime import datetime
from typing import Dict, Any, Optional
from decimal import Decimal
from adapters.db.models.activity_log import ActivityLog

# Import مدل‌ها برای mapping
from adapters.db.models.document import Document
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.product import Product
from adapters.db.models.person import Person
from adapters.db.models.business import Business
from adapters.db.models.account import Account
from adapters.db.models.user import User
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.warehouse import Warehouse
from adapters.db.models.bank_account import BankAccount
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.petty_cash import PettyCash
from adapters.db.models.check import Check
from adapters.db.models.category import BusinessCategory
from adapters.db.models.product_attribute import ProductAttribute
from adapters.db.models.price_list import PriceList
from adapters.db.models.product_bom import ProductBOM
from adapters.db.models.tax_setting import TaxSetting
from adapters.db.models.tax_type import TaxType
from adapters.db.models.tax_unit import TaxUnit
from adapters.db.models.business_permission import BusinessPermission
from adapters.db.models.business_print_settings import BusinessPrintSettings
from adapters.db.models.person import PersonBankAccount
from adapters.db.models.credit import BusinessCreditSetting
from adapters.db.models.report_template import ReportTemplate
from adapters.db.models.document_numbering import BusinessDocumentNumberingSetting
from adapters.db.models.support.ticket import Ticket
from adapters.db.models.wallet import WalletAccount, WalletTransaction


# Context برای ذخیره اطلاعات کاربر جاری در session
class ActivityLogContext:
	"""Context برای ذخیره اطلاعات کاربر و request در session"""
	_contexts: Dict[int, Dict[str, Any]] = {}  # session_id -> context
	
	@classmethod
	def set_context(cls, session: Session, user_id: int, business_id: Optional[int] = None, request: Optional[Any] = None):
		"""تنظیم context برای session"""
		session_id = id(session)
		cls._contexts[session_id] = {
			"user_id": user_id,
			"business_id": business_id,
			"request": request,
			"session": session
		}
	
	@classmethod
	def get_context(cls, session: Session) -> Optional[Dict[str, Any]]:
		"""دریافت context از session"""
		session_id = id(session)
		return cls._contexts.get(session_id)
	
	@classmethod
	def clear_context(cls, session: Session):
		"""پاک کردن context بعد از commit"""
		session_id = id(session)
		cls._contexts.pop(session_id, None)


# Mapping مدل‌ها به category و entity_type
MODEL_CATEGORY_MAP = {
	# Accounting
	Document: ("accounting", "document"),
	Account: ("accounting", "account"),
	FiscalYear: ("accounting", "fiscal_year"),
	BankAccount: ("accounting", "bank_account"),
	CashRegister: ("accounting", "cash_register"),
	PettyCash: ("accounting", "petty_cash"),
	Check: ("accounting", "check"),
	BusinessCreditSetting: ("accounting", "credit_setting"),
	
	# Warehouse
	WarehouseDocument: ("warehouse", "warehouse_document"),
	Warehouse: ("warehouse", "warehouse"),
	
	# Product
	Product: ("product", "product"),
	BusinessCategory: ("product", "category"),
	ProductAttribute: ("product", "product_attribute"),
	PriceList: ("product", "price_list"),
	ProductBOM: ("product", "product_bom"),
	
	# Person
	Person: ("person", "person"),
	PersonBankAccount: ("person", "person_bank_account"),
	
	# Business
	Business: ("business", "business"),
	BusinessPermission: ("business", "business_permission"),
	BusinessPrintSettings: ("business", "business_print_settings"),
	
	# Settings
	TaxSetting: ("settings", "tax_setting"),
	TaxType: ("settings", "tax_type"),
	TaxUnit: ("settings", "tax_unit"),
	ReportTemplate: ("settings", "report_template"),
	BusinessDocumentNumberingSetting: ("settings", "document_numbering"),
	
	# Support
	Ticket: ("support", "ticket"),
	
	# Wallet
	WalletAccount: ("wallet", "wallet_account"),
	WalletTransaction: ("wallet", "wallet_transaction"),
	
	# User
	User: ("user", "user"),
}


# Helper function برای استخراج business_id از instance
def get_business_id(instance) -> Optional[int]:
	"""استخراج business_id از instance"""
	if hasattr(instance, 'business_id'):
		return getattr(instance, 'business_id')
	# برای User که business_id ندارد
	return None


# Helper function برای استخراج user_id از instance
def get_user_id(instance, context: Optional[Dict[str, Any]]) -> Optional[int]:
	"""استخراج user_id از instance یا context"""
	# اول از context بگیر
	if context and context.get("user_id"):
		return context["user_id"]
	
	# اگر context نبود، از instance بگیر (مثلاً Document.created_by_user_id)
	if hasattr(instance, 'created_by_user_id'):
		return getattr(instance, 'created_by_user_id')
	
	return None


# Helper function برای ساخت description
def build_description(instance, action: str) -> str:
	"""ساخت description قابل خواندن"""
	model_name = instance.__class__.__name__
	
	# استخراج نام یا کد برای نمایش
	name = None
	if hasattr(instance, 'name'):
		name = getattr(instance, 'name')
	elif hasattr(instance, 'code'):
		code = getattr(instance, 'code')
		if code:
			name = str(code)
	elif hasattr(instance, 'first_name') and hasattr(instance, 'last_name'):
		first = getattr(instance, 'first_name', '') or ''
		last = getattr(instance, 'last_name', '') or ''
		name = f"{first} {last}".strip()
		if not name and hasattr(instance, 'alias_name'):
			name = getattr(instance, 'alias_name')
	elif hasattr(instance, 'alias_name'):
		name = getattr(instance, 'alias_name')
	elif hasattr(instance, 'email'):
		name = getattr(instance, 'email')
	
	name_str = f" '{name}'" if name else ""
	
	action_map = {
		"create": "ایجاد شد",
		"update": "ویرایش شد",
		"delete": "حذف شد"
	}
	action_persian = action_map.get(action, action)
	
	# نام فارسی برای مدل‌ها
	model_name_map = {
		# Accounting
		"Document": "سند",
		"Account": "حساب",
		"FiscalYear": "سال مالی",
		"BankAccount": "حساب بانکی",
		"CashRegister": "صندوق",
		"PettyCash": "تنخواه گردان",
		"Check": "چک",
		"BusinessCreditSetting": "تنظیمات اعتبار",
		
		# Warehouse
		"WarehouseDocument": "حواله انبار",
		"Warehouse": "انبار",
		
		# Product
		"Product": "محصول",
		"BusinessCategory": "دسته‌بندی",
		"ProductAttribute": "ویژگی محصول",
		"PriceList": "لیست قیمت",
		"ProductBOM": "فرمول تولید",
		
		# Person
		"Person": "شخص",
		"PersonBankAccount": "حساب بانکی شخص",
		
		# Business
		"Business": "کسب و کار",
		"BusinessPermission": "مجوز کسب و کار",
		"BusinessPrintSettings": "تنظیمات چاپ",
		
		# Settings
		"TaxSetting": "تنظیمات مالیاتی",
		"TaxType": "نوع مالیات",
		"TaxUnit": "واحد مالیاتی",
		"ReportTemplate": "قالب گزارش",
		"BusinessDocumentNumberingSetting": "شماره‌گذاری اسناد",
		
		# Support
		"Ticket": "تیکت پشتیبانی",
		
		# Wallet
		"WalletAccount": "حساب کیف پول",
		"WalletTransaction": "تراکنش کیف پول",
		
		# User
		"User": "کاربر",
	}
	model_persian = model_name_map.get(model_name, model_name)
	
	return f"{model_persian}{name_str} {action_persian}"


# Helper function برای استخراج داده‌های مهم
def _to_json_serializable(value: Any) -> Any:
	"""تبدیل مقدار به نوع قابل JSON"""
	if value is None:
		return None
	if hasattr(value, 'value'):  # Enum
		return value.value
	if isinstance(value, datetime):
		return value.isoformat()
	if isinstance(value, Decimal):
		return float(value)
	if isinstance(value, (int, float, str, bool)):
		return value
	# برای سایر انواع، به string تبدیل کن
	return str(value)


def extract_key_fields(instance) -> Dict[str, Any]:
	"""استخراج فیلدهای مهم برای لاگ"""
	key_fields = {}
	
	# فیلدهای مشترک
	if hasattr(instance, 'id'):
		key_fields['id'] = getattr(instance, 'id')
	if hasattr(instance, 'code'):
		code = getattr(instance, 'code')
		if code is not None:
			key_fields['code'] = str(code)
	if hasattr(instance, 'name'):
		name = getattr(instance, 'name')
		if name:
			key_fields['name'] = name
	
	# فیلدهای خاص برای Document
	if isinstance(instance, Document):
		if hasattr(instance, 'document_type'):
			key_fields['document_type'] = getattr(instance, 'document_type')
		if hasattr(instance, 'document_date'):
			doc_date = getattr(instance, 'document_date')
			if doc_date:
				key_fields['document_date'] = str(doc_date)
	
	# فیلدهای خاص برای Product
	if isinstance(instance, Product):
		if hasattr(instance, 'base_sales_price'):
			price = getattr(instance, 'base_sales_price')
			if price is not None:
				key_fields['base_sales_price'] = float(price)
	
	# فیلدهای خاص برای Person
	if isinstance(instance, Person):
		if hasattr(instance, 'first_name'):
			key_fields['first_name'] = getattr(instance, 'first_name')
		if hasattr(instance, 'last_name'):
			key_fields['last_name'] = getattr(instance, 'last_name')
		if hasattr(instance, 'alias_name'):
			key_fields['alias_name'] = getattr(instance, 'alias_name')
	
	# فیلدهای خاص برای Business
	if isinstance(instance, Business):
		if hasattr(instance, 'business_type'):
			key_fields['business_type'] = getattr(instance, 'business_type')
	
	# فیلدهای خاص برای Warehouse
	if isinstance(instance, Warehouse):
		if hasattr(instance, 'code'):
			key_fields['code'] = getattr(instance, 'code')
	
	# فیلدهای خاص برای BankAccount
	if isinstance(instance, BankAccount):
		if hasattr(instance, 'account_number'):
			key_fields['account_number'] = getattr(instance, 'account_number')
	
	# فیلدهای خاص برای Check
	if isinstance(instance, Check):
		if hasattr(instance, 'check_number'):
			key_fields['check_number'] = getattr(instance, 'check_number')
		if hasattr(instance, 'amount'):
			amount = getattr(instance, 'amount')
			if amount is not None:
				key_fields['amount'] = float(amount)
	
	# فیلدهای خاص برای PriceList
	if isinstance(instance, PriceList):
		if hasattr(instance, 'is_active'):
			key_fields['is_active'] = getattr(instance, 'is_active')
	
	# فیلدهای خاص برای ProductBOM
	if isinstance(instance, ProductBOM):
		if hasattr(instance, 'version'):
			key_fields['version'] = getattr(instance, 'version')
		if hasattr(instance, 'product_id'):
			key_fields['product_id'] = getattr(instance, 'product_id')
	
	# فیلدهای خاص برای BusinessCategory
	if isinstance(instance, BusinessCategory):
		# از title_translations استفاده کن
		if hasattr(instance, 'title_translations'):
			title_trans = getattr(instance, 'title_translations')
			if title_trans and isinstance(title_trans, dict):
				# اولین مقدار را بگیر
				if title_trans:
					key_fields['title'] = list(title_trans.values())[0] if title_trans.values() else None
	
	# فیلدهای خاص برای BusinessPermission
	if isinstance(instance, BusinessPermission):
		if hasattr(instance, 'user_id'):
			key_fields['user_id'] = getattr(instance, 'user_id')
	
	# فیلدهای خاص برای Ticket
	if isinstance(instance, Ticket):
		if hasattr(instance, 'title'):
			key_fields['title'] = getattr(instance, 'title')
		if hasattr(instance, 'status_id'):
			key_fields['status_id'] = getattr(instance, 'status_id')
	
	# فیلدهای خاص برای WalletTransaction
	if isinstance(instance, WalletTransaction):
		if hasattr(instance, 'type'):
			key_fields['type'] = getattr(instance, 'type')
		if hasattr(instance, 'amount'):
			amount = getattr(instance, 'amount')
			if amount is not None:
				key_fields['amount'] = float(amount)
		if hasattr(instance, 'status'):
			key_fields['status'] = getattr(instance, 'status')
	
	# فیلدهای خاص برای WalletAccount
	if isinstance(instance, WalletAccount):
		if hasattr(instance, 'available_balance'):
			balance = getattr(instance, 'available_balance')
			if balance is not None:
				key_fields['available_balance'] = float(balance)
	
	return key_fields


# Helper function برای استخراج extra_info از request
def extract_extra_info(request: Optional[Any]) -> Dict[str, Any]:
	"""استخراج اطلاعات اضافی از request"""
	extra_info = {}
	if request:
		if hasattr(request, 'client') and request.client:
			extra_info['ip_address'] = request.client.host
		if hasattr(request, 'headers'):
			user_agent = request.headers.get("User-Agent")
			if user_agent:
				extra_info['user_agent'] = user_agent
	return extra_info


# Event Handlers

@event.listens_for(Session, "after_flush")
def receive_after_flush(session: Session, flush_context):
	"""لاگ‌گیری بعد از flush (قبل از commit)"""
	context = ActivityLogContext.get_context(session)
	if not context:
		return  # اگر context تنظیم نشده، لاگ نگیر
	
	user_id = context.get("user_id")
	business_id = context.get("business_id")
	request = context.get("request")
	
	if not user_id:
		return
	
	# پردازش instances جدید (insert)
	for instance in session.new:
		if instance.__class__ not in MODEL_CATEGORY_MAP:
			continue
		
		# برای ActivityLog خودش لاگ نگیر (جلوگیری از recursion)
		if isinstance(instance, ActivityLog):
			continue
		
		category, entity_type = MODEL_CATEGORY_MAP[instance.__class__]
		instance_business_id = get_business_id(instance) or business_id
		
		# برای User، business_id نداریم
		if isinstance(instance, User):
			instance_business_id = None
		
		# استخراج user_id از instance یا context
		instance_user_id = get_user_id(instance, context) or user_id
		
		description = build_description(instance, "create")
		after_data = extract_key_fields(instance)
		extra_info = extract_extra_info(request)
		
		log = ActivityLog(
			user_id=instance_user_id,
			business_id=instance_business_id,
			category=category,
			action="create",
			entity_type=entity_type,
			entity_id=getattr(instance, 'id', None),
			description=description,
			after_data=after_data if after_data else None,
			extra_info=extra_info if extra_info else None,
			created_at=datetime.utcnow()
		)
		session.add(log)
	
	# پردازش instances تغییر یافته (update)
	for instance in session.dirty:
		if instance.__class__ not in MODEL_CATEGORY_MAP:
			continue
		
		# برای ActivityLog خودش لاگ نگیر
		if isinstance(instance, ActivityLog):
			continue
		
		category, entity_type = MODEL_CATEGORY_MAP[instance.__class__]
		instance_business_id = get_business_id(instance) or business_id
		
		if isinstance(instance, User):
			instance_business_id = None
		
		instance_user_id = get_user_id(instance, context) or user_id
		
		# استخراج تغییرات
		before_data = {}
		after_data = {}
		
		# SQLAlchemy history برای تغییرات
		from sqlalchemy.orm.attributes import get_history
		
		for attr_name in instance.__table__.columns.keys():
			# فیلدهای خاص را skip کن
			if attr_name in ['id', 'created_at', 'updated_at']:
				continue
			
			try:
				history = get_history(instance, attr_name)
				if history.has_changes():
					# مقدار قبلی
					if history.deleted:
						old_val = history.deleted[0]
						before_data[attr_name] = _to_json_serializable(old_val)
					# مقدار جدید
					if history.added:
						new_val = history.added[0]
						after_data[attr_name] = _to_json_serializable(new_val)
			except Exception:
				# اگر خطا در get_history بود، skip کن
				continue
		
		# فقط اگر تغییری وجود داشت
		if before_data or after_data:
			description = build_description(instance, "update")
			extra_info = extract_extra_info(request)
			
			log = ActivityLog(
				user_id=instance_user_id,
				business_id=instance_business_id,
				category=category,
				action="update",
				entity_type=entity_type,
				entity_id=getattr(instance, 'id', None),
				description=description,
				before_data=before_data if before_data else None,
				after_data=after_data if after_data else None,
				extra_info=extra_info if extra_info else None,
				created_at=datetime.utcnow()
			)
			session.add(log)
	
	# پردازش instances حذف شده (delete)
	for instance in session.deleted:
		if instance.__class__ not in MODEL_CATEGORY_MAP:
			continue
		
		# برای ActivityLog خودش لاگ نگیر
		if isinstance(instance, ActivityLog):
			continue
		
		category, entity_type = MODEL_CATEGORY_MAP[instance.__class__]
		instance_business_id = get_business_id(instance) or business_id
		
		if isinstance(instance, User):
			instance_business_id = None
		
		instance_user_id = get_user_id(instance, context) or user_id
		
		description = build_description(instance, "delete")
		before_data = extract_key_fields(instance)
		extra_info = extract_extra_info(request)
		
		log = ActivityLog(
			user_id=instance_user_id,
			business_id=instance_business_id,
			category=category,
			action="delete",
			entity_type=entity_type,
			entity_id=getattr(instance, 'id', None),
			description=description,
			before_data=before_data if before_data else None,
			extra_info=extra_info if extra_info else None,
			created_at=datetime.utcnow()
		)
		session.add(log)


@event.listens_for(Session, "after_commit")
def receive_after_commit(session: Session):
	"""پاک کردن context بعد از commit"""
	ActivityLogContext.clear_context(session)


@event.listens_for(Session, "after_rollback")
def receive_after_rollback(session: Session):
	"""پاک کردن context بعد از rollback"""
	ActivityLogContext.clear_context(session)

