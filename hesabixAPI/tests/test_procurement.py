"""قواعد و جریان تدارکات بدون وابستگی به PostgreSQL."""
from __future__ import annotations

import unittest
from datetime import date, timedelta
from types import SimpleNamespace
from unittest.mock import patch

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from adapters.db.models.activity_log import ActivityLog
from adapters.db.models.document import Document
from adapters.db.models.procurement import (
	ProcApproval,
	ProcBudget,
	ProcBudgetMovement,
	ProcCommitment,
	ProcContract,
	ProcContractLine,
	ProcCostCenter,
	ProcDelegation,
	ProcGuarantee,
	ProcInvoiceLink,
	ProcMatchLine,
	ProcOrder,
	ProcOrderLine,
	ProcPortalInvoice,
	ProcPrepayment,
	ProcReceipt,
	ProcReceiptLine,
	ProcReorderSuggestion,
	ProcRequisition,
	ProcRequisitionLine,
	ProcScore,
	ProcSettings,
	ProcShareLink,
	ProcSourcingBid,
	ProcSourcingBidLine,
	ProcSourcingEvent,
	ProcSourcingInvite,
	ProcSourcingLine,
	ProcSupplierDocument,
	ProcSupplierProfile,
)
from adapters.db.models.product import Product, ProductItemType
from adapters.db.models.product_supplier import ProductSupplier
from app.core.responses import ApiError
from app.services import procurement_service as svc
from app.services.procurement_domain import (
	budget_available,
	compare_bids,
	covered_by_stock,
	grade_for_score,
	match_line,
	suggested_buy_qty,
)


def _line(**extra):
	row = {"description": "کالای آزمایشی", "qty": 10, "unit_price": 100, "item_kind": "goods"}
	row.update(extra)
	return row


def _store_file(db, file_id, business_id=1):
	from adapters.db.models.file_storage import FileStorage

	FileStorage.__table__.create(db.get_bind(), checkfirst=True)
	db.add(
		FileStorage(
			id=file_id,
			original_name=f"{file_id}.pdf",
			stored_name=f"{file_id}.pdf",
			file_path=f"/tmp/{file_id}.pdf",
			file_size=1,
			mime_type="application/pdf",
			storage_type="local",
			uploaded_by=7,
			business_id=business_id,
			module_context="procurement",
			is_active=True,
		)
	)
	db.flush()


