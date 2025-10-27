from typing import List, Dict, Any, Optional

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session
from pydantic import BaseModel

from adapters.db.session import get_db
from adapters.api.v1.schemas import SuccessResponse
from adapters.api.v1.schema_models.account import AccountTreeNode
from app.core.responses import success_response
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from adapters.db.models.account import Account


router = APIRouter(prefix="/accounts", tags=["accounts"])


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
			id=n['id'], code=n['code'], name=n['name'], account_type=n.get('account_type'), parent_id=n.get('parent_id')
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
	db: Session = Depends(get_db)
) -> dict:
	# دریافت حساب‌های عمومی (business_id IS NULL) و حساب‌های مختص این کسب و کار
	rows = db.query(Account).filter(
		(Account.business_id == None) | (Account.business_id == business_id)  # noqa: E711
	).order_by(Account.code.asc()).all()
	flat = [
		{"id": r.id, "code": r.code, "name": r.name, "account_type": r.account_type, "parent_id": r.parent_id}
		for r in rows
	]
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
	db: Session = Depends(get_db)
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
	db: Session = Depends(get_db)
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
	db: Session = Depends(get_db)
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


