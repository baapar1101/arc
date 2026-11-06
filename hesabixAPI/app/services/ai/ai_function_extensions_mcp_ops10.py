"""MCP leftovers: warehouse-from-invoice, FX rates, opening-balance eligibility, tax link, persons bulk, storage extras."""
from __future__ import annotations

from typing import Any, Dict, List

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_commit, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

INV_ID = mcp_schema({"invoice_id": {"type": "integer", "minimum": 1}}, ["invoice_id"])
FROM_INV = mcp_schema(
    {
        "invoice_id": {"type": "integer", "minimum": 1},
        "lines": {"type": "array", "items": {"type": "object"}},
        "movement": {"type": "string", "enum": ["in", "out"]},
        "doc_type": {"type": "string", "maxLength": 40},
        "document_date": {"type": "string"},
        "description": {"type": "string", "maxLength": 500},
        "delivery_method": {"type": "string", "maxLength": 80},
        "carrier_name": {"type": "string", "maxLength": 80},
        "recipient_name": {"type": "string", "maxLength": 80},
        "recipient_phone": {"type": "string", "maxLength": 40},
        "tracking_number": {"type": "string", "maxLength": 80},
    },
    ["invoice_id"],
)
SRC_SEARCH = mcp_schema(
    {
        "invoice_type": {"type": "string", "maxLength": 40},
        "search": {"type": "string", "maxLength": 80},
        "include_completed": {"type": "boolean"},
        "skip": {"type": "integer", "minimum": 0},
        "take": {"type": "integer", "minimum": 1, "maximum": 50},
        "doc_type_hint": {"type": "string", "maxLength": 40},
    }
)
LINE_UPD = mcp_schema(
    {
        "warehouse_document_id": {"type": "integer", "minimum": 1},
        "line_id": {"type": "integer", "minimum": 1},
        "warehouse_id": {"type": "integer", "minimum": 1},
        "quantity": {"type": "number"},
    },
    ["warehouse_document_id", "line_id"],
)
BULK_WH = mcp_schema(
    {
        "operation": {"type": "string", "enum": ["create_draft", "remove_linked", "post_drafts"]},
        "invoice_ids": {"type": "array", "minItems": 1, "maxItems": 30, "items": {"type": "integer", "minimum": 1}},
        "existing_posted_policy": {
            "type": "string",
            "enum": ["skip", "post_drafts_only", "remove_all_then_create_and_post"],
        },
    },
    ["operation", "invoice_ids"],
)
BULK_DEL_WH = mcp_schema(
    {
        "ids": {
            "type": "array",
            "minItems": 1,
            "maxItems": 50,
            "uniqueItems": True,
            "items": {"type": "integer", "minimum": 1},
        },
    },
    ["ids"],
)
OB_PERSON = mcp_schema({"person_id": {"type": "integer", "minimum": 1}, "fiscal_year_id": {"type": "integer", "minimum": 1}})
OB_PROD = mcp_schema(
    {
        "product_id": {"type": "integer", "minimum": 1},
        "warehouse_id": {"type": "integer", "minimum": 1},
        "fiscal_year_id": {"type": "integer", "minimum": 1},
    }
)
TAX_LINK = mcp_schema(
    {"invoice_id": {"type": "integer", "minimum": 1}, "reference_invoice_id": {"type": "integer", "minimum": 1}},
    ["invoice_id", "reference_invoice_id"],
)
UPSERT = mcp_schema(
    {
        "items": {"type": "array", "minItems": 1, "maxItems": 50, "items": {"type": "object"}},
        "create_if_update_missing": {"type": "boolean"},
    },
    ["items"],
)
DEL_P = mcp_schema(
    {
        "ids": {"type": "array", "maxItems": 50, "items": {"type": "integer", "minimum": 1}},
        "codes": {"type": "array", "maxItems": 50, "items": {"type": "integer"}},
    }
)
APPLY_FX = mcp_schema({"items": {"type": "array", "minItems": 1, "maxItems": 40, "items": {"type": "object"}}, "note": {"type": "string"}}, ["items"])
BULK_RATES = mcp_schema(
    {
        "items": {"type": "array", "minItems": 1, "maxItems": 40, "items": {"type": "object"}},
        "note": {"type": "string"},
        "effective_at": {"type": "string"},
    },
    ["items"],
)
SYNC_ONE = mcp_schema(
    {
        "product_id": {"type": "integer", "minimum": 1},
        "force": {"type": "boolean"},
        "sync_price_list": {"type": "boolean"},
        "price_list_id": {"type": "integer", "minimum": 1},
    },
    ["product_id"],
)
SYNC_ALL = mcp_schema(
    {
        "only_auto": {"type": "boolean"},
        "product_ids": {"type": "array", "maxItems": 100, "items": {"type": "integer", "minimum": 1}},
        "sync_price_list": {"type": "boolean"},
    }
)
RENEW = mcp_schema({"subscription_id": {"type": "integer", "minimum": 1}}, ["subscription_id"])
OVER = mcp_schema({"over_usage_gb": {"type": "number", "exclusiveMinimum": 0}, "file_size_bytes": {"type": "integer", "minimum": 0}}, ["over_usage_gb"])
FILE_ID = mcp_schema({"file_id": {"type": "string", "minLength": 4, "maxLength": 64}}, ["file_id"])
SHARE_UPD = mcp_schema(
    {
        "share_id": {"type": "integer", "minimum": 1},
        "clear_password": {"type": "boolean"},
        "expires_in_days": {"type": ["integer", "null"], "minimum": 1, "maximum": 365},
        "set_expires": {"type": "boolean"},
    },
    ["share_id"],
)
EMPTY = mcp_schema({})


