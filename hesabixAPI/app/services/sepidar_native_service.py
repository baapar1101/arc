"""Transactional projection of Sepidar snapshots into native Hesabix entities.

Sepidar remains authoritative. Original voucher lines are posted exactly once;
invoice creation here deliberately does not invoke services that generate GL,
inventory, wallet charges, notifications or workflow side effects.
"""
from __future__ import annotations

import hashlib
import json
from collections import Counter, defaultdict
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any

from sqlalchemy import delete, select, tuple_
from sqlalchemy.orm import Session

from adapters.db.models.account import Account
from adapters.db.models.business import Business
from adapters.db.models.currency import BusinessCurrency, Currency
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.person import Person
from adapters.db.models.product import Product, ProductItemType
from adapters.db.models.sepidar_live_import import SepidarImportRow, SepidarImportSetting, SepidarNativeMap
from adapters.db.models.warehouse import Warehouse
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.bank_account import BankAccount
from adapters.db.models.cash_register import CashRegister
from app.core.responses import ApiError


class NativeConversionError(ValueError):
    """Safe, identifier-only diagnostics; never include customer row payloads."""


INVOICES = (
    ("SLS.Invoice", "InvoiceId", "SLS.InvoiceItem", "InvoiceRef", "invoice_sales", "S", "NetPrice", "VoucherRef"),
    ("SLS.ReturnedInvoice", "ReturnedInvoiceId", "SLS.ReturnedInvoiceItem", "ReturnedInvoiceRef", "invoice_sales_return", "R", "NetPrice", "VoucherRef"),
    ("INV.InventoryPurchaseInvoice", "InventoryPurchaseInvoiceID", "INV.InventoryPurchaseInvoiceItem", "InventoryPurchaseInvoiceRef", "invoice_purchase", "P", "TotalNetPrice", "AccountingVoucherRef"),
    ("SLS.Quotation", "QuotationId", "SLS.QuotationItem", "QuotationRef", "invoice_sales", "Q", "NetPrice", None),
)
SOURCE_IDS = {
    "FMK.FiscalYear": "FiscalYearId", "GNR.Currency": "CurrencyID", "GNR.Party": "PartyId",
    "INV.Item": "ItemID", "INV.Stock": "StockID", "ACC.Account": "AccountId", "ACC.Voucher": "VoucherId",
    **{spec[0]: spec[1] for spec in INVOICES},
}
OPERATION_IDS = {'INV.InventoryReceipt':'InventoryReceiptID','INV.InventoryDelivery':'InventoryDeliveryID',
                 'RPA.ReceiptHeader':'ReceiptHeaderId','RPA.PaymentHeader':'PaymentHeaderId',
                 'RPA.BankAccount':'BankAccountId','RPA.Cash':'CashId'}
OPERATION_TABLES = set(OPERATION_IDS) | {'INV.InventoryReceiptItem','INV.InventoryDeliveryItem','INV.ItemStockSummary',
    'RPA.PartyAccountSettlement','RPA.PartyAccountSettlementItem','RPA.ReceiptDraft','RPA.PaymentDraft',
    'RPA.ReceiptCheque','RPA.PaymentCheque','RPA.PaymentChequeOther','GNR.Shred'}


def decimal(value: Any) -> Decimal:
    result = Decimal(str(value or 0))
    if not result.is_finite():
        raise NativeConversionError("Non-finite source amount")
    return result


def money(value: Any) -> Decimal:
    result = decimal(value)
    if result != result.quantize(Decimal(".01")):
        raise NativeConversionError("Source monetary precision exceeds native ledger precision")
    return result


def source_date(value: Any) -> date:
    if not value:
        raise NativeConversionError("Missing source document date")
    return date.fromisoformat(str(value)[:10])


def fingerprint(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, default=str, separators=(",", ":")).encode()).hexdigest()


