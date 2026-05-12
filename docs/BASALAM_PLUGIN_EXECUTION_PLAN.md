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

## Phase 2 - Data Sync Core (Partially Implemented)

- ✅ Implement Basalam SDK-based client adapter (payments/chat paths used in Phase 2/3)
- ✅ Add idempotency storage for webhook/event processing
- ✅ Order ingestion pipeline (initial):
  - ✅ customer matching policy (match/create/manual)
  - ✅ product matching policy (match/create/manual)
  - ✅ order line normalization
  - ✅ default `basalam` tagging
  - ✅ optional automatic sales-invoice creation on sync
- Payment ingestion mapping:
  - ✅ bank/cash routing (auto_bank / auto_cash)
  - ✅ receipt document creation for matched orders/invoices
  - ✅ optional remote verify for unverified transactions
  - document-level reconciliation hardening

## Phase 3 - CRM Chat Bridge (Partially Implemented)

- ✅ Inbound Basalam chat -> CRM conversation/message model
- ✅ Outbound CRM agent reply -> Basalam chat API (`/v1/chats/{chat_id}/messages`)
- ✅ Operator relay from primary CRM chat endpoint (auto relay for Basalam-source conversations)
- ✅ Attachment upload relay (local-storage CRM files -> Basalam upload + chat file message)
- FTP-backed attachment relay (pending hardening)

## Phase 4 - Product Sync (Partially Implemented)

- ✅ Basalam -> Hesabix product sync (manual payload path, match/create/manual-review modes)
- ✅ Hesabix -> Basalam product publish/update (manual payload path via Basalam SDK core service)
- ✅ Incremental pull/push endpoints for product sync
- ✅ Stock/price conflict strategy (local_wins / remote_wins / manual_review)
- ✅ Variant conflict strategy baseline (manual-review queue for variant-bearing items)
- ✅ Conflict resolution endpoints (batch apply local_wins / remote_wins / discard)
- ✅ Manual review queue for ambiguous mappings (stored in Basalam plugin settings)

## Phase 5 - Automation UX + Hardening (Next)

- Add Basalam trigger translations in workflow metadata i18n
- Add Basalam workflow actions (send chat reply, sync order, sync product)
- ✅ Retry queue for failed product publish items (settings-backed)
- Retry policy + dead-letter queue for all failed sync items
- Observability dashboards and alerts
- Contract tests against Basalam OpenAPI and staging samples

## Acceptance Checklist

- Settings are editable per business and persisted
- Webhook calls are accepted and mapped to workflow triggers
- Manual sync endpoint exists and dispatches events
- Plugin page is accessible only when plugin license is active
- UI works with FA/EN app language context
