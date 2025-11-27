from __future__ import annotations

import logging
import os
import shutil
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from dataclasses import dataclass
from typing import Dict, Generator, List, Tuple

from sqlalchemy import or_
from sqlalchemy.dialects.mysql import insert as mysql_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from adapters.db.models.product_tax_code import ProductTaxCode
from adapters.db.session import get_db_session
from app.core.smart_normalizer import smart_normalize_numbers
from app.services.job_manager import JobManager

logger = logging.getLogger(__name__)

BATCH_SIZE = 500


@dataclass
class TaxCodeRecord:
    code: str
    description: str
    vat_rate: str | None = None
    taxable_status: str | None = None
    run_date: str | None = None
    expiration_date: str | None = None
    create_date: str | None = None
    last_edit_date: str | None = None
    source_type: str | None = None
    pricing_description: str | None = None

    def to_dict(self) -> Dict[str, str | None]:
        return {
            "code": self.code,
            "description": self.description,
            "vat_rate": self.vat_rate,
            "taxable_status": self.taxable_status,
            "run_date": self.run_date,
            "expiration_date": self.expiration_date,
            "create_date": self.create_date,
            "last_edit_date": self.last_edit_date,
            "source_type": self.source_type,
            "pricing_description": self.pricing_description,
        }


def search_tax_product_codes(
    db: Session,
    query: str | None,
    skip: int,
    take: int,
    sort_by: str | None = None,
    sort_desc: bool = False,
) -> Dict[str, object]:
    q = db.query(ProductTaxCode)
    normalized = _clean_query(query)
    if normalized:
        pattern = f"%{normalized}%"
        q = q.filter(
            or_(
                ProductTaxCode.code.like(pattern),
                ProductTaxCode.description.ilike(pattern),
            )
        )
    total = q.count()
    sort_column = _resolve_sort_column(sort_by)
    order_clause = sort_column.desc() if sort_desc else sort_column.asc()
    items = q.order_by(order_clause).offset(skip).limit(take).all()
    return {
        "items": [_serialize_tax_code(item) for item in items],
        "total": total,
    }


def get_tax_product_code(db: Session, code: str) -> Dict[str, object] | None:
    normalized = _clean_code(code)
    if not normalized:
        return None
    obj = (
        db.query(ProductTaxCode)
        .filter(ProductTaxCode.code == normalized)
        .first()
    )
    if not obj:
        return None
    return _serialize_tax_code(obj)


