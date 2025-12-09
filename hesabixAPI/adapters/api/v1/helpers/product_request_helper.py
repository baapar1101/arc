"""
Helper functions for processing product requests (multipart/form-data and JSON)
"""
import json
from typing import Dict, Any, Optional
from fastapi import Request, UploadFile, HTTPException
from adapters.api.v1.schema_models.product import ProductCreateRequest, ProductUpdateRequest
from app.core.responses import ApiError


async def process_product_request(
    request: Request,
    business_id: int,
    ctx,
    db,
    is_update: bool = False,
) -> tuple[Optional[ProductCreateRequest | ProductUpdateRequest], Optional[UploadFile], Optional[str]]:
    """
    پردازش درخواست محصول (multipart/form-data یا JSON)
    
    Returns:
        tuple: (payload, file, image_file_id)
    """
    content_type = request.headers.get("content-type", "")
    is_multipart = "multipart/form-data" in content_type
    
    image_file_id = None
    payload = None
    file = None
    
    if is_multipart:
        form_data = await request.form()
        
        # پردازش فایل
        if "file" in form_data:
            file = form_data["file"]
            if hasattr(file, 'filename') and file.filename:
                # بررسی فرمت فایل
                allowed_extensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'}
                file_ext = file.filename.split('.')[-1].lower() if '.' in file.filename else ''
                if f'.{file_ext}' not in allowed_extensions:
                    raise ApiError(
                        "INVALID_FILE_FORMAT",
                        "فرمت فایل معتبر نیست. فقط فرمت‌های JPG, PNG, GIF, WebP و BMP پشتیبانی می‌شوند",
                        http_status=400
                    )
                
                # آپلود فایل
                from app.services.file_storage_service import FileStorageService
                storage_service = FileStorageService(db)
                try:
                    upload_result = await storage_service.upload_file(
                        file=file,
                        user_id=ctx.get_user_id(),
                        module_context="products",
                        context_id=None,
                        developer_data={"business_id": business_id},
                        is_temporary=False,
                        expires_in_days=3650,
                        business_id=business_id,
                        check_storage_limit=True,
                    )
                    image_file_id = upload_result.get("file_id")
                except HTTPException as e:
                    # اگر خطای محدودیت ذخیره‌سازی باشد، جزئیات را برمی‌گردانیم
                    if e.status_code == 400 and isinstance(e.detail, dict) and e.detail.get("error") == "STORAGE_LIMIT_EXCEEDED":
                        error_detail = {
                            "success": False,
                            "error": {
                                "code": "STORAGE_LIMIT_EXCEEDED",
                                "message": e.detail.get("message", "حجم فایل از محدودیت ذخیره‌سازی تجاوز می‌کند"),
                                "total_limit_gb": e.detail.get("total_limit_gb"),
                                "current_usage_gb": e.detail.get("current_usage_gb"),
                                "available_gb": e.detail.get("available_gb"),
                                "required_gb": e.detail.get("required_gb"),
                                "over_usage_gb": e.detail.get("over_usage_gb"),
                            }
                        }
                        raise HTTPException(status_code=400, detail=error_detail)
                    raise ApiError("FILE_UPLOAD_ERROR", f"خطا در آپلود فایل: {str(e.detail)}", http_status=400)
                except Exception as e:
                    raise ApiError("FILE_UPLOAD_ERROR", f"خطا در آپلود فایل: {str(e)}", http_status=400)
        
        # ساخت payload از form data
        product_data = _parse_form_data(form_data)
        
        try:
            if is_update:
                payload = ProductUpdateRequest(**product_data)
            else:
                payload = ProductCreateRequest(**product_data)
        except Exception as e:
            raise ApiError("INVALID_PAYLOAD", f"خطا در پردازش داده‌ها: {str(e)}", http_status=400)
    else:
        # اگر JSON است، payload را از body می‌خوانیم
        try:
            body_data = await request.json()
            if not isinstance(body_data, dict):
                raise ApiError("INVALID_PAYLOAD", "داده‌های ارسالی باید یک object JSON باشد", http_status=400)
            
            # برای update، باید default_warehouse_id را به صورت صریح set کنیم
            if is_update and 'default_warehouse_id' in body_data:
                default_warehouse_id_value = body_data.get('default_warehouse_id')
                body_data['default_warehouse_id'] = default_warehouse_id_value
            
            if is_update:
                payload = ProductUpdateRequest(**body_data)
                # اضافه کردن به fields_set برای Pydantic v2
                if 'default_warehouse_id' in body_data:
                    if hasattr(payload, 'model_fields_set'):
                        payload.model_fields_set.add('default_warehouse_id')
                    elif hasattr(payload, '__fields_set__'):
                        payload.__fields_set__.add('default_warehouse_id')
            else:
                payload = ProductCreateRequest(**body_data)
        except ValueError as e:
            raise ApiError("INVALID_PAYLOAD", f"خطا در parse کردن JSON: {str(e)}", http_status=400)
        except Exception as e:
            raise ApiError("INVALID_PAYLOAD", f"خطا در پردازش داده‌های JSON: {str(e)}", http_status=400)
        
        # اگر فایل هم ارسال شده (در JSON request)
        # این حالت معمولاً اتفاق نمی‌افتد اما برای سازگاری بررسی می‌کنیم
        # در این حالت باید از endpoint جداگانه استفاده شود
    
    # تنظیم image_file_id در payload
    if image_file_id and payload:
        payload.image_file_id = image_file_id
    
    return payload, file, image_file_id


def _parse_form_data(form_data) -> Dict[str, Any]:
    """
    تبدیل form data به dictionary با تبدیل نوع مناسب
    """
    product_data = {}
    for key, value in form_data.items():
        if key != "file":
            # تبدیل مقادیر به نوع مناسب
            if isinstance(value, str):
                # سعی می‌کنیم به عنوان JSON parse کنیم
                try:
                    parsed = json.loads(value)
                    product_data[key] = parsed
                except (json.JSONDecodeError, ValueError):
                    # اگر JSON نیست، بررسی می‌کنیم که آیا boolean یا number است
                    value_lower = value.strip().lower()
                    if value_lower in ('true', 'false'):
                        product_data[key] = value_lower == 'true'
                    elif value_lower == 'null' or value_lower == '':
                        product_data[key] = None
                    elif value.isdigit() or (value.startswith('-') and value[1:].isdigit()):
                        product_data[key] = int(value)
                    elif value.replace('.', '', 1).replace('-', '', 1).isdigit():
                        product_data[key] = float(value)
                    else:
                        product_data[key] = value
            else:
                product_data[key] = value
    return product_data


