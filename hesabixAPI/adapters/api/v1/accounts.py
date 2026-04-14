from typing import List, Dict, Any, Optional

from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session
from pydantic import BaseModel

from adapters.db.session import get_db
from adapters.api.v1.schemas import SuccessResponse
from adapters.api.v1.schema_models.account import AccountTreeNode, AccountCreateRequest, AccountUpdateRequest
from app.core.responses import success_response, ApiError
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_permission_dep, require_business_permission_by_entity_dep
from adapters.db.models.account import Account
from app.services.account_service import create_account, update_account, delete_account, get_account


router = APIRouter(prefix="/accounts", tags=["حسابداری"])


class SearchAccountsRequest(BaseModel):
	"""درخواست جستجوی حساب‌ها"""
	take: int = 50
	skip: int = 0
	search: Optional[str] = None
	sort_by: Optional[str] = "code"
	sort_desc: bool = False


def _build_tree(nodes: list[Dict[str, Any]]) -> list[AccountTreeNode]:
	by_id: dict[int, AccountTreeNode] = {}
	roots: list[AccountTreeNode] = []
	for n in nodes:
		node = AccountTreeNode(
			id=n['id'],
			code=n['code'],
			name=n['name'],
			account_type=n.get('account_type'),
			parent_id=n.get('parent_id'),
			business_id=n.get('business_id'),
			is_public=n.get('is_public'),
			has_children=n.get('has_children'),
			can_edit=n.get('can_edit'),
			can_delete=n.get('can_delete'),
		)
		by_id[node.id] = node
	for node in list(by_id.values()):
		pid = node.parent_id
		if pid and pid in by_id:
			by_id[pid].children.append(node)
		else:
			roots.append(node)
	return roots


@router.get("/business/{business_id}/tree",
	summary="دریافت درخت حساب‌ها برای یک کسب و کار",
	description="لیست حساب‌های عمومی و حساب‌های اختصاصی کسب و کار به صورت درختی",
)
@require_business_access("business_id")
def get_accounts_tree(
	request: Request,
	business_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_dep("chart_of_accounts", "view")),
) -> dict:
	# دریافت حساب‌های عمومی (business_id IS NULL) و حساب‌های مختص این کسب و کار
	rows = db.query(Account).filter(
		(Account.business_id == None) | (Account.business_id == business_id)  # noqa: E711
	).order_by(Account.code.asc()).all()
	# محاسبه has_children با شمارش فرزندان در مجموعه
	children_map: dict[int, int] = {}
	for r in rows:
		if r.parent_id:
			children_map[r.parent_id] = children_map.get(r.parent_id, 0) + 1
	flat: list[Dict[str, Any]] = []
	for r in rows:
		is_public = r.business_id is None
		has_children = children_map.get(r.id, 0) > 0
		can_edit = (r.business_id == business_id) and True  # شرط دسترسی نوشتن پایین‌تر بررسی می‌شود در UI/Endpoint
		can_delete = can_edit and (not has_children)
		flat.append({
			"id": r.id,
			"code": r.code,
			"name": r.name,
			"account_type": r.account_type,
			"parent_id": r.parent_id,
			"business_id": r.business_id,
			"is_public": is_public,
			"has_children": has_children,
			"can_edit": can_edit,
			"can_delete": can_delete,
		})
	tree = _build_tree(flat)
	return success_response({"items": [n.model_dump() for n in tree]}, request)


@router.get("/business/{business_id}",
	summary="دریافت لیست حساب‌ها برای یک کسب و کار",
	description="لیست تمام حساب‌های عمومی و حساب‌های اختصاصی کسب و کار (بدون ساختار درختی)",
)
@require_business_access("business_id")
def get_accounts_list(
	request: Request,
	business_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_dep("chart_of_accounts", "view")),
) -> dict:
	"""دریافت لیست ساده حساب‌ها"""
	rows = db.query(Account).filter(
		(Account.business_id == None) | (Account.business_id == business_id)  # noqa: E711
	).order_by(Account.code.asc()).all()
	
	items = [
		{
			"id": r.id,
			"code": r.code,
			"name": r.name,
			"account_type": r.account_type,
			"parent_id": r.parent_id,
			"business_id": r.business_id,
			"created_at": r.created_at.isoformat() if r.created_at else None,
			"updated_at": r.updated_at.isoformat() if r.updated_at else None,
		}
		for r in rows
	]
	return success_response({"items": items}, request)


