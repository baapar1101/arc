"""«معتمد آسا»: the invoice JSON sent to API v2 and the document state read back from it."""

from __future__ import annotations

from types import SimpleNamespace

import pytest

from app.core.responses import ApiError
from app.integrations.moadian.dto import InvoiceBodyDto, InvoiceDto, InvoiceHeaderDto, InvoicePaymentDto
from app.services.motamed_asa_tax_submission_service import (
    _document_result,
    _hesabix_status,
    _payments_internal_id,
    build_motamed_asa_invoice,
    build_motamed_asa_payment_rows,
    build_motamed_asa_return_invoice,
    motamed_asa_internal_id,
    normalize_article6_status,
)


def _row(sstid: str, am: int, fee: int, dis: int = 0, vra: int = 10) -> InvoiceBodyDto:
    prdis = am * fee
    adis = prdis - dis
    vam = round(adis * vra / 100)
    return InvoiceBodyDto(
        sstid=sstid, sstt=f"کالا {sstid[-2:]}", mu="1627", am=am, fee=fee, prdis=prdis,
        dis=dis, adis=adis, vra=vra, vam=vam, tsstam=adis + vam,
    )


def _dto(body: list[InvoiceBodyDto], *, inty: int = 1, inp: int = 1, ins: int = 1, payments=None) -> InvoiceDto:
    header = InvoiceHeaderDto(
        taxid="A1B2C3D4E5F6G7H8I9J0K1", indatim=1782940800000, indati2m=1782940800000,
        inno="0000000042", inty=inty, inp=inp, ins=ins, tins="14001234567",
        tob=2 if inty == 1 else None, tinb="10987654321" if inty == 1 else None,
        tprdis=sum(b.prdis for b in body), tdis=sum(b.dis for b in body),
        tadis=sum(b.adis for b in body), tvam=sum(b.vam for b in body), todam=0,
        tbill=sum(b.adis + b.vam for b in body), tax17=0,
        setm=1 if inty == 1 else None, cap=sum(b.adis + b.vam for b in body) if inty == 1 else None,
    )
    return InvoiceDto(header=header, body=body, payments=payments or [])


def test_original_invoice_drops_hesabix_taxid_and_marks_sale_pattern() -> None:
    dto = _dto([_row("2720000114542", 2, 500_000)], inp=4, ins=4)
    data = build_motamed_asa_invoice(dto, document_id=42, subject=1)
    header = data["Header"]
    assert "taxid" not in header and "indati2m" not in header and "tax17" not in header
    assert (header["inp"], header["ins"], header["inno"]) == (1, 1, "000000002A")
    assert header["tbill"] == sum(row["tsstam"] for row in data["Body"])
    assert data["Body"][0]["sstid"] == "2720000114542"


def test_payments_without_type_are_left_out_and_dates_become_unix_ms() -> None:
    payments = [
        InvoicePaymentDto(),
        InvoicePaymentDto(pmt="3", pdt="2026-07-01T00:00:00+00:00", trn="123"),
    ]
    data = build_motamed_asa_invoice(_dto([_row("2720000114542", 1, 1000)], payments=payments), document_id=1, subject=1)
    assert data["Payments"] == [{"trn": "123", "pdt": 1782864000000, "pmt": 3}]


def test_type_two_sends_no_payments() -> None:
    data = build_motamed_asa_invoice(
        _dto([_row("2720000114542", 1, 1000)], inty=2, payments=[InvoicePaymentDto(pmt=3)]), document_id=1, subject=1
    )
    assert data["Payments"] == []


def _reference(rows: list[dict], *, setm: int = 1) -> dict:
    return {
        "asatspId": 900,
        "taxId": "ATAXIDOFTHELATESTCHAIN",
        "status": 2,
        "issue": 1,
        "json": {"Header": {"inty": 1, "inp": 1, "setm": setm}, "Body": rows},
    }


