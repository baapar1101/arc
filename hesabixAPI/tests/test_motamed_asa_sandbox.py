"""«معتمد آسا» and the tax organisation's sandbox: which environment each operation goes to."""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from app.core.responses import ApiError
from app.services import motamed_asa_tax_submission_service as service

_NOT_FOUND = {"status": 3, "error": ["صورتحساب یافت نشد"]}


def _document(**extra) -> SimpleNamespace:
    return SimpleNamespace(id=42, business_id=5, description=None, extra_info=dict(extra))


def _setting(sandbox: bool) -> SimpleNamespace:
    return SimpleNamespace(sandbox_mode=sandbox)


def _sandbox_chain(**extra) -> SimpleNamespace:
    return _document(
        tax_submission_provider="motamed_asa", asa_internal_id="hesabix-sandbox-42", asa_sandbox=True, **extra
    )


def _production_chain(**extra) -> SimpleNamespace:
    # Sent before sandbox support: no asa_sandbox flag.
    return _document(tax_submission_provider="motamed_asa", asa_internal_id="hesabix-42", **extra)


@pytest.fixture
def client() -> MagicMock:
    client = MagicMock()
    client.inquire_internal_ids.side_effect = lambda token, ids: [{"internalId": ids[0], **_NOT_FOUND}]
    client.send_invoices.return_value = {"result": 1, "data": [{"asatspId": 9, "taxId": "T" * 22, "status": 0}]}
    return client


@pytest.fixture
def asa(monkeypatch: pytest.MonkeyPatch, client: MagicMock) -> MagicMock:
    """Runs each ASA operation against the mocked client; the business's memory is a production one."""
    account = SimpleNamespace(memory_number="PRD123")
    calls = MagicMock(side_effect=lambda db, business_id, operation: operation(client, "token", account))
    monkeypatch.setattr(service, "motamed_asa_business_call", calls)
    monkeypatch.setattr(
        service, "build_motamed_asa_invoice",
        lambda dto, *, document_id, subject: {"Header": {"ins": subject}, "Body": [], "Payments": []},
    )
    return calls


def _sent_member(client: MagicMock) -> dict:
    return client.send_invoices.call_args.args[1]["data"][0]


def test_sandbox_mode_sends_a_sandbox_member_without_the_production_memory(asa, client) -> None:
    document = _document()

    service.send_document_via_motamed_asa(
        MagicMock(), document, _setting(True), MagicMock(), submission_mode="normal"
    )

    member = _sent_member(client)
    assert member["sandBox"] is True
    assert member["internalId"] == "hesabix-sandbox-42"
    assert "fiscalId" not in member, "ASA picks the business's Sandbox memory itself"
    assert (document.extra_info["asa_sandbox"], document.extra_info["asa_internal_id"]) == (True, "hesabix-sandbox-42")


def test_production_mode_sends_a_production_member_with_its_memory(asa, client) -> None:
    document = _document()

    service.send_document_via_motamed_asa(
        MagicMock(), document, _setting(False), MagicMock(), submission_mode="normal"
    )

    member = _sent_member(client)
    assert (member["sandBox"], member["fiscalId"], member["internalId"]) == (False, "PRD123", "hesabix-42")
    assert document.extra_info["asa_sandbox"] is False


@pytest.mark.parametrize("mode", ["corrective", "cancel"])
@pytest.mark.parametrize(
    ("document", "sandbox_mode"),
    [(_production_chain, True), (_sandbox_chain, False)],
    ids=["production-invoice-in-sandbox-mode", "sandbox-invoice-in-production-mode"],
)
def test_correction_or_cancellation_never_crosses_environments(asa, client, mode, document, sandbox_mode) -> None:
    doc = document()
    before = dict(doc.extra_info)

    with pytest.raises(ApiError) as error:
        service.prepare_motamed_asa_environment(MagicMock(), doc, _setting(sandbox_mode), submission_mode=mode)

    assert error.value.code == "MOTAMED_ASA_ENVIRONMENT_MISMATCH"
    assert doc.extra_info == before
    asa.assert_not_called()
    with pytest.raises(ApiError):
        service.send_document_via_motamed_asa(MagicMock(), doc, _setting(sandbox_mode), MagicMock(), submission_mode=mode)
    client.edit_invoice.assert_not_called()
    client.cancel_invoice.assert_not_called()


