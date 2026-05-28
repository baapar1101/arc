"""
اجرای گزارش‌های AI — فاز ۶ (یک نقطهٔ ورود برای get_report).
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from app.core.auth_dependency import AuthContext
from app.services.ai.ai_permission_map import has_any_ai_tool_permission
from app.services.ai.ai_reports_catalog import (
    REPORT_DEFINITIONS,
    REPORT_TYPES,
    ReportDefinition,
    get_report_definition,
)

_MAX_TAKE = 200


def _pag(args: Dict[str, Any]) -> Dict[str, int]:
    take = max(1, min(int(args.get("take") or 50), _MAX_TAKE))
    skip = max(0, int(args.get("skip") or 0))
    return {"skip": skip, "take": take}


def _date_kw(args: Dict[str, Any], *, db: Session, business_id: int) -> Dict[str, Any]:
    kw: Dict[str, Any] = {
        "fiscal_year_id": args.get("fiscal_year_id"),
        "currency_id": args.get("currency_id"),
        "date_from": args.get("from_date"),
        "date_to": args.get("to_date"),
    }
    kw.update(_pag(args))
    return kw


def _ids_arg(args: Dict[str, Any], key: str) -> Optional[List[int]]:
    raw = args.get(key)
    if raw is None and key == "account_ids" and args.get("account_id") is not None:
        return [int(args["account_id"])]
    if isinstance(raw, list):
        return [int(x) for x in raw if x is not None]
    if raw is not None:
        return [int(raw)]
    return None


def list_available_reports(
    ctx: AuthContext,
    *,
    business_id: Optional[int] = None,
    category: Optional[str] = None,
) -> Dict[str, Any]:
    """گزارش‌هایی که کاربر فعلی مجاز به فراخوانی آن‌هاست."""
    bid = business_id or ctx.business_id
    items: List[Dict[str, Any]] = []
    cat_filter = (category or "").strip().lower() or None
    for d in REPORT_DEFINITIONS:
        if cat_filter and d.category != cat_filter:
            continue
        if has_any_ai_tool_permission(ctx, d.permissions, business_id=bid):
            items.append(
                {
                    "report_type": d.report_type,
                    "label_fa": d.label_fa,
                    "category": d.category,
                    "required_params": list(d.requires),
                    "description": d.description or d.label_fa,
                }
            )
    return {
        "items": items,
        "total": len(items),
        "categories": sorted({i["category"] for i in items}),
        "hint": "برای دریافت داده از get_report با report_type یکی از موارد بالا استفاده کنید.",
    }


def execute_ai_report(
    db: Session,
    business_id: int,
    report_type: str,
    args: Dict[str, Any],
    *,
    user_context: Optional[AuthContext] = None,
) -> Any:
    rt = (report_type or "").strip().lower()
    defn = get_report_definition(rt)
    if not defn:
        raise ValueError(f"report_type نامعتبر: {rt}. از list_available_reports کمک بگیرید.")
    for req in defn.requires:
        if req == "account_ids" and not _ids_arg(args, "account_ids"):
            raise ValueError("برای general_ledger پارامتر account_ids (لیست) یا account_id لازم است.")
        elif req not in args or args.get(req) is None:
            raise ValueError(f"پارامتر {req} برای گزارش {rt} الزامی است.")

    kw = _date_kw(args, db=db, business_id=business_id)

    if rt == "sales_by_product" or rt == "sales":
        from app.services.product_service import get_sales_by_product_report

        return get_sales_by_product_report(db, business_id, **kw)

    if rt == "item_movements":
        from app.services.product_service import get_item_movements_report

        pids = _ids_arg(args, "product_ids") or (
            [int(args["product_id"])] if args.get("product_id") else None
        )
        return get_item_movements_report(
            db, business_id, product_ids=pids, fiscal_year_id=kw.get("fiscal_year_id"),
            date_from=kw.get("date_from"), date_to=kw.get("date_to"),
            skip=kw["skip"], take=kw["take"],
        )

    if rt == "debtors":
        from app.services.person_service import get_debtors_report

        return get_debtors_report(
            db, business_id,
            fiscal_year_id=kw.get("fiscal_year_id"),
            date_from=kw.get("date_from"), date_to=kw.get("date_to"),
            skip=kw["skip"], take=kw["take"],
        )

    if rt == "creditors":
        from app.services.person_service import get_creditors_report

        return get_creditors_report(
            db, business_id,
            fiscal_year_id=kw.get("fiscal_year_id"),
            date_from=kw.get("date_from"), date_to=kw.get("date_to"),
            skip=kw["skip"], take=kw["take"],
        )

    if rt == "cash_flow":
        from app.services.receipt_payment_service import list_receipts_payments

        q_r = {
            "document_type": "receipt",
            "from_date": kw.get("date_from"),
            "to_date": kw.get("date_to"),
            "take": kw["take"],
            "skip": kw["skip"],
        }
        q_p = {**q_r, "document_type": "payment"}
        receipts = list_receipts_payments(db, business_id, q_r)
        payments = list_receipts_payments(db, business_id, q_p)
        total_r = sum(
            float((i.get("extra_info") or {}).get("total_amount") or 0)
            for i in receipts.get("items", [])
        )
        total_p = sum(
            float((i.get("extra_info") or {}).get("total_amount") or 0)
            for i in payments.get("items", [])
        )
        return {
            "total_receipts": total_r,
            "total_payments": total_p,
            "net_cash_flow": total_r - total_p,
        }

    if rt == "inventory_valuation":
        from adapters.db.models.product import Product
        from app.services.warehouse_service import get_warehouse_stock_report
        from decimal import Decimal

        stock = get_warehouse_stock_report(
            db,
            business_id,
            {
                "product_ids": [args["product_id"]] if args.get("product_id") else [],
                "as_of_date": args.get("as_of_date"),
                "include_zero": False,
            },
        )
        total = Decimal(0)
        items_out = []
        for item in stock.get("items", []):
            pid = item.get("product_id")
            product = db.query(Product).filter(Product.id == pid).first()
            if not product:
                continue
            qty = Decimal(str(item.get("quantity", 0)))
            price = Decimal(str(product.cost_price or product.base_purchase_price or 0))
            val = qty * price
            total += val
            items_out.append({"product_id": pid, "valuation": float(val)})
        return {"items": items_out, "total_valuation": float(total)}

    if rt == "purchase":
        return execute_ai_report(db, business_id, "daily_purchases", args)

    if rt == "daily_sales":
        from app.services.invoice_service import get_daily_sales_report

        return get_daily_sales_report(db, business_id, **kw)

    if rt == "daily_purchases":
        from app.services.invoice_service import get_daily_purchases_report

        return get_daily_purchases_report(db, business_id, **kw)

    if rt == "monthly_sales":
        from app.services.invoice_service import get_monthly_sales_report

        return get_monthly_sales_report(db, business_id, **kw)

    if rt == "top_customers":
        from app.services.invoice_service import get_top_customers_report

        return get_top_customers_report(db, business_id, **kw)

    if rt == "top_suppliers":
        from app.services.invoice_service import get_top_suppliers_report

        return get_top_suppliers_report(db, business_id, **kw)

    if rt == "materials_consumption":
        from app.services.invoice_service import get_materials_consumption_report

        return get_materials_consumption_report(db, business_id, **kw)

    if rt == "production":
        from app.services.invoice_service import get_production_report

        return get_production_report(db, business_id, **kw)

    if rt == "people_transactions":
        from app.services.person_service import get_people_transactions_report

        return get_people_transactions_report(
            db,
            business_id,
            person_ids=_ids_arg(args, "person_ids"),
            document_type=args.get("document_type"),
            search=args.get("search"),
            **kw,
        )

    if rt == "bank_accounts_turnover":
        from app.services.bank_account_service import get_bank_accounts_turnover_report

        return get_bank_accounts_turnover_report(
            db,
            business_id,
            bank_account_ids=_ids_arg(args, "bank_account_ids"),
            **kw,
        )

    if rt == "cash_petty_turnover":
        from app.services.cash_register_service import get_cash_petty_turnover_report

        return get_cash_petty_turnover_report(
            db,
            business_id,
            cash_register_ids=_ids_arg(args, "cash_register_ids"),
            petty_cash_ids=_ids_arg(args, "petty_cash_ids"),
            **kw,
        )

    if rt == "inventory_stock":
        from app.services.product_service import get_inventory_stock_report

        return get_inventory_stock_report(
            db,
            business_id,
            product_ids=_ids_arg(args, "product_ids"),
            warehouse_ids=_ids_arg(args, "warehouse_ids"),
            category_ids=_ids_arg(args, "category_ids"),
            as_of_date=args.get("as_of_date"),
            skip=kw["skip"],
            take=kw["take"],
        )

    if rt == "inventory_kardex":
        from app.services.product_service import get_inventory_kardex_report

        return get_inventory_kardex_report(
            db,
            business_id,
            product_ids=_ids_arg(args, "product_ids"),
            warehouse_ids=_ids_arg(args, "warehouse_ids"),
            category_ids=_ids_arg(args, "category_ids"),
            fiscal_year_id=kw.get("fiscal_year_id"),
            date_from=kw.get("date_from"),
            date_to=kw.get("date_to"),
            skip=kw["skip"],
            take=kw["take"],
        )

    if rt == "warehouse_documents_summary":
        from app.services.warehouse_reports_service import get_warehouse_documents_summary_report

        return get_warehouse_documents_summary_report(
            db,
            business_id,
            date_from=kw.get("date_from"),
            date_to=kw.get("date_to"),
            warehouse_ids=_ids_arg(args, "warehouse_ids"),
            skip=kw["skip"],
            take=kw["take"],
        )

    if rt == "slow_moving_items":
        from app.services.warehouse_reports_service import get_slow_moving_items_report

        return get_slow_moving_items_report(
            db, business_id, date_from=kw.get("date_from"), date_to=kw.get("date_to"),
            skip=kw["skip"], take=kw["take"],
        )

    if rt == "critical_stock":
        from app.services.warehouse_reports_service import get_critical_stock_report

        return get_critical_stock_report(db, business_id, skip=kw["skip"], take=kw["take"])

    if rt == "inter_warehouse_transfers":
        from app.services.warehouse_reports_service import get_inter_warehouse_transfers_report

        return get_inter_warehouse_transfers_report(
            db, business_id, date_from=kw.get("date_from"), date_to=kw.get("date_to"),
            skip=kw["skip"], take=kw["take"],
        )

    if rt == "adjustment_documents":
        from app.services.warehouse_reports_service import get_adjustment_documents_report

        return get_adjustment_documents_report(
            db, business_id, date_from=kw.get("date_from"), date_to=kw.get("date_to"),
            skip=kw["skip"], take=kw["take"],
        )

    if rt == "warehouse_performance":
        from app.services.warehouse_reports_service import get_warehouse_performance_report

        return get_warehouse_performance_report(
            db, business_id, date_from=kw.get("date_from"), date_to=kw.get("date_to"),
            skip=kw["skip"], take=kw["take"],
        )

    if rt == "product_movement_history":
        from app.services.warehouse_reports_service import get_product_movement_history_report

        return get_product_movement_history_report(
            db,
            business_id,
            product_ids=_ids_arg(args, "product_ids"),
            date_from=kw.get("date_from"),
            date_to=kw.get("date_to"),
            skip=kw["skip"],
            take=kw["take"],
        )

    if rt == "inventory_turnover":
        from app.services.warehouse_reports_service import get_inventory_turnover_report

        return get_inventory_turnover_report(
            db, business_id, date_from=kw.get("date_from"), date_to=kw.get("date_to"),
            skip=kw["skip"], take=kw["take"],
        )

    if rt == "pending_documents":
        from app.services.warehouse_reports_service import get_pending_documents_report

        return get_pending_documents_report(db, business_id, skip=kw["skip"], take=kw["take"])

    if rt == "trial_balance":
        from app.services.trial_balance_service import get_trial_balance_report

        return get_trial_balance_report(
            db,
            business_id,
            account_ids=_ids_arg(args, "account_ids"),
            account_type=args.get("account_type"),
            project_id=args.get("project_id"),
            include_zero_balance=bool(args.get("include_zero_balance", False)),
            **kw,
        )

    if rt == "general_ledger":
        from app.services.general_ledger_service import get_general_ledger_report

        aids = _ids_arg(args, "account_ids") or []
        return get_general_ledger_report(
            db,
            business_id,
            account_ids=aids,
            person_id=args.get("person_id"),
            project_id=args.get("project_id"),
            include_proforma=bool(args.get("include_proforma", False)),
            fiscal_year_id=kw.get("fiscal_year_id"),
            currency_id=kw.get("currency_id"),
            date_from=kw.get("date_from"),
            date_to=kw.get("date_to"),
            skip=kw["skip"],
            take=kw["take"],
        )

    if rt == "journal_ledger":
        from app.services.journal_ledger_service import get_journal_ledger_report

        return get_journal_ledger_report(
            db,
            business_id,
            document_type=args.get("document_type"),
            project_id=args.get("project_id"),
            include_proforma=bool(args.get("include_proforma", False)),
            fiscal_year_id=kw.get("fiscal_year_id"),
            currency_id=kw.get("currency_id"),
            date_from=kw.get("date_from"),
            date_to=kw.get("date_to"),
            skip=kw["skip"],
            take=kw["take"],
        )

    if rt == "pnl_period":
        from app.services.pnl_service import get_pnl_period_report

        return get_pnl_period_report(
            db, business_id, project_id=args.get("project_id"), **kw
        )

    if rt == "pnl_cumulative":
        from app.services.pnl_service import get_pnl_cumulative_report

        return get_pnl_cumulative_report(
            db, business_id, project_id=args.get("project_id"), **kw
        )

    if rt == "accounts_review":
        from app.services.account_review_service import get_accounts_review_report

        return get_accounts_review_report(
            db,
            business_id,
            account_type=args.get("account_type"),
            account_id=args.get("account_id"),
            include_zero_balance=bool(args.get("include_zero_balance", False)),
            **kw,
        )

    if rt == "distribution_dashboard":
        from datetime import date as date_cls, datetime as dt_cls

        from app.services.distribution_service import get_distribution_reports_dashboard

        if user_context is None:
            raise ValueError("گزارش distribution_dashboard به context کاربر نیاز دارد.")
        fd = kw.get("date_from")
        td = kw.get("date_to")
        if not fd or not td:
            raise ValueError("from_date و to_date برای distribution_dashboard الزامی است.")
        try:
            d_from = dt_cls.strptime(str(fd)[:10], "%Y-%m-%d").date()
            d_to = dt_cls.strptime(str(td)[:10], "%Y-%m-%d").date()
        except ValueError as exc:
            raise ValueError("فرمت تاریخ باید YYYY-MM-DD باشد.") from exc
        return get_distribution_reports_dashboard(
            db,
            business_id,
            user_context,
            d_from,
            d_to,
            args.get("target_user_id"),
        )

    if rt == "basalam_overview":
        from app.services.basalam_reports_service import get_overview

        return get_overview(db, business_id, chart_days=int(args.get("chart_days") or 90))

    if rt == "basalam_dead_letter":
        from app.services.basalam_reports_service import list_dead_letter_for_report

        return list_dead_letter_for_report(
            db,
            business_id,
            item_type=args.get("item_type"),
            limit=kw["take"],
            offset=kw["skip"],
        )

    raise ValueError(f"گزارش {rt} در کاتالوگ است ولی handler پیاده‌سازی نشده است.")


__all__ = ["REPORT_TYPES", "execute_ai_report", "list_available_reports"]
