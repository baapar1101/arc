from typing import List, Dict, Any

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.api.v1.schemas import SuccessResponse
from adapters.api.v1.schema_models.account import AccountTreeNode
from app.core.responses import success_response
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from adapters.db.models.account import Account


router = APIRouter(prefix="/accounts", tags=["accounts"])


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


