"""
سرویس دانلود ZIP تمام فایل‌های کسب‌وکار
"""

from __future__ import annotations

import io
import zipfile
from typing import Optional, Dict, Any
from datetime import datetime
from uuid import UUID

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from adapters.db.models.file_storage import FileStorage
from app.services.file_storage_service import FileStorageService
from app.core.responses import ApiError


async def export_business_files_as_zip(
	db: Session,
	business_id: int,
	module_context: Optional[str] = None,
	from_date: Optional[datetime] = None,
	to_date: Optional[datetime] = None,
) -> bytes:
	"""ایجاد فایل ZIP از تمام فایل‌های کسب‌وکار"""
	# دریافت فایل‌های کسب‌وکار
	query = db.query(FileStorage).filter(
		and_(
			FileStorage.business_id == business_id,
			FileStorage.deleted_at.is_(None),
			FileStorage.is_active == True,
			FileStorage.is_marked_for_deletion == False
		)
	)
	
	if module_context:
		query = query.filter(FileStorage.module_context == module_context)
	
	if from_date:
		query = query.filter(FileStorage.created_at >= from_date)
	
	if to_date:
		query = query.filter(FileStorage.created_at <= to_date)
	
	files = query.order_by(FileStorage.created_at).all()
	
	if not files:
		raise ApiError("NO_FILES_FOUND", "فایلی برای دانلود یافت نشد", http_status=404)
	
	# ایجاد ZIP
	zip_buffer = io.BytesIO()
	file_service = FileStorageService(db)
	
	with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zip_file:
		for file_storage in files:
			try:
				# خواندن فایل
				file_id = UUID(file_storage.id)
				file_data = await file_service.download_file(file_id)
				
				# نام فایل در ZIP: module_context/original_name
				zip_path = f"{file_storage.module_context}/{file_storage.original_name}"
				
				# اگر فایل با همین نام وجود دارد، شماره اضافه کن
				counter = 1
				original_zip_path = zip_path
				while zip_path in zip_file.namelist():
					name_parts = original_zip_path.rsplit('.', 1)
					if len(name_parts) == 2:
						zip_path = f"{name_parts[0]}_{counter}.{name_parts[1]}"
					else:
						zip_path = f"{original_zip_path}_{counter}"
					counter += 1
				
				zip_file.writestr(zip_path, file_data["content"])
			except Exception as e:
				# در صورت خطا، فایل را رد می‌کنیم و ادامه می‌دهیم
				continue
	
	zip_buffer.seek(0)
	return zip_buffer.read()


def get_export_info(
	db: Session,
	business_id: int,
	module_context: Optional[str] = None,
	from_date: Optional[datetime] = None,
	to_date: Optional[datetime] = None,
) -> Dict[str, Any]:
	"""دریافت اطلاعات فایل‌های قابل دانلود (بدون دانلود)"""
	query = db.query(FileStorage).filter(
		and_(
			FileStorage.business_id == business_id,
			FileStorage.deleted_at.is_(None),
			FileStorage.is_active == True,
			FileStorage.is_marked_for_deletion == False
		)
	)
	
	if module_context:
		query = query.filter(FileStorage.module_context == module_context)
	
	if from_date:
		query = query.filter(FileStorage.created_at >= from_date)
	
	if to_date:
		query = query.filter(FileStorage.created_at <= to_date)
	
	files = query.all()
	
	total_size = sum(f.file_size for f in files)
	total_size_gb = total_size / (1024 * 1024 * 1024)
	
	# گروه‌بندی بر اساس module_context
	by_context = {}
	for f in files:
		ctx = f.module_context or "unknown"
		if ctx not in by_context:
			by_context[ctx] = {"count": 0, "size": 0}
		by_context[ctx]["count"] += 1
		by_context[ctx]["size"] += f.file_size
	
	return {
		"total_files": len(files),
		"total_size_bytes": total_size,
		"total_size_gb": round(total_size_gb, 3),
		"by_context": {
			ctx: {
				"count": data["count"],
				"size_bytes": data["size"],
				"size_gb": round(data["size"] / (1024 * 1024 * 1024), 3)
			}
			for ctx, data in by_context.items()
		}
	}