@router.get("/business/{business_id}/account/{account_id}",
	summary="دریافت جزئیات یک حساب خاص",
	description="دریافت اطلاعات کامل یک حساب بر اساس ID",
)
@require_business_access("business_id")
def get_account_by_id(
	request: Request,
	business_id: int,
	account_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_by_entity_dep("chart_of_accounts", "view", Account, "account_id", allow_null_business_id=True)),
) -> dict:
	"""دریافت یک حساب خاص"""
	account = db.query(Account).filter(
		Account.id == account_id,
		(Account.business_id == None) | (Account.business_id == business_id)  # noqa: E711
	).first()
	
	if not account:
		from fastapi import HTTPException
		raise HTTPException(status_code=404, detail="حساب یافت نشد")
	
	account_data = {
		"id": account.id,
		"code": account.code,
		"name": account.name,
		"account_type": account.account_type,
		"parent_id": account.parent_id,
		"business_id": account.business_id,
		"created_at": account.created_at.isoformat() if account.created_at else None,
		"updated_at": account.updated_at.isoformat() if account.updated_at else None,
	}
	
	return success_response(account_data, request)


@router.post("/business/{business_id}",
	summary="جستجو و فیلتر حساب‌ها",
	description="جستجو در حساب‌ها با قابلیت فیلتر، مرتب‌سازی و صفحه‌بندی",
)
@require_business_access("business_id")
def search_accounts(
	request: Request,
	business_id: int,
	search_request: SearchAccountsRequest,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_dep("chart_of_accounts", "view")),
) -> dict:
	"""جستجوی حساب‌ها با فیلتر"""
	query = db.query(Account).filter(
		(Account.business_id == None) | (Account.business_id == business_id)  # noqa: E711
	)
	
	# اعمال جستجو
	if search_request.search:
		search_term = f"%{search_request.search}%"
		query = query.filter(
			(Account.code.ilike(search_term)) | (Account.name.ilike(search_term))
		)
	
	# شمارش کل
	total = query.count()
	
	# مرتب‌سازی
	if search_request.sort_by == "name":
		order_col = Account.name
	else:
		order_col = Account.code
	
	if search_request.sort_desc:
		query = query.order_by(order_col.desc())
	else:
		query = query.order_by(order_col.asc())
	
	# صفحه‌بندی
	query = query.offset(search_request.skip).limit(search_request.take)
	rows = query.all()
	
	items = [
		{
			"id": r.id,
			"code": r.code,
			"name": r.name,
			"account_type": r.account_type,
			"parent_id": r.parent_id,
			"business_id": r.business_id,
			"created_at": r.created_at.isoformat() if r.created_at else None,
			"updated_at": r.updated_at.isoformat() if r.updated_at else None,
		}
		for r in rows
	]
	
	return success_response({
		"items": items,
		"total": total,
		"skip": search_request.skip,
		"take": search_request.take,
	}, request)


@router.post(
	"/business/{business_id}/create",
	summary="ایجاد حساب جدید برای یک کسب‌وکار",
	description="ایجاد حساب اختصاصی (business-specific).",
)
@require_business_access("business_id")
def create_business_account(
	request: Request,
	business_id: int,
	body: AccountCreateRequest = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_dep("chart_of_accounts", "add")),
) -> dict:
	# والد اجباری است
	if body.parent_id is None:
		raise ApiError("PARENT_REQUIRED", "Parent account is required", http_status=400)
	# اگر والد عمومی است باید قبلا دارای زیرمجموعه باشد (اجازه ایجاد زیر شاخه برای برگ عمومی را نمی‌دهیم)
	parent = db.get(Account, int(body.parent_id)) if body.parent_id is not None else None
	if parent is None:
		raise ApiError("PARENT_NOT_FOUND", "Parent account not found", http_status=400)
	if parent.business_id is None:
		# lazy-load children count
		if not parent.children or len(parent.children) == 0:
			raise ApiError("INVALID_PUBLIC_PARENT", "Cannot add child under a public leaf account", http_status=400)
	try:
		created = create_account(
			db,
			name=body.name,
			code=body.code,
			account_type=body.account_type,
			business_id=business_id,
			parent_id=body.parent_id,
		)
		return success_response(created, request, message="ACCOUNT_CREATED")
	except ValueError as e:
		code = str(e)
		if code == "ACCOUNT_CODE_NOT_UNIQUE":
			raise ApiError("ACCOUNT_CODE_NOT_UNIQUE", "Account code must be unique per business", http_status=400)
		if code == "PARENT_NOT_FOUND":
			raise ApiError("PARENT_NOT_FOUND", "Parent account not found", http_status=400)
		if code == "INVALID_PARENT_BUSINESS":
			raise ApiError("INVALID_PARENT_BUSINESS", "Parent must be public or within the same business", http_status=400)
		raise


