"""
Helper functions for processing product requests (multipart/form-data and JSON)
"""
import json
import os
from typing import Dict, Any, Optional
from fastapi import Request, UploadFile, HTTPException
from adapters.api.v1.schema_models.product import ProductCreateRequest, ProductUpdateRequest
from adapters.api.v1.helpers.storage_upload_errors import raise_if_storage_upload_error
from app.core.responses import ApiError

_ALLOWED_IMAGE_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'}

_STRING_FORM_FIELDS = frozenset({
	'code', 'name', 'description', 'main_unit', 'secondary_unit',
	'base_sales_note', 'base_purchase_note', 'tax_code', 'image_file_id',
})


async def process_product_request(
	request: Request,
	business_id: int,
	ctx,
	db,
	is_update: bool = False,
	product_id: Optional[int] = None,
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

		# ابتدا payload را اعتبارسنجی می‌کنیم تا در صورت خطا فایل آپلود نشود
		product_data = _parse_form_data(form_data)
		try:
			if is_update:
				payload = ProductUpdateRequest(**product_data)
			else:
				payload = ProductCreateRequest(**product_data)
		except Exception as e:
			raise ApiError("INVALID_PAYLOAD", f"خطا در پردازش داده‌ها: {str(e)}", http_status=400)

		if "file" in form_data:
			file = form_data["file"]
			if hasattr(file, 'filename') and file.filename:
				_validate_image_extension(file.filename)
				image_file_id = await _upload_product_image(
					file=file,
					user_id=ctx.get_user_id(),
					business_id=business_id,
					db=db,
					context_id=str(product_id) if product_id is not None else None,
					developer_data={
						"business_id": business_id,
						**({"product_id": product_id} if product_id is not None else {}),
					},
				)
	else:
		try:
			body_data = await request.json()
			if not isinstance(body_data, dict):
				raise ApiError("INVALID_PAYLOAD", "داده‌های ارسالی باید یک object JSON باشد", http_status=400)

			if is_update and 'default_warehouse_id' in body_data:
				default_warehouse_id_value = body_data.get('default_warehouse_id')
				body_data['default_warehouse_id'] = default_warehouse_id_value

			if is_update:
				payload = ProductUpdateRequest(**body_data)
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

	if image_file_id and payload:
		payload.image_file_id = image_file_id
		if hasattr(payload, "model_fields_set"):
			payload.model_fields_set.add("image_file_id")
		elif hasattr(payload, "__fields_set__"):
			payload.__fields_set__.add("image_file_id")

	return payload, file, image_file_id


def _validate_image_extension(filename: str) -> None:
	file_ext = os.path.splitext(filename)[1].lower()
	if file_ext not in _ALLOWED_IMAGE_EXTENSIONS:
		raise ApiError(
			"INVALID_FILE_FORMAT",
			"فرمت فایل معتبر نیست. فقط فرمت‌های JPG, PNG, GIF, WebP و BMP پشتیبانی می‌شوند",
			http_status=400,
		)


async def _upload_product_image(
	*,
	file: UploadFile,
	user_id: int,
	business_id: int,
	db,
	context_id: Optional[str],
	developer_data: dict,
) -> str:
	from app.services.file_storage_service import FileStorageService
	storage_service = FileStorageService(db)
	try:
		upload_result = await storage_service.upload_file(
			file=file,
			user_id=user_id,
			module_context="products",
			context_id=context_id,
			developer_data=developer_data,
			is_temporary=False,
			expires_in_days=3650,
			business_id=business_id,
			check_storage_limit=True,
		)
		image_file_id = upload_result.get("file_id")
		if not image_file_id:
			raise ApiError("FILE_UPLOAD_ERROR", "خطا در آپلود فایل: شناسه فایل دریافت نشد", http_status=400)
		return image_file_id
	except HTTPException as e:
		raise_if_storage_upload_error(e)
		raise ApiError("FILE_UPLOAD_ERROR", f"خطا در آپلود فایل: {str(e.detail)}", http_status=400)
	except Exception as e:
		raise ApiError("FILE_UPLOAD_ERROR", f"خطا در آپلود فایل: {str(e)}", http_status=400)


def _parse_form_data(form_data) -> Dict[str, Any]:
	"""تبدیل form data به dictionary با تبدیل نوع مناسب"""
	product_data = {}
	for key, value in form_data.items():
		if key == "file":
			continue
		if isinstance(value, str):
			try:
				parsed = json.loads(value)
				product_data[key] = parsed
			except (json.JSONDecodeError, ValueError):
				value_lower = value.strip().lower()
				if value_lower in ('true', 'false'):
					product_data[key] = value_lower == 'true'
				elif value_lower == 'null' or value_lower == '':
					product_data[key] = None
				elif key in _STRING_FORM_FIELDS:
					product_data[key] = value
				elif value.isdigit() or (value.startswith('-') and value[1:].isdigit()):
					product_data[key] = int(value)
				elif value.replace('.', '', 1).replace('-', '', 1).isdigit():
					product_data[key] = float(value)
				else:
					product_data[key] = value
		else:
			product_data[key] = value
	return product_data