def _invoice(db, bid: int, invoice_id: int):
    from adapters.db.models.document import Document

    inv = db.query(Document).filter(Document.id == int(invoice_id), Document.business_id == int(bid)).first()
    if not inv:
        raise ValueError("فاکتور در این کسب‌وکار یافت نشد")
    return inv


def get_invoice_warehouse_line_quantities_handler(args, context):
    from app.services.warehouse_service import compute_invoice_line_quantities

    db, bid = mcp_db(context), mcp_bid(context)
    inv = _invoice(db, bid, int(args["invoice_id"]))
    return mcp_jsonable({"lines": mcp_run(compute_invoice_line_quantities, db, bid, inv)})


def create_warehouse_document_from_invoice_handler(args, context):
    from adapters.api.v1.warehouse_docs import _load_invoice_lines, _resolve_doc_type
    from app.services.warehouse_service import create_from_invoice

    db, bid = mcp_db(context), mcp_bid(context)
    inv = _invoice(db, bid, int(args["invoice_id"]))
    if bool(getattr(inv, "is_proforma", False)):
        raise ValueError("برای پیش‌فاکتور ایجاد حواله مجاز نیست")
    lines = args.get("lines")
    if not isinstance(lines, list) or not lines:
        lines = _load_invoice_lines(db, int(args["invoice_id"]))
    movement = str(args.get("movement") or "").strip().lower()
    if movement in ("in", "out"):
        lines = [ln for ln in lines if (ln.get("extra_info") or {}).get("movement") == movement]
        if not lines:
            raise ValueError("هیچ خطی با حرکت انتخاب‌شده یافت نشد")
    extra = {
        k: args[k]
        for k in ("document_date", "description", "delivery_method", "carrier_name", "recipient_name", "recipient_phone", "tracking_number")
        if args.get(k) is not None
    }
    wh_type = _resolve_doc_type(inv.document_type, movement or None, args.get("doc_type"))
    wh = mcp_run(create_from_invoice, db, bid, inv, lines, wh_type, mcp_uid(context), extra or None)
    mcp_commit(context)
    return {"id": wh.id, "code": wh.code, "status": wh.status}


def search_warehouse_invoice_sources_handler(args, context):
    from adapters.api.v1.warehouse_docs import _INVOICE_SOURCE_CONFIG
    from app.services.warehouse_service import search_invoices_for_warehouse_sources

    key = str(args.get("invoice_type") or "sales").strip().lower()
    cfg = _INVOICE_SOURCE_CONFIG.get(key)
    if not cfg:
        raise ValueError("نوع فاکتور معتبر نیست")
    take = max(1, min(50, int(args.get("take") or 20)))
    skip = max(0, int(args.get("skip") or 0))
    return mcp_jsonable(
        mcp_run(
            search_invoices_for_warehouse_sources,
            mcp_db(context),
            mcp_bid(context),
            list(cfg["invoice_types"]),
            doc_type_hint=args.get("doc_type_hint") or cfg.get("doc_type"),
            search_term=str(args.get("search") or ""),
            include_completed=bool(args.get("include_completed")),
            skip=skip,
            take=take,
        )
    )


