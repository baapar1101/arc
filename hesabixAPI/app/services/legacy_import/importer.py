from __future__ import annotations

import logging
from datetime import datetime
from typing import Any, Callable, Dict, Optional

from sqlalchemy import and_
from sqlalchemy.orm import Session

from adapters.api.v1.schemas import BusinessCreateRequest, FiscalYearCreate
from adapters.db.models.bank_account import BankAccount
from adapters.db.models.business import Business
from adapters.db.models.category import BusinessCategory
from adapters.db.models.currency import Currency
from adapters.db.models.person import Person
from adapters.db.models.product import Product, ProductItemType
from adapters.db.models.warehouse import Warehouse
from app.core.responses import ApiError
from app.services.business_backup_financial_policy import (
    compute_backup_checksum,
    finalize_financial_state_after_restore,
    guard_new_business_import,
    register_backup_import,
)
from app.services.business_service import create_business
from app.services.file_storage_service import FileStorageService
from app.services.legacy_import.archive import parse_legacy_archive
from app.services.legacy_import.client import LegacyApiClient
from app.services.legacy_import.constants import IMPORT_MODE_LEGACY_API
from app.services.legacy_import.context import reset_legacy_import_active, set_legacy_import_active
from app.services.legacy_import.document_importer import LegacyDocumentImporter
from app.services.legacy_import.id_map import LegacyIdMap, LegacyImportStats
from app.services.legacy_import.mappers import (
    epoch_to_date,
    khadamat_to_item_type,
    map_business_field,
    map_business_type,
    map_legacy_person_types,
    person_alias,
    person_types_json,
    safe_decimal,
    safe_int,
    sanitize_business_name,
    split_person_name,
)
from app.services.legacy_import.preview_service import LegacyImportOptions

logger = logging.getLogger(__name__)


