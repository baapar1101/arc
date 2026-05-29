from __future__ import annotations

from typing import Any, Callable, Dict, List, Optional, Tuple

from sqlalchemy import and_, select
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.warehouse import WarehouseCreateRequest
from adapters.db.models.warehouse import Warehouse
from app.services.legacy_sql.sql_dump_reader import LegacySqlData
from app.services.warehouse_service import create_warehouse

ProgressCb = Optional[Callable[[int, str], None]]


class LegacyWarehouseImporter:
	"""انتقال انبارها از جدول storeroom."""

	def __init__(self, db: Session, data: LegacySqlData, *, dry_run: bool = False):
		self.db = db
		self.data = data
		self.dry_run = dry_run
		self.stats = {
			"warehouses_created": 0,
			"warehouses_linked": 0,
			"warehouse_documents": {},
		}

	def run(
		self,
		*,
		business_id_map: Dict[int, int],
		user_id_map: Optional[Dict[int, int]] = None,
		product_id_map: Optional[Dict[Tuple[int, int], int]] = None,
		import_documents: bool = True,
		on_progress: ProgressCb = None,
	) -> Tuple[Dict[str, Any], Dict[Tuple[int, int], int]]:
		warehouse_map: Dict[Tuple[int, int], int] = {}
		rows = self.data.rows("storeroom")
		total = len(rows) or 1
		for i, row in enumerate(rows):
			if on_progress and i % 5 == 0:
				on_progress(68, f"انبار {i + 1}/{total}")
			old_bid = int(row.get("bid_id") or 0)
			new_bid = business_id_map.get(old_bid)
			if not new_bid or new_bid < 0:
				continue
			try:
				old_wid = int(row["id"])
			except (TypeError, ValueError):
				continue
			name = str(row.get("name") or "انبار").strip()
			existing = self.db.execute(
				select(Warehouse).where(
					and_(Warehouse.business_id == new_bid, Warehouse.name == name)
				)
			).scalars().first()
			if existing:
				warehouse_map[(old_bid, old_wid)] = existing.id
				self.stats["warehouses_linked"] += 1
				continue
			if self.dry_run:
				warehouse_map[(old_bid, old_wid)] = -old_wid
				self.stats["warehouses_created"] += 1
				continue
			code = str(row.get("code") or "").strip() or None
			payload = WarehouseCreateRequest(
				code=code,
				name=name,
				description=row.get("adr"),
				warehouse_keeper=row.get("manager"),
				phone=row.get("tel"),
				address=row.get("adr"),
				is_default=(i == 0),
			)
			created = create_warehouse(self.db, new_bid, payload)
			new_id = int(created["data"]["id"])
			warehouse_map[(old_bid, old_wid)] = new_id
			self.stats["warehouses_created"] += 1

		if import_documents and user_id_map and product_id_map:
			from app.services.legacy_sql.warehouse_document_importer import (
				LegacyWarehouseDocumentImporter,
			)

			doc_imp = LegacyWarehouseDocumentImporter(self.db, self.data, dry_run=self.dry_run)
			self.stats["warehouse_documents"] = doc_imp.run(
				business_id_map=business_id_map,
				user_id_map=user_id_map,
				product_id_map=product_id_map,
				warehouse_id_map=warehouse_map,
				on_progress=on_progress,
			)
		return dict(self.stats), warehouse_map
