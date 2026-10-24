"""Shared approval checks, including direct accounting-service entry points."""
from adapters.db.models.business import Business
from adapters.db.models.payroll import PayrollRun, PayrollSettings
from app.core.responses import ApiError


def owner_approval_only(settings):
    return (settings.extra_settings or {}).get('financial_approval_policy', {}).get('owner_only') is True


def approval_required(settings):
    return bool(settings.require_approval) or owner_approval_only(settings)


def require_owner(db, business_id, user_id):
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business or user_id is None or business.owner_id != user_id:
        raise ApiError('PAYROLL_OWNER_APPROVAL_REQUIRED', 'فقط مالک کسب‌وکار مجاز به تأیید و صدور حقوق است.', http_status=403)


def lock_context(db, business_id, run_id):
    # Same lock order for approval, settings changes, accrual and payment. The
    # run lock also serializes duplicate requests before checking document links.
    settings = db.query(PayrollSettings).filter(PayrollSettings.business_id == business_id).with_for_update().populate_existing().one()
    run = db.query(PayrollRun).filter(PayrollRun.business_id == business_id, PayrollRun.id == run_id).with_for_update().populate_existing().first()
    if not run:
        raise ApiError('NOT_FOUND', 'اجرای حقوق یافت نشد.', http_status=404)
    return settings, run


def require_approved(db, business_id, user_id, run, settings):
    if approval_required(settings) and (
        run.status not in ('finalized', 'posted') or not run.approved_at or not run.approved_by_user_id
    ):
        raise ApiError('PAYROLL_APPROVAL_REQUIRED', 'قبل از صدور سند، تأیید مدیر برای این اجرای حقوق لازم است.', http_status=409)
    if owner_approval_only(settings):
        require_owner(db, business_id, user_id)
        require_owner(db, business_id, run.approved_by_user_id)
