from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from typing import List

from adapters.db.session import get_db
from adapters.db.models.email_config import EmailConfig
from adapters.db.repositories.email_config_repository import EmailConfigRepository
from adapters.api.v1.schema_models.email import (
    EmailConfigCreate,
    EmailConfigUpdate,
    EmailConfigResponse,
    SendEmailRequest,
    TestConnectionRequest
)
from adapters.api.v1.schemas import SuccessResponse
from app.core.responses import success_response, format_datetime_fields
from app.core.permissions import require_app_permission
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.i18n import gettext, negotiate_locale

router = APIRouter(prefix="/admin/email", tags=["Email Configuration"])


@router.get("/configs", response_model=SuccessResponse)
@require_app_permission("superadmin")
async def get_email_configs(
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user)
):
    """Get all email configurations"""
    try:
        email_repo = EmailConfigRepository(db)
        configs = email_repo.get_all_configs()
        
        config_responses = [
            EmailConfigResponse.model_validate(config) for config in configs
        ]
        
        # Format datetime fields based on calendar type
        formatted_data = format_datetime_fields(config_responses, request)
        
        return success_response(
            data=formatted_data,
            request=request
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/configs/{config_id}", response_model=SuccessResponse)
@require_app_permission("superadmin")
async def get_email_config(
    config_id: int,
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user)
):
    """Get specific email configuration"""
    try:
        email_repo = EmailConfigRepository(db)
        config = email_repo.get_by_id(config_id)
        
        if not config:
            locale = negotiate_locale(request.headers.get("Accept-Language"))
            raise HTTPException(status_code=404, detail=gettext("Email configuration not found", locale))
        
        config_response = EmailConfigResponse.model_validate(config)
        
        # Format datetime fields based on calendar type
        formatted_data = format_datetime_fields(config_response.model_dump(), request)
        
        return success_response(
            data=formatted_data,
            request=request
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/configs", response_model=SuccessResponse)
@require_app_permission("superadmin")
async def create_email_config(
    request_data: EmailConfigCreate,
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user)
):
    """Create new email configuration"""
    try:
        email_repo = EmailConfigRepository(db)
        
        # Get locale from request
        locale = negotiate_locale(request.headers.get("Accept-Language"))
        
        # Check if name already exists
        existing_config = email_repo.get_by_name(request_data.name)
        if existing_config:
            raise HTTPException(status_code=400, detail=gettext("Configuration name already exists", locale))
        
        # Create new config
        config = EmailConfig(**request_data.model_dump())
        email_repo.db.add(config)
        email_repo.db.commit()
        email_repo.db.refresh(config)
        
        # If this is the first config, set it as default
        if not email_repo.get_default_config():
            email_repo.set_default_config(config.id)
        
        config_response = EmailConfigResponse.model_validate(config)
        
        # Format datetime fields based on calendar type
        formatted_data = format_datetime_fields(config_response.model_dump(), request)
        
        return success_response(
            data=formatted_data,
            request=request
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/configs/{config_id}", response_model=SuccessResponse)
@require_app_permission("superadmin")
async def update_email_config(
    config_id: int,
    request_data: EmailConfigUpdate,
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user)
):
    """Update email configuration"""
    try:
        email_repo = EmailConfigRepository(db)
        config = email_repo.get_by_id(config_id)
        
        # Get locale from request
        locale = negotiate_locale(request.headers.get("Accept-Language"))
        
        if not config:
            raise HTTPException(status_code=404, detail=gettext("Email configuration not found", locale))
        
        # Check name uniqueness if name is being updated
        if request_data.name and request_data.name != config.name:
            existing_config = email_repo.get_by_name(request_data.name)
            if existing_config:
                raise HTTPException(status_code=400, detail=gettext("Configuration name already exists", locale))
        
        # Update config
        update_data = request_data.model_dump(exclude_unset=True)
        
        # Prevent changing is_default through update - use set-default endpoint instead
        if 'is_default' in update_data:
            del update_data['is_default']
        
        for field, value in update_data.items():
            setattr(config, field, value)
        
        email_repo.update(config)
        
        config_response = EmailConfigResponse.model_validate(config)
        
        # Format datetime fields based on calendar type
        formatted_data = format_datetime_fields(config_response.model_dump(), request)
        
        return success_response(
            data=formatted_data,
            request=request
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/configs/{config_id}", response_model=SuccessResponse)
@require_app_permission("superadmin")
async def delete_email_config(
    config_id: int,
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user)
):
    """Delete email configuration"""
    try:
        email_repo = EmailConfigRepository(db)
        config = email_repo.get_by_id(config_id)
        
        # Get locale from request
        locale = negotiate_locale(request.headers.get("Accept-Language"))
        
        if not config:
            raise HTTPException(status_code=404, detail=gettext("Email configuration not found", locale))
        
        # Prevent deletion of default config
        if config.is_default:
            raise HTTPException(status_code=400, detail=gettext("Cannot delete default configuration", locale))
        
        email_repo.delete(config)
        
        return success_response(
            data=None,
            request=request
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/configs/{config_id}/test", response_model=SuccessResponse)
@require_app_permission("superadmin")
async def test_email_config(
    config_id: int,
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user)
):
    """Test email configuration connection"""
    try:
        email_repo = EmailConfigRepository(db)
        config = email_repo.get_by_id(config_id)
        
        # Get locale from request
        locale = negotiate_locale(request.headers.get("Accept-Language"))
        
        if not config:
            raise HTTPException(status_code=404, detail=gettext("Email configuration not found", locale))
        
        result = email_repo.test_connection(config)
        
        return success_response(
            data={
                "connected": result.get("connected", False),
                "error_message": result.get("error_message")
            },
            request=request
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/configs/{config_id}/activate", response_model=SuccessResponse)
@require_app_permission("superadmin")
async def activate_email_config(
    config_id: int,
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user)
):
    """Activate email configuration"""
    try:
        email_repo = EmailConfigRepository(db)
        config = email_repo.get_by_id(config_id)
        
        # Get locale from request
        locale = negotiate_locale(request.headers.get("Accept-Language"))
        
        if not config:
            raise HTTPException(status_code=404, detail=gettext("Email configuration not found", locale))
        
        success = email_repo.set_active_config(config_id)
        
        if not success:
            raise HTTPException(status_code=500, detail=gettext("Failed to activate configuration", locale))
        
        return success_response(
            data=None,
            request=request
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/configs/{config_id}/set-default", response_model=SuccessResponse)
@require_app_permission("superadmin")
async def set_default_email_config(
    config_id: int,
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user)
):
    """Set email configuration as default"""
    try:
        email_repo = EmailConfigRepository(db)
        config = email_repo.get_by_id(config_id)
        
        # Get locale from request
        locale = negotiate_locale(request.headers.get("Accept-Language"))
        
        if not config:
            raise HTTPException(status_code=404, detail=gettext("Email configuration not found", locale))
        
        success = email_repo.set_default_config(config_id)
        
        if not success:
            raise HTTPException(status_code=500, detail=gettext("Failed to set default configuration", locale))
        
        return success_response(
            data=None,
            request=request
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/send", response_model=SuccessResponse)
@require_app_permission("superadmin")
async def send_email(
    request_data: SendEmailRequest,
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user)
):
    """Send email using configured SMTP"""
    try:
        from app.services.email_service import EmailService
        
        email_service = EmailService(db)
        success = email_service.send_email(
            to=request_data.to,
            subject=request_data.subject,
            body=request_data.body,
            html_body=request_data.html_body,
            config_id=request_data.config_id
        )
        
        # Get locale from request
        locale = negotiate_locale(request.headers.get("Accept-Language"))
        
        if not success:
            raise HTTPException(status_code=500, detail=gettext("Failed to send email", locale))
        
        return success_response(
            data={"sent": True},
            request=request
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
