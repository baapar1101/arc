"""واریز لینک عمومی نباید مانده کیف‌پول SaaS را تغییر دهد."""
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from adapters.db.models.wallet import WalletTransaction
from app.services.public_pay_page_payment_service import confirm_public_pay_page_payment


def test_failed_gateway_does_not_create_receipt():
	db = MagicMock()
	tx = WalletTransaction(
		business_id=1,
		type="public_pay_link",
		status="pending",
		amount=100000,
	)
	tx.id = 9
	tx.extra_info = "{}"
	result = confirm_public_pay_page_payment(db, tx, success=False, external_ref="x")
	assert result["status"] == "failed"
	assert tx.document_id is None


def test_confirm_success_posts_receipt_wallet_line_not_saas_balance():
	db = MagicMock()
	tx = WalletTransaction(
		business_id=7,
		type="public_pay_link",
		status="pending",
		amount=150000,
		fee_amount=0,
	)
	tx.id = 3
	tx.extra_info = (
		'{"gateway_id": 1, "currency_id": 1, "created_by_user_id": 4, '
		'"payer_name": "علی", "username": "ali"}'
	)

	business = SimpleNamespace(id=7, owner_id=4, name="فروشگاه علی", deleted_at=None)
	page = SimpleNamespace(
		business_id=7,
		is_enabled=True,
		username="ali",
		gateway_id=1,
		notify_inapp=True,
		notify_sms=False,
		match_customer_by_mobile=True,
		create_customer_if_missing=True,
		use_anonymous_if_no_mobile=True,
	)
	person = SimpleNamespace(id=88, alias_name="علی")

	q = db.query.return_value
	q.filter.return_value.first.side_effect = [business, page]

	with patch(
		"app.services.public_pay_page_payment_service.ensure_wallet_currency_in_business"
	), patch(
		"app.services.public_pay_page_payment_service.resolve_pay_link_person",
		return_value=person,
	), patch(
		"app.services.public_pay_page_payment_service.create_receipt_payment",
		return_value={"id": 501},
	) as create_rp, patch(
		"app.services.public_pay_page_payment_service._notify_owner_after_payment"
	):
		result = confirm_public_pay_page_payment(db, tx, success=True, external_ref="REF1")

	assert result["status"] == "succeeded"
	assert result["receipt_document_id"] == 501
	assert tx.document_id == 501
	kwargs = create_rp.call_args.kwargs
	assert kwargs["commit"] is False
	data = kwargs["data"]
	assert data["document_type"] == "receipt"
	assert data["account_lines"][0]["transaction_type"] == "wallet"
	assert data["person_lines"][0]["person_id"] == 88
	assert data["extra_info"]["person_is_receivable"] is True
	assert data["extra_info"]["source"] == "public_pay_link"
