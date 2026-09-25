"""V2-P8: گزارش سلامت دادهٔ چندارزی + backfill با dry-run."""
from __future__ import annotations

from typing import Any, Dict, Optional

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.services.document_line_fx_service import backfill_document_lines_fx_base
from app.services.fx_rate_provider_service import assert_multi_currency


def get_fx_data_health(db: Session, business_id: int) -> Dict[str, Any]:
	"""
	شمارش اسناد ارزی بدون snapshot fx و خطوط بدون debit_base/credit_base.
	"""
	assert_multi_currency(db, int(business_id))
	bid = int(business_id)

	foreign_docs = db.execute(
		text(
			"""
			SELECT COUNT(*) FROM documents d
			JOIN businesses b ON b.id = d.business_id
			WHERE d.business_id = :bid
			  AND b.default_currency_id IS NOT NULL
			  AND d.currency_id IS NOT NULL
			  AND d.currency_id <> b.default_currency_id
			"""
		),
		{"bid": bid},
	).scalar() or 0

	foreign_without_fx = db.execute(
		text(
			"""
			SELECT COUNT(*) FROM documents d
			JOIN businesses b ON b.id = d.business_id
			WHERE d.business_id = :bid
			  AND b.default_currency_id IS NOT NULL
			  AND d.currency_id IS NOT NULL
			  AND d.currency_id <> b.default_currency_id
			  AND (
				d.extra_info IS NULL
				OR NOT ((d.extra_info::jsonb) ? 'fx')
				OR COALESCE(((d.extra_info::jsonb)->'fx'->>'skipped')::boolean, false) = true
				OR ((d.extra_info::jsonb)->'fx'->>'rate') IS NULL
			  )
			"""
		),
		{"bid": bid},
	).scalar() or 0

	lines_missing_base = db.execute(
		text(
			"""
			SELECT COUNT(*) FROM document_lines dl
			JOIN documents d ON d.id = dl.document_id
			WHERE d.business_id = :bid
			  AND (dl.debit_base IS NULL OR dl.credit_base IS NULL)
			"""
		),
		{"bid": bid},
	).scalar() or 0

	docs_with_missing_line_base = db.execute(
		text(
			"""
			SELECT COUNT(DISTINCT d.id) FROM documents d
			JOIN document_lines dl ON dl.document_id = d.id
			WHERE d.business_id = :bid
			  AND (dl.debit_base IS NULL OR dl.credit_base IS NULL)
			"""
		),
		{"bid": bid},
	).scalar() or 0

	return {
		"business_id": bid,
		"foreign_documents": int(foreign_docs),
		"foreign_documents_missing_fx": int(foreign_without_fx),
		"lines_missing_base": int(lines_missing_base),
		"documents_with_missing_line_base": int(docs_with_missing_line_base),
		"needs_attention": int(foreign_without_fx) > 0 or int(lines_missing_base) > 0,
	}


def run_fx_base_backfill(
	db: Session,
	business_id: int,
	*,
	dry_run: bool = True,
	only_with_fx_snapshot: bool = True,
	allow_infer: bool = False,
	max_documents: Optional[int] = 200,
	batch_size: int = 50,
) -> Dict[str, Any]:
	"""
	اجرای backfill لایه ۲. dry_run=True هیچ commitی نمی‌زند (rollback).
	allow_infer=True همان مسیر D9 inferred است (پیش‌فرض خاموش).
	"""
	assert_multi_currency(db, int(business_id))
	# backfill_document_lines_fx_base فعلی allow_infer را مستقیم نمی‌گیرد —
	# only_with_fx_snapshot=False معادل اجازهٔ اسناد بدون fx برای stamp با infer در stamp است.
	# برای dry-run: commit_every_batch=False و در پایان rollback.
	stats = backfill_document_lines_fx_base(
		db,
		business_id=int(business_id),
		batch_size=int(batch_size),
		only_with_fx_snapshot=bool(only_with_fx_snapshot) and not bool(allow_infer),
		max_documents=max_documents,
		commit_every_batch=False,
	)
	out = {
		"dry_run": bool(dry_run),
		"allow_infer": bool(allow_infer),
		"only_with_fx_snapshot": bool(only_with_fx_snapshot) and not bool(allow_infer),
		"stats": stats,
	}
	if dry_run:
		db.rollback()
		out["applied"] = False
	else:
		db.commit()
		out["applied"] = True
	return out