def update_warehouse_document_line_handler(args, context):
    from app.services.warehouse_service import update_warehouse_document_line

    data = {k: args[k] for k in ("warehouse_id", "quantity") if k in args}
    wline = mcp_run(
        update_warehouse_document_line,
        mcp_db(context),
        mcp_bid(context),
        int(args["warehouse_document_id"]),
        int(args["line_id"]),
        data,
    )
    mcp_commit(context)
    return mcp_jsonable(
        {
            "id": wline.id,
            "product_id": wline.product_id,
            "warehouse_id": wline.warehouse_id,
            "movement": wline.movement,
            "quantity": float(wline.quantity),
        }
    )


def bulk_delete_warehouse_documents_handler(args, context):
    from app.services.warehouse_service import bulk_delete_warehouse_documents

    ids: List[int] = []
    seen = set()
    for x in args.get("ids") or []:
        i = int(x)
        if i not in seen:
            seen.add(i)
            ids.append(i)
    result = bulk_delete_warehouse_documents(mcp_db(context), mcp_bid(context), ids[:50])
    mcp_commit(context)
    return mcp_jsonable(result)


def bulk_warehouse_invoice_operations_handler(args, context):
    from adapters.db.session import SessionLocal
    from app.services.invoice_warehouse_bulk_service import run_bulk_warehouse_invoice_operation

    bid = mcp_bid(context)
    uid = mcp_uid(context)
    op = str(args["operation"]).strip().lower()
    policy = str(args.get("existing_posted_policy") or "skip").strip().lower()
    ids: List[int] = []
    seen = set()
    for x in args.get("invoice_ids") or []:
        i = int(x)
        if i not in seen:
            seen.add(i)
            ids.append(i)
    results = []
    for iid in ids[:30]:
        sess = SessionLocal()
        try:
            out = run_bulk_warehouse_invoice_operation(sess, bid, iid, op, uid, existing_posted_policy=policy)
            if out.get("ok"):
                sess.commit()
            else:
                sess.rollback()
            results.append({"invoice_id": iid, **out})
        except Exception as exc:
            sess.rollback()
            results.append({"invoice_id": iid, "ok": False, "code": "EXCEPTION", "message": str(exc)})
        finally:
            sess.close()
    return {"results": results, "operation": op, "existing_posted_policy": policy}


def get_person_opening_balance_eligibility_handler(args, context):
    from app.services.person_opening_balance_service import get_person_opening_balance_eligibility

    ctx = context.get("user_context")
    can_edit = bool(ctx and ctx.has_business_permission("opening_balance", "edit"))
    return mcp_jsonable(
        mcp_run(
            get_person_opening_balance_eligibility,
            mcp_db(context),
            mcp_bid(context),
            args.get("fiscal_year_id"),
            can_edit_opening_balance=can_edit,
            person_id=args.get("person_id"),
        )
    )


def get_product_opening_balance_eligibility_handler(args, context):
    from app.services.product_opening_balance_service import get_product_opening_balance_eligibility

    ctx = context.get("user_context")
    can_edit = bool(ctx and ctx.has_business_permission("opening_balance", "edit"))
    return mcp_jsonable(
        mcp_run(
            get_product_opening_balance_eligibility,
            mcp_db(context),
            mcp_bid(context),
            args.get("fiscal_year_id"),
            can_edit_opening_balance=can_edit,
            product_id=args.get("product_id"),
            warehouse_id=args.get("warehouse_id"),
        )
    )


def link_tax_workspace_reference_handler(args, context):
    from app.core.moadian_plugin_dependency import ensure_moadian_plugin_active
    from app.services.tax_reference_service import get_document_extra, link_reference_invoice

    db, bid = mcp_db(context), mcp_bid(context)
    mcp_run(ensure_moadian_plugin_active, db, bid)
    doc = _invoice(db, bid, int(args["invoice_id"]))
    ref = mcp_run(link_reference_invoice, db, bid, doc, int(args["reference_invoice_id"]))
    mcp_commit(context)
    return {
        "id": doc.id,
        "reference_invoice_id": int(args["reference_invoice_id"]),
        "reference_invoice_code": ref.code,
        "reference_tax_status": (get_document_extra(ref) or {}).get("tax_status"),
    }


def bulk_upsert_persons_handler(args, context):
    from app.services.person_bulk_upsert_service import bulk_upsert_persons_integration

    return mcp_jsonable(
        mcp_run(
            bulk_upsert_persons_integration,
            mcp_db(context),
            mcp_bid(context),
            context.get("user_context"),
            {"items": list(args.get("items") or [])[:50], "create_if_update_missing": bool(args.get("create_if_update_missing", True))},
        )
    )


