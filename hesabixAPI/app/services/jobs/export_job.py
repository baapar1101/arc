"""
Job برای export داده‌ها (محصولات و سایر انواع).
"""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


def export_products_excel_job(
	business_id: int,
	user_id: int,
	body: Optional[Dict[str, Any]] = None,
	calendar_type: str = "jalali",
	accept_language: str = "fa",
	**kwargs,
) -> Dict[str, Any]:
	"""
	ساخت Excel محصولات در پس‌زمینه و آپلود به storage.
	نتیجه شامل file_id برای دانلود است.
	"""
	from adapters.db.session import get_db_session
	from app.services.product_excel_export_service import (
		build_products_excel_export,
		upload_export_bytes,
	)

	body = dict(body or {})
	body.pop("async", None)
	body.pop("async_mode", None)

	logger.info(
		"Starting products excel export job business_id=%s user_id=%s",
		business_id,
		user_id,
	)

	with get_db_session() as db:
		data, filename, record_count = build_products_excel_export(
			db,
			business_id,
			body,
			calendar_type=calendar_type,
			accept_language=accept_language,
		)
		saved = upload_export_bytes(
			db,
			business_id=business_id,
			user_id=user_id,
			data=data,
			filename=filename,
		)
		file_id = saved.get("file_id")
		result = {
			"success": True,
			"export_type": "products",
			"format": "xlsx",
			"business_id": business_id,
			"filename": filename,
			"file_id": file_id,
			"file": saved,
			"record_count": record_count,
			"file_size": len(data),
			"exported_at": datetime.now().isoformat(),
		}
		logger.info(
			"Products excel export completed business_id=%s records=%s file_id=%s",
			business_id,
			record_count,
			file_id,
		)
		return result


def export_data_job(
	export_type: str,
	business_id: int,
	user_id: int,
	format: str = "xlsx",
	filters: Optional[Dict[str, Any]] = None,
	**kwargs,
) -> Dict[str, Any]:
	"""
	Entry عمومی export. برای products به export_products_excel_job می‌رود.
	"""
	try:
		export_type_norm = (export_type or "").strip().lower()
		if export_type_norm in {"products", "product", "products_excel"}:
			body = kwargs.get("body")
			if body is None and filters is not None:
				body = dict(filters)
			return export_products_excel_job(
				business_id=business_id,
				user_id=user_id,
				body=body,
				calendar_type=str(kwargs.get("calendar_type") or "jalali"),
				accept_language=str(kwargs.get("accept_language") or "fa"),
			)

		logger.warning("Unsupported export_type=%s — returning stub result", export_type)
		return {
			"success": False,
			"export_type": export_type,
			"business_id": business_id,
			"format": format,
			"exported_at": datetime.now().isoformat(),
			"file_path": None,
			"file_size": 0,
			"record_count": 0,
			"error": f"Unsupported export_type: {export_type}",
		}
	except Exception as e:
		logger.error(
			"Error exporting %s for business %s: %s",
			export_type,
			business_id,
			e,
			exc_info=True,
		)
		raise
