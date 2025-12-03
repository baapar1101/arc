from __future__ import annotations

from typing import Optional
from fastapi import Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import ApiError
from app.services.warranty_service import _check_warranty_plugin_active


def require_warranty_plugin_active(business_id_param: str = "business_id"):
    """
    Dependency برای بررسی فعال بودن پلاگین گارانتی
    
    Args:
        business_id_param: نام پارامتر path که business_id را دارد
    """
    def dependency(
        request: Request,
        ctx: AuthContext = Depends(get_current_user),
        db: Session = Depends(get_db)
    ) -> None:
        # استخراج business_id از path parameters
        business_id = None
        if hasattr(request, "path_params") and business_id_param in request.path_params:
            try:
                business_id = int(request.path_params[business_id_param])
            except (ValueError, TypeError):
                pass
        
        # اگر از path پیدا نشد، از query parameters امتحان کن
        if business_id is None and hasattr(request, "query_params"):
            try:
                business_id = int(request.query_params.get(business_id_param, 0))
            except (ValueError, TypeError):
                pass
        
        if not business_id:
            raise ApiError(
                "INVALID_BUSINESS_ID",
                f"شناسه کسب و کار ({business_id_param}) معتبر نیست",
                http_status=400
            )
        
        # بررسی فعال بودن پلاگین
        if not _check_warranty_plugin_active(db, business_id):
            raise ApiError(
                "PLUGIN_NOT_ACTIVE",
                "پلاگین گارانتی برای این کسب و کار فعال نیست",
                http_status=403
            )
        
        return None
    
    return dependency