class LegacyBusinessImporter:
    """Orchestrates full legacy → v2 business import inside one DB transaction."""

    def __init__(
        self,
        db: Session,
        owner_id: int,
        server_url: str,
        api_key: str,
        options: Optional[LegacyImportOptions] = None,
        progress_callback: Optional[Callable[[int, str], None]] = None,
    ) -> None:
        self.db = db
        self.owner_id = owner_id
        self.client = LegacyApiClient(server_url, api_key)
        self.options = options or LegacyImportOptions()
        self.progress = progress_callback or (lambda _p, _m: None)
        self.id_map = LegacyIdMap()
        self.stats = LegacyImportStats()
        self.person_type_map: Dict[int, str] = {}
        self._currency_id: int = 0

    def run(self, *, archive_bytes: Optional[bytes] = None) -> Dict[str, Any]:
        token = set_legacy_import_active(True)
        try:
            return self._run_import(archive_bytes=archive_bytes)
        finally:
            reset_legacy_import_active(token)

    def _run_import(self, *, archive_bytes: Optional[bytes] = None) -> Dict[str, Any]:
        self.progress(5, "Connecting to legacy server")
        connection = self.client.test_connection()
        self.person_type_map = self.client.fetch_person_type_map()

        self.progress(10, "Downloading archive")
        raw = archive_bytes if archive_bytes is not None else self.client.download_archive()
        archive = parse_legacy_archive(raw)
        checksum = compute_backup_checksum(raw)

        guard_new_business_import(
            self.db,
            user_id=self.owner_id,
            backup_checksum=checksum,
            import_mode=IMPORT_MODE_LEGACY_API,
        )

        self.progress(15, "Creating business")
        business_id, currency_id = self._create_business(archive, connection)
        self._currency_id = currency_id

        if self.options.import_persons:
            self.progress(35, "Importing persons")
            self._import_persons(business_id, archive)

        if self.options.import_products:
            self.progress(45, "Importing products")
            self._import_categories_and_products(business_id, archive)

        if self.options.import_banks:
            self.progress(52, "Importing bank accounts")
            self._import_bank_accounts(business_id, archive)

        if self.options.import_warehouses:
            self.progress(58, "Importing warehouses")
            self._import_warehouses(business_id, archive)

        if self.options.import_documents:
            self.progress(70, "Importing accounting documents")
            LegacyDocumentImporter(
                self.db,
                business_id,
                self.owner_id,
                currency_id,
                self.id_map,
                self.stats,
                legacy_client=self.client,
            ).import_all(archive)

        if self.options.import_files:
            self.progress(88, "Importing logo and seal")
            self._import_files(business_id, archive)

        self.progress(92, "Finalizing financial state")
        finalize_financial_state_after_restore(self.db, business_id)

        register_backup_import(
            self.db,
            user_id=self.owner_id,
            backup_checksum=checksum,
            import_mode=IMPORT_MODE_LEGACY_API,
            source_business_id=archive.source_business_id,
            target_business_id=business_id,
        )

        self.progress(100, "Import completed")
        return {
            "business_id": business_id,
            "source_business_id": archive.source_business_id,
            "source_business_name": archive.source_business_name,
            "stats": self.stats.to_dict(),
            "id_map_summary": self.id_map.summary(),
            "archive_checksum": checksum,
        }

    def _create_business(
        self,
        archive,
        connection: Dict[str, Any],
    ) -> tuple[int, int]:
        biz_rows = archive.data.get("business.json") or []
        legacy_biz = biz_rows[0] if biz_rows else {}
        api_biz = connection.get("business") or {}

        name = self.options.business_name_override
        if not name:
            name = sanitize_business_name(
                str(legacy_biz.get("name") or api_biz.get("name") or "کسب‌وکار"),
                suffix=self.options.business_name_suffix or "",
            )

        currency_id = self._resolve_currency_id(archive)
        fiscal_years = self._build_fiscal_years(archive)

        req = BusinessCreateRequest(
            name=name,
            business_type=map_business_type(legacy_biz.get("type") or api_biz.get("type")),
            business_field=map_business_field(legacy_biz.get("field") or api_biz.get("field")),
            address=legacy_biz.get("address") or api_biz.get("address"),
            phone=legacy_biz.get("tel") or api_biz.get("tel"),
            mobile=legacy_biz.get("mobile") or api_biz.get("mobile"),
            national_id=legacy_biz.get("shenasemeli") or None,
            registration_number=legacy_biz.get("shomaresabt") or None,
            economic_id=legacy_biz.get("codeeghtesadi") or None,
            country=legacy_biz.get("country") or api_biz.get("country"),
            province=legacy_biz.get("ostan") or api_biz.get("ostan"),
            city=legacy_biz.get("shahrestan") or api_biz.get("shahrestan"),
            postal_code=legacy_biz.get("postalcode") or api_biz.get("postalcode"),
            default_currency_id=currency_id,
            currency_ids=[currency_id],
            fiscal_years=fiscal_years,
            include_sample_data=False,
        )

        created = create_business(
            self.db,
            req,
            self.owner_id,
            defer_commit=True,
        )
        return int(created["id"]), currency_id

    def _resolve_currency_id(self, archive) -> int:
        monies = archive.data.get("money_used.json") or []
        code = "IRR"
        if monies and monies[0].get("name"):
            code = str(monies[0]["name"]).strip().upper()
        row = self.db.query(Currency).filter(Currency.code == code).first()
        if not row:
            row = self.db.query(Currency).filter(Currency.code == "IRR").first()
        if not row:
            raise ApiError(
                "CURRENCY_NOT_FOUND",
                "ارز پیش‌فرض در سیستم یافت نشد",
                http_status=500,
            )
        return int(row.id)

    def _build_fiscal_years(self, archive) -> list[FiscalYearCreate]:
        years = archive.data.get("years.json") or []
        result: list[FiscalYearCreate] = []
        last_marked = False
        for y in years:
            start = epoch_to_date(y.get("start"))
            end = epoch_to_date(y.get("end"))
            if not start or not end:
                continue
            is_last = bool(y.get("head"))
            if is_last:
                last_marked = True
            result.append(
                FiscalYearCreate(
                    title=str(y.get("label") or "سال مالی"),
                    start_date=start,
                    end_date=end,
                    is_last=is_last,
                )
            )
        if result and not last_marked:
            result[-1].is_last = True
        if not result:
            today = datetime.utcnow().date()
            result.append(
                FiscalYearCreate(
                    title="سال مالی جاری",
                    start_date=today.replace(month=1, day=1),
                    end_date=today.replace(month=12, day=29),
                    is_last=True,
                )
            )
        return result

    def _import_persons(self, business_id: int, archive) -> None:
        for row in archive.data.get("persons.json") or []:
            old_id = row.get("id")
            code = safe_int(row.get("code"))
            if code is None:
                self.stats.persons_skipped += 1
                continue
            exists = (
                self.db.query(Person)
                .filter(and_(Person.business_id == business_id, Person.code == code))
                .first()
            )
            if exists:
                if old_id is not None:
                    self.id_map.set("persons", int(old_id), int(exists.id))
                self.stats.persons_skipped += 1
                continue

            types = map_legacy_person_types(
                row.get("type_ids"),
                type_id_to_label=self.person_type_map or None,
            )
            first, last = split_person_name(row.get("name"))
            person = Person(
                business_id=business_id,
                code=code,
                alias_name=person_alias(row.get("nikename"), row.get("name")),
                first_name=first,
                last_name=last,
                person_types=person_types_json(types),
                national_id=row.get("shenasemeli") or None,
                economic_id=row.get("codeeghtesadi") or None,
                address=row.get("address") or None,
                phone=row.get("tel") or None,
                mobile=row.get("mobile") or None,
                email=row.get("email") or None,
            )
            self.db.add(person)
            self.db.flush()
            if old_id is not None:
                self.id_map.set("persons", int(old_id), int(person.id))
            self.stats.persons_imported += 1

    def _import_categories_and_products(self, business_id: int, archive) -> None:
        unit_map: Dict[int, str] = {}
        for u in archive.data.get("commodity_units.json") or []:
            uid = u.get("id")
            if uid is not None and u.get("name"):
                unit_map[int(uid)] = str(u["name"])

        for cat in archive.data.get("commodity_cats.json") or []:
            old_cid = cat.get("id")
            name = str(cat.get("name") or "دسته‌بندی").strip()
            found = None
            for c in self.db.query(BusinessCategory).filter(
                BusinessCategory.business_id == business_id
            ):
                titles = c.title_translations or {}
                if titles.get("fa") == name:
                    found = c
                    break
            if found:
                if old_cid is not None:
                    self.id_map.set("categories", int(old_cid), int(found.id))
                continue
            obj = BusinessCategory(
                business_id=business_id,
                title_translations={"fa": name},
                sort_order=0,
                is_active=True,
            )
            self.db.add(obj)
            self.db.flush()
            if old_cid is not None:
                self.id_map.set("categories", int(old_cid), int(obj.id))
            self.stats.categories_imported += 1

        for row in archive.data.get("commodities.json") or []:
            old_id = row.get("id")
            code = str(row.get("code") or "").strip()
            if not code:
                self.stats.products_skipped += 1
                continue
            exists = (
                self.db.query(Product)
                .filter(and_(Product.business_id == business_id, Product.code == code))
                .first()
            )
            if exists:
                if old_id is not None:
                    self.id_map.set("products", int(old_id), int(exists.id))
                self.stats.products_skipped += 1
                continue

            cat_id = self.id_map.get("categories", row.get("cat_id"))
            unit_name = unit_map.get(int(row["unit_id"])) if row.get("unit_id") else None
            item_type = (
                ProductItemType.SERVICE
                if khadamat_to_item_type(row.get("khadamat")) == "service"
                else ProductItemType.PRODUCT
            )
            product = Product(
                business_id=business_id,
                item_type=item_type,
                code=code[:64],
                name=str(row.get("name") or code)[:255],
                description=row.get("des"),
                category_id=cat_id,
                main_unit=unit_name,
                base_purchase_price=safe_decimal(row.get("priceBuy")),
                base_sales_price=safe_decimal(row.get("priceSell")),
                track_inventory=False,
                inventory_mode="bulk",
            )
            self.db.add(product)
            self.db.flush()
            if old_id is not None:
                self.id_map.set("products", int(old_id), int(product.id))
            self.stats.products_imported += 1

    def _import_bank_accounts(self, business_id: int, archive) -> None:
        currency_id = self._currency_id
        next_auto_code = 100
        for row in archive.data.get("bank_accounts.json") or []:
            old_id = row.get("id")
            name = str(row.get("name") or "بانک").strip()
            code = str(row.get("code") or old_id or "")
            if not code.isdigit() or len(code) < 3:
                code = str(next_auto_code)
                next_auto_code += 1

            exists = (
                self.db.query(BankAccount)
                .filter(and_(BankAccount.business_id == business_id, BankAccount.code == code))
                .first()
            )
            if exists:
                if old_id is not None:
                    self.id_map.set("bank_accounts", int(old_id), int(exists.id))
                continue

            bank = BankAccount(
                business_id=business_id,
                code=code,
                name=name[:255],
                account_number=row.get("accountNum") or None,
                card_number=row.get("cardNum") or None,
                sheba_number=row.get("shaba") or None,
                currency_id=currency_id,
                is_active=True,
            )
            self.db.add(bank)
            self.db.flush()
            if old_id is not None:
                self.id_map.set("bank_accounts", int(old_id), int(bank.id))
            self.stats.bank_accounts_imported += 1

    def _import_warehouses(self, business_id: int, archive) -> None:
        default_set = False
        for row in archive.data.get("storerooms.json") or []:
            old_id = row.get("id")
            code = str(row.get("id") or row.get("code") or "").strip()
            if not code:
                continue
            exists = (
                self.db.query(Warehouse)
                .filter(and_(Warehouse.business_id == business_id, Warehouse.code == code))
                .first()
            )
            if exists:
                if old_id is not None:
                    self.id_map.set("warehouses", int(old_id), int(exists.id))
                continue
            wh = Warehouse(
                business_id=business_id,
                code=code[:64],
                name=str(row.get("name") or "انبار")[:255],
                warehouse_keeper=row.get("manager"),
                phone=row.get("tel"),
                address=row.get("adr"),
                is_default=not default_set,
            )
            default_set = True
            self.db.add(wh)
            self.db.flush()
            if old_id is not None:
                self.id_map.set("warehouses", int(old_id), int(wh.id))
            self.stats.warehouses_imported += 1

    def _import_files(self, business_id: int, archive) -> None:
        import asyncio
        from io import BytesIO

        from starlette.datastructures import UploadFile as StarletteUploadFile

        biz_rows = archive.data.get("business.json") or []
        if not biz_rows:
            return
        legacy = biz_rows[0]
        storage = FileStorageService(self.db)
        business = self.db.get(Business, business_id)
        if not business:
            return

        async def _upload_one(content: bytes, filename: str, module: str) -> Optional[str]:
            upload = StarletteUploadFile(
                file=BytesIO(content),
                filename=filename,
                headers={"content-type": "image/jpeg"},
            )
            result = await storage.upload_file(
                upload,
                user_id=self.owner_id,
                module_context=module,
                business_id=business_id,
                check_storage_limit=False,
                is_temporary=False,
            )
            return str(result.get("file_id") or result.get("id") or "")

        for field_name, file_key, module in (
            ("logo_file_id", legacy.get("avatar"), "business_logo"),
            ("stamp_file_id", legacy.get("sealFile"), "business_stamp"),
        ):
            if not file_key:
                continue
            zip_path = (
                f"files/avatars/{file_key}"
                if field_name == "logo_file_id"
                else f"files/seal/{file_key}"
            )
            content = archive.files.get(zip_path)
            if not content:
                for path, data in archive.files.items():
                    if path.endswith(str(file_key)):
                        content = data
                        break
            if not content:
                self.stats.add_warning(f"فایل {file_key} در آرشیو یافت نشد")
                continue
            try:
                fid = asyncio.run(_upload_one(content, str(file_key), module))
                if fid:
                    setattr(business, field_name, fid)
                    self.stats.files_imported += 1
            except Exception as exc:
                self.stats.add_warning(f"آپلود {file_key}: {exc}")
        self.db.flush()
