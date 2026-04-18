"""
دادهٔ نمونه برای کسب‌وکار تازه (فقط همراه ایجاد معمولی، نه ایمپورت .hbx).
"""
from __future__ import annotations

from sqlalchemy import and_
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.person import PersonCreateRequest, PersonType
from adapters.api.v1.schema_models.person_group import PersonGroupCreateRequest
from adapters.api.v1.schema_models.product import ProductCreateRequest
from adapters.api.v1.schema_models.warehouse import WarehouseCreateRequest
from adapters.db.models.business import Business
from adapters.db.models.warehouse import Warehouse
from adapters.db.repositories.category_repository import CategoryRepository
from app.core.responses import ApiError
from app.services.bank_account_service import create_bank_account
from app.services.cash_register_service import create_cash_register
from app.services.person_group_service import create_person_group
from app.services.person_service import create_person
from app.services.petty_cash_service import create_petty_cash
from app.services.product_service import create_product
from app.services.warehouse_service import create_warehouse


def seed_sample_data_for_new_business(db: Session, business_id: int, owner_id: int) -> None:
    """
    ایجاد مجموعهٔ حداقلی برای آزمایش: انبار، دسته و کالا، گروه شخص و دو مشتری، بانک، صندوق، تنخواه.
    هر مرحله از همان سرویس‌های موجود استفاده می‌کند (هر کدام تراکنش خود را دارد).
    """
    del owner_id  # آماده برای مجوز یا لاگ در آینده

    business = db.query(Business).filter(Business.id == business_id).first()
    if not business:
        raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)

    currency_id = business.default_currency_id
    if not currency_id:
        raise ApiError(
            "BUSINESS_DEFAULT_CURRENCY_REQUIRED",
            "برای ثبت دادهٔ نمونه، ارز پیش‌فرض کسب‌وکار الزامی است",
            http_status=400,
        )

    wh_payload = WarehouseCreateRequest(name="انبار اصلی", is_default=True)
    create_warehouse(db, business_id, wh_payload)

    default_wh = (
        db.query(Warehouse)
        .filter(and_(Warehouse.business_id == business_id, Warehouse.is_default.is_(True)))
        .first()
    )
    warehouse_id = default_wh.id if default_wh else None

    cat_repo = CategoryRepository(db)
    cat = cat_repo.create_category(
        business_id=business_id,
        parent_id=None,
        translations={"fa": "دسته نمونه", "en": "Sample category"},
        description=None,
    )
    category_id = cat.id

    prod_req = ProductCreateRequest(
        name="کالای نمونه",
        item_type="کالا",
        category_id=category_id,
        main_unit="عدد",
        description="ایجاد خودکار هنگام انتخاب «داده نمونه»",
        track_inventory=True if warehouse_id else False,
        default_warehouse_id=warehouse_id,
        inventory_mode="bulk",
    )
    create_product(db, business_id, prod_req)

    pg_req = PersonGroupCreateRequest(name="گروه مشتریان نمونه")
    pg_row = create_person_group(db, business_id, pg_req)
    group_id_raw = pg_row.get("id")
    if not group_id_raw:
        raise ApiError("SAMPLE_SEED_FAILED", "ایجاد گروه اشخاص ناموفق بود", http_status=500)
    group_id = int(group_id_raw)

    for label in ("مشتری 1", "مشتری 2"):
        person_req = PersonCreateRequest(
            alias_name=label,
            person_types=[PersonType.CUSTOMER],
            person_group_id=group_id,
        )
        create_person(db, business_id, person_req)

    create_bank_account(
        db,
        business_id,
        {
            "name": "حساب بانکی نمونه",
            "currency_id": currency_id,
            "is_default": True,
            "is_active": True,
        },
    )

    create_cash_register(
        db,
        business_id,
        {
            "name": "صندوق اصلی",
            "currency_id": currency_id,
            "is_default": True,
            "is_active": True,
        },
    )

    create_petty_cash(
        db,
        business_id,
        {
            "name": "تنخواه",
            "currency_id": currency_id,
            "is_default": True,
            "is_active": True,
        },
    )