def bulk_delete_persons_handler(args, context):
    from sqlalchemy import and_ as _and
    from adapters.db.models.person import Person
    from app.services.person_service import delete_person

    db, bid = mcp_db(context), mcp_bid(context)
    deleted = skipped = 0
    errors: List[str] = []
    ids = [int(x) for x in (args.get("ids") or [])][:50]
    codes = [int(x) for x in (args.get("codes") or [])][:50]
    for pid in ids:
        person = db.query(Person).filter(_and(Person.id == pid, Person.business_id == bid)).first()
        if person is None:
            skipped += 1
            errors.append(f"شخص با شناسه {pid} یافت نشد")
            continue
        ok, err = mcp_run(delete_person, db, pid, bid)
        if ok:
            deleted += 1
        else:
            skipped += 1
            errors.append(err or f"امکان حذف شخص {pid} وجود ندارد")
    if codes:
        items = db.query(Person).filter(_and(Person.business_id == bid, Person.code.in_(codes))).all()
        for obj in items:
            ok, err = mcp_run(delete_person, db, obj.id, bid)
            if ok:
                deleted += 1
            else:
                skipped += 1
                errors.append(err or f"امکان حذف شخص {obj.id} وجود ندارد")
    return {"deleted": deleted, "skipped": skipped, "errors": errors[:40]}


def list_business_fx_global_rates_handler(args, context):
    from app.services.fx_rate_provider_service import list_business_relevant_global_rates

    return mcp_jsonable(mcp_run(list_business_relevant_global_rates, mcp_db(context), mcp_bid(context)))


def apply_currency_rates_from_global_handler(args, context):
    from app.services.fx_rate_provider_service import apply_global_rates_to_business

    out = mcp_run(apply_global_rates_to_business, mcp_db(context), mcp_bid(context), mcp_uid(context), {"items": args.get("items") or [], "note": args.get("note")})
    mcp_commit(context)
    return mcp_jsonable(out)


def bulk_create_currency_rates_handler(args, context):
    from app.services.business_currency_rate_service import bulk_create_business_currency_rates

    payload: Dict[str, Any] = {"items": args.get("items") or []}
    if args.get("note") is not None:
        payload["note"] = args["note"]
    if args.get("effective_at") is not None:
        payload["effective_at"] = args["effective_at"]
    out = mcp_run(bulk_create_business_currency_rates, mcp_db(context), mcp_bid(context), mcp_uid(context), payload)
    mcp_commit(context)
    return mcp_jsonable(out)


def sync_product_base_price_from_fx_handler(args, context):
    from app.services.product_fx_price_service import sync_product_base_from_fx

    return mcp_jsonable(
        mcp_run(
            sync_product_base_from_fx,
            mcp_db(context),
            mcp_bid(context),
            int(args["product_id"]),
            force=bool(args.get("force", True)),
            sync_price_list=bool(args.get("sync_price_list")),
            price_list_id=args.get("price_list_id"),
        )
    )


def sync_products_base_prices_from_fx_handler(args, context):
    from app.services.product_fx_price_service import sync_business_products_base_from_fx

    return mcp_jsonable(
        mcp_run(
            sync_business_products_base_from_fx,
            mcp_db(context),
            mcp_bid(context),
            only_auto=bool(args.get("only_auto", True)),
            product_ids=args.get("product_ids"),
            sync_price_list=bool(args.get("sync_price_list")),
        )
    )


def finalize_document_monetization_volume_handler(args, context):
    from app.services.document_monetization_service import finalize_volume_periods

    out = mcp_run(finalize_volume_periods, mcp_db(context), business_id=mcp_bid(context))
    mcp_commit(context)
    return mcp_jsonable(out)


def renew_storage_subscription_handler(args, context):
    from app.services.storage_invoice_service import create_renewal_invoice

    out = mcp_run(create_renewal_invoice, mcp_db(context), mcp_bid(context), int(args["subscription_id"]))
    mcp_commit(context)
    return mcp_jsonable(out)


def pay_storage_over_usage_handler(args, context):
    from app.services.storage_invoice_service import create_over_usage_invoice, pay_storage_invoice_from_wallet

    db, bid = mcp_db(context), mcp_bid(context)
    invoice = mcp_run(create_over_usage_invoice, db, bid, float(args["over_usage_gb"]), args.get("file_size_bytes"))
    payment = mcp_run(pay_storage_invoice_from_wallet, db, bid, invoice["id"], mcp_uid(context))
    return mcp_jsonable({"invoice": invoice, "payment": payment})