def test_return_sends_remaining_rows_and_recomputes_totals() -> None:
    reference = _reference([
        {"sstid": "2720000114542", "sstt": "کالا 42", "mu": "1627", "am": 3, "fee": 1000, "dis": 300, "vra": 10},
        {"sstid": "2720000114559", "sstt": "کالا 59", "mu": "1627", "am": 1, "fee": 5000, "dis": 0, "vra": 10},
    ])
    returned = _dto([_row("2720000114542", 1, 1000, dis=100)], ins=4)
    data = build_motamed_asa_return_invoice(returned, document_id=77, reference=reference)

    header, body = data["Header"], data["Body"]
    assert (header["ins"], header["irtaxid"], header["inno"]) == (4, "ATAXIDOFTHELATESTCHAIN", "000000004D")
    assert [(row["sstid"], row["am"], row["dis"]) for row in body] == [
        ("2720000114542", 2, 200),
        ("2720000114559", 1, 0),
    ]
    assert body[0]["prdis"] == 2000 and body[0]["adis"] == 1800 and body[0]["vam"] == 180
    assert header["tbill"] == sum(row["tsstam"] for row in body) == header["cap"]
    assert "tob" not in header and "tinb" not in header
    assert data["Payments"] == []


def test_returning_everything_asks_for_cancellation() -> None:
    reference = _reference([{"sstid": "2720000114542", "am": 2, "fee": 1000, "dis": 0, "vra": 10}])
    with pytest.raises(ApiError) as error:
        build_motamed_asa_return_invoice(_dto([_row("2720000114542", 2, 1000)], ins=4), document_id=1, reference=reference)
    assert error.value.code == "MOTAMED_ASA_RETURN_NEEDS_CANCELLATION"


def test_returning_more_than_remaining_is_refused() -> None:
    reference = _reference([{"sstid": "2720000114542", "am": 1, "fee": 1000, "dis": 0, "vra": 10}])
    with pytest.raises(ApiError) as error:
        build_motamed_asa_return_invoice(_dto([_row("2720000114542", 2, 1000)], ins=4), document_id=1, reference=reference)
    assert error.value.code == "MOTAMED_ASA_RETURN_ROW_INVALID"


def test_return_needs_the_accepted_reference_json() -> None:
    with pytest.raises(ApiError) as error:
        build_motamed_asa_return_invoice(
            _dto([_row("2720000114542", 1, 1000)], ins=4), document_id=1, reference={"taxId": "X", "status": 1}
        )
    assert error.value.code == "MOTAMED_ASA_REFERENCE_UNAVAILABLE"


@pytest.mark.parametrize(
    ("info", "expected"),
    [
        ({"status": 0}, ("pending", None)),
        ({"status": 1}, ("pending", None)),
        ({"status": 2, "statusInquery": "APPROVED"}, ("finalized", None)),
        ({"status": 3, "error": ["خطای ۱", "خطای ۲"]}, ("failed", "خطای ۱؛ خطای ۲")),
        ({"status": "Success"}, ("finalized", None)),
    ],
)
def test_hesabix_status(info: dict, expected: tuple) -> None:
    assert _hesabix_status(info) == expected


def test_buyer_rejection_keeps_the_invoice_registered() -> None:
    # The buyer's reaction is the separate کارپوشه status, not a sending failure.
    assert _hesabix_status({"status": 2, "statusInquery": "REJECTED"}) == ("finalized", None)


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("NOT_EXCEEDED", "not_violated"),
        ("false", "not_violated"),
        ("عدم عدول", "not_violated"),
        ("EXCEEDED", "violated"),
        ("1", "violated"),
        ("عدول", "violated"),
        ("SOMETHING_NEW", None),
        ("", None),
    ],
)
def test_article6_status(raw: str, expected: str | None) -> None:
    assert normalize_article6_status(raw) == expected