def account_report_prefix(path: list[dict]) -> str:
    """Translate the standard Sepidar chart, retaining its original path after SPD.

    Hesabix reports classify by code, not the source account's hierarchy Type.
    Mixed income/expense groups use the source's declared normal balance (1/2),
    never the current signed balance, so classification is stable across polls.
    """
    codes = [str(row['Code']) for row in path if row.get('Type') != 0]
    if not codes:
        return '9'
    group = codes[0]
    prefixes = {'11': '101', '12': '106', '21': '201', '22': '205',
                '31': '301', '41': '5', '51': '4', '61': '701', '62': '9', '91': '9'}
    if group not in prefixes:
        raise NativeConversionError(f"Unmapped source account group: {group}")
    if group == '12' and len(codes) > 1 and codes[1] == '11':
        return '108'  # accumulated depreciation
    if group == '31' and len(codes) > 1:
        if codes[1] == '13':
            return '30106'  # retained earnings
        if codes[1] == '14':
            return '30105'  # current-year profit
    if len(codes) > 1 and (group == '62' or group == '41' and codes[1] == '12'):
        normal_side = path[-1].get('BalanceType')
        if normal_side not in (1, 2):
            raise NativeConversionError("Mixed source income/expense account needs a declared normal balance")
        return ('708' if normal_side == 1 else '602') if group == '62' else ('701' if normal_side == 1 else '601')
    return prefixes[group]


def assert_document_editable(document: Document) -> None:
    if (document.extra_info or {}).get("sepidar", {}).get("managed"):
        raise ApiError("SEPIDAR_SOURCE_MANAGED", "این سند با سپیدار همگام می‌شود؛ ویرایش و حذف مالی را در سپیدار انجام دهید.", http_status=409)


def validate_voucher(lines: list[dict]) -> None:
    if len(lines) < 2:
        raise NativeConversionError("Source voucher has fewer than two lines")
    debit = sum((money(r.get("Debit")) for r in lines), Decimal(0))
    credit = sum((money(r.get("Credit")) for r in lines), Decimal(0))
    if debit != credit:
        raise NativeConversionError("Source voucher is not balanced")
    if any(money(r.get("Debit")) < 0 or money(r.get("Credit")) < 0 or
           (money(r.get("Debit")) and money(r.get("Credit"))) for r in lines):
        raise NativeConversionError("Invalid source debit/credit direction")


def validate_invoice(header: dict, lines: list[dict], net_field: str) -> None:
    if not lines or sum((decimal(r.get("NetPrice")) for r in lines), Decimal(0)) != decimal(header.get(net_field)):
        raise NativeConversionError("Source invoice header/line totals disagree")
    if any(decimal(r.get("Quantity")) <= 0 or decimal(r.get("Quantity")) != decimal(r.get("Quantity")).quantize(Decimal(".000001")) for r in lines):
        raise NativeConversionError("Source invoice quantity is not representable")


