# Basalam Plugin Execution Plan

This document is the executable roadmap for the Basalam plugin in Hesabix.
It is aligned with existing marketplace plugin architecture, CRM chat flow, and workflow i18n patterns.

## Phase 1 - Foundation (Implemented)

- Marketplace plugin code: `basalam_connector`
- Backend dependency check for license/activity
- Business-level settings API
- Public webhook endpoint with optional HMAC verification
- Workflow trigger emission for:
  - `basalam.webhook.received`
  - `basalam.order.created`
  - `basalam.order.updated`
  - `basalam.order.paid`
  - `basalam.chat.message.received`
- Workflow trigger registry integration
- Flutter business page for Basalam settings and manual sync
- Sidebar/menu and route integration in business shell

## Phase 2 - Data Sync Core (Implemented)

- ✅ Implement Basalam SDK-based client adapter (payments/chat paths used in Phase 2/3)
- ✅ Add idempotency storage for webhook/event processing
- ✅ Order ingestion pipeline (initial):
  - ✅ customer matching policy (match/create/manual)
  - ✅ product matching policy (match/create/manual)
  - ✅ order line normalization
  - ✅ default `basalam` tagging
  - ✅ optional automatic sales-invoice creation on sync
  - ✅ dead-letter queue for blocked orders (`sync_dead_letter`, type `order_sync`)
  - ✅ IRR-only guard for business default + secondary currencies; rejection if invoice matched for payment is non-IRR
  - ✅ `basalam_monetary_unit` (`rial` | `toman`): inbound ×10 to IRR where needed; outbound publish divides by 10 when `toman`
- Payment ingestion mapping:
  - ✅ bank/cash routing (auto_bank / auto_cash)
  - ✅ receipt document creation for matched orders/invoices
  - ✅ optional remote verify for unverified transactions
  - ✅ dead-letter queue entries for failed payment sync (`sync_dead_letter`, type `payment_sync`)
  - ✅ idempotent receipt sync by Basalam transaction `hash_id` (`already_synced`)
  - ✅ document-level reconciliation: block overpayment vs `calculate_invoice_remaining`; optional tolerance (`payment_reconcile_tolerance_rial`); DLQ subtypes `payment_exceeds_invoice_remaining`, `payment_invoice_already_settled`; link receipt id into invoice `extra_info.links.receipt_payment_document_ids`

## Phase 3 - CRM Chat Bridge (Implemented; remote storage backends depend on platform FileStorageService)

- ✅ Inbound Basalam chat -> CRM conversation/message model
- ✅ Outbound CRM agent reply -> Basalam chat API (`/v1/chats/{chat_id}/messages`)
- ✅ Operator relay from primary CRM chat endpoint (auto relay for Basalam-source conversations)
- ✅ Attachment upload relay via unified `FileStorageService` (reads bytes from configured backend; requires active storage plan)
- FTP/S3 و غیره در همین مسیر با تکمیل `_read_file_from_storage` در سرویس فایل پوشش داده می‌شود (نه منطق جدا در افزونهٔ باسلام)

## Phase 4 - Product Sync (Implemented)

- ✅ Basalam -> Hesabix product sync (manual payload path, match/create/manual-review modes)
- ✅ Hesabix -> Basalam product publish/update (manual payload path via Basalam SDK core service)
- ✅ Incremental pull/push endpoints for product sync
- ✅ Stock/price conflict strategy (local_wins / remote_wins / manual_review)
- ✅ Variant conflict strategy baseline (manual-review queue for variant-bearing items)
- ✅ Conflict resolution endpoints (batch apply local_wins / remote_wins / discard)
- ✅ Manual review queue for ambiguous mappings (stored in Basalam plugin settings)
- ✅ Conflict management UX (filters, sorting, pagination, per-row detail and resolution)

## Phase 5 - Automation UX + Hardening (Mostly implemented)

- ✅ Basalam trigger translations in workflow metadata i18n
- ✅ Basalam workflow actions (chat reply, sync order/product, pull/push/publish, retry publish queue)
- ✅ Retry queue for failed product publish items (settings-backed)
- ✅ Unified sync dead-letter queue (`sync_dead_letter`) for order/payment sync failures + API list/clear + workflow actions
- ✅ Baseline structured logs (`structlog`) for webhook processing and payment sync batches
- ✅ Operator UX: currency readiness (`GET .../currency-readiness`), IRR warning card + sync dead-letter panel on Basalam settings page
- ✅ Observability baseline: Redis counters (`metrics:basalam:v1:*`) for webhook/payment/order paths + `GET /api/v1/basalam/observability/metrics-summary` (سوپرادمین / system_settings.superadmin); Grafana-style dashboards remain optional
- ✅ Contract tests against bundled `basalam.json` (critical HTTP paths + methods)
- Staging sample payloads / golden fixtures (optional)

## Acceptance Checklist

- Settings are editable per business and persisted
- Webhook calls are accepted and mapped to workflow triggers
- Manual sync endpoint exists and dispatches events
- Plugin page is accessible only when plugin license is active
- UI works with FA/EN app language context
- Conflict queue is reviewable and resolvable from UI (batch + per-item)

## Remaining backlog (count)

Two deliberate follow-ups remain outside core MVP:

1. **Phase 3 dependency:** Completing FTP/S3 (etc.) in platform `FileStorageService._read_file_from_storage` for attachment relay paths used by chat/storage — not Basalam-specific logic.
2. **Phase 5 (optional):** Staging golden fixtures / sample payloads for regression harnesses beyond existing OpenAPI contract tests.

Everything above Phase 1 in this roadmap that ships merchant-visible behaviour for Basalam is otherwise implemented unless marked optional/future inline.