def process_tax_product_code_import(
    file_path: str,
    job_id: str,
    source_filename: str,
    checksum: str | None = None,
) -> None:
    jm = JobManager.instance()
    total = 0
    inserted = 0
    skipped = 0
    batch: List[Dict[str, str | None]] = []
    extracted_dir: str | None = None
    
    try:
        jm.start(job_id, "شروع پردازش فایل")
        xml_files, extracted_dir = _collect_xml_sources(file_path)
        if not xml_files:
            raise ValueError("NO_XML_FILES_FOUND")

        with get_db_session() as session:
            for index, xml_path in enumerate(xml_files, start=1):
                jm.update(
                    job_id,
                    min(10 + index * 5, 40),
                    f"پردازش فایل {index}/{len(xml_files)}",
                )

                display_name = (
                    f"{source_filename}::{os.path.basename(xml_path)}"
                    if len(xml_files) > 1
                    else source_filename
                )

                for record in _stream_tax_codes(xml_path):
                    total += 1
                    payload = record.to_dict()
                    payload["source_filename"] = display_name[:255]
                    payload["source_checksum"] = checksum
                    batch.append(payload)

                    if len(batch) >= BATCH_SIZE:
                        batch_inserted, batch_skipped = _flush_batch(session, batch)
                        inserted += batch_inserted
                        skipped += batch_skipped
                        batch.clear()
                        if total % (BATCH_SIZE * 4) == 0:
                            jm.update(
                                job_id,
                                min(95, 40 + total // 1000),
                                f"پردازش {total:,} رکورد",
                            )

            if batch:
                batch_inserted, batch_skipped = _flush_batch(session, batch)
                inserted += batch_inserted
                skipped += batch_skipped

        jm.succeed(
            job_id,
            {
                "total": total,
                "inserted": inserted,
                "skipped": skipped,
                "checksum": checksum,
                "filename": source_filename,
                "files_processed": len(xml_files),
            },
            "ایمپورت کدهای مالیاتی تکمیل شد",
        )
    except Exception as exc:
        logger.exception("failed to import tax codes")
        jm.fail(job_id, str(exc), "ایمپورت کدهای مالیاتی ناموفق بود")
        raise
    finally:
        try:
            os.remove(file_path)
        except OSError:
            pass
        if extracted_dir:
            shutil.rmtree(extracted_dir, ignore_errors=True)


def _collect_xml_sources(file_path: str) -> Tuple[List[str], str | None]:
    if zipfile.is_zipfile(file_path):
        temp_dir = tempfile.mkdtemp(prefix="tax_codes_zip_")
        xml_paths: List[str] = []
        with zipfile.ZipFile(file_path) as archive:
            for info in archive.infolist():
                if info.is_dir():
                    continue
                if not info.filename.lower().endswith(".xml"):
                    continue
                target_path = os.path.join(temp_dir, os.path.basename(info.filename))
                with archive.open(info) as src, open(target_path, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                xml_paths.append(target_path)
        return xml_paths, temp_dir if xml_paths else temp_dir
    return [file_path], None


def _resolve_sort_column(sort_by: str | None):
    mapping = {
        "code": ProductTaxCode.code,
        "description": ProductTaxCode.description,
        "vat_rate": ProductTaxCode.vat_rate,
        "taxable_status": ProductTaxCode.taxable_status,
        "run_date": ProductTaxCode.run_date,
        "last_edit_date": ProductTaxCode.last_edit_date,
    }
    return mapping.get(sort_by or "code", ProductTaxCode.code)


def _flush_batch(session: Session, batch: List[Dict[str, str | None]]) -> Tuple[int, int]:
    if not batch:
        return 0, 0
    dialect = session.bind.dialect.name if session.bind else "default"
    inserted = 0
    skipped = 0
    try:
        if dialect == "mysql":
            stmt = mysql_insert(ProductTaxCode).values(batch)
            stmt = stmt.prefix_with("IGNORE")
            result = session.execute(stmt)
            session.commit()
            inserted = result.rowcount or 0
            skipped = len(batch) - inserted
        elif dialect == "postgresql":
            from sqlalchemy.dialects.postgresql import insert as pg_insert

            stmt = pg_insert(ProductTaxCode).values(batch)
            stmt = stmt.on_conflict_do_nothing(index_elements=["code"])
            result = session.execute(stmt)
            session.commit()
            inserted = result.rowcount or 0
            skipped = len(batch) - inserted
        else:
            for row in batch:
                obj = ProductTaxCode(**row)  # type: ignore[arg-type]
                session.add(obj)
                try:
                    session.commit()
                    inserted += 1
                except IntegrityError:
                    session.rollback()
                    skipped += 1
    except IntegrityError:
        session.rollback()
        # اگر batch به دلیل رکورد تکراری fail شد، یکی یکی insert می‌کنیم
        for row in batch:
            obj = ProductTaxCode(**row)  # type: ignore[arg-type]
            session.add(obj)
            try:
                session.commit()
                inserted += 1
            except IntegrityError:
                session.rollback()
                skipped += 1
    return inserted, skipped


def _stream_tax_codes(file_path: str) -> Generator[TaxCodeRecord, None, None]:
    context = ET.iterparse(file_path, events=("end",))
    for _, elem in context:
        if elem.tag.endswith("ProductSet"):
            payload = {}
            for child in elem:
                tag = child.tag.split("}")[-1]
                payload[tag] = (child.text or "").strip()
            elem.clear()
            record = _build_record(payload)
            if record:
                yield record


def _build_record(data: Dict[str, str]) -> TaxCodeRecord | None:
    raw_code = _clean_code(data.get("ID"))
    if not raw_code:
        return None
    description = (data.get("DescriptionOfID") or "").strip()
    if not description:
        return None
    return TaxCodeRecord(
        code=raw_code,
        description=description[:1024],
        vat_rate=_clean_text(data.get("Vat"), limit=16),
        taxable_status=_clean_text(data.get("Taxable"), limit=64),
        run_date=_clean_text(data.get("RunDate"), limit=32),
        expiration_date=_clean_text(data.get("ExpirationDate"), limit=32),
        create_date=_clean_text(data.get("CreateDate"), limit=32),
        last_edit_date=_clean_text(data.get("LastEditDate"), limit=32),
        source_type=_clean_text(data.get("Type"), limit=128),
        pricing_description=_clean_text(data.get("PricingDescription"), limit=1024),
    )


def _serialize_tax_code(obj: ProductTaxCode) -> Dict[str, object]:
    return {
        "code": obj.code,
        "description": obj.description,
        "vat_rate": obj.vat_rate,
        "taxable_status": obj.taxable_status,
        "run_date": obj.run_date,
        "expiration_date": obj.expiration_date,
        "create_date": obj.create_date,
        "last_edit_date": obj.last_edit_date,
        "source_type": obj.source_type,
        "pricing_description": obj.pricing_description,
        "source_filename": obj.source_filename,
        "source_checksum": obj.source_checksum,
        "imported_at": obj.imported_at.isoformat() if obj.imported_at else None,
    }


def _clean_text(value: str | None, *, limit: int | None = None) -> str | None:
    if not value:
        return None
    text = value.strip()
    if not text:
        return None
    if limit:
        return text[:limit]
    return text


def _clean_code(value: str | None) -> str | None:
    if not value:
        return None
    normalized = smart_normalize_numbers(value.strip())
    return normalized[:32] if normalized else None


def _clean_query(value: str | None) -> str | None:
    if not value:
        return None
    text = smart_normalize_numbers(value.strip())
    return text if text else None