def test_correction_in_the_invoices_own_environment_keeps_its_chain(asa, client) -> None:
    client.edit_invoice.return_value = {
        "result": 1, "edit": {"outcome": "correctionIssued", "taxId": "C" * 22},
        "data": [{"asatspId": 10, "issue": 2, "status": 0}],
    }
    document = _sandbox_chain()

    service.prepare_motamed_asa_environment(MagicMock(), document, _setting(True), submission_mode="corrective")
    service.send_document_via_motamed_asa(MagicMock(), document, _setting(True), MagicMock(), submission_mode="corrective")

    body = client.edit_invoice.call_args.args[1]
    assert body["internalId"] == "hesabix-sandbox-42"
    assert "sandBox" not in body, "editInvoice keeps the invoice's environment and takes no sandBox"


@pytest.mark.parametrize("status", [0, 1, 2])
def test_an_original_registered_or_in_flight_is_not_moved(asa, client, status) -> None:
    client.inquire_internal_ids.side_effect = lambda token, ids: [
        {"internalId": ids[0], "asatspId": 9, "issue": 1, "status": status}
    ]
    document = _sandbox_chain(tax_moadian_taxid="S" * 22)
    before = dict(document.extra_info)

    with pytest.raises(ApiError) as error:
        service.prepare_motamed_asa_environment(MagicMock(), document, _setting(False), submission_mode="normal")

    assert error.value.code == "MOTAMED_ASA_ENVIRONMENT_MISMATCH"
    assert client.inquire_internal_ids.call_args.args[1] == ["hesabix-sandbox-42"]
    assert document.extra_info == before
    client.send_invoices.assert_not_called()


@pytest.mark.parametrize(
    "held",
    [_NOT_FOUND, {"asatspId": 9, "issue": 1, "status": 3, "error": ["خطای سازمان"]}],
    ids=["unknown-to-asa", "refused"],
)
def test_an_original_never_registered_starts_again_in_the_current_environment(asa, client, held) -> None:
    client.inquire_internal_ids.side_effect = [[{"internalId": "hesabix-sandbox-42", **held}], [
        {"internalId": "hesabix-42", **_NOT_FOUND}
    ]]
    document = _sandbox_chain(
        tax_moadian_taxid="S" * 22, tax_tracking_code="9", asa_latest_invoice_id=9,
        asa_tax_ids_by_mode={"normal": "S" * 22}, asa_fiscal_id="SND123",
    )

    service.prepare_motamed_asa_environment(MagicMock(), document, _setting(False), submission_mode="normal")

    extra = document.extra_info
    assert (extra["asa_internal_id"], extra["asa_sandbox"]) == ("hesabix-42", False)
    assert not {"tax_moadian_taxid", "tax_tracking_code", "asa_latest_invoice_id", "asa_tax_ids_by_mode", "asa_fiscal_id"} & set(extra)

    service.send_document_via_motamed_asa(MagicMock(), document, _setting(False), MagicMock(), submission_mode="normal")
    member = _sent_member(client)
    assert (member["internalId"], member["sandBox"]) == ("hesabix-42", False)


def test_same_environment_needs_no_extra_inquiry(asa, client) -> None:
    service.prepare_motamed_asa_environment(MagicMock(), _sandbox_chain(), _setting(True), submission_mode="normal")
    service.prepare_motamed_asa_environment(MagicMock(), _document(), _setting(True), submission_mode="normal")
    asa.assert_not_called()