class ProcurementTests(unittest.TestCase):
	def setUp(self):
		engine = create_engine("sqlite:///:memory:")
		for table in (
			ActivityLog.__table__,
			Product.__table__,
			ProductSupplier.__table__,
			Document.__table__,
			ProcSettings.__table__,
			ProcCostCenter.__table__,
			ProcSupplierProfile.__table__,
			ProcSupplierDocument.__table__,
			ProcDelegation.__table__,
			ProcBudget.__table__,
			ProcBudgetMovement.__table__,
			ProcContract.__table__,
			ProcContractLine.__table__,
			ProcRequisition.__table__,
			ProcRequisitionLine.__table__,
			ProcSourcingEvent.__table__,
			ProcSourcingLine.__table__,
			ProcSourcingInvite.__table__,
			ProcSourcingBid.__table__,
			ProcSourcingBidLine.__table__,
			ProcOrder.__table__,
			ProcOrderLine.__table__,
			ProcCommitment.__table__,
			ProcReceipt.__table__,
			ProcReceiptLine.__table__,
			ProcInvoiceLink.__table__,
			ProcMatchLine.__table__,
			ProcGuarantee.__table__,
			ProcPrepayment.__table__,
			ProcScore.__table__,
			ProcShareLink.__table__,
			ProcPortalInvoice.__table__,
			ProcReorderSuggestion.__table__,
			ProcApproval.__table__,
		):
			table.create(engine, checkfirst=True)
		self.db = sessionmaker(bind=engine)()
		from adapters.db.models.warehouse import Warehouse

		Warehouse.__table__.create(engine, checkfirst=True)
		self.db.add(Product(id=5, business_id=1, code="P-5", name="کالای ۵", item_type=ProductItemType.PRODUCT, track_inventory=True))
		self.db.add(Product(id=6, business_id=1, code="P-6", name="کالای ۶", item_type=ProductItemType.PRODUCT, track_inventory=True))
		self.db.add(Warehouse(id=2, business_id=1, code="W-2", name="انبار ۲"))
		self.db.add(Warehouse(id=3, business_id=1, code="W-3", name="انبار ۳"))
		self.db.flush()
		self._counter = {"n": 0}
		self._patches = [
			patch("app.services.procurement_service.generate_document_code", self._fake_code),
			patch("app.services.procurement_service._load_person", lambda db, business_id, person_id: SimpleNamespace(id=int(person_id), alias_name="آکام")),
			patch("app.services.procurement_service._emit", lambda *args, **kwargs: None),
			patch("app.services.procurement_service._stock", lambda *args, **kwargs: 0),
		]
		for item in self._patches:
			item.start()

	def tearDown(self):
		for item in reversed(self._patches):
			item.stop()
		self.db.close()

	def _fake_code(self, db, business_id, document_type, document_date=None):
		self._counter["n"] += 1
		return f"{document_type}-{self._counter['n']:04d}"

	def test_ai_view_follows_procurement_permission_implication(self):
		from app.services.ai.ai_permission_map import has_ai_tool_permission

		class Ctx:
			def __init__(self, action):
				self.action = action
				self.business_id = 1

			def is_superadmin(self):
				return False

			def is_business_owner(self, business_id):
				return False

			def has_app_permission(self, perm):
				return False

			def has_business_permission(self, section, action):
				return section == "procurement" and action == self.action

		for action in ("view", "operate", "approve", "manage", "admin"):
			self.assertTrue(has_ai_tool_permission(Ctx(action), "procurement.view", business_id=1))
		self.assertFalse(has_ai_tool_permission(Ctx("operate"), "procurement.approve", business_id=1))
		self.assertFalse(has_ai_tool_permission(Ctx("view"), "procurement.operate", business_id=1))

	def test_expensive_supplier_wins_when_quality_dominates(self):
		ranking = compare_bids(
			[
				{"invite_id": 1, "price_total": 100, "delivery_days": 10, "payment_days": 30, "quality": 10, "risk": 10},
				{"invite_id": 2, "price_total": 200, "delivery_days": 10, "payment_days": 30, "quality": 100, "risk": 10},
			],
			{"price": 20, "delivery": 0, "payment": 0, "quality": 80, "risk": 0},
		)
		self.assertEqual(ranking[0]["invite_id"], 2)
		self.assertEqual(ranking[0]["rank"], 1)

	def test_match_blocks_quantity_and_flags_price(self):
		blocked = match_line(ordered=10, accepted=10, invoice_qty=11, po_price=100, invoice_price=100, item_kind="goods")
		self.assertEqual(blocked["status"], "exception")
		self.assertIn("qty", blocked["reasons"])
		priced = match_line(ordered=10, accepted=10, invoice_qty=10, po_price=100, invoice_price=130, price_tolerance=5, item_kind="goods")
		self.assertEqual(priced["status"], "exception")
		self.assertIn("price", priced["reasons"])

	def test_budget_grade_and_reorder_math(self):
		self.assertEqual(budget_available(1000, 100, 50, 20, 200, 300), 630)
		self.assertEqual(grade_for_score(85), "A")
		self.assertEqual(grade_for_score(70), "B")
		self.assertEqual(grade_for_score(50), "C")
		self.assertEqual(grade_for_score(49), "D")
		self.assertEqual(suggested_buy_qty(on_hand=2, open_qty=1, reorder_point=10, min_order_qty=4), 7)
		self.assertEqual(suggested_buy_qty(on_hand=8, open_qty=3, reorder_point=10, min_order_qty=4), 0)
		self.assertTrue(covered_by_stock(needed=5, on_hand=4, open_qty=1))

	def test_returned_requisition_and_draft_order_can_be_edited(self):
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		created = svc.create_requisition(self.db, 1, {"reason": "اول", "lines": [_line(qty=2)]}, 7)
		svc.submit_requisition(self.db, 1, created["id"], {}, 7)
		self.assertEqual(svc.decide(self.db, 1, "requisition", created["id"], "return", "مقدار را کم کن", 7)["status"], "returned")
		edited = svc.update_requisition(self.db, 1, created["id"], {"reason": "اصلاح", "lines": [_line(qty=3)]}, 7)
		self.assertEqual(edited["status"], "returned")
		self.assertEqual(edited["lines"][0]["qty"], 3)
		svc.submit_requisition(self.db, 1, created["id"], {}, 7)
		svc.decide(self.db, 1, "requisition", created["id"], "approve", None, 7)
		with self.assertRaises(ApiError) as locked:
			svc.update_requisition(self.db, 1, created["id"], {"reason": "دیر"}, 7)
		self.assertEqual(locked.exception.code, "REQUISITION_LOCKED")
		_store_file(self.db, "a")
		_store_file(self.db, "b")
		_store_file(self.db, "foreign", business_id=2)
		with self.assertRaises(ApiError) as foreign:
			svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(qty=1)], "file_ids": ["foreign"]}, 7)
		self.assertEqual(foreign.exception.code, "FILE_NOT_FOUND")
		order = svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(qty=1)], "file_ids": ["a"]}, 7)
		changed = svc.update_order(self.db, 1, order["id"], {"freight": 15, "file_ids": ["b"], "lines": [_line(qty=4)]}, 7)
		self.assertEqual(changed["freight"], 15)
		self.assertEqual(changed["lines"][0]["qty"], 4)
		self.assertEqual(changed["file_ids"], ["b"])

	def test_requisition_submit_and_approve(self):
		created = svc.create_requisition(self.db, 1, {"reason": "نیاز انبار", "lines": [_line()]}, 7)
		self.assertEqual(created["status"], "draft")
		submitted = svc.submit_requisition(self.db, 1, created["id"], {"approver_user_ids": [9]}, 7)
		self.assertEqual(submitted["status"], "pending_approval")
		self.assertEqual(svc.list_requisitions(self.db, 1)["items"][0]["approvals"][0]["approver_user_id"], 9)
		with self.assertRaises(ApiError) as denied:
			svc.decide(self.db, 1, "requisition", created["id"], "approve", None, 7)
		self.assertEqual(denied.exception.code, "NOT_THE_APPROVER")
		decision = svc.decide(self.db, 1, "requisition", created["id"], "approve", None, 9)
		self.assertEqual(decision["status"], "approved")
		self.assertEqual(svc.get_requisition(self.db, 1, created["id"])["status"], "approved")

	def test_product_and_warehouse_must_belong_to_the_business(self):
		from adapters.db.models.warehouse import Warehouse

		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		self.db.add(Product(id=9, business_id=2, code="P-9", name="بیگانه", item_type=ProductItemType.PRODUCT))
		self.db.add(Warehouse(id=8, business_id=2, code="W-8", name="انبار بیگانه"))
		self.db.flush()
		with self.assertRaises(ApiError) as foreign_product:
			svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(product_id=9)]}, 7)
		self.assertEqual(foreign_product.exception.code, "PRODUCT_NOT_FOUND")
		with self.assertRaises(ApiError) as foreign_warehouse:
			svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(product_id=5, warehouse_id=8)]}, 7)
		self.assertEqual(foreign_warehouse.exception.code, "WAREHOUSE_NOT_FOUND")
		order = svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(product_id=5, warehouse_id=2)]}, 7)
		svc.submit_order(self.db, 1, order["id"], {}, 7)
		svc.decide(self.db, 1, "order", order["id"], "approve", None, 7)
		with self.assertRaises(ApiError) as receipt_warehouse:
			svc.receive_order(self.db, 1, order["id"], {"lines": [{"order_line_id": order["lines"][0]["id"], "qty": 1, "warehouse_id": 8}]}, 7)
		self.assertEqual(receipt_warehouse.exception.code, "WAREHOUSE_NOT_FOUND")
		with self.assertRaises(ApiError) as foreign_budget:
			svc.create_order(self.db, 1, {"person_id": 3, "budget_id": 999, "lines": [_line()]}, 7)
		self.assertEqual(foreign_budget.exception.code, "BUDGET_NOT_FOUND")
		foreign_center = svc.create_cost_center(self.db, 2, {"code": "X", "name": "دیگر"}, 7)
		with self.assertRaises(ApiError) as foreign_cost:
			svc.create_order(self.db, 1, {"person_id": 3, "cost_center_id": foreign_center["id"], "lines": [_line()]}, 7)
		self.assertEqual(foreign_cost.exception.code, "COST_CENTER_NOT_FOUND")
		from adapters.db.models.project import Project

		Project.__table__.create(self.db.get_bind(), checkfirst=True)
		self.db.add(Project(id=4, business_id=2, code="PX", name="پروژه دیگر", created_by_user_id=7))
		self.db.flush()
		with self.assertRaises(ApiError) as foreign_project:
			svc.create_requisition(self.db, 1, {"project_id": 4, "lines": [_line()]}, 7)
		self.assertEqual(foreign_project.exception.code, "PROJECT_NOT_FOUND")

	def test_direct_order_cannot_borrow_a_source_and_cancel_reopens_the_need(self):
		with self.assertRaises(ApiError) as borrowed:
			svc.create_order(self.db, 1, {"person_id": 3, "requisition_id": 4, "lines": [_line()]}, 7)
		self.assertEqual(borrowed.exception.code, "ORDER_SOURCE_PATH")
		with self.assertRaises(ApiError) as contract:
			svc.create_order(self.db, 1, {"person_id": 3, "contract_id": 1, "lines": [_line()]}, 7)
		self.assertEqual(contract.exception.code, "ORDER_SOURCE_PATH")
		with self.assertRaises(ApiError) as event:
			svc.create_order(self.db, 1, {"person_id": 3, "sourcing_event_id": 1, "lines": [_line()]}, 7)
		self.assertEqual(event.exception.code, "ORDER_SOURCE_PATH")
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		created = svc.create_requisition(self.db, 1, {"lines": [_line(qty=2)]}, 7)
		svc.submit_requisition(self.db, 1, created["id"], {}, 7)
		svc.decide(self.db, 1, "requisition", created["id"], "approve", None, 7)
		order = svc.create_order_from_requisition(self.db, 1, created["id"], {"person_id": 3, "currency_id": 1}, 7)
		self.assertEqual(svc.get_requisition(self.db, 1, created["id"])["status"], "converted")
		svc.submit_order(self.db, 1, order["id"], {}, 7)
		svc.decide(self.db, 1, "order", order["id"], "reject", "نیست", 7)
		self.assertEqual(svc.get_requisition(self.db, 1, created["id"])["status"], "approved")
		again = svc.create_order_from_requisition(self.db, 1, created["id"], {"person_id": 3, "currency_id": 1}, 7)
		self.assertNotEqual(again["id"], order["id"])
		svc.cancel_order(self.db, 1, again["id"], 7)
		self.assertEqual(svc.get_requisition(self.db, 1, created["id"])["status"], "approved")

	def test_draft_edit_keeps_discount_and_tax(self):
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		order = svc.create_order(
			self.db,
			1,
			{
				"person_id": 3,
				"currency_id": 1,
				"header_discount": 10,
				"lines": [
					_line(product_id=5, item_kind="service", qty=2, unit_price=100, discount=20, tax=8),
					_line(product_id=6, item_kind="service", description="دوم", qty=1, unit_price=50, discount=5, tax=2),
				],
			},
			7,
		)
		updated = svc.update_order(
			self.db,
			1,
			order["id"],
			{
				"freight": 5,
				"header_discount": 10,
				"lines": [
					{"description": "کالای آزمایشی", "qty": 2, "unit_price": 100, "discount": 20, "tax": 8, "item_kind": "service", "product_id": 5, "warehouse_id": 2},
					{"description": "دوم", "qty": 1, "unit_price": 50, "discount": 5, "tax": 2, "item_kind": "service", "product_id": 6, "warehouse_id": 3},
				],
			},
			7,
		)
		self.assertEqual(updated["lines"][0]["discount"], 20.0)
		self.assertEqual(updated["lines"][0]["tax"], 8.0)
		self.assertEqual(updated["lines"][0]["product_id"], 5)
		self.assertEqual(updated["lines"][0]["warehouse_id"], 2)
		self.assertEqual(updated["lines"][1]["discount"], 5.0)
		self.assertEqual(updated["lines"][1]["tax"], 2.0)
		self.assertEqual(updated["lines"][1]["product_id"], 6)
		self.assertEqual(updated["lines"][1]["warehouse_id"], 3)
		self.assertEqual(updated["header_discount"], 10.0)
		self.assertEqual(updated["freight"], 5.0)
		self.assertEqual(updated["total"], 230.0)

	def test_invoice_matches_payable_price_after_discount(self):
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		budget = svc.create_budget(self.db, 1, {"name": "فاکتور", "amount": 500, "period_key": "2026-11"}, 7)
		order = svc.create_order(
			self.db,
			1,
			{"person_id": 3, "currency_id": 1, "budget_id": budget["id"], "header_discount": 10, "lines": [_line(product_id=5, item_kind="service", qty=2, unit_price=100, discount=20, tax=8)]},
			7,
		)
		with self.assertRaises(ApiError) as too_soon:
			svc.create_invoice_for_order(self.db, 1, order["id"], {"lines": [{"order_line_id": order["lines"][0]["id"], "qty": 1}]}, 7)
		self.assertEqual(too_soon.exception.code, "ORDER_NOT_BILLABLE")
		with self.assertRaises(ApiError) as line_discount:
			svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(qty=1, unit_price=100, discount=500)]}, 7)
		self.assertEqual(line_discount.exception.code, "DISCOUNT_EXCEEDS_LINE")
		with self.assertRaises(ApiError) as header_discount:
			svc.create_order(self.db, 1, {"person_id": 3, "header_discount": 500, "lines": [_line(qty=1, unit_price=100)]}, 7)
		self.assertEqual(header_discount.exception.code, "DISCOUNT_EXCEEDS_ORDER")
		svc.submit_order(self.db, 1, order["id"], {}, 7)
		svc.decide(self.db, 1, "order", order["id"], "approve", None, 7)
		svc.receive_order(self.db, 1, order["id"], {"lines": [{"order_line_id": order["lines"][0]["id"], "qty": 2}]}, 7)
		captured = {}

		def fake_invoice(db, business_id, user_id, data, commit=False):
			captured["price"] = data["lines"][0]["extra_info"]["unit_price"]
			captured["tax"] = data["lines"][0]["extra_info"]["tax_amount"]
			return {"data": {"id": 77}}

		with patch("app.services.invoice_service.create_invoice", fake_invoice), patch.object(svc, "_mark_receipt_stock_not_on_invoice", lambda *args, **kwargs: None), patch.object(svc, "_clear_grni", lambda *args, **kwargs: None):
			svc.create_invoice_for_order(self.db, 1, order["id"], {"lines": [{"order_line_id": order["lines"][0]["id"], "qty": 2}]}, 7)
		self.assertEqual(captured["price"], 85.0)
		self.assertEqual(captured["tax"], 8.0)
		self.assertEqual(float(self.db.query(ProcMatchLine).one().po_price), 85.0)
		svc.close_order(self.db, 1, order["id"], 7)
		figures = next(item for item in svc.list_budgets(self.db, 1)["items"] if item["id"] == budget["id"])
		self.assertEqual(figures["actuals"], 178.0)
		self.assertEqual(figures["available"], 322.0)
		split = svc.create_order(
			self.db,
			1,
			{"person_id": 3, "currency_id": 1, "lines": [_line(product_id=5, item_kind="service", qty=3, unit_price=100, tax=10)]},
			7,
		)
		svc.submit_order(self.db, 1, split["id"], {}, 7)
		svc.decide(self.db, 1, "order", split["id"], "approve", None, 7)
		svc.receive_order(self.db, 1, split["id"], {"lines": [{"order_line_id": split["lines"][0]["id"], "qty": 3}]}, 7)
		taxes = []

		def fake_split(db, business_id, user_id, data, commit=False):
			taxes.append(data["lines"][0]["extra_info"]["tax_amount"])
			return {"data": {"id": 80 + len(taxes)}}

		with patch("app.services.invoice_service.create_invoice", fake_split), patch.object(svc, "_mark_receipt_stock_not_on_invoice", lambda *args, **kwargs: None), patch.object(svc, "_clear_grni", lambda *args, **kwargs: None):
			for _ in range(3):
				svc.create_invoice_for_order(self.db, 1, split["id"], {"lines": [{"order_line_id": split["lines"][0]["id"], "qty": 1}]}, 7)
		self.assertEqual(taxes, [3.33, 3.34, 3.33])
		self.assertEqual(sum(taxes), 10.0)

	def test_direct_po_and_unapproved_supplier_are_blocked(self):
		with self.assertRaises(ApiError) as direct:
			svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line()]}, 7)
		self.assertEqual(direct.exception.code, "DIRECT_PO_DISABLED")
		svc.update_settings(self.db, 1, {"allow_direct_po": True}, 7)
		with self.assertRaises(ApiError) as unapproved:
			svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line()]}, 7)
		self.assertEqual(unapproved.exception.code, "SUPPLIER_NOT_APPROVED")
		enterprise = svc.update_settings(self.db, 1, {"mode": "enterprise"}, 7)
		self.assertFalse(enterprise["allow_direct_po"])
		self.assertTrue(enterprise["require_approved_supplier"])
		self.assertTrue(enterprise["budget_required"])
		small = svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		self.assertTrue(small["allow_direct_po"])
		self.assertFalse(small["require_approved_supplier"])
		svc.update_settings(self.db, 1, {"allow_direct_po": False}, 7)
		with self.assertRaises(ApiError) as blocked:
			svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line()]}, 7)
		self.assertEqual(blocked.exception.code, "DIRECT_PO_DISABLED")

	def test_budget_blocks_approval_and_warns_after_eighty_percent(self):
		svc.update_settings(self.db, 1, {"mode": "small", "budget_required": True}, 7)
		missing_budget = svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(qty=1)]}, 7)
		svc.submit_order(self.db, 1, missing_budget["id"], {}, 7)
		with self.assertRaises(ApiError) as missing:
			svc.decide(self.db, 1, "order", missing_budget["id"], "approve", None, 7)
		self.assertEqual(missing.exception.code, "BUDGET_REQUIRED")
		budget = svc.create_budget(self.db, 1, {"name": "خرید", "amount": 1000, "period_key": "2026-11"}, 7)
		self.assertFalse(budget["warn"])
		small = svc.create_order(self.db, 1, {"person_id": 3, "budget_id": budget["id"], "lines": [_line(qty=9)]}, 7)
		svc.submit_order(self.db, 1, small["id"], {}, 7)
		self.assertEqual(svc.decide(self.db, 1, "order", small["id"], "approve", None, 7)["status"], "approved")
		figures = svc.list_budgets(self.db, 1)["items"][0]
		self.assertEqual(figures["open_commitments"], 900)
		self.assertEqual(figures["available"], 100)
		self.assertTrue(figures["warn"])
		huge = svc.create_order(self.db, 1, {"person_id": 3, "budget_id": budget["id"], "lines": [_line(qty=2)]}, 7)
		svc.submit_order(self.db, 1, huge["id"], {}, 7)
		with self.assertRaises(ApiError) as exceeded:
			svc.decide(self.db, 1, "order", huge["id"], "approve", None, 7)
		self.assertEqual(exceeded.exception.code, "BUDGET_EXCEEDED")

	def test_order_approval_rechecks_supplier_block(self):
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		order = svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(qty=1)]}, 7)
		svc.upsert_supplier(self.db, 1, {"person_id": 3, "status": "suspended"}, 7)
		svc.submit_order(self.db, 1, order["id"], {}, 7)
		with self.assertRaises(ApiError) as blocked:
			svc.decide(self.db, 1, "order", order["id"], "approve", None, 7)
		self.assertEqual(blocked.exception.code, "SUPPLIER_BLOCKED")
		self.assertEqual(svc.get_order(self.db, 1, order["id"])["status"], "pending_approval")
		self.assertEqual(self.db.query(ProcCommitment).count(), 0)
		svc.upsert_supplier(self.db, 1, {"person_id": 3, "status": "approved"}, 7)
		self.assertEqual(svc.decide(self.db, 1, "order", order["id"], "approve", None, 7)["status"], "approved")

	def test_expired_supplier_document_blocks_the_order(self):
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		profile = svc.upsert_supplier(self.db, 1, {"person_id": 3, "status": "approved"}, 7)
		svc.add_supplier_document(self.db, 1, profile["id"], {"title": "بیمه", "expires_on": (date.today() + timedelta(days=1)).isoformat()}, 7)
		svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(qty=1)]}, 7)
		svc.add_supplier_document(self.db, 1, profile["id"], {"title": "مجوز", "expires_on": (date.today() - timedelta(days=1)).isoformat()}, 7)
		with self.assertRaises(ApiError) as blocked:
			svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(qty=1)]}, 7)
		self.assertEqual(blocked.exception.code, "SUPPLIER_DOCUMENT_EXPIRED")
		license_row = self.db.query(ProcSupplierDocument).filter(ProcSupplierDocument.title == "مجوز").one()
		license_row.expires_on = date.today()
		self.db.flush()
		renewed = svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(qty=1)]}, 7)
		self.assertEqual(renewed["person_id"], 3)

	def test_budget_period_cost_center_and_delegation_are_checked(self):
		from datetime import datetime

		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		svc.create_cost_center(self.db, 1, {"code": "CC", "name": "بازرگانی"}, 7)
		with self.assertRaises(ApiError) as duplicate:
			svc.create_cost_center(self.db, 1, {"code": "CC", "name": "تکرار"}, 7)
		self.assertEqual(duplicate.exception.code, "COST_CENTER_EXISTS")
		with self.assertRaises(ApiError) as period:
			svc.create_budget(self.db, 1, {"name": "بد", "amount": 10, "period_key": "2026-13"}, 7)
		self.assertEqual(period.exception.code, "INVALID_PERIOD")
		with self.assertRaises(ApiError) as warn:
			svc.create_budget(self.db, 1, {"name": "هشدار", "amount": 10, "period_key": "2026-11", "warn_percent": 0}, 7)
		self.assertEqual(warn.exception.code, "INVALID_WARN_PERCENT")
		self.assertEqual(svc.create_budget(self.db, 1, {"name": "آبان", "amount": 10, "period_key": "2026-11"}, 7)["period_key"], "2026-11")
		from adapters.db.models.fiscal_year import FiscalYear

		FiscalYear.__table__.create(self.db.get_bind(), checkfirst=True)
		foreign_year = FiscalYear(business_id=2, title="دیگر", start_date=date(2026, 1, 1), end_date=date(2026, 12, 31))
		own_year = FiscalYear(business_id=1, title="همین", start_date=date(2026, 1, 1), end_date=date(2026, 12, 31), is_last=True)
		self.db.add(foreign_year)
		self.db.add(own_year)
		self.db.flush()
		with self.assertRaises(ApiError) as foreign_budget:
			svc.create_budget(self.db, 1, {"name": "سال دیگر", "amount": 10, "period_key": "2026-11", "fiscal_year_id": foreign_year.id}, 7)
		self.assertEqual(foreign_budget.exception.code, "FISCAL_YEAR_NOT_FOUND")
		own_budget = svc.create_budget(self.db, 1, {"name": "سال خود", "amount": 10, "period_key": "2026-11", "fiscal_year_id": own_year.id}, 7)
		self.assertEqual(self.db.query(ProcBudget).filter(ProcBudget.id == own_budget["id"]).one().fiscal_year_id, own_year.id)
		with self.assertRaises(ApiError) as same_person:
			svc.create_delegation(self.db, 1, {"user_id": 7, "delegate_user_id": 7}, 7)
		self.assertEqual(same_person.exception.code, "DELEGATION_SELF")
		with self.assertRaises(ApiError) as past:
			svc.create_delegation(self.db, 1, {"user_id": 9, "delegate_user_id": 7, "ends_at": datetime.utcnow() - timedelta(days=1)}, 7)
		self.assertEqual(past.exception.code, "DELEGATION_EXPIRED")
		order = svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(qty=1)]}, 7)
		svc.submit_order(self.db, 1, order["id"], {"approver_user_ids": [9]}, 7)
		svc.create_delegation(self.db, 1, {"user_id": 9, "delegate_user_id": 7}, 7)
		delegation = self.db.query(ProcDelegation).one()
		delegation.starts_at = datetime.utcnow() + timedelta(days=2)
		self.db.flush()
		with self.assertRaises(ApiError) as early:
			svc.decide(self.db, 1, "order", order["id"], "approve", None, 7)
		self.assertEqual(early.exception.code, "NOT_THE_APPROVER")
		delegation.starts_at = datetime.utcnow() - timedelta(minutes=1)
		self.db.flush()
		self.assertEqual(svc.decide(self.db, 1, "order", order["id"], "approve", None, 7)["status"], "approved")

	def test_partial_receipt_over_receipt_and_three_way_match(self):
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		order = svc.create_order(self.db, 1, {"person_id": 3, "currency_id": 1, "lines": [_line(product_id=5, item_kind="service")]}, 7)
		svc.submit_order(self.db, 1, order["id"], {}, 7)
		svc.decide(self.db, 1, "order", order["id"], "approve", None, 7)
		line_id = svc.get_order(self.db, 1, order["id"])["lines"][0]["id"]
		with self.assertRaises(ApiError) as empty:
			svc.receive_order(self.db, 1, order["id"], {"lines": [{"order_line_id": line_id, "qty": 0}]}, 7)
		self.assertEqual(empty.exception.code, "INVALID_QTY")
		partial = svc.receive_order(self.db, 1, order["id"], {"lines": [{"order_line_id": line_id, "qty": 4}]}, 7)
		self.assertEqual(partial["status"], "partial")
		self.assertEqual(partial["lines"][0]["accepted_qty"], 4)
		with self.assertRaises(ApiError) as over:
			svc.receive_order(self.db, 1, order["id"], {"lines": [{"order_line_id": line_id, "qty": 7}]}, 7)
		self.assertEqual(over.exception.code, "OVER_RECEIPT")
		called = {"invoice": 0}

		def fake_invoice(*args, **kwargs):
			called["invoice"] += 1
			return {"data": {"id": 55, "code": "PINV-1", "document_type": "invoice_purchase"}}

		with patch("app.services.invoice_service.create_invoice", fake_invoice), patch.object(svc, "_mark_receipt_stock_not_on_invoice", lambda *args, **kwargs: None), patch.object(svc, "_clear_grni", lambda *args, **kwargs: None):
			with self.assertRaises(ApiError) as qty_block:
				svc.create_invoice_for_order(self.db, 1, order["id"], {"lines": [{"order_line_id": line_id, "qty": 5}]}, 7)
			self.assertEqual(qty_block.exception.code, "MATCH_QTY_BLOCKED")
			self.assertEqual(called["invoice"], 0)
			with self.assertRaises(ApiError) as price_block:
				svc.create_invoice_for_order(self.db, 1, order["id"], {"lines": [{"order_line_id": line_id, "qty": 4, "unit_price": 180}]}, 7)
			self.assertEqual(price_block.exception.code, "MATCH_PRICE_BLOCKED")
			invoiced = svc.create_invoice_for_order(
				self.db, 1, order["id"], {"accept_price_variance": True, "lines": [{"order_line_id": line_id, "qty": 4, "unit_price": 180}]}, 7
			)
		self.assertEqual(called["invoice"], 1)
		self.assertEqual(invoiced["document_id"], 55)
		self.assertEqual(invoiced["match_status"], "tolerance")
		self.assertTrue(invoiced["invoices"][0]["price_variance_accepted"])
		with self.assertRaises(ApiError) as again:
			svc.create_invoice_for_order(self.db, 1, order["id"], {"lines": [{"order_line_id": line_id, "qty": 1}]}, 7)
		self.assertEqual(again.exception.code, "MATCH_QTY_BLOCKED")
		self.assertEqual(called["invoice"], 1)

	def test_tender_hides_prices_until_financial_open_and_award_needs_minutes(self):
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		event = svc.create_sourcing(self.db, 1, {"event_type": "tender", "title": "مناقصه پیچ", "lines": [_line(qty=2)]}, 7)
		invited = svc.invite_suppliers(self.db, 1, event["id"], [3, 4], 7)
		for invite, price in zip(invited["invites"], (100, 80)):
			extra = {"freight": 20, "tax": 8, "discount": 5, "warranty": "۱۲ ماه"} if price == 100 else {}
			svc.submit_bid(
				self.db,
				1,
				invite["id"],
				{"delivery_days": 5, "payment_days": 30, **extra, "lines": [{"sourcing_line_id": event["lines"][0]["id"], "unit_price": price}]},
				7,
			)
		with self.assertRaises(ApiError) as negative_price:
			svc.submit_bid(self.db, 1, invited["invites"][0]["id"], {"lines": [{"sourcing_line_id": event["lines"][0]["id"], "unit_price": -1}]}, 7)
		self.assertEqual(negative_price.exception.code, "INVALID_PRICE")
		with self.assertRaises(ApiError) as fat_discount:
			svc.submit_bid(self.db, 1, invited["invites"][0]["id"], {"discount": 999, "lines": [{"sourcing_line_id": event["lines"][0]["id"], "unit_price": 100}]}, 7)
		self.assertEqual(fat_discount.exception.code, "DISCOUNT_EXCEEDS_BID")
		hidden = svc.get_sourcing(self.db, 1, event["id"])
		self.assertFalse(hidden["financial_visible"])
		self.assertIsNone(hidden["invites"][0]["bid"]["total"])
		with self.assertRaises(ApiError) as sealed:
			svc.compare_sourcing(self.db, 1, event["id"])
		self.assertEqual(sealed.exception.code, "FINANCIAL_SEALED")
		svc.open_technical(self.db, 1, event["id"], 7)
		with self.assertRaises(ApiError) as rewritten:
			svc.submit_bid(self.db, 1, invited["invites"][0]["id"], {"lines": [{"sourcing_line_id": event["lines"][0]["id"], "unit_price": 1}]}, 7)
		self.assertEqual(rewritten.exception.code, "BID_LOCKED")
		self.assertEqual(self.db.query(ProcSourcingBidLine).filter(ProcSourcingBidLine.unit_price == 100).count(), 1)
		with self.assertRaises(ApiError) as unscored:
			svc.open_financial(self.db, 1, event["id"], 7)
		self.assertEqual(unscored.exception.code, "TECHNICAL_SCORE_REQUIRED")
		svc.score_technical(
			self.db,
			1,
			event["id"],
			{"scores": [{"invite_id": row["id"], "technical_score": 70} for row in invited["invites"]]},
			7,
		)
		svc.open_financial(self.db, 1, event["id"], 7)
		with self.assertRaises(ApiError) as minutes:
			svc.award_sourcing(self.db, 1, event["id"], {"invite_id": invited["invites"][0]["id"], "reason": "کیفیت بهتر"}, 7)
		self.assertEqual(minutes.exception.code, "MINUTES_REQUIRED")
		awarded = svc.award_sourcing(
			self.db,
			1,
			event["id"],
			{"invite_id": invited["invites"][0]["id"], "reason": "کیفیت بهتر", "minutes": "جلسه کمیته برگزار شد."},
			7,
		)
		self.assertEqual(awarded["order"]["person_id"], invited["invites"][0]["person_id"])
		self.assertEqual(awarded["order"]["status"], "draft")
		self.assertEqual(awarded["order"]["freight"], 20)
		self.assertEqual(awarded["order"]["header_discount"], 5)
		self.assertEqual(awarded["order"]["lines"][0]["tax"], 8)
		self.assertEqual(awarded["order"]["warranty"], "۱۲ ماه")
		self.assertEqual(awarded["order"]["total"], 223)
		self.assertEqual(self.db.query(ProcOrder).count(), 1)
		with self.assertRaises(ApiError) as twice:
			svc.award_sourcing(self.db, 1, event["id"], {"invite_id": invited["invites"][0]["id"], "reason": "تکرار", "minutes": "جلسه کمیته برگزار شد."}, 7)
		self.assertEqual(twice.exception.code, "ALREADY_AWARDED")
		self.assertEqual(self.db.query(ProcOrder).count(), 1)
		with self.assertRaises(ApiError) as cancel_awarded:
			svc.cancel_sourcing(self.db, 1, event["id"], 7)
		self.assertEqual(cancel_awarded.exception.code, "EVENT_AWARDED")

	def test_share_link_submits_bid_without_creating_order(self):
		event = svc.create_sourcing(self.db, 1, {"event_type": "rfq", "title": "استعلام", "lines": [_line(qty=1)]}, 7)
		invited = svc.invite_suppliers(self.db, 1, event["id"], [3], 7)
		listed = svc.list_sourcing(self.db, 1)["items"]
		self.assertEqual(listed[0]["id"], event["id"])
		self.assertNotIn("invites", listed[0])
		with self.assertRaises(ApiError) as wrong_supplier:
			svc.create_share_link(self.db, 1, {"kind": "rfq", "entity_id": invited["invites"][0]["id"], "person_id": 9}, 7)
		self.assertEqual(wrong_supplier.exception.code, "INVITE_NOT_FOUND")
		from datetime import datetime

		with self.assertRaises(ApiError) as past:
			svc.create_share_link(self.db, 1, {"kind": "rfq", "entity_id": invited["invites"][0]["id"], "person_id": 3, "expires_at": (datetime.utcnow() - timedelta(days=1)).isoformat()}, 7)
		self.assertEqual(past.exception.code, "SHARE_EXPIRY_INVALID")
		link = svc.create_share_link(self.db, 1, {"kind": "rfq", "entity_id": invited["invites"][0]["id"], "person_id": 3, "expires_at": (datetime.utcnow() + timedelta(days=100)).isoformat()}, 7)
		self.assertLessEqual(datetime.fromisoformat(link["expires_at"]), datetime.utcnow() + timedelta(days=14, minutes=1))
		result = svc.portal_bid(
			self.db,
			link["token"],
			{"delivery_days": 3, "payment_days": 15, "lines": [{"sourcing_line_id": event["lines"][0]["id"], "unit_price": 90}]},
		)
		self.assertEqual(result["invite_id"], invited["invites"][0]["id"])
		self.assertEqual(self.db.query(ProcOrder).count(), 0)
		shown = svc.get_sourcing(self.db, 1, event["id"])["invites"][0]["share_links"][0]
		self.assertEqual(shown["id"], link["id"])
		self.assertFalse(shown["revoked"])
		self.assertNotIn("token", shown)
		svc.revoke_share_link(self.db, 1, link["id"], 7)
		with self.assertRaises(ApiError) as revoked:
			svc.portal_view(self.db, link["token"])
		self.assertEqual(revoked.exception.code, "SHARE_LINK_INVALID")

	def test_reorder_creates_draft_need_not_order(self):
		self.db.add(Product(business_id=1, code="P-1", name="پیچ", item_type=ProductItemType.PRODUCT, track_inventory=True, reorder_point=10, min_order_qty=4))
		self.db.flush()
		refreshed = svc.refresh_reorder(self.db, 1, 7)
		self.assertEqual(refreshed["created"], 1)
		suggestion = self.db.query(ProcReorderSuggestion).one()
		self.assertEqual(float(suggestion.suggested_qty), 10)
		req = svc.convert_reorder(self.db, 1, suggestion.id, 7)
		self.assertEqual(req["status"], "draft")
		self.assertEqual(req["source"], "reorder")
		self.assertEqual(self.db.query(ProcOrder).count(), 0)

	def test_duplicate_demand_requires_acknowledgement(self):
		with patch.object(svc, "_stock", lambda *args, **kwargs: 20):
			with self.assertRaises(ApiError) as risk:
				svc.create_requisition(self.db, 1, {"lines": [_line(product_id=5, qty=5)]}, 7)
			self.assertEqual(risk.exception.code, "DUPLICATE_BUY_RISK")
			created = svc.create_requisition(self.db, 1, {"acknowledge_duplicate": True, "lines": [_line(product_id=5, qty=5)]}, 7)
			with self.assertRaises(ApiError) as edited:
				svc.update_requisition(self.db, 1, created["id"], {"lines": [_line(product_id=5, qty=6)]}, 7)
			self.assertEqual(edited.exception.code, "DUPLICATE_BUY_RISK")
			updated = svc.update_requisition(self.db, 1, created["id"], {"acknowledge_duplicate": True, "lines": [_line(product_id=5, qty=6)]}, 7)
		self.assertTrue(created["duplicate_risk"])
		self.assertEqual(updated["lines"][0]["qty"], 6)
		self.assertEqual(updated["lines"][0]["on_hand_snapshot"], 20)
		self.assertTrue(updated["duplicate_ack"])

	def _approved_service_order(self):
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		order = svc.create_order(self.db, 1, {"person_id": 3, "currency_id": 1, "lines": [_line(item_kind="service", qty=10, unit_price=20)]}, 7)
		svc.submit_order(self.db, 1, order["id"], {}, 7)
		svc.decide(self.db, 1, "order", order["id"], "approve", None, 7)
		return svc.get_order(self.db, 1, order["id"])

	def test_qc_reject_does_not_accept_and_return_reduces_accepted(self):
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		goods = svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(qty=6)]}, 7)
		svc.submit_order(self.db, 1, goods["id"], {}, 7)
		svc.decide(self.db, 1, "order", goods["id"], "approve", None, 7)
		line_id = goods["lines"][0]["id"]
		rejected = svc.receive_order(self.db, 1, goods["id"], {"lines": [{"order_line_id": line_id, "qty": 6, "qc_status": "reject"}]}, 7)
		self.assertEqual(rejected["lines"][0]["accepted_qty"], 0)
		self.assertEqual(rejected["lines"][0]["rejected_qty"], 6)
		self.assertEqual(rejected["receipts"][0]["lines"][0]["qty"], 0)
		self.assertEqual(rejected["receipts"][0]["lines"][0]["rejected_qty"], 6)
		self.assertIsNone(rejected["receipts"][0]["warehouse_document_id"])
		order = self._approved_service_order()
		line_id = order["lines"][0]["id"]
		svc.receive_order(self.db, 1, order["id"], {"lines": [{"order_line_id": line_id, "qty": 4}]}, 7)
		returned = svc.return_to_supplier(self.db, 1, order["id"], {"lines": [{"order_line_id": line_id, "qty": 1}]}, 7)
		self.assertEqual(returned["lines"][0]["accepted_qty"], 3)
		refused = self._approved_service_order()
		refused_line = refused["lines"][0]["id"]
		refused = svc.receive_order(self.db, 1, refused["id"], {"lines": [{"order_line_id": refused_line, "qty": 4, "qc_status": "reject"}]}, 7)
		self.assertFalse(refused["lines"][0]["service_confirmed"])
		self.assertEqual(refused["lines"][0]["accepted_qty"], 0)
		self.assertEqual(refused["lines"][0]["rejected_qty"], 4)
		self.assertEqual(refused["receipts"][0]["lines"][0]["rejected_qty"], 4)

	def test_requisition_becomes_order_and_delegate_can_approve(self):
		created = svc.create_requisition(self.db, 1, {"lines": [_line(qty=2)]}, 7)
		svc.submit_requisition(self.db, 1, created["id"], {"approver_user_ids": [9]}, 7)
		svc.create_delegation(self.db, 1, {"user_id": 9, "delegate_user_id": 8}, 7)
		self.assertEqual(svc.decide(self.db, 1, "requisition", created["id"], "approve", None, 8)["status"], "approved")
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		order = svc.create_order_from_requisition(self.db, 1, created["id"], {"person_id": 3, "currency_id": 1}, 7)
		self.assertEqual(order["requisition_id"], created["id"])
		self.assertEqual(svc.get_requisition(self.db, 1, created["id"])["status"], "converted")

	def test_budget_increase_transfer_and_prepayment(self):
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		source = svc.create_budget(self.db, 1, {"name": "مبدأ", "amount": 100, "period_key": "2026-11"}, 7)
		target = svc.create_budget(self.db, 1, {"name": "مقصد", "amount": 10, "period_key": "2026-11"}, 7)
		increase = svc.request_budget_increase(self.db, 1, source["id"], {"amount": 50, "reason": "کمبود"}, 7)
		queued = {row["id"]: row for row in svc.list_pending_budget_movements(self.db, 1)["items"]}
		self.assertEqual(queued[increase["id"]]["kind"], "increase")
		svc.decide(self.db, 1, "budget_movement", increase["id"], "approve", None, 7)
		rejected = svc.request_budget_transfer(self.db, 1, {"from_budget_id": source["id"], "to_budget_id": target["id"], "amount": 15, "reason": "نادرست"}, 7)
		visible = {row["id"] for row in svc.list_pending_budget_movements(self.db, 1)["items"]}
		self.assertIn(rejected["transfer_out_id"], visible)
		self.assertNotIn(rejected["transfer_in_id"], visible)
		svc.decide(self.db, 1, "budget_movement", rejected["transfer_out_id"], "reject", "اشتباه", 7)
		self.assertEqual(svc.list_pending_budget_movements(self.db, 1)["items"], [])
		self.assertEqual(self.db.query(ProcBudgetMovement).filter(ProcBudgetMovement.id == rejected["transfer_in_id"]).one().status, "rejected")
		transfer = svc.request_budget_transfer(self.db, 1, {"from_budget_id": source["id"], "to_budget_id": target["id"], "amount": 40, "reason": "جابه‌جایی"}, 7)
		svc.decide(self.db, 1, "budget_movement", transfer["transfer_out_id"], "approve", None, 7)
		figures = {row["name"]: row for row in svc.list_budgets(self.db, 1)["items"]}
		self.assertEqual(figures["مبدأ"]["available"], 110)
		self.assertEqual(figures["مقصد"]["available"], 50)
		with self.assertRaises(ApiError) as same_budget:
			svc.request_budget_transfer(self.db, 1, {"from_budget_id": source["id"], "to_budget_id": source["id"], "amount": 1, "reason": "خودش"}, 7)
		self.assertEqual(same_budget.exception.code, "TRANSFER_SAME_BUDGET")
		pending = svc.request_budget_transfer(self.db, 1, {"from_budget_id": source["id"], "to_budget_id": target["id"], "amount": 100, "reason": "دیر"}, 7)
		self.db.add(ProcBudgetMovement(business_id=1, budget_id=source["id"], kind="actual", amount=20, status="approved", created_by_user_id=7))
		self.db.flush()
		with self.assertRaises(ApiError) as late:
			svc.decide(self.db, 1, "budget_movement", pending["transfer_out_id"], "approve", None, 7)
		self.assertEqual(late.exception.code, "BUDGET_EXCEEDED")
		self.assertEqual(self.db.query(ProcBudgetMovement).filter(ProcBudgetMovement.id == pending["transfer_out_id"]).one().status, "pending")
		from adapters.db.models.document_line import DocumentLine

		DocumentLine.__table__.create(self.db.get_bind(), checkfirst=True)
		order = svc.create_order(self.db, 1, {"person_id": 3, "currency_id": 1, "lines": [_line(qty=1, unit_price=10)]}, 7)
		payment = Document(code="PAY-1", business_id=1, fiscal_year_id=1, currency_id=1, created_by_user_id=7, document_date=date.today(), document_type="payment")
		self.db.add(payment)
		self.db.flush()
		self.db.add(DocumentLine(document_id=payment.id, person_id=3, debit=10, credit=0))
		self.db.flush()
		linked = svc.link_prepayment(self.db, 1, order["id"], {"document_id": payment.id, "amount": 10}, 7)
		self.assertEqual(linked["prepayments"][0]["document_id"], payment.id)
		with self.assertRaises(ApiError) as over:
			svc.link_prepayment(self.db, 1, order["id"], {"document_id": payment.id, "amount": 1}, 7)
		self.assertEqual(over.exception.code, "PREPAYMENT_EXCEEDS_PAYMENT")
		other = Document(code="PAY-2", business_id=1, fiscal_year_id=1, currency_id=1, created_by_user_id=7, document_date=date.today(), document_type="payment")
		self.db.add(other)
		self.db.flush()
		self.db.add(DocumentLine(document_id=other.id, person_id=9, debit=10, credit=0))
		self.db.flush()
		with self.assertRaises(ApiError) as mismatch:
			svc.link_prepayment(self.db, 1, order["id"], {"document_id": other.id, "amount": 5}, 7)
		self.assertEqual(mismatch.exception.code, "PAYMENT_SUPPLIER_MISMATCH")
		self.db.add(Document(code="INV-1", business_id=1, fiscal_year_id=1, currency_id=1, created_by_user_id=7, document_date=date.today(), document_type="invoice_purchase"))
		self.db.flush()
		invoice = self.db.query(Document).filter(Document.code == "INV-1").one()
		with self.assertRaises(ApiError) as wrong:
			svc.link_prepayment(self.db, 1, order["id"], {"document_id": invoice.id, "amount": 5}, 7)
		self.assertEqual(wrong.exception.code, "PAYMENT_DOCUMENT_REQUIRED")

	def test_return_closes_later_steps_and_budget_can_be_resubmitted(self):
		created = svc.create_requisition(self.db, 1, {"lines": [_line(qty=1)]}, 7)
		svc.submit_requisition(self.db, 1, created["id"], {"approver_user_ids": [9, 10]}, 7)
		self.assertEqual(svc.decide(self.db, 1, "requisition", created["id"], "return", "کم شود", 9)["status"], "returned")
		with self.assertRaises(ApiError) as later:
			svc.decide(self.db, 1, "requisition", created["id"], "approve", None, 10)
		self.assertEqual(later.exception.code, "NO_PENDING_APPROVAL")
		self.assertEqual(svc.get_requisition(self.db, 1, created["id"])["status"], "returned")
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		order = svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(qty=1)]}, 7)
		svc.submit_order(self.db, 1, order["id"], {"approver_user_ids": [9, 10]}, 7)
		self.assertEqual(svc.decide(self.db, 1, "order", order["id"], "reject", "نیست", 9)["status"], "rejected")
		with self.assertRaises(ApiError) as second:
			svc.decide(self.db, 1, "order", order["id"], "approve", None, 10)
		self.assertEqual(second.exception.code, "NO_PENDING_APPROVAL")
		self.assertEqual(svc.get_order(self.db, 1, order["id"])["status"], "cancelled")
		source = svc.create_budget(self.db, 1, {"name": "اصل", "amount": 100}, 7)
		target = svc.create_budget(self.db, 1, {"name": "دیگر", "amount": 20}, 7)
		increase = svc.request_budget_increase(self.db, 1, source["id"], {"amount": 30, "reason": "اول"}, 7)
		self.assertEqual(svc.decide(self.db, 1, "budget_movement", increase["id"], "return", "مبلغ را عوض کن", 7)["status"], "returned")
		self.assertEqual(self.db.query(ProcBudgetMovement).filter(ProcBudgetMovement.id == increase["id"]).one().status, "returned")
		listed = {row["id"]: row for row in svc.list_pending_budget_movements(self.db, 1)["items"]}
		self.assertEqual(listed[increase["id"]]["status"], "returned")
		svc.resubmit_budget_movement(self.db, 1, increase["id"], {"amount": 40, "reason": "اصلاح", "approver_user_ids": [7]}, 7)
		svc.decide(self.db, 1, "budget_movement", increase["id"], "approve", None, 7)
		self.assertEqual(next(row["available"] for row in svc.list_budgets(self.db, 1)["items"] if row["id"] == source["id"]), 140)
		transfer = svc.request_budget_transfer(self.db, 1, {"from_budget_id": source["id"], "to_budget_id": target["id"], "amount": 10, "reason": "جابه‌جایی"}, 7)
		svc.decide(self.db, 1, "budget_movement", transfer["transfer_out_id"], "return", "بعداً", 7)
		self.assertEqual(self.db.query(ProcBudgetMovement).filter(ProcBudgetMovement.id == transfer["transfer_in_id"]).one().status, "returned")
		with self.assertRaises(ApiError) as too_much:
			svc.resubmit_budget_movement(self.db, 1, transfer["transfer_out_id"], {"amount": 500}, 7)
		self.assertEqual(too_much.exception.code, "BUDGET_EXCEEDED")
		self.assertEqual(self.db.query(ProcBudgetMovement).filter(ProcBudgetMovement.id == transfer["transfer_out_id"]).one().status, "returned")

	def test_pending_transfer_reserves_budget_and_invoice_edit_keeps_receipt_stock_flag(self):
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		source = svc.create_budget(self.db, 1, {"name": "مبدأ", "amount": 100}, 7)
		target = svc.create_budget(self.db, 1, {"name": "مقصد", "amount": 10}, 7)
		svc.request_budget_transfer(self.db, 1, {"from_budget_id": source["id"], "to_budget_id": target["id"], "amount": 60, "reason": "رزرو"}, 7)
		figures = {row["id"]: row for row in svc.list_budgets(self.db, 1)["items"]}
		self.assertEqual(figures[source["id"]]["available"], 40)
		self.assertEqual(figures[source["id"]]["pending_transfers"], 60)
		with self.assertRaises(ApiError) as second:
			svc.request_budget_transfer(self.db, 1, {"from_budget_id": source["id"], "to_budget_id": target["id"], "amount": 50, "reason": "اضافه"}, 7)
		self.assertEqual(second.exception.code, "BUDGET_EXCEEDED")
		order = svc.create_order(self.db, 1, {"person_id": 3, "budget_id": source["id"], "lines": [_line(qty=1, unit_price=50)]}, 7)
		svc.submit_order(self.db, 1, order["id"], {}, 7)
		with self.assertRaises(ApiError) as blocked:
			svc.decide(self.db, 1, "order", order["id"], "approve", None, 7)
		self.assertEqual(blocked.exception.code, "BUDGET_EXCEEDED")
		from app.services.invoice_service import _restore_procurement_receipt_stock_flags

		class _Line:
			def __init__(self):
				self.product_id = 5
				self.extra_info = {"unit_price": 10, "warehouse_id": 1}

		line = _Line()
		_restore_procurement_receipt_stock_flags([(line, {"extra_info": {"warehouse_id": 1}})], [{"product_id": 5, "order_line_id": 9}])
		self.assertIs(line.extra_info["inventory_posted"], False)
		self.assertTrue(line.extra_info["procurement_stocked_on_receipt"])
		self.assertEqual(line.extra_info["procurement_order_line_id"], 9)
		self.assertEqual(line.extra_info["warehouse_id"], 1)

		class _Service:
			def __init__(self):
				self.product_id = 8
				self.extra_info = {"unit_price": 4}

		service = _Service()
		_restore_procurement_receipt_stock_flags([(service, {"extra_info": {"procurement_skip_inventory": True, "procurement_order_line_id": 4}})], [{"product_id": 8, "order_line_id": 4, "skip": True}])
		self.assertIs(service.extra_info["inventory_posted"], False)
		self.assertIs(service.extra_info["procurement_skip_inventory"], True)
		self.assertNotIn("procurement_stocked_on_receipt", service.extra_info)

	def test_prepayment_stays_within_order_and_sourcing_needs_an_approved_requisition(self):
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		from adapters.db.models.document_line import DocumentLine

		DocumentLine.__table__.create(self.db.get_bind(), checkfirst=True)
		order = svc.create_order(self.db, 1, {"person_id": 3, "currency_id": 1, "lines": [_line(qty=1, unit_price=10)]}, 7)
		payment = Document(code="PAY-BIG", business_id=1, fiscal_year_id=1, currency_id=1, created_by_user_id=7, document_date=date.today(), document_type="payment")
		self.db.add(payment)
		self.db.flush()
		self.db.add(DocumentLine(document_id=payment.id, person_id=3, debit=100, credit=0))
		self.db.flush()
		with self.assertRaises(ApiError) as over_order:
			svc.link_prepayment(self.db, 1, order["id"], {"document_id": payment.id, "amount": 11}, 7)
		self.assertEqual(over_order.exception.code, "PREPAYMENT_EXCEEDS_ORDER")
		svc.link_prepayment(self.db, 1, order["id"], {"document_id": payment.id, "amount": 10}, 7)
		with self.assertRaises(ApiError) as second:
			svc.link_prepayment(self.db, 1, order["id"], {"document_id": payment.id, "amount": 1}, 7)
		self.assertEqual(second.exception.code, "PREPAYMENT_EXCEEDS_ORDER")
		draft = svc.create_requisition(self.db, 1, {"lines": [_line(qty=1)]}, 7)
		with self.assertRaises(ApiError) as unapproved:
			svc.create_sourcing(self.db, 1, {"title": "زود", "requisition_id": draft["id"], "lines": [_line(qty=1)]}, 7)
		self.assertEqual(unapproved.exception.code, "REQUISITION_NOT_APPROVED")
		svc.submit_requisition(self.db, 1, draft["id"], {}, 7)
		svc.decide(self.db, 1, "requisition", draft["id"], "approve", None, 7)
		event = svc.create_sourcing(self.db, 1, {"title": "به‌موقع", "requisition_id": draft["id"], "lines": [_line(qty=99)]}, 7)
		self.assertEqual(event["requisition_id"], draft["id"])
		self.assertEqual(event["lines"][0]["qty"], 1.0)
		with self.assertRaises(ApiError) as ordered:
			svc.create_order_from_requisition(self.db, 1, draft["id"], {"person_id": 3, "currency_id": 1}, 7)
		self.assertEqual(ordered.exception.code, "REQUISITION_IN_SOURCING")
		with self.assertRaises(ApiError) as duplicate:
			svc.create_sourcing(self.db, 1, {"title": "تکراری", "requisition_id": draft["id"], "lines": [_line(qty=1)]}, 7)
		self.assertEqual(duplicate.exception.code, "REQUISITION_IN_SOURCING")
		cancelled = svc.cancel_sourcing(self.db, 1, event["id"], 7, "تأمین‌کننده نیامد")
		self.assertEqual(cancelled["status"], "cancelled")
		self.assertEqual(svc.get_requisition(self.db, 1, draft["id"])["status"], "approved")
		with self.assertRaises(ApiError) as closed:
			svc.award_sourcing(self.db, 1, event["id"], {"invite_id": 1, "reason": "دیر", "currency_id": 1}, 7)
		self.assertEqual(closed.exception.code, "EVENT_CLOSED")
		ordered = svc.create_order_from_requisition(self.db, 1, draft["id"], {"person_id": 3, "currency_id": 1}, 7)
		self.assertEqual(ordered["requisition_id"], draft["id"])

	def test_guarantee_cannot_cross_contract_or_missing_target(self):
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		contract = svc.create_contract(self.db, 1, {"title": "ضمانت", "person_id": 3, "lines": [_line(qty=1, unit_price=10)]}, 7)
		with self.assertRaises(ApiError) as missing:
			svc.add_guarantee(self.db, 1, {"contract_id": 999, "amount": 10}, 7)
		self.assertEqual(missing.exception.code, "CONTRACT_NOT_FOUND")
		order = svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(qty=1)]}, 7)
		with self.assertRaises(ApiError) as mismatch:
			svc.add_guarantee(self.db, 1, {"contract_id": contract["id"], "order_id": order["id"], "amount": 10}, 7)
		self.assertEqual(mismatch.exception.code, "GUARANTEE_TARGET_MISMATCH")
		saved = svc.add_guarantee(self.db, 1, {"contract_id": contract["id"], "amount": 25}, 7)
		self.assertEqual(svc.get_contract(self.db, 1, contract["id"])["guarantees"][0]["id"], saved["id"])
		self.assertEqual(self.db.query(ProcGuarantee).count(), 1)

	def test_contract_release_and_expiry(self):
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		active = svc.create_contract(self.db, 1, {"title": "چارچوب", "person_id": 3, "lines": [_line(qty=5, unit_price=12)]}, 7)
		svc.activate_contract(self.db, 1, active["id"], 7)
		line_id = svc.get_contract(self.db, 1, active["id"])["lines"][0]["id"]
		order = svc.release_contract_order(self.db, 1, active["id"], {"currency_id": 1, "lines": [{"contract_line_id": line_id, "qty": 2}]}, 7)
		self.assertEqual(order["contract_id"], active["id"])
		self.assertEqual(svc.get_contract(self.db, 1, active["id"])["lines"][0]["released_qty"], 2)
		with self.assertRaises(ApiError) as bad_dates:
			svc.create_contract(self.db, 1, {"title": "تاریخ", "person_id": 3, "start_date": (date.today() + timedelta(days=2)).isoformat(), "end_date": (date.today() - timedelta(days=1)).isoformat(), "lines": [_line(qty=1)]}, 7)
		self.assertEqual(bad_dates.exception.code, "CONTRACT_DATES_INVALID")
		with self.assertRaises(ApiError) as negative_ceiling:
			svc.create_contract(self.db, 1, {"title": "منفی", "person_id": 3, "ceiling_amount": -1, "lines": [_line(qty=1)]}, 7)
		self.assertEqual(negative_ceiling.exception.code, "INVALID_AMOUNT")
		future = svc.create_contract(self.db, 1, {"title": "آینده", "person_id": 3, "start_date": (date.today() + timedelta(days=2)).isoformat(), "lines": [_line(qty=2)]}, 7)
		svc.activate_contract(self.db, 1, future["id"], 7)
		future_line = future["lines"][0]["id"]
		with self.assertRaises(ApiError) as not_started:
			svc.release_contract_order(self.db, 1, future["id"], {"lines": [{"contract_line_id": future_line, "qty": 1}]}, 7)
		self.assertEqual(not_started.exception.code, "CONTRACT_NOT_STARTED")
		self.assertEqual(svc.get_contract(self.db, 1, future["id"])["lines"][0]["released_qty"], 0)
		expired = svc.create_contract(self.db, 1, {"title": "گذشته", "person_id": 3, "end_date": (date.today() - timedelta(days=1)).isoformat(), "lines": [_line(qty=1)]}, 7)
		with self.assertRaises(ApiError) as blocked:
			svc.activate_contract(self.db, 1, expired["id"], 7)
		self.assertEqual(blocked.exception.code, "CONTRACT_EXPIRED")
		self.assertEqual(svc.get_contract(self.db, 1, expired["id"])["status"], "draft")
		ended = self.db.query(ProcContract).filter(ProcContract.id == active["id"]).one()
		ended.end_date = date.today() - timedelta(days=1)
		self.db.flush()
		with self.assertRaises(ApiError) as ended_release:
			svc.release_contract_order(self.db, 1, active["id"], {"lines": [{"contract_line_id": line_id, "qty": 1}]}, 7)
		self.assertEqual(ended_release.exception.code, "CONTRACT_EXPIRED")
		self.assertEqual(svc.get_contract(self.db, 1, active["id"])["status"], "expired")
		self.assertEqual(svc.get_contract(self.db, 1, active["id"])["lines"][0]["released_qty"], 2)
		capped = svc.create_contract(self.db, 1, {"title": "سقف", "person_id": 3, "ceiling_amount": 30, "lines": [_line(qty=5, unit_price=12)]}, 7)
		svc.activate_contract(self.db, 1, capped["id"], 7)
		capped_line = svc.get_contract(self.db, 1, capped["id"])["lines"][0]["id"]
		svc.release_contract_order(self.db, 1, capped["id"], {"currency_id": 1, "lines": [{"contract_line_id": capped_line, "qty": 2}]}, 7)
		self.assertEqual(svc.get_contract(self.db, 1, capped["id"])["released_amount"], 24.0)
		with self.assertRaises(ApiError) as ceiling:
			svc.release_contract_order(self.db, 1, capped["id"], {"lines": [{"contract_line_id": capped_line, "qty": 1}]}, 7)
		self.assertEqual(ceiling.exception.code, "CONTRACT_CEILING_EXCEEDED")
		self.assertEqual(svc.get_contract(self.db, 1, capped["id"])["lines"][0]["released_qty"], 2)
		blanket = svc.create_contract(self.db, 1, {"title": "برگشت سقف", "person_id": 3, "ceiling_amount": 100, "lines": [_line(qty=5, unit_price=10)]}, 7)
		svc.activate_contract(self.db, 1, blanket["id"], 7)
		blanket_line = svc.get_contract(self.db, 1, blanket["id"])["lines"][0]["id"]
		draft = svc.release_contract_order(self.db, 1, blanket["id"], {"currency_id": 1, "lines": [{"contract_line_id": blanket_line, "qty": 2}]}, 7)
		svc.cancel_order(self.db, 1, draft["id"], 7)
		self.assertEqual(svc.get_contract(self.db, 1, blanket["id"])["released_amount"], 0)
		kept = svc.release_contract_order(self.db, 1, blanket["id"], {"currency_id": 1, "lines": [{"contract_line_id": blanket_line, "qty": 4}]}, 7)
		svc.submit_order(self.db, 1, kept["id"], {}, 7)
		svc.decide(self.db, 1, "order", kept["id"], "approve", None, 7)
		svc.receive_order(self.db, 1, kept["id"], {"lines": [{"order_line_id": kept["lines"][0]["id"], "qty": 3, "rejected_qty": 1}]}, 7)
		self.assertEqual(svc.get_contract(self.db, 1, blanket["id"])["lines"][0]["released_qty"], 3)
		svc.return_to_supplier(self.db, 1, kept["id"], {"lines": [{"order_line_id": kept["lines"][0]["id"], "qty": 1}]}, 7)
		self.assertEqual(svc.get_contract(self.db, 1, blanket["id"])["lines"][0]["released_qty"], 2)
		self.assertEqual(svc.get_contract(self.db, 1, blanket["id"])["released_amount"], 20.0)
		with self.assertRaises(ApiError) as bad_percent:
			svc.create_contract(self.db, 1, {"title": "درصد", "person_id": 3, "lines": [_line(qty=1, unit_price=100, discount_percent=150)]}, 7)
		self.assertEqual(bad_percent.exception.code, "DISCOUNT_EXCEEDS_LINE")
		discounted = svc.create_contract(self.db, 1, {"title": "تخفیف", "person_id": 3, "payment_terms": "۳۰ روز", "ceiling_amount": 190, "lines": [_line(qty=5, unit_price=100, discount_percent=10)]}, 7)
		svc.activate_contract(self.db, 1, discounted["id"], 7)
		discounted_line = svc.get_contract(self.db, 1, discounted["id"])["lines"][0]["id"]
		released = svc.release_contract_order(self.db, 1, discounted["id"], {"currency_id": 1, "lines": [{"contract_line_id": discounted_line, "qty": 2}]}, 7)
		self.assertEqual(released["lines"][0]["discount"], 20)
		self.assertEqual(released["total"], 180)
		self.assertEqual(released["payment_terms"], "۳۰ روز")
		self.assertEqual(svc.get_contract(self.db, 1, discounted["id"])["released_amount"], 180)
		with self.assertRaises(ApiError) as discounted_ceiling:
			svc.release_contract_order(self.db, 1, discounted["id"], {"lines": [{"contract_line_id": discounted_line, "qty": 1}]}, 7)
		self.assertEqual(discounted_ceiling.exception.code, "CONTRACT_CEILING_EXCEEDED")
		self.assertEqual(svc.get_contract(self.db, 1, discounted["id"])["lines"][0]["released_qty"], 2)
		self.db.add(Product(id=8, business_id=1, code="P-8", name="نصب", item_type=ProductItemType.SERVICE, track_inventory=True))
		self.db.flush()
		service_contract = svc.create_contract(self.db, 1, {"title": "خدمت", "person_id": 3, "lines": [_line(qty=2, unit_price=10, product_id=8)]}, 7)
		self.assertEqual(svc.get_contract(self.db, 1, service_contract["id"])["lines"][0]["item_kind"], "service")
		svc.activate_contract(self.db, 1, service_contract["id"], 7)
		service_line = service_contract["lines"][0]["id"]
		service_order = svc.release_contract_order(self.db, 1, service_contract["id"], {"currency_id": 1, "lines": [{"contract_line_id": service_line, "qty": 2}]}, 7)
		self.assertEqual(service_order["lines"][0]["item_kind"], "service")
		svc.submit_order(self.db, 1, service_order["id"], {}, 7)
		svc.decide(self.db, 1, "order", service_order["id"], "approve", None, 7)
		received = svc.receive_order(self.db, 1, service_order["id"], {"lines": [{"order_line_id": service_order["lines"][0]["id"], "qty": 2}]}, 7)
		self.assertEqual(received["lines"][0]["accepted_qty"], 2)
		self.assertIsNone(received["receipts"][0]["warehouse_document_id"])
		stocked = svc.create_contract(self.db, 1, {"title": "انبار", "person_id": 3, "lines": [_line(qty=3, unit_price=10, product_id=5, warehouse_id=2)]}, 7)
		self.assertEqual(stocked["lines"][0]["warehouse_id"], 2)
		svc.activate_contract(self.db, 1, stocked["id"], 7)
		stocked_line = stocked["lines"][0]["id"]
		kept_warehouse = svc.release_contract_order(self.db, 1, stocked["id"], {"currency_id": 1, "lines": [{"contract_line_id": stocked_line, "qty": 1}]}, 7)
		self.assertEqual(kept_warehouse["lines"][0]["warehouse_id"], 2)
		overridden = svc.release_contract_order(self.db, 1, stocked["id"], {"lines": [{"contract_line_id": stocked_line, "qty": 1, "warehouse_id": 3}]}, 7)
		self.assertEqual(overridden["lines"][0]["warehouse_id"], 3)

	def test_comparison_uses_technical_score_then_supplier_history(self):
		svc.update_settings(self.db, 1, {"mode": "small", "weights": {"price": 20, "quality": 80, "delivery": 0, "payment": 0, "risk": 0}}, 7)
		event = svc.create_sourcing(self.db, 1, {"title": "مقایسه کیفیت", "lines": [_line(qty=1)]}, 7)
		invited = svc.invite_suppliers(self.db, 1, event["id"], [3, 4], 7)
		for invite, price in zip(invited["invites"], (100, 200)):
			svc.submit_bid(self.db, 1, invite["id"], {"delivery_days": 5, "payment_days": 30, "lines": [{"sourcing_line_id": event["lines"][0]["id"], "unit_price": price}]}, 7)
		cheap = invited["invites"][0]["id"]
		costly = invited["invites"][1]["id"]
		self.assertEqual(svc.compare_sourcing(self.db, 1, event["id"])["ranking"][0]["invite_id"], cheap)
		from datetime import datetime
		stored = self.db.query(ProcSourcingEvent).filter(ProcSourcingEvent.id == event["id"]).one()
		stored.deadline_at = datetime(2026, 11, 15)
		self.db.add(ProcScore(business_id=1, person_id=3, period_key="2026-11", metrics={"quality": 10}, weights={}, total=10, grade="D"))
		self.db.add(ProcScore(business_id=1, person_id=4, period_key="2026-11", metrics={"quality": 100}, weights={}, total=100, grade="A"))
		self.db.add(ProcScore(business_id=1, person_id=3, period_key="2026-12", metrics={"quality": 100}, weights={}, total=100, grade="A"))
		self.db.add(ProcScore(business_id=1, person_id=4, period_key="2026-12", metrics={"quality": 10}, weights={}, total=10, grade="D"))
		self.db.flush()
		history = svc.compare_sourcing(self.db, 1, event["id"])
		self.assertEqual(history["quality_period"], "2026-11")
		self.assertEqual(history["ranking"][0]["invite_id"], costly)
		self.assertIn("quality", history["ranking"][0]["parts"])
		stored.deadline_at = datetime(2026, 12, 15)
		self.db.flush()
		december = svc.compare_sourcing(self.db, 1, event["id"])
		self.assertEqual(december["quality_period"], "2026-12")
		self.assertEqual(december["ranking"][0]["invite_id"], cheap)
		stored.deadline_at = datetime(2026, 9, 1)
		self.db.flush()
		blank = svc.compare_sourcing(self.db, 1, event["id"])
		self.assertEqual(blank["quality_period"], "2026-09")
		self.assertNotIn("quality", blank["ranking"][0]["parts"])
		self.assertEqual(blank["ranking"][0]["invite_id"], cheap)
		svc.score_technical(self.db, 1, event["id"], {"scores": [{"invite_id": cheap, "technical_score": 100}, {"invite_id": costly, "technical_score": 10}]}, 7)
		self.assertEqual(svc.compare_sourcing(self.db, 1, event["id"])["ranking"][0]["invite_id"], cheap)

	def test_sourcing_lines_stay_with_the_requisition_and_lock_after_a_bid(self):
		event = svc.create_sourcing(self.db, 1, {"title": "چند قلم", "lines": [_line(qty=1, description="نخست")]}, 7)
		added = svc.add_sourcing_lines(self.db, 1, event["id"], {"lines": [_line(qty=2, description="دوم", product_id=5, warehouse_id=2)]}, 7)
		self.assertEqual([line["description"] for line in added["lines"]], ["نخست", "دوم"])
		self.assertEqual(added["lines"][1]["product_id"], 5)
		self.assertEqual(added["lines"][1]["warehouse_id"], 2)
		invited = svc.invite_suppliers(self.db, 1, event["id"], [3], 7)
		svc.submit_bid(
			self.db,
			1,
			invited["invites"][0]["id"],
			{"lines": [{"sourcing_line_id": line["id"], "unit_price": 10} for line in added["lines"]]},
			7,
		)
		with self.assertRaises(ApiError) as locked:
			svc.add_sourcing_lines(self.db, 1, event["id"], {"lines": [_line(qty=1, description="سوم")]}, 7)
		self.assertEqual(locked.exception.code, "BIDS_LOCKED")
		center = svc.create_cost_center(self.db, 1, {"code": "AW", "name": "جایزه"}, 7)
		need = svc.create_requisition(self.db, 1, {"currency_id": 1, "cost_center_id": center["id"], "needed_by": "2026-12-01", "lines": [_line(qty=1, product_id=5, warehouse_id=2)]}, 7)
		svc.submit_requisition(self.db, 1, need["id"], {"approver_user_ids": [7]}, 7)
		svc.decide(self.db, 1, "requisition", need["id"], "approve", None, 7)
		linked = svc.create_sourcing(self.db, 1, {"title": "از درخواست", "requisition_id": need["id"], "lines": [_line(qty=99)]}, 7)
		with self.assertRaises(ApiError) as requisition_locked:
			svc.add_sourcing_lines(self.db, 1, linked["id"], {"lines": [_line(qty=1)]}, 7)
		self.assertEqual(requisition_locked.exception.code, "REQUISITION_LINES_LOCKED")
		self.assertEqual(len(svc.get_sourcing(self.db, 1, linked["id"])["lines"]), 1)
		self.assertEqual(linked["lines"][0]["warehouse_id"], 2)
		self.assertEqual(linked["lines"][0]["requisition_line_id"], need["lines"][0]["id"])
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		linked_invites = svc.invite_suppliers(self.db, 1, linked["id"], [3], 7)
		svc.submit_bid(self.db, 1, linked_invites["invites"][0]["id"], {"lines": [{"sourcing_line_id": linked["lines"][0]["id"], "unit_price": 40}]}, 7)
		awarded = svc.award_sourcing(self.db, 1, linked["id"], {"invite_id": linked_invites["invites"][0]["id"], "reason": "انبار درخواست"}, 7)
		self.assertEqual(awarded["order"]["lines"][0]["warehouse_id"], 2)
		self.assertEqual(awarded["order"]["lines"][0]["product_id"], 5)
		self.assertEqual(awarded["order"]["currency_id"], 1)
		self.assertEqual(awarded["order"]["cost_center_id"], center["id"])
		self.assertEqual(awarded["order"]["delivery_date"], "2026-12-01")
		self.assertEqual(awarded["order"]["lines"][0]["requisition_line_id"], need["lines"][0]["id"])
		kept = awarded["order"]["lines"][0]
		edited = svc.update_order(
			self.db,
			1,
			awarded["order"]["id"],
			{"lines": [{"description": kept["description"], "qty": 1, "unit_price": kept["unit_price"], "product_id": kept["product_id"], "warehouse_id": kept["warehouse_id"], "item_kind": kept["item_kind"], "requisition_line_id": kept["requisition_line_id"]}]},
			7,
		)
		self.assertEqual(edited["lines"][0]["requisition_line_id"], need["lines"][0]["id"])
		other = svc.create_requisition(self.db, 1, {"lines": [_line(qty=1)]}, 7)
		with self.assertRaises(ApiError) as mismatch:
			svc.update_order(
				self.db,
				1,
				awarded["order"]["id"],
				{"lines": [{"description": kept["description"], "qty": 1, "unit_price": kept["unit_price"], "requisition_line_id": other["lines"][0]["id"]}]},
				7,
			)
		self.assertEqual(mismatch.exception.code, "REQUISITION_LINE_MISMATCH")

	def test_technical_score_waits_for_opening(self):
		from datetime import datetime

		early = svc.create_sourcing(
			self.db,
			1,
			{"event_type": "tender", "title": "زود", "deadline_at": (datetime.utcnow() + timedelta(days=1)).isoformat(), "lines": [_line(qty=1)]},
			7,
		)
		with self.assertRaises(ApiError) as before_deadline:
			svc.open_technical(self.db, 1, early["id"], 7)
		self.assertEqual(before_deadline.exception.code, "ENVELOPE_BEFORE_DEADLINE")
		event = svc.create_sourcing(self.db, 1, {"event_type": "tender", "title": "فنی", "lines": [_line(qty=1)]}, 7)
		invited = svc.invite_suppliers(self.db, 1, event["id"], [3], 7)
		svc.submit_bid(self.db, 1, invited["invites"][0]["id"], {"lines": [{"sourcing_line_id": event["lines"][0]["id"], "unit_price": 10}]}, 7)
		with self.assertRaises(ApiError) as sealed:
			svc.score_technical(self.db, 1, event["id"], {"scores": [{"invite_id": invited["invites"][0]["id"], "technical_score": 80}]}, 7)
		self.assertEqual(sealed.exception.code, "TECHNICAL_SEALED")
		svc.open_technical(self.db, 1, event["id"], 7)
		with self.assertRaises(ApiError) as too_high:
			svc.score_technical(self.db, 1, event["id"], {"scores": [{"invite_id": invited["invites"][0]["id"], "technical_score": 120}]}, 7)
		self.assertEqual(too_high.exception.code, "TECHNICAL_SCORE_INVALID")
		opened = svc.score_technical(self.db, 1, event["id"], {"scores": [{"invite_id": invited["invites"][0]["id"], "technical_score": 80}]}, 7)
		self.assertEqual(opened["invites"][0]["bid"]["technical_score"], 80)

	def test_two_step_approval_and_position_holder(self):
		from adapters.db.models.office_automation import OaPositionHolder

		OaPositionHolder.__table__.create(self.db.get_bind(), checkfirst=True)
		_store_file(self.db, "file-1")
		created = svc.create_requisition(self.db, 1, {"file_ids": ["file-1"], "org_unit_name": "خرید", "lines": [_line(qty=1)]}, 7)
		self.assertEqual(created["file_ids"], ["file-1"])
		self.assertEqual(created["org_unit_name"], "خرید")
		svc.submit_requisition(self.db, 1, created["id"], {"approver_user_ids": [9, 10]}, 7)
		with self.assertRaises(ApiError) as early:
			svc.decide(self.db, 1, "requisition", created["id"], "approve", None, 10)
		self.assertEqual(early.exception.code, "NOT_THE_APPROVER")
		self.assertEqual(svc.decide(self.db, 1, "requisition", created["id"], "approve", None, 9)["status"], "pending_approval")
		self.assertEqual(svc.decide(self.db, 1, "requisition", created["id"], "approve", None, 10)["status"], "approved")
		positioned = svc.create_requisition(self.db, 1, {"lines": [_line(qty=1)]}, 7)
		svc.submit_requisition(self.db, 1, positioned["id"], {"position_id": 4}, 7)
		self.db.add(OaPositionHolder(business_id=1, position_id=4, user_id=11, is_active=True))
		self.db.flush()
		from datetime import datetime

		from adapters.db.models.office_automation import OaDelegation

		OaDelegation.__table__.create(self.db.get_bind(), checkfirst=True)
		with self.assertRaises(ApiError):
			svc.decide(self.db, 1, "requisition", positioned["id"], "approve", None, 12)
		self.assertEqual(svc.decide(self.db, 1, "requisition", positioned["id"], "approve", None, 11)["status"], "approved")
		future = svc.create_requisition(self.db, 1, {"lines": [_line(qty=1)]}, 7)
		svc.submit_requisition(self.db, 1, future["id"], {"position_id": 8}, 7)
		self.db.add(OaPositionHolder(business_id=1, position_id=8, user_id=15, is_active=True, starts_at=datetime.utcnow() + timedelta(days=2)))
		self.db.add(OaDelegation(business_id=1, position_id=8, delegate_user_id=13, created_by_user_id=7, scope="view", is_active=True))
		self.db.add(OaDelegation(business_id=1, position_id=8, delegate_user_id=14, created_by_user_id=7, scope="full", is_active=True))
		self.db.flush()
		with self.assertRaises(ApiError):
			svc.decide(self.db, 1, "requisition", future["id"], "approve", None, 15)
		with self.assertRaises(ApiError):
			svc.decide(self.db, 1, "requisition", future["id"], "approve", None, 13)
		self.assertEqual(svc.decide(self.db, 1, "requisition", future["id"], "approve", None, 14)["status"], "approved")

	def test_receipt_posts_purchase_order_warehouse_document(self):
		from adapters.db.models.warehouse_document import WarehouseDocument
		from adapters.db.models.warehouse_document_line import WarehouseDocumentLine

		from adapters.db.models.fiscal_year import FiscalYear

		WarehouseDocument.__table__.create(self.db.get_bind(), checkfirst=True)
		WarehouseDocumentLine.__table__.create(self.db.get_bind(), checkfirst=True)
		FiscalYear.__table__.create(self.db.get_bind(), checkfirst=True)
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		order = svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(product_id=5, qty=4, unit_price=100, discount=20, warehouse_id=2)]}, 7)
		svc.submit_order(self.db, 1, order["id"], {}, 7)
		svc.decide(self.db, 1, "order", order["id"], "approve", None, 7)
		nested = self.db.begin_nested()
		with self.assertRaises(ApiError) as missing_year:
			svc.receive_order(self.db, 1, order["id"], {"lines": [{"order_line_id": order["lines"][0]["id"], "qty": 4, "warehouse_id": 2}]}, 7)
		self.assertEqual(missing_year.exception.code, "NO_FISCAL_YEAR")
		nested.rollback()
		year = FiscalYear(business_id=1, title="1405", start_date=date(2026, 3, 21), end_date=date(2027, 3, 20), is_last=True)
		self.db.add(year)
		self.db.flush()

		def fake_post(db, document_id):
			row = db.query(WarehouseDocument).filter(WarehouseDocument.id == int(document_id)).one()
			row.status = "posted"

		with patch("app.services.warehouse_service.post_warehouse_document", fake_post):
			received = svc.receive_order(self.db, 1, order["id"], {"lines": [{"order_line_id": order["lines"][0]["id"], "qty": 4, "warehouse_id": 2}]}, 7)
		document = self.db.query(WarehouseDocument).one()
		self.assertEqual(document.fiscal_year_id, year.id)
		self.assertEqual(document.source_type, "purchase_order")
		self.assertEqual(document.doc_type, "receipt")
		self.assertEqual(document.status, "posted")
		self.assertIsNone(document.source_document_id)
		self.assertEqual(document.extra_info["procurement_order_id"], order["id"])
		self.db.add(Document(id=order["id"], code="PINV-COLLIDE", business_id=1, fiscal_year_id=1, currency_id=1, created_by_user_id=7, document_date=date.today(), document_type="invoice_purchase"))
		self.db.flush()
		from app.services.warehouse_service import _warehouse_document_source_is_invoice
		self.assertFalse(_warehouse_document_source_is_invoice(self.db, 1, document))
		line = self.db.query(WarehouseDocumentLine).one()
		self.assertEqual(line.movement, "in")
		self.assertEqual(float(line.quantity), 4)
		self.assertEqual(line.extra_info["unit_price"], 95.0)
		self.assertEqual(received["receipts"][0]["warehouse_document_id"], document.id)
		self.assertEqual(received["receipts"][0]["warehouse_document_ids"], [document.id])

	def test_receipt_splits_warehouse_documents_and_clears_each_grni(self):
		from adapters.db.models.fiscal_year import FiscalYear
		from adapters.db.models.warehouse_document import WarehouseDocument
		from adapters.db.models.warehouse_document_line import WarehouseDocumentLine

		WarehouseDocument.__table__.create(self.db.get_bind(), checkfirst=True)
		WarehouseDocumentLine.__table__.create(self.db.get_bind(), checkfirst=True)
		FiscalYear.__table__.create(self.db.get_bind(), checkfirst=True)
		self.db.add(FiscalYear(business_id=1, title="1405", start_date=date(2026, 3, 21), end_date=date(2027, 3, 20), is_last=True))
		self.db.flush()
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		order = svc.create_order(
			self.db,
			1,
			{"person_id": 3, "currency_id": 1, "lines": [_line(product_id=5, qty=2, warehouse_id=2), _line(product_id=6, qty=1, warehouse_id=3, description="دوم")]},
			7,
		)
		svc.submit_order(self.db, 1, order["id"], {}, 7)
		svc.decide(self.db, 1, "order", order["id"], "approve", None, 7)

		def fake_post(db, document_id):
			row = db.query(WarehouseDocument).filter(WarehouseDocument.id == int(document_id)).one()
			row.status = "posted"

		with patch("app.services.warehouse_service.post_warehouse_document", fake_post):
			received = svc.receive_order(
				self.db,
				1,
				order["id"],
				{"lines": [
					{"order_line_id": order["lines"][0]["id"], "qty": 2, "warehouse_id": 2},
					{"order_line_id": order["lines"][1]["id"], "qty": 1, "warehouse_id": 3},
				]},
				7,
			)
		documents = self.db.query(WarehouseDocument).order_by(WarehouseDocument.id).all()
		self.assertEqual(sorted(row.warehouse_id_to for row in documents), [2, 3])
		self.assertEqual(len(received["receipts"][0]["warehouse_document_ids"]), 2)
		cleared = []
		with patch("app.services.purchase_accounting_service.post_grni_clearance_for_receipt_invoice", side_effect=lambda *args, **kwargs: cleared.append(kwargs["warehouse_document_id"]) or True):
			svc._clear_grni(self.db, order["id"], 90)
		self.assertEqual(sorted(cleared), sorted(received["receipts"][0]["warehouse_document_ids"]))

	def test_invoice_stock_flag_and_supplier_score_use_real_receipts(self):
		from adapters.db.models.invoice_item_line import InvoiceItemLine

		InvoiceItemLine.__table__.create(self.db.get_bind(), checkfirst=True)
		self.db.add(InvoiceItemLine(document_id=1, product_id=5, quantity=1, extra_info={"procurement_stocked_on_receipt": True}))
		self.db.add(InvoiceItemLine(document_id=1, product_id=6, quantity=1, extra_info={"unit_price": 10}))
		self.db.flush()
		svc._mark_receipt_stock_not_on_invoice(self.db, 1)
		rows = self.db.query(InvoiceItemLine).order_by(InvoiceItemLine.id).all()
		self.assertFalse(rows[0].extra_info["inventory_posted"])
		self.assertNotIn("inventory_posted", rows[1].extra_info)
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		order = svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(qty=10)]}, 7)
		svc.submit_order(self.db, 1, order["id"], {}, 7)
		svc.decide(self.db, 1, "order", order["id"], "approve", None, 7)
		svc.receive_order(self.db, 1, order["id"], {"received_on": "2026-11-15", "lines": [{"order_line_id": order["lines"][0]["id"], "qty": 8, "rejected_qty": 2}]}, 7)
		scored = svc.recompute_score(self.db, 1, 3, "2026-11", 7)
		self.assertEqual(scored["metrics"]["quality"], 80.0)
		self.assertEqual(scored["total"], 90.0)
		self.assertEqual(scored["grade"], "A")
		with self.assertRaises(ApiError) as bad_period:
			svc.recompute_score(self.db, 1, 3, "2026-13", 7)
		self.assertEqual(bad_period.exception.code, "INVALID_PERIOD")
		older = svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(qty=1)]}, 7)
		svc.submit_order(self.db, 1, older["id"], {}, 7)
		svc.decide(self.db, 1, "order", older["id"], "approve", None, 7)
		svc.receive_order(self.db, 1, older["id"], {"received_on": "2026-10-02", "lines": [{"order_line_id": older["lines"][0]["id"], "qty": 0, "rejected_qty": 1}]}, 7)
		october = svc.recompute_score(self.db, 1, 3, "2026-10", 7)
		self.assertEqual(october["metrics"]["quality"], 0.0)
		self.assertEqual(october["grade"], "C")
		again = svc.recompute_score(self.db, 1, 3, "2026-11", 7)
		self.assertEqual(again["metrics"]["quality"], 80.0)
		self.assertEqual(again["total"], 90.0)

	def test_reorder_exposes_lead_time_and_internal_source_price(self):
		from adapters.db.models.product_supplier import ProductSupplier

		ProductSupplier.__table__.create(self.db.get_bind(), checkfirst=True)
		product = Product(business_id=1, code="P-2", name="مهره", item_type=ProductItemType.PRODUCT, track_inventory=True, reorder_point=5, min_order_qty=2, lead_time_days=12)
		self.db.add(product)
		self.db.flush()
		refreshed = svc.refresh_reorder(self.db, 1, 7)
		self.assertEqual(refreshed["items"][0]["lead_time_days"], 12)
		self.assertEqual(refreshed["items"][0]["reorder_scope"], "product")
		self.assertEqual(refreshed["items"][0]["name"], "مهره")
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(product_id=product.id, qty=1, unit_price=42)]}, 7)
		self.db.add(ProductSupplier(business_id=1, product_id=product.id, person_id=3, name="آکام", is_preferred=True))
		self.db.flush()
		sources = svc.product_sources(self.db, 1, product.id)
		self.assertTrue(sources["items"][0]["is_preferred"])
		self.assertEqual(sources["items"][0]["last_price"], 42.0)
		listed = svc.list_reorder(self.db, 1)
		self.assertEqual(listed["items"][0]["source_person_id"], 3)
		self.assertEqual(listed["items"][0]["source_name"], "آکام")
		self.assertTrue(listed["items"][0]["source_is_preferred"])
		self.assertEqual(listed["items"][0]["last_price"], 42.0)
		converted = svc.convert_reorder(self.db, 1, listed["items"][0]["id"], 7)
		self.assertEqual(converted["status"], "draft")
		self.assertEqual(converted["lines"][0]["unit_price_estimate"], 42.0)
		self.assertIn("آکام", converted["reason"])
		self.assertEqual(self.db.query(ProcOrder).count(), 1)
		from adapters.db.models.project import Project

		Project.__table__.create(self.db.get_bind(), checkfirst=True)
		self.db.add(Project(id=6, business_id=1, code="PR", name="پروژه خرید", created_by_user_id=7))
		self.db.flush()
		center = svc.create_cost_center(self.db, 1, {"code": "CC", "name": "بازرگانی"}, 7)
		budget = svc.create_budget(self.db, 1, {"name": "واحد", "amount": 10, "period_key": "2026-11", "org_unit_name": "خرید", "project_id": 6, "cost_center_id": center["id"]}, 7)
		self.assertEqual(budget["org_unit_name"], "خرید")
		self.assertEqual(budget["project_id"], 6)
		self.assertEqual(budget["cost_center_id"], center["id"])

	def test_reject_and_return_release_commitment_and_allow_close(self):
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		budget = svc.create_budget(self.db, 1, {"name": "رد", "amount": 1000, "period_key": "2026-11"}, 7)
		rejected = svc.create_order(
			self.db,
			1,
			{"person_id": 3, "currency_id": 1, "budget_id": budget["id"], "freight": 50, "lines": [_line(item_kind="service", qty=4, unit_price=100)]},
			7,
		)
		svc.submit_order(self.db, 1, rejected["id"], {}, 7)
		svc.decide(self.db, 1, "order", rejected["id"], "approve", None, 7)
		svc.receive_order(self.db, 1, rejected["id"], {"lines": [{"order_line_id": rejected["lines"][0]["id"], "qty": 4, "qc_status": "reject"}]}, 7)
		self.assertEqual(svc.list_budgets(self.db, 1)["items"][0]["open_commitments"], 0)
		self.assertEqual(svc.close_order(self.db, 1, rejected["id"], 7)["status"], "closed")
		kept = svc.create_order(
			self.db,
			1,
			{"person_id": 3, "currency_id": 1, "budget_id": budget["id"], "lines": [_line(product_id=5, item_kind="service", qty=4, unit_price=100)]},
			7,
		)
		svc.submit_order(self.db, 1, kept["id"], {}, 7)
		svc.decide(self.db, 1, "order", kept["id"], "approve", None, 7)
		line_id = kept["lines"][0]["id"]
		from adapters.db.models.fiscal_year import FiscalYear
		from adapters.db.models.warehouse_document import WarehouseDocument
		from adapters.db.models.warehouse_document_line import WarehouseDocumentLine

		WarehouseDocument.__table__.create(self.db.get_bind(), checkfirst=True)
		WarehouseDocumentLine.__table__.create(self.db.get_bind(), checkfirst=True)
		FiscalYear.__table__.create(self.db.get_bind(), checkfirst=True)
		self.db.add(FiscalYear(business_id=1, title="1405", start_date=date(2026, 3, 21), end_date=date(2027, 3, 20), is_last=True))
		self.db.flush()
		svc.receive_order(self.db, 1, kept["id"], {"lines": [{"order_line_id": line_id, "qty": 4}]}, 7)
		with patch("app.services.warehouse_service.post_warehouse_document", lambda db, document_id: None):
			svc.return_to_supplier(self.db, 1, kept["id"], {"lines": [{"order_line_id": line_id, "qty": 1, "warehouse_id": 2}]}, 7)
		self.assertEqual(svc.list_budgets(self.db, 1)["items"][0]["open_commitments"], 300)
		with self.assertRaises(ApiError) as open_invoice:
			svc.close_order(self.db, 1, kept["id"], 7)
		self.assertEqual(open_invoice.exception.code, "ORDER_NOT_CLOSABLE")
		with patch("app.services.invoice_service.create_invoice", lambda *args, **kwargs: {"data": {"id": 78}}), patch.object(svc, "_mark_receipt_stock_not_on_invoice", lambda *args, **kwargs: None), patch.object(svc, "_clear_grni", lambda *args, **kwargs: None):
			svc.create_invoice_for_order(self.db, 1, kept["id"], {"lines": [{"order_line_id": line_id, "qty": 3, "unit_price": 100}]}, 7)
		self.assertEqual(svc.close_order(self.db, 1, kept["id"], 7)["status"], "closed")
		figures = svc.list_budgets(self.db, 1)["items"][0]
		self.assertEqual(figures["open_commitments"], 0)
		self.assertEqual(figures["actuals"], 300)
		self.assertEqual(figures["available"], 700)

	def test_close_releases_unbilled_freight_commitment(self):
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		budget = svc.create_budget(self.db, 1, {"name": "بستن", "amount": 500, "period_key": "2026-11"}, 7)
		order = svc.create_order(
			self.db,
			1,
			{"person_id": 3, "currency_id": 1, "budget_id": budget["id"], "freight": 50, "lines": [_line(product_id=5, item_kind="service", qty=4, unit_price=100)]},
			7,
		)
		svc.submit_order(self.db, 1, order["id"], {}, 7)
		svc.decide(self.db, 1, "order", order["id"], "approve", None, 7)
		line_id = order["lines"][0]["id"]
		svc.receive_order(self.db, 1, order["id"], {"lines": [{"order_line_id": line_id, "qty": 4}]}, 7)
		with patch("app.services.invoice_service.create_invoice", lambda *args, **kwargs: {"data": {"id": 77}}), patch.object(svc, "_mark_receipt_stock_not_on_invoice", lambda *args, **kwargs: None), patch.object(svc, "_clear_grni", lambda *args, **kwargs: None):
			svc.create_invoice_for_order(self.db, 1, order["id"], {"lines": [{"order_line_id": line_id, "qty": 4, "unit_price": 100}]}, 7)
		self.assertEqual(svc.list_budgets(self.db, 1)["items"][0]["open_commitments"], 50)
		closed = svc.close_order(self.db, 1, order["id"], 7)
		self.assertEqual(closed["status"], "closed")
		figures = svc.list_budgets(self.db, 1)["items"][0]
		self.assertEqual(figures["open_commitments"], 0)
		self.assertEqual(figures["actuals"], 400)
		self.assertEqual(figures["available"], 100)

	def test_cancel_releases_commitment_including_freight(self):
		from adapters.db.models.activity_log import ActivityLog as Log

		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		budget = svc.create_budget(self.db, 1, {"name": "لغو", "amount": 500, "period_key": "2026-11"}, 7)
		order = svc.create_order(self.db, 1, {"person_id": 3, "budget_id": budget["id"], "freight": 50, "lines": [_line(qty=4, unit_price=100)]}, 7)
		svc.submit_order(self.db, 1, order["id"], {}, 7)
		svc.decide(self.db, 1, "order", order["id"], "approve", None, 7)
		self.assertEqual(svc.list_budgets(self.db, 1)["items"][0]["open_commitments"], 450)
		cancelled = svc.cancel_order(self.db, 1, order["id"], 7)
		self.assertEqual(cancelled["status"], "cancelled")
		self.assertEqual(cancelled["lines"][0]["cancelled_qty"], 4)
		self.assertEqual(svc.list_budgets(self.db, 1)["items"][0]["available"], 500)
		self.assertTrue(self.db.query(Log).filter(Log.action == "approve", Log.entity_type == "proc_order").count() >= 1)

	def test_return_cannot_take_invoiced_quantity(self):
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		order = svc.create_order(self.db, 1, {"person_id": 3, "currency_id": 1, "lines": [_line(product_id=5, item_kind="service", qty=4, unit_price=10)]}, 7)
		with self.assertRaises(ApiError) as too_soon:
			svc.return_to_supplier(self.db, 1, order["id"], {"lines": [{"order_line_id": order["lines"][0]["id"], "qty": 1}]}, 7)
		self.assertEqual(too_soon.exception.code, "ORDER_NOT_RETURNABLE")
		svc.submit_order(self.db, 1, order["id"], {}, 7)
		svc.decide(self.db, 1, "order", order["id"], "approve", None, 7)
		svc.receive_order(self.db, 1, order["id"], {"lines": [{"order_line_id": order["lines"][0]["id"], "qty": 4}]}, 7)
		captured = {}

		def fake_invoice(*args, **kwargs):
			captured["extra"] = args[3]["lines"][0]["extra_info"]
			return {"data": {"id": 91}}

		with patch("app.services.invoice_service.create_invoice", fake_invoice), patch.object(svc, "_mark_receipt_stock_not_on_invoice", lambda *args, **kwargs: None), patch.object(svc, "_clear_grni", lambda *args, **kwargs: None):
			svc.create_invoice_for_order(self.db, 1, order["id"], {"lines": [{"order_line_id": order["lines"][0]["id"], "qty": 3}]}, 7)
		self.assertIs(captured["extra"]["procurement_skip_inventory"], True)
		self.assertIs(captured["extra"]["procurement_stocked_on_receipt"], False)
		with self.assertRaises(ApiError) as over:
			svc.return_to_supplier(self.db, 1, order["id"], {"lines": [{"order_line_id": order["lines"][0]["id"], "qty": 2}]}, 7)
		self.assertEqual(over.exception.code, "INVALID_RETURN_QTY")
		with patch.object(svc, "_post_issue_warehouse", side_effect=AssertionError("service return must not issue stock")):
			returned = svc.return_to_supplier(self.db, 1, order["id"], {"lines": [{"order_line_id": order["lines"][0]["id"], "qty": 1}]}, 7)
		self.assertEqual(returned["lines"][0]["accepted_qty"], 3.0)
		self.assertEqual(returned["lines"][0]["invoiced_qty"], 3.0)

	def test_untracked_goods_skip_the_warehouse_document(self):
		self.db.add(Product(id=7, business_id=1, code="P-7", name="غیرموجودی", item_type=ProductItemType.PRODUCT, track_inventory=False))
		self.db.flush()
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		order = svc.create_order(self.db, 1, {"person_id": 3, "currency_id": 1, "lines": [_line(product_id=7, qty=2, unit_price=10)]}, 7)
		svc.submit_order(self.db, 1, order["id"], {}, 7)
		svc.decide(self.db, 1, "order", order["id"], "approve", None, 7)
		received = svc.receive_order(self.db, 1, order["id"], {"lines": [{"order_line_id": order["lines"][0]["id"], "qty": 2}]}, 7)
		self.assertEqual(received["lines"][0]["accepted_qty"], 2)
		self.assertIsNone(received["receipts"][0]["warehouse_document_id"])
		captured = {}

		def fake_invoice(*args, **kwargs):
			captured["stocked"] = args[3]["lines"][0]["extra_info"]["procurement_stocked_on_receipt"]
			return {"data": {"id": 77, "code": "PINV-U", "document_type": "invoice_purchase"}}

		with patch("app.services.invoice_service.create_invoice", fake_invoice), patch.object(svc, "_mark_receipt_stock_not_on_invoice", lambda *args, **kwargs: None), patch.object(svc, "_clear_grni", lambda *args, **kwargs: None):
			svc.create_invoice_for_order(self.db, 1, order["id"], {"lines": [{"order_line_id": order["lines"][0]["id"], "qty": 1}]}, 7)
		self.assertIs(captured["stocked"], False)
		returned = svc.return_to_supplier(self.db, 1, order["id"], {"lines": [{"order_line_id": order["lines"][0]["id"], "qty": 1}]}, 7)
		self.assertEqual(returned["lines"][0]["accepted_qty"], 1)
		tracked = svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(product_id=5, qty=1)]}, 7)
		svc.submit_order(self.db, 1, tracked["id"], {}, 7)
		svc.decide(self.db, 1, "order", tracked["id"], "approve", None, 7)
		with self.assertRaises(ApiError) as missing_warehouse:
			svc.receive_order(self.db, 1, tracked["id"], {"lines": [{"order_line_id": tracked["lines"][0]["id"], "qty": 1}]}, 7)
		self.assertEqual(missing_warehouse.exception.code, "WAREHOUSE_REQUIRED")

	def test_supplier_return_posts_issue_and_portal_notice_is_not_an_invoice(self):
		from adapters.db.models.warehouse_document import WarehouseDocument
		from adapters.db.models.warehouse_document_line import WarehouseDocumentLine

		from adapters.db.models.fiscal_year import FiscalYear

		WarehouseDocument.__table__.create(self.db.get_bind(), checkfirst=True)
		WarehouseDocumentLine.__table__.create(self.db.get_bind(), checkfirst=True)
		FiscalYear.__table__.create(self.db.get_bind(), checkfirst=True)
		self.db.add(FiscalYear(business_id=1, title="1405", start_date=date(2026, 3, 21), end_date=date(2027, 3, 20), is_last=True))
		self.db.flush()
		svc.update_settings(self.db, 1, {"mode": "small"}, 7)
		order = svc.create_order(self.db, 1, {"person_id": 3, "lines": [_line(product_id=5, qty=4, warehouse_id=2)]}, 7)
		with self.assertRaises(ApiError) as not_sent:
			svc.create_share_link(self.db, 1, {"kind": "order", "entity_id": order["id"], "person_id": 3}, 7)
		self.assertEqual(not_sent.exception.code, "ORDER_NOT_SENT")
		with self.assertRaises(ApiError) as not_open:
			svc.create_share_link(self.db, 1, {"kind": "invoice", "entity_id": order["id"], "person_id": 3}, 7)
		self.assertEqual(not_open.exception.code, "ORDER_NOT_OPEN")
		svc.submit_order(self.db, 1, order["id"], {}, 7)
		svc.decide(self.db, 1, "order", order["id"], "approve", None, 7)

		def fake_post(db, document_id):
			row = db.query(WarehouseDocument).filter(WarehouseDocument.id == int(document_id)).one()
			row.status = "posted"

		with patch("app.services.warehouse_service.post_warehouse_document", fake_post):
			svc.receive_order(self.db, 1, order["id"], {"lines": [{"order_line_id": order["lines"][0]["id"], "qty": 4, "warehouse_id": 2}]}, 7)
			returned = svc.return_to_supplier(self.db, 1, order["id"], {"lines": [{"order_line_id": order["lines"][0]["id"], "qty": 1, "warehouse_id": 2}]}, 7)
		self.assertEqual(returned["lines"][0]["accepted_qty"], 3)
		issue = self.db.query(WarehouseDocument).filter(WarehouseDocument.doc_type == "issue").one()
		self.assertEqual(issue.source_type, "purchase_order")
		self.assertIsNone(issue.source_document_id)
		self.assertEqual(issue.extra_info["procurement_order_id"], order["id"])
		self.assertEqual(self.db.query(WarehouseDocumentLine).filter(WarehouseDocumentLine.movement == "out").one().warehouse_document_id, issue.id)
		link = svc.create_share_link(self.db, 1, {"kind": "order", "entity_id": order["id"], "person_id": 3}, 7)
		self.assertTrue(svc.portal_ack(self.db, link["token"])["acknowledged_at"])
		invoice_link = svc.create_share_link(self.db, 1, {"kind": "invoice", "entity_id": order["id"], "person_id": 3}, 7)
		before = self.db.query(Document).count()
		notice = svc.portal_invoice_notice(self.db, invoice_link["token"], {"reference": "SUP-9", "amount": 120, "note": "پیوست جدا ارسال می‌شود", "file_id": "stolen"})
		self.assertEqual(notice["reference"], "SUP-9")
		self.assertEqual(self.db.query(Document).count(), before)
		self.assertEqual(svc.portal_view(self.db, invoice_link["token"])["lines"][0]["description"], order["lines"][0]["description"])
		self.assertEqual(self.db.query(ProcPortalInvoice).one().note, "پیوست جدا ارسال می‌شود")
		self.assertIsNone(self.db.query(ProcPortalInvoice).one().file_id)

	def test_grni_clearance_posts_only_in_two_step_mode(self):
		from decimal import Decimal
		from types import SimpleNamespace

		from adapters.db.models.document_line import DocumentLine
		from adapters.db.models.warehouse_document import WarehouseDocument
		from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
		from app.services.purchase_accounting_service import post_grni_clearance_for_receipt_invoice

		WarehouseDocument.__table__.create(self.db.get_bind(), checkfirst=True)
		WarehouseDocumentLine.__table__.create(self.db.get_bind(), checkfirst=True)
		DocumentLine.__table__.create(self.db.get_bind(), checkfirst=True)
		receipt = WarehouseDocument(business_id=1, code="WH-1", document_date=date.today(), status="posted", doc_type="receipt", source_type="purchase_order")
		self.db.add(receipt)
		self.db.flush()
		self.db.add(WarehouseDocumentLine(warehouse_document_id=receipt.id, product_id=5, movement="in", quantity=2, extra_info={"unit_price": 10}))
		direct = Document(code="PINV-D", business_id=1, fiscal_year_id=1, currency_id=1, created_by_user_id=7, document_date=date.today(), document_type="invoice_purchase", extra_info={"purchase_accounting_mode": "direct_inventory"})
		grni = Document(code="PINV-G", business_id=1, fiscal_year_id=1, currency_id=1, created_by_user_id=7, document_date=date.today(), document_type="invoice_purchase", extra_info={"purchase_accounting_mode": "grni_two_step"})
		self.db.add_all([direct, grni])
		self.db.flush()
		self.assertFalse(post_grni_clearance_for_receipt_invoice(self.db, invoice_id=direct.id, warehouse_document_id=receipt.id))
		self.assertEqual(self.db.query(DocumentLine).count(), 0)

		def account(db, code):
			return SimpleNamespace(id=int(code))

		with patch("app.services.invoice_service._get_fixed_account_by_code", account), patch("app.services.purchase_accounting_service.compute_warehouse_receipt_inventory_amount", return_value=Decimal("20")), patch("app.services.purchase_accounting_service._grni_net_on_document", return_value=Decimal("100")):
			self.assertTrue(post_grni_clearance_for_receipt_invoice(self.db, invoice_id=grni.id, warehouse_document_id=receipt.id))
			self.assertFalse(post_grni_clearance_for_receipt_invoice(self.db, invoice_id=grni.id, warehouse_document_id=receipt.id))
		lines = self.db.query(DocumentLine).filter(DocumentLine.document_id == grni.id).all()
		self.assertEqual(len(lines), 2)
		debit = next(row for row in lines if row.debit and Decimal(str(row.debit)) > 0)
		credit = next(row for row in lines if row.credit and Decimal(str(row.credit)) > 0)
		self.assertEqual(debit.account_id, 10102)
		self.assertEqual(credit.account_id, 10107)
		self.assertEqual(Decimal(str(debit.debit)), Decimal("20"))
		self.assertEqual(debit.extra_info["procurement"], True)

	def test_invoice_route_requires_purchase_invoice_permission(self):
		from adapters.api.v1 import procurement as api

		request = SimpleNamespace(state=SimpleNamespace())
		with patch.object(api, "_allow"), patch.object(api, "has_invoice_type_permission_for_business", return_value=False):
			with self.assertRaises(ApiError) as blocked:
				api.invoice_order(request, 1, 1, {"lines": [{"order_line_id": 1, "qty": 1}]}, SimpleNamespace(), self.db)
		self.assertEqual(blocked.exception.code, "FORBIDDEN")
		ctx = SimpleNamespace(get_user_id=lambda: 7)
		with patch.object(api, "_allow"), patch.object(api, "has_invoice_type_permission_for_business", return_value=True), patch.object(api.svc, "create_invoice_for_order", return_value={"id": 1}) as create:
			api.invoice_order(request, 1, 1, {"lines": [{"order_line_id": 1, "qty": 1}]}, ctx, self.db)
		create.assert_called_once()


if __name__ == "__main__":
	unittest.main()
