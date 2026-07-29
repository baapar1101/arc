"""اعتبارسنجی مالکیت فایل بکاپ نسبت به کسب‌وکار."""

from __future__ import annotations

from uuid import UUID

from sqlalchemy.orm import Session

from adapters.db.models.file_storage import FileStorage
from app.core.responses import ApiError


def _same_business_id(dev_value, business_id: int) -> bool:
	if isinstance(dev_value, int):
		return dev_value == business_id
	try:
		return int(str(dev_value)) == int(business_id)
	except Exception:
		return False


def assert_backup_file_belongs_to_business(
	db: Session,
	backup_id: str,
	business_id: int,
) -> FileStorage:
	file = db.query(FileStorage).filter(FileStorage.id == str(UUID(backup_id))).first()
	if not file or file.deleted_at is not None:
		raise ApiError("FILE_NOT_FOUND", "Backup not found", http_status=404)

	dev = file.developer_data or {}
	if file.module_context != "business_backup" or not _same_business_id(
		dev.get("business_id"), business_id
	):
		raise ApiError("FILE_NOT_FOUND", "Backup not found", http_status=404)
	return file