def _reference(monkeypatch: pytest.MonkeyPatch, **extra) -> SimpleNamespace:
    reference = SimpleNamespace(id=41, extra_info={"tax_submission_provider": "motamed_asa", "tax_moadian_taxid": "A" * 22, **extra})
    monkeypatch.setattr(service, "resolve_reference_document", lambda db, business_id, document: reference)
    return reference


@pytest.mark.parametrize(
    ("reference_extra", "sandbox"),
    [
        ({"asa_internal_id": "hesabix-41"}, True),
        ({"asa_internal_id": "hesabix-sandbox-41", "asa_sandbox": True}, False),
    ],
    ids=["production-sale-in-sandbox-mode", "sandbox-sale-in-production-mode"],
)
def test_return_of_a_sale_from_the_other_environment_is_refused(monkeypatch, reference_extra, sandbox) -> None:
    _reference(monkeypatch, **reference_extra)

    with pytest.raises(ApiError) as error:
        service.motamed_asa_return_reference_tax_id(MagicMock(), _document(), sandbox=sandbox)

    assert error.value.code == "MOTAMED_ASA_REFERENCE_OTHER_ENVIRONMENT"


def test_sandbox_return_refers_to_a_sandbox_sale(monkeypatch, asa, client) -> None:
    _reference(monkeypatch, asa_internal_id="hesabix-sandbox-41", asa_sandbox=True)
    document = _document()

    service.send_document_via_motamed_asa(MagicMock(), document, _setting(True), MagicMock(), submission_mode="return")

    member = _sent_member(client)
    assert (member["sandBox"], member["returnRows"]) == (True, "returned")
    assert member["data"]["Header"]["irtaxid"] == "A" * 22


def test_payments_of_an_invoice_are_registered_only_in_its_environment(monkeypatch, asa, client) -> None:
    monkeypatch.setattr(service, "_business_sandbox", lambda db, business_id: False)

    with pytest.raises(ApiError) as error:
        service.register_motamed_asa_payments(
            MagicMock(), 5, _sandbox_chain(), [{"type": 3, "timestamp": 1789446000000, "price": 1000}]
        )

    assert error.value.code == "MOTAMED_ASA_ENVIRONMENT_MISMATCH"
    client.register_payments.assert_not_called()


def test_payments_of_a_sandbox_invoice_can_still_be_read_in_production_mode(monkeypatch, asa, client) -> None:
    monkeypatch.setattr(service, "_business_sandbox", lambda db, business_id: False)
    client.inquire_payments.return_value = {"result": 1, "data": [{"taxId": "S" * 22, "payments": []}]}

    view = service.motamed_asa_invoice_payments(MagicMock(), 5, _sandbox_chain())

    assert view["tax_id"] == "S" * 22
    assert client.inquire_payments.call_args.args[1] == "hesabix-sandbox-42"


def test_inquiry_reads_each_chain_where_it_lives(asa, client) -> None:
    client.inquire_internal_ids.side_effect = lambda token, ids: [
        {"internalId": internal_id, "asatspId": 9, "issue": 1, "status": 2, "taxId": "T" * 22} for internal_id in ids
    ]
    documents = [
        _sandbox_chain(tax_last_submission_mode="normal"),
        SimpleNamespace(id=43, business_id=5, extra_info={"tax_submission_provider": "motamed_asa", "asa_internal_id": "hesabix-43"}),
    ]

    results = service.motamed_asa_inquire_documents(MagicMock(), 5, documents)

    assert client.inquire_internal_ids.call_args.args[1] == ["hesabix-sandbox-42", "hesabix-43"]
    assert [result["status"] for _, result in results] == ["finalized", "finalized"]


@pytest.mark.parametrize(
    ("extra", "expected"),
    [
        ({}, None),
        ({"asa_internal_id": "hesabix-42"}, False),
        ({"asa_internal_id": "hesabix-sandbox-42", "asa_sandbox": True}, True),
        ({"asa_internal_id": "hesabix-42", "asa_sandbox": False}, False),
    ],
)
def test_document_environment(extra, expected) -> None:
    assert service.motamed_asa_document_sandbox(_document(**extra)) is expected