class Projector:
    def __init__(self, db: Session, setting: SepidarImportSetting):
        self.db, self.setting = db, setting
        self.business = db.get(Business, setting.business_id)
        if not self.business or self.business.deleted_at is not None:
            raise NativeConversionError("Destination business unavailable")
        self.bid = setting.business_id
        self.data: dict[str, list[dict]] = defaultdict(list)
        required = set(SOURCE_IDS) | {"ACC.VoucherItem", "ACC.DL", "GNR.PartyAddress", "GNR.PartyPhone", "INV.Unit"} | {s[2] for s in INVOICES}
        if setting.operations_enabled:
            required |= OPERATION_TABLES
        for schema, table, payload in db.execute(select(SepidarImportRow.source_schema, SepidarImportRow.source_table, SepidarImportRow.payload).where(
            SepidarImportRow.business_id == self.bid, SepidarImportRow.is_deleted.is_(False),
            tuple_(SepidarImportRow.source_schema, SepidarImportRow.source_table).in_([tuple(t.split('.')) for t in required]))):
            fullname = f"{schema}.{table}"
            if fullname in required:
                self.data[fullname].append(payload)
        for table, id_field in SOURCE_IDS.items():
            if not self.data[table] and table in {"FMK.FiscalYear", "GNR.Currency", "GNR.Party", "INV.Item", "ACC.Account", "ACC.Voucher"}:
                raise NativeConversionError(f"Missing required source snapshot: {table}")
            ids = [str(row[id_field]) for row in self.data[table]]
            if len(ids) != len(set(ids)):
                raise NativeConversionError(f"Duplicate source identity: {table}")
        self.maps = {(m.source_table, m.source_id): m for m in db.scalars(select(SepidarNativeMap).where(
            SepidarNativeMap.business_id == self.bid, SepidarNativeMap.database_name == setting.database_name))}
        self.targets = {model.__tablename__: {obj.id: obj for obj in db.scalars(select(model).where(model.business_id == self.bid))}
                        for model in (Person, Product, Account, FiscalYear, Warehouse, Document, WarehouseDocument, BankAccount, CashRegister)}
        self.stats: dict[str, dict[str, int]] = defaultdict(lambda: {"created": 0, "updated": 0, "unchanged": 0})
        self.warnings: list[str] = []
        self.currency_ids: dict[int, int] = {}
        # Physical source deletes cannot silently leave active native postings.
        # Full snapshots retain raw history; reconciliation of financial removals
        # requires an explicit correction in Sepidar rather than deleting ledgers here.
        source_ids = {**SOURCE_IDS, **(OPERATION_IDS if setting.operations_enabled else {})}
        source_id_sets = {table: {str(r[key]) for r in self.data[table]} for table, key in source_ids.items()}
        for (table, source_id), mapping in self.maps.items():
            if table in source_ids and source_id not in source_id_sets[table]:
                raise NativeConversionError(f"Source identity missing; reconciliation required: {table}/{source_id}")

    def target(self, table: str, source_id: Any, *, optional: bool = False):
        if source_id is None:
            if optional:
                return None
            raise NativeConversionError(f"Missing reference: {table}")
        mapping = self.maps.get((table, str(source_id)))
        if not mapping:
            raise NativeConversionError(f"Unresolved source reference: {table}/{source_id}")
        obj = self.targets[mapping.target_table].get(mapping.target_id)
        if not obj:
            raise NativeConversionError(f"Native target missing: {table}/{source_id}")
        return obj

    def upsert(self, table: str, source_id: Any, model, payload: Any, fields: dict, *, reuse=None):
        key = (table, str(source_id))
        hashed = fingerprint(payload)
        mapping = self.maps.get(key)
        if mapping:
            obj = self.target(table, source_id)
            if reuse is not None and obj.id != reuse.id:
                raise NativeConversionError(f"Source financial linkage changed; reconciliation required: {table}/{source_id}")
            if mapping.source_hash == hashed:
                self.stats[table]["unchanged"] += 1
                return obj, False
            for name, value in fields.items():
                setattr(obj, name, value)
            mapping.source_hash = hashed
            self.stats[table]["updated"] += 1
            return obj, True
        obj = reuse
        if obj is None:
            obj = model(**fields)
            self.db.add(obj)
            self.db.flush()
            self.targets[model.__tablename__][obj.id] = obj
        else:
            for name, value in fields.items():
                setattr(obj, name, value)
        mapping = SepidarNativeMap(business_id=self.bid, database_name=self.setting.database_name,
                                  source_table=table, source_id=str(source_id), target_table=model.__tablename__,
                                  target_id=obj.id, source_hash=hashed)
        self.db.add(mapping)
        self.maps[key] = mapping
        self.stats[table]["created"] += 1
        return obj, True

    def meta(self, existing=None, **source) -> dict:
        extra = dict(existing.extra_info or {}) if existing else {}
        extra["sepidar"] = {**extra.get("sepidar", {}), "managed": True, "database": self.setting.database_name, **source}
        return extra

    def reference_data(self):
        aliases = {"ریال": "IRR", "دلار": "USD", "یورو": "EUR", "پوند انگلیس": "GBP", "درهم امارات": "AED"}
        currencies = {c.code: c for c in self.db.scalars(select(Currency))}
        used = {int(r.get("CurrencyRef") or 1) for spec in INVOICES for r in self.data[spec[0]]}
        for row in self.data["GNR.Currency"]:
            title = str(row["Title"]).replace("ي", "ی").replace("ك", "ک").strip()
            code = aliases.get(title) or (row.get("Title_En") if row.get("Title_En") in currencies else None)
            if not code or code not in currencies:
                if int(row["CurrencyID"]) in used:
                    raise NativeConversionError(f"Unresolved used currency: {row['CurrencyID']}")
                continue
            self.currency_ids[int(row["CurrencyID"])] = currencies[code].id
        self.base_currency = self.currency_ids.get(1)
        if self.base_currency != self.business.default_currency_id:
            raise NativeConversionError("Destination base currency differs from Sepidar base currency")
        existing = {r.currency_id for r in self.db.scalars(select(BusinessCurrency).where(BusinessCurrency.business_id == self.bid))}
        for cid in set(self.currency_ids.values()) - existing:
            self.db.add(BusinessCurrency(business_id=self.bid, currency_id=cid))
        latest = max(self.data["FMK.FiscalYear"], key=lambda r: source_date(r["StartDate"]))["FiscalYearId"]
        for row in self.data["FMK.FiscalYear"]:
            self.upsert("FMK.FiscalYear", row["FiscalYearId"], FiscalYear, {"row": row, "latest": latest}, {
                "business_id": self.bid, "title": row["Title"], "start_date": source_date(row["StartDate"]),
                "end_date": source_date(row["EndDate"]), "is_last": row["FiscalYearId"] == latest})
        stocks = sorted(self.data["INV.Stock"], key=lambda r: int(r["StockID"]))
        for index, row in enumerate(stocks):
            self.upsert("INV.Stock", row["StockID"], Warehouse, row, {"business_id": self.bid, "code": str(row["Code"]),
                "name": row["Title"], "address": row.get("Address"), "phone": row.get("Phone"),
                "warehouse_keeper": row.get("StockClerk"), "is_default": index == 0})

    def persons_products(self):
        dls = {r["DLId"]: r for r in self.data["ACC.DL"]}
        self.party_by_dl = {}
        addresses, phones = defaultdict(list), defaultdict(list)
        for r in self.data["GNR.PartyAddress"]:
            addresses[r["PartyRef"]].append(r)
        for r in self.data["GNR.PartyPhone"]:
            phones[r["PartyRef"]].append(r)
        for row in self.data["GNR.Party"]:
            sid = row["PartyId"]
            phone_rows = sorted(phones[sid], key=lambda r: (not r.get("IsMain"), r["PartyPhoneId"]))
            mobiles, landlines = [], []
            for p in phone_rows:
                value = str(p.get("Phone") or "").strip()
                if len(value) > 20:
                    raise NativeConversionError(f"Phone exceeds native length: GNR.Party/{sid}")
                if value:
                    digits = value.replace(" ", "").replace("-", "").replace("+98", "0")
                    (mobiles if digits.startswith("09") else landlines).append(value)
            addr = sorted(addresses[sid], key=lambda r: (not r.get("IsMain"), r["PartyAddressId"]))
            address = addr[0] if addr else {}
            full_name = " ".join(str(row.get(k) or "").strip() for k in ("Name", "LastName")).strip() or f"سپیدار {sid}"
            roles = [label for key, label in (("IsCustomer", "مشتری"), ("IsVendor", "تامین‌کننده"), ("IsBroker", "بازاریاب"), ("IsEmployee", "کارمند")) if row.get(key)] or ["همکار"]
            code = str(dls.get(row.get("DLRef"), {}).get("Code") or sid)
            code = int(code) if code.isdigit() and int(code) <= 2147483647 else int(sid)
            person, _ = self.upsert("GNR.Party", sid, Person, {"row": row, "addresses": addresses[sid], "phones": phones[sid]}, {
                "business_id": self.bid, "code": code, "alias_name": full_name,
                "first_name": row.get("Name"), "last_name": row.get("LastName"),
                "company_name": full_name if row.get("Type") == 2 else None,
                "legal_entity_type": "legal" if row.get("Type") == 2 else "natural",
                "person_types": json.dumps(roles, ensure_ascii=False), "national_id": row.get("IdentificationCode"),
                "economic_id": row.get("EconomicCode"), "registration_number": row.get("RegistrationCode"),
                "email": row.get("Email"), "website": row.get("Website"),
                "credit_limit": decimal(row.get("MaximumCredit")) if row.get("MaximumCredit") is not None else None,
                "credit_check_enabled": bool(row.get("HasCredit")), "address": address.get("Address"), "postal_code": address.get("ZipCode"),
                "phone": landlines[0] if landlines else None, "mobile": mobiles[0] if mobiles else None,
                "mobile_2": mobiles[1] if len(mobiles) > 1 else None, "mobile_3": mobiles[2] if len(mobiles) > 2 else None})
            if row.get("DLRef") is not None:
                self.party_by_dl[row["DLRef"]] = person.id
        units = {r["UnitID"]: r["Title"] for r in self.data["INV.Unit"]}
        for row in self.data["INV.Item"]:
            warehouse = self.target("INV.Stock", row.get("DefaultStockRef"), optional=True)
            unit = units.get(row.get("UnitRef")); secondary = units.get(row.get("SecondaryUnitRef"))
            self.upsert("INV.Item", row["ItemID"], Product, {"row": row, "unit": unit, "secondary": secondary}, {
                "business_id": self.bid, "code": str(row["Code"]), "name": row["Title"],
                "item_type": ProductItemType.PRODUCT if row.get("Type") == 1 else ProductItemType.SERVICE,
                "main_unit": unit, "secondary_unit": secondary, "unit_conversion_factor": decimal(row["UnitsRatio"]) if row.get("UnitsRatio") else None,
                "general_barcodes": row.get("BarCode"), "is_active": bool(row.get("IsActive", True)),
                "track_inventory": row.get("Type") == 1, "track_serial": bool(row.get("SerialTracking")),
                "default_warehouse_id": warehouse.id if warehouse else None,
                "is_sales_taxable": not row.get("TaxExempt", False), "is_purchase_taxable": not row.get("TaxExemptPurchase", False),
                "sales_tax_rate": decimal(row.get("TaxRate")), "purchase_tax_rate": decimal(row.get("TaxRate")), "tax_code": row.get("IranCode")})

    def accounts(self):
        source = {r["AccountId"]: r for r in self.data["ACC.Account"]}
        resolved = set()
        def visit(sid, path):
            if sid in resolved:
                return self.target("ACC.Account", sid)
            if sid in path or sid not in source:
                raise NativeConversionError("Invalid source account hierarchy")
            row = source[sid]
            parent = visit(row["ParentAccountRef"], path | {sid}) if row.get("ParentAccountRef") else None
            ancestors = [row]
            while ancestors[0].get('ParentAccountRef'):
                ancestors.insert(0, source[ancestors[0]['ParentAccountRef']])
            source_path = '.'.join(str(r['Code']) for r in ancestors)
            code = f"{account_report_prefix(ancestors)}.SPD.{source_path}"
            # The source's universal root is not a report section. Financial
            # group roots must be discoverable by native balance-sheet reports.
            native_parent = parent if parent and source[row['ParentAccountRef']].get('Type') != 0 else None
            if len(code) > 50:
                raise NativeConversionError("Source account path exceeds native code length")
            obj, _ = self.upsert("ACC.Account", sid, Account, {"row": row, "code": code, "version": 2}, {
                "business_id": self.bid, "name": row["Title"], "code": code,
                "account_type": "accounting_document",
                "parent_id": native_parent.id if native_parent else None})
            resolved.add(sid)
            return obj
        for sid in source:
            visit(sid, set())

    def ledger(self):
        self.vouchers = {r["VoucherId"]: r for r in self.data["ACC.Voucher"]}
        self.voucher_hashes = {}
        by_voucher = defaultdict(list)
        for row in self.data["ACC.VoucherItem"]:
            by_voucher[row["VoucherRef"]].append(row)
        for sid, row in self.vouchers.items():
            lines = sorted(by_voucher[sid], key=lambda r: r["VoucherItemId"])
            validate_voucher(lines)
            year = self.target("FMK.FiscalYear", row["FiscalYearRef"])
            day = source_date(row["Date"])
            if not year.start_date <= day <= year.end_date:
                raise NativeConversionError(f"Voucher date outside fiscal year: ACC.Voucher/{sid}")
            existing = self.target("ACC.Voucher", sid) if ("ACC.Voucher", str(sid)) in self.maps else None
            extra = self.meta(existing, voucher_id=sid, voucher_number=row["Number"], voucher_state=row.get("State"))
            original = {"header": row, "lines": lines}
            self.voucher_hashes[sid] = fingerprint(original)
            fields = {"business_id": self.bid, "fiscal_year_id": year.id, "currency_id": self.base_currency,
                "created_by_user_id": self.business.owner_id, "document_date": day,
                "code": existing.code if existing and (extra["sepidar"].get("invoice_table") or extra['sepidar'].get('operational_table')) else f"SPD-V-{row['FiscalYearRef']}-{row['Number']}-{sid}",
                "document_type": existing.document_type if existing and (extra["sepidar"].get("invoice_table") or extra['sepidar'].get('operational_table')) else "manual",
                "description": row.get("Description"), "is_proforma": False, "extra_info": extra}
            document, changed = self.upsert("ACC.Voucher", sid, Document, original, fields)
            if changed:
                self.db.execute(delete(DocumentLine).where(DocumentLine.document_id == document.id))
                for line in lines:
                    account = self.target("ACC.Account", line["AccountSLRef"])
                    self.db.add(DocumentLine(document_id=document.id, account_id=account.id,
                        person_id=self.party_by_dl.get(line.get("DLRef")), debit=money(line.get("Debit")), credit=money(line.get("Credit")),
                        exchange_rate=Decimal(1), debit_base=money(line.get("Debit")), credit_base=money(line.get("Credit")),
                        description=line.get("Description"), extra_info={"sepidar_voucher_item_id": line["VoucherItemId"], "sepidar_dl_ref": line.get("DLRef"),
                            "tracking_number": line.get("TrackingNumber"), "tracking_date": line.get("TrackingDate"),
                            "source_currency_ref": line.get("CurrencyRef"), "source_currency_debit": line.get("CurrencyDebit"), "source_currency_credit": line.get("CurrencyCredit")}))

    def invoices(self):
        links = Counter(row.get(spec[7]) for spec in INVOICES if spec[7] for row in self.data[spec[0]] if row.get(spec[7]))
        for table, id_key, child, parent_key, doc_type, prefix, net_key, voucher_key in INVOICES:
            by_header = defaultdict(list)
            for line in self.data[child]:
                by_header[line[parent_key]].append(line)
            for row in self.data[table]:
                sid = row[id_key]
                lines = sorted(by_header[sid], key=lambda r: (r.get("RowID", r.get("RowNumber", 0)), fingerprint(r)))
                validate_invoice(row, lines, net_key)
                person_id = self.party_by_dl.get(row.get("VendorDLRef")) if prefix == "P" else self.target("GNR.Party", row.get("CustomerPartyRef")).id
                if not person_id:
                    raise NativeConversionError(f"Unresolved invoice person: {table}/{sid}")
                year = self.target("FMK.FiscalYear", row["FiscalYearRef"])
                currency_id = self.currency_ids.get(int(row.get("CurrencyRef") or 1))
                if not currency_id:
                    raise NativeConversionError(f"Unresolved invoice currency: {table}/{sid}")
                day = source_date(row["Date"])
                if not year.start_date <= day <= year.end_date:
                    raise NativeConversionError(f"Invoice date outside fiscal year: {table}/{sid}")
                voucher_id = row.get(voucher_key) if voucher_key else None
                voucher = self.vouchers.get(voucher_id)
                ledger_doc = self.target("ACC.Voucher", voucher_id) if voucher else None
                reuse = ledger_doc if voucher and links[voucher_id] == 1 and day == source_date(voucher["Date"]) and year.id == ledger_doc.fiscal_year_id and currency_id == ledger_doc.currency_id else None
                existing = self.target(table, sid) if (table, str(sid)) in self.maps else reuse
                extra = self.meta(existing, invoice_table=table, invoice_id=sid, invoice_number=row["Number"], invoice_state=row.get("State"),
                                  ledger_document_id=ledger_doc.id if ledger_doc else None)
                purchase = prefix == "P"
                gross = decimal(row.get("TotalPrice" if purchase else "Price"))
                discount = sum((decimal(l.get("Discount")) for l in lines), Decimal(0))
                tax = sum((decimal(l.get("Tax")) + decimal(l.get("Duty")) + decimal(l.get("TransportTax")) + decimal(l.get("TransportDuty")) for l in lines), Decimal(0))
                net = decimal(row[net_key])
                extra.update({"person_id": person_id, "post_inventory": False, "auto_post_warehouse": False,
                    "accounting_source": "sepidar_voucher", "accounting_posted": bool(ledger_doc),
                    # Sepidar NetPrice already contains source additions/freight.
                    # Native payable = net + header adjustments; adding them a
                    # second time changes balances. Keep the original breakdown
                    # separately, with a native row-total-compatible gross.
                    "totals": {"gross": float(net + discount - tax), "discount": float(discount), "tax": float(tax), "net": float(net),
                               "adjustments_net": 0.0, "adjustments_tax": 0.0}})
                extra['sepidar']['source_gross'] = str(gross)
                extra['sepidar']['source_additions_net'] = str(net - gross + discount - tax)
                aggregate = {"version": 2, "header": row, "lines": lines, "voucher_hash": self.voucher_hashes.get(voucher_id)}
                document, changed = self.upsert(table, sid, Document, aggregate, {"business_id": self.bid,
                    "code": f"SPD-{prefix}-{row['FiscalYearRef']}-{row['Number']}-{sid}", "fiscal_year_id": year.id,
                    "currency_id": currency_id, "created_by_user_id": self.business.owner_id, "document_date": day,
                    "document_type": doc_type, "is_proforma": prefix == "Q", "description": row.get("Description") or (ledger_doc.description if ledger_doc else None), "extra_info": extra}, reuse=reuse)
                if changed:
                    self.db.execute(delete(InvoiceItemLine).where(InvoiceItemLine.document_id == document.id))
                    for line in lines:
                        product = self.target("INV.Item", line["ItemRef"])
                        warehouse = self.target("INV.Stock", line.get("StockRef"), optional=True)
                        quantity = decimal(line["Quantity"])
                        info = {"unit_price": float(decimal(line.get("Fee"))), "line_total": float(decimal(line["NetPrice"])),
                            "line_discount": float(decimal(line.get("Discount"))), "tax_amount": float(decimal(line.get("Tax")) + decimal(line.get("Duty"))),
                            "source_price": float(decimal(line.get("Price"))), "sepidar_source": child,
                            "sepidar_row_id": line.get("InvoiceItemID", line.get("ReturnedInvoiceItemID", line.get("InventoryPurchaseInvoiceItemID", line.get("QuotationItemID")))),
                            "warehouse_id": warehouse.id if warehouse else None, "inventory_posted": False,
                            "movement": "in" if doc_type in {"invoice_purchase", "invoice_sales_return"} else "out",
                            "sepidar_adjustments": {k: line.get(k) for k in ("Addition", "Duty", "TransportPrice", "TransportTax", "TransportDuty", "InsuranceAmount", "WithHoldingTaxAmount")}}
                        self.db.add(InvoiceItemLine(document_id=document.id, product_id=product.id, quantity=quantity,
                                                    description=line.get("Description"), extra_info=info))

    def run(self):
        self.reference_data()
        self.persons_products()
        self.accounts()
        self.ledger()
        self.invoices()
        operation_summary = None
        if self.setting.operations_enabled:
            # Production sessions disable autoflush. Inventory links/costs must
            # see the freshly replaced invoice rows, not their deleted versions.
            self.db.flush()
            from app.services.sepidar_operations_service import OperationsProjector
            operations = OperationsProjector(self)
            operations.run()
            operation_summary = {'priced_lines':operations.priced,'unpriced_lines':operations.unpriced}
        self.db.flush()
        return {"completed_at": datetime.now(timezone.utc).isoformat(), "database": self.setting.database_name,
                "entities": dict(self.stats), "warnings": self.warnings,
                "operations": operation_summary,
                "policy": "source_managed; original voucher lines posted once; source-only costing; explicit fiscal carry reset"}


def project_native(db: Session, business_id: int) -> dict:
    """Called under the import's business lock, one atomic native transaction."""
    try:
        setting = db.scalars(select(SepidarImportSetting).where(SepidarImportSetting.business_id == business_id)).one()
        with db.begin_nested():
            summary = Projector(db, setting).run()
            setting.native_summary = summary
            setting.native_last_error = None
        db.commit()
    except Exception as exc:
        db.rollback()
        setting = db.scalars(select(SepidarImportSetting).where(SepidarImportSetting.business_id == business_id)).one()
        setting.native_last_error = str(exc)[:500] if isinstance(exc, NativeConversionError) else f"Native projection failed ({type(exc).__name__})"
        db.commit()
        raise
    from app.core.cache import get_cache
    cache = get_cache()
    if cache.enabled:
        # Source updates affect entity lists, invoice totals, person balances and reports.
        for pattern in (f"*:{business_id}:*", f"*:{business_id}", "user_businesses:*"):
            cache.delete_pattern(pattern)
    return summary