@router.put(
	"/account/{account_id}",
	summary="ویرایش حساب",
	description="ویرایش حساب اختصاصی بیزنس (دارای دسترسی write). حساب‌های عمومی غیرقابل‌ویرایش هستند.",
)
def update_account_endpoint(
	request: Request,
	account_id: int,
	body: AccountUpdateRequest = Body(...),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_by_entity_dep("chart_of_accounts", "edit", Account, "account_id")),
) -> dict:
	data = get_account(db, account_id)
	if not data:
		raise ApiError("ACCOUNT_NOT_FOUND", "Account not found", http_status=404)
	acc_business_id = data.get("business_id")
	# حساب‌های عمومی غیرقابل‌ویرایش هستند
	if acc_business_id is None:
		raise ApiError("FORBIDDEN", "Public accounts are immutable", http_status=403)
	try:
		updated = update_account(
			db,
			account_id,
			name=body.name,
			code=body.code,
			account_type=body.account_type,
			parent_id=body.parent_id,
		)
		if updated is None:
			raise ApiError("ACCOUNT_NOT_FOUND", "Account not found", http_status=404)
		return success_response(updated, request, message="ACCOUNT_UPDATED")
	except ValueError as e:
		code = str(e)
		if code == "ACCOUNT_CODE_NOT_UNIQUE":
			raise ApiError("ACCOUNT_CODE_NOT_UNIQUE", "Account code must be unique per business", http_status=400)
		if code == "PARENT_NOT_FOUND":
			raise ApiError("PARENT_NOT_FOUND", "Parent account not found", http_status=400)
		if code == "INVALID_PARENT_BUSINESS":
			raise ApiError("INVALID_PARENT_BUSINESS", "Parent must be public or within the same business", http_status=400)
		if code == "PUBLIC_IMMUTABLE":
			raise ApiError("FORBIDDEN", "Public accounts are immutable", http_status=403)
		raise


@router.delete(
	"/account/{account_id}",
	summary="حذف حساب",
	description="حذف حساب اختصاصی بیزنس (دارای دسترسی write). حساب‌های عمومی غیرقابل‌حذف هستند.",
)
def delete_account_endpoint(
	request: Request,
	account_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_by_entity_dep("chart_of_accounts", "delete", Account, "account_id")),
) -> dict:
	data = get_account(db, account_id)
	if not data:
		raise ApiError("ACCOUNT_NOT_FOUND", "Account not found", http_status=404)
	acc_business_id = data.get("business_id")
	# حساب‌های عمومی غیرقابل‌حذف هستند
	if acc_business_id is None:
		raise ApiError("FORBIDDEN", "Public accounts are immutable", http_status=403)
	try:
		ok = delete_account(db, account_id)
		if not ok:
			raise ApiError("ACCOUNT_NOT_FOUND", "Account not found", http_status=404)
		return success_response(None, request, message="ACCOUNT_DELETED")
	except ValueError as e:
		code = str(e)
		if code == "ACCOUNT_HAS_CHILDREN":
			raise ApiError("ACCOUNT_HAS_CHILDREN", "Cannot delete account with children", http_status=400)
		if code == "ACCOUNT_IN_USE":
			raise ApiError("ACCOUNT_IN_USE", "Cannot delete account that is referenced by documents", http_status=400)
		raise