def test_own_invoice_carries_workspace_and_article6_status() -> None:
    result = _document_result(
        _document(tax_last_submission_mode="normal"),
        {"internalId": "hesabix-42", "asatspId": 5, "issue": 1, "status": 2, "taxId": "T" * 22,
         "statusInquery": "AWAITING_REACTION", "article6Status": "NOT_EXCEEDED"},
    )
    assert result["updates"]["tax_provider_invoice_status"] == "AWAITING_REACTION"
    assert result["updates"]["tax_article6_status"] == "not_violated"


def test_later_invoice_status_is_not_copied_to_the_original() -> None:
    result = _document_result(
        _document(tax_last_submission_mode="normal"),
        {"internalId": "hesabix-42", "asatspId": 9, "issue": 4, "status": 2, "statusInquery": "REJECTED"},
    )
    assert "tax_provider_invoice_status" not in result["updates"]


def test_payment_rows_are_checked_and_shaped_for_register_payment() -> None:
    rows = build_motamed_asa_payment_rows([
        {"type": "6", "timestamp": 1789446000000, "price": "25000000", "trace_no": "۱۳۰۲۳۸۷۸۶۵۶۴۳۱",
         "terminal_number": "1302387", "description": " قسط دوم "},
    ])
    assert rows == [{
        "type": 6, "dateTime": "1789446000000", "price": 25000000, "traceNo": "13023878656431",
        "terminalNumber": "1302387", "description": "قسط دوم",
    }]


@pytest.mark.parametrize(
    "payment",
    [
        {"type": 9, "timestamp": 1789446000000, "price": 1},
        {"type": 3, "timestamp": None, "price": 1},
        {"type": 3, "timestamp": 1789446000000, "price": 0},
        {"type": 3, "timestamp": 1789446000000, "price": "12.5"},
        {"type": 3, "timestamp": 1789446000000, "price": 1, "terminal_number": "123456789"},
    ],
)
def test_invalid_payment_rows_are_refused(payment: dict) -> None:
    with pytest.raises(ApiError) as error:
        build_motamed_asa_payment_rows([payment])
    assert error.value.code == "MOTAMED_ASA_PAYMENT_INVALID"


def test_payments_need_an_invoice_sent_through_motamed_asa() -> None:
    with pytest.raises(ApiError) as error:
        _payments_internal_id(_document(tax_submission_provider="moadian_direct"))
    assert error.value.code == "MOTAMED_ASA_PAYMENTS_NOT_APPLICABLE"


def _document(**extra) -> SimpleNamespace:
    return SimpleNamespace(id=42, extra_info=extra)


def test_internal_id_is_stable() -> None:
    assert motamed_asa_internal_id(_document()) == "hesabix-42"
    assert motamed_asa_internal_id(_document(asa_internal_id="hesabix-7")) == "hesabix-7"


def test_original_follows_its_own_invoice() -> None:
    result = _document_result(
        _document(tax_last_submission_mode="normal"),
        {"internalId": "hesabix-42", "asatspId": 5, "issue": 1, "status": 3, "error": ["رد شد"]},
    )
    assert (result["status"], result["error_message"]) == ("failed", "رد شد")


def test_a_later_invoice_in_the_chain_means_the_original_was_registered() -> None:
    result = _document_result(
        _document(tax_last_submission_mode="normal"),
        {"internalId": "hesabix-42", "asatspId": 9, "issue": 4, "status": 1},
    )
    assert result["status"] == "finalized"
    assert "tax_cancelled_in_modian" not in result["updates"]


def test_accepted_cancellation_marks_the_document_cancelled() -> None:
    result = _document_result(
        _document(tax_last_submission_mode="cancel"),
        {"internalId": "hesabix-42-cancel", "asatspId": 9, "issue": 3, "status": 2},
    )
    assert result["status"] == "finalized"
    assert result["updates"]["tax_cancelled_in_modian"] is True


def test_unknown_document_keeps_its_status() -> None:
    result = _document_result(
        _document(tax_last_submission_mode="normal"),
        {"internalId": "hesabix-42", "status": 3, "error": ["صورتحساب یافت نشد"]},
    )
    assert result["status"] == "unknown"
