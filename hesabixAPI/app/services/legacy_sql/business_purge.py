from __future__ import annotations

import logging
from typing import Any, Dict

from sqlalchemy.orm import Session

from adapters.db.models.bank_account import BankAccount
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.document import Document
from adapters.db.models.person import Person
from adapters.db.models.petty_cash import PettyCash
from adapters.db.models.product import Product
from adapters.db.models.warehouse import Warehouse
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from adapters.db.models.check import Check
from app.services.document_service import delete_document
from app.services.expense_income_service import delete_expense_income
from app.services.invoice_service import SUPPORTED_INVOICE_TYPES, delete_invoice
from app.services.receipt_payment_service import delete_receipt_payment
from app.services.transfer_service import delete_transfer

logger = logging.getLogger(__name__)


def purge_business_operational_data(db: Session, business_id: int) -> Dict[str, Any]:
	"""
	پاک‌سازی داده‌های عملیاتی کسب‌وکار قبل از بازنویسی legacy import.
	اسناد از مسیر سرویس حذف حذف می‌شوند تا side-effect انبار/مانده درست باشد.
	"""
	bid = int(business_id)
	stats: Dict[str, Any] = {
		"documents_deleted": 0,
		"documents_failed": 0,
		"persons_deleted": 0,
		"products_deleted": 0,
		"bank_accounts_deleted": 0,
		"warehouses_deleted": 0,
		"warehouse_documents_deleted": 0,
		"checks_deleted": 0,
	}

	docs = (
		db.query(Document)
		.filter(Document.business_id == bid)
		.order_by(Document.id.desc())
		.all()
	)
	for doc in docs:
		try:
			dt = doc.document_type
			if dt in SUPPORTED_INVOICE_TYPES:
				delete_invoice(db, doc.id, commit=False)
			elif dt in ("receipt", "payment"):
				delete_receipt_payment(db, doc.id, commit=False)
			elif dt in ("expense", "income"):
				delete_expense_income(db, doc.id, commit=False)
			elif dt == "transfer":
				delete_transfer(db, doc.id, commit=False)
			else:
				delete_document(db, doc.id, commit=False)
			stats["documents_deleted"] += 1
		except Exception as exc:
			logger.warning("purge_document_failed", extra={"doc_id": doc.id, "error": str(exc)})
			stats["documents_failed"] += 1

	stats["persons_deleted"] = db.query(Person).filter(Person.business_id == bid).delete(synchronize_session=False)
	stats["products_deleted"] = db.query(Product).filter(Product.business_id == bid).delete(synchronize_session=False)
	stats["bank_accounts_deleted"] = (
		db.query(BankAccount).filter(BankAccount.business_id == bid).delete(synchronize_session=False)
	)
	db.query(CashRegister).filter(CashRegister.business_id == bid).delete(synchronize_session=False)
	db.query(PettyCash).filter(PettyCash.business_id == bid).delete(synchronize_session=False)
	wh_doc_ids = [
		row[0]
		for row in db.query(WarehouseDocument.id).filter(WarehouseDocument.business_id == bid).all()
	]
	if wh_doc_ids:
		db.query(WarehouseDocumentLine).filter(
			WarehouseDocumentLine.warehouse_document_id.in_(wh_doc_ids)
		).delete(synchronize_session=False)
		stats["warehouse_documents_deleted"] = (
			db.query(WarehouseDocument)
			.filter(WarehouseDocument.business_id == bid)
			.delete(synchronize_session=False)
		)

	stats["checks_deleted"] = (
		db.query(Check).filter(Check.business_id == bid).delete(synchronize_session=False)
	)

	stats["warehouses_deleted"] = (
		db.query(Warehouse).filter(Warehouse.business_id == bid).delete(synchronize_session=False)
	)
	db.flush()
	return stats
