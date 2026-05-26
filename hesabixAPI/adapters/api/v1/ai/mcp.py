from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError, success_response
from app.services.ai.ai_mcp_service import handle_mcp_request

router = APIRouter(prefix="/ai/mcp", tags=["هوش مصنوعی-MCP"])


@router.post("", summary="پروتکل MCP (JSON-RPC 2.0)")
async def mcp_jsonrpc_endpoint(
    request: Request,
    body: Dict[str, Any] = Body(...),
    business_id: Optional[int] = Query(None, description="شناسه کسب‌وکار برای tools"),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    """
    Endpoint سازگار با MCP برای لیست و فراخوانی ابزارهای Hesabix.
    احراز هویت مانند سایر APIها (Bearer / Api-Key).
    """
    effective_business_id = business_id or ctx.business_id
    if body.get("method") == "tools/call" and not effective_business_id:
        raise ApiError("BUSINESS_ID_REQUIRED", "شناسه کسب و کار الزامی است", http_status=400)
    if effective_business_id and not ctx.can_access_business(int(effective_business_id)):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار مجاز نیست", http_status=403)

    response = await handle_mcp_request(db, ctx, body, business_id=effective_business_id)
    return response