def get_storage_file_dependencies_handler(args, context):
    from adapters.db.models.file_storage import FileStorage
    from app.services.file_dependency_service import FileDependencyService

    db, bid = mcp_db(context), mcp_bid(context)
    fs = (
        db.query(FileStorage)
        .filter(FileStorage.id == str(args["file_id"]), FileStorage.business_id == bid, FileStorage.deleted_at.is_(None))
        .first()
    )
    if not fs:
        raise ValueError("فایل یافت نشد")
    deps = FileDependencyService(db).get_dependencies(fs)
    return mcp_jsonable(
        {
            "file": {"id": str(fs.id), "name": fs.original_name, "module_context": fs.module_context, "context_id": fs.context_id},
            "dependencies": [d.to_dict() for d in deps],
        }
    )


def revoke_all_storage_file_shares_handler(args, context):
    from app.services.file_storage_share_service import revoke_all_for_business

    n = mcp_run(revoke_all_for_business, mcp_db(context), mcp_bid(context))
    return {"revoked_count": n}


def update_storage_file_share_handler(args, context):
    from app.services.file_storage_share_service import update_share

    return mcp_jsonable(
        mcp_run(
            update_share,
            mcp_db(context),
            mcp_bid(context),
            int(args["share_id"]),
            password=None,
            clear_password=bool(args.get("clear_password")),
            expires_in_days=args.get("expires_in_days"),
            set_expires=bool(args.get("set_expires") or ("expires_in_days" in args)),
        )
    )


def register_mcp_ops10_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(name="get_invoice_warehouse_line_quantities", description="مقدار حواله‌شده و باقی‌مانده هر ردیف فاکتور برای صدور حواله انبار.", parameters_schema=INV_ID, handler=get_invoice_warehouse_line_quantities_handler, allowed_roles=roles, required_permissions=["warehouses.view"], category="warehouse", is_readonly=True))
    registry.register(AIFunction(name="create_warehouse_document_from_invoice", description="صدور حواله پیش‌نویس از فاکتور قطعی. نیازمند تأیید.", parameters_schema=FROM_INV, handler=create_warehouse_document_from_invoice_handler, allowed_roles=roles, required_permissions=["warehouses.write"], category="warehouse", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="search_warehouse_invoice_sources", description="جستجوی فاکتورهای قابل صدور حواله (فروش/خرید و مشابه).", parameters_schema=SRC_SEARCH, handler=search_warehouse_invoice_sources_handler, allowed_roles=roles, required_permissions=["warehouses.view"], category="warehouse", is_readonly=True))
    registry.register(AIFunction(name="update_warehouse_document_line", description="ویرایش انبار یا مقدار یک خط حواله پیش‌نویس. نیازمند تأیید.", parameters_schema=LINE_UPD, handler=update_warehouse_document_line_handler, allowed_roles=roles, required_permissions=["warehouses.write"], category="warehouse", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="bulk_warehouse_invoice_operations", description="عملیات گروهی حواله روی چند فاکتور: پیش‌نویس، حذف پیوند، یا پست. نیازمند تأیید.", parameters_schema=BULK_WH, handler=bulk_warehouse_invoice_operations_handler, allowed_roles=roles, required_permissions=["warehouses.write"], category="warehouse", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="bulk_delete_warehouse_documents", description="حذف گروهی حداکثر ۵۰ حواله پیش‌نویس انبار کسب‌وکار متصل. حواله قطعی/ابطال‌شده حذف نمی‌شود. نیازمند تأیید.", parameters_schema=BULK_DEL_WH, handler=bulk_delete_warehouse_documents_handler, allowed_roles=roles, required_permissions=["warehouses.delete"], category="warehouse", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="get_person_opening_balance_eligibility", description="آیا فرم شخص می‌تواند مانده افتتاحیه سال مالی جاری را نشان دهد.", parameters_schema=OB_PERSON, handler=get_person_opening_balance_eligibility_handler, allowed_roles=roles, required_permissions=["opening_balance.view"], category="accounting", is_readonly=True))
    registry.register(AIFunction(name="get_product_opening_balance_eligibility", description="آیا فرم کالا می‌تواند موجودی افتتاحیه را نشان دهد.", parameters_schema=OB_PROD, handler=get_product_opening_balance_eligibility_handler, allowed_roles=roles, required_permissions=["opening_balance.view"], category="accounting", is_readonly=True))
    registry.register(AIFunction(name="link_tax_workspace_reference", description="اتصال فاکتور مرجع به فاکتور برگشت/اصلاح در کارپوشه مالیاتی. نیازمند تأیید.", parameters_schema=TAX_LINK, handler=link_tax_workspace_reference_handler, allowed_roles=roles, required_permissions=["invoices.write"], category="tax", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="bulk_upsert_persons", description="ایجاد یا به‌روزرسانی گروهی حداکثر ۵۰ شخص. نیازمند تأیید.", parameters_schema=UPSERT, handler=bulk_upsert_persons_handler, allowed_roles=roles, required_permissions=["people.write"], category="persons", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="bulk_delete_persons", description="حذف گروهی اشخاص با شناسه یا کد. نیازمند تأیید.", parameters_schema=DEL_P, handler=bulk_delete_persons_handler, allowed_roles=roles, required_permissions=["people.delete"], category="persons", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="list_business_fx_global_rates", description="آخرین نرخ‌های جهانی مرتبط با ارزهای جانبی کسب‌وکار.", parameters_schema=EMPTY, handler=list_business_fx_global_rates_handler, allowed_roles=roles, required_permissions=["currency_revaluation.view"], category="accounting", is_readonly=True))
    registry.register(AIFunction(name="apply_currency_rates_from_global", description="ثبت نرخ تسعیر کسب‌وکار از اسنپ‌شات مرکزی. نیازمند تأیید.", parameters_schema=APPLY_FX, handler=apply_currency_rates_from_global_handler, allowed_roles=roles, required_permissions=["currency_revaluation.write"], category="accounting", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="bulk_create_currency_rates", description="ثبت چند نرخ ارز دستی یکجا. نیازمند تأیید.", parameters_schema=BULK_RATES, handler=bulk_create_currency_rates_handler, allowed_roles=roles, required_permissions=["currency_revaluation.write"], category="accounting", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="sync_product_base_price_from_fx", description="همگام قیمت پایه یک کالا از نرخ ارز. نیازمند تأیید.", parameters_schema=SYNC_ONE, handler=sync_product_base_price_from_fx_handler, allowed_roles=roles, required_permissions=["products.write"], category="products", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="sync_products_base_prices_from_fx", description="همگام گروهی قیمت پایه کالاها از نرخ ارز. نیازمند تأیید.", parameters_schema=SYNC_ALL, handler=sync_products_base_prices_from_fx_handler, allowed_roles=roles, required_permissions=["products.write"], category="products", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="finalize_document_monetization_volume", description="بستن دوره‌های باز درآمدزایی حجمی اسناد این کسب‌وکار. نیازمند تأیید.", parameters_schema=EMPTY, handler=finalize_document_monetization_volume_handler, allowed_roles=roles, required_permissions=["settings.business"], category="accounting", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="renew_storage_subscription", description="صدور صورتحساب تمدید اشتراک فضای ذخیره. نیازمند تأیید.", parameters_schema=RENEW, handler=renew_storage_subscription_handler, allowed_roles=roles, required_permissions=["storage.write"], category="business", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="pay_storage_over_usage", description="صدور و پرداخت صورتحساب اضافه مصرف فضای ذخیره از کیف پول. نیازمند تأیید.", parameters_schema=OVER, handler=pay_storage_over_usage_handler, allowed_roles=roles, required_permissions=["storage.write"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="get_storage_file_dependencies", description="موجودیت‌هایی که به یک فایل ذخیره کسب‌وکار وابسته‌اند.", parameters_schema=FILE_ID, handler=get_storage_file_dependencies_handler, allowed_roles=roles, required_permissions=["storage.view"], category="business", is_readonly=True))
    registry.register(AIFunction(name="revoke_all_storage_file_shares", description="لغو همه لینک‌های اشتراک فعال فایل. نیازمند تأیید.", parameters_schema=EMPTY, handler=revoke_all_storage_file_shares_handler, allowed_roles=roles, required_permissions=["storage.write"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="update_storage_file_share", description="تغییر انقضا یا حذف رمز لینک اشتراک فایل (رمز جدید از طریق UI). نیازمند تأیید.", parameters_schema=SHARE_UPD, handler=update_storage_file_share_handler, allowed_roles=roles, required_permissions=["storage.write"], category="business", requires_approval=True, risk_level="medium", is_readonly=False))
