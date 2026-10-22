# Workspace Model
Updated: 2026-10-20

## Product
- **Purpose**: Complete accounting & business management system for Iranian SMBs (small/medium businesses)
- **Users**: Business owners, accountants, sales teams, warehouse managers, support operators, system admins
- **Surfaces**: Web (Flutter Web), REST API (FastAPI), Telegram/Bale bots, Webhooks, MCP server
- **License**: GNU GPL v3.0

## Domain
### Core Entities
- **Business** (multi-tenant) — isolated data per business, membership/roles
- **Person** (Customer/Supplier/Contact) — with groups, credit limits, ledgers
- **Product/Service** — categories, attributes, bundles, instances (serialized), price lists, tax codes
- **Warehouse** — locations, stock, transfers, inventory docs (receipt/issue/adjustment/count)
- **Accounting** — Chart of accounts (multi-level), journal entries, fiscal years, period-end FX revaluation
- **Documents** — Sales/Purchase invoices, Proformas, Receipts/Payments, Transfers, Expense/Income, BOMs
- **Financial Instruments** — Bank accounts, Cash registers, Petty cash, Checks, Loan facilities, Wallets
- **Tax** — Moadian integration (inquiry, submission), tax units/types/codes, VAT reports

### Key Workflows
- Sales cycle: Quotation → Proforma → Invoice → Receipt/Payment → Accounting entry
- Purchase cycle: PO → Purchase Invoice → Payment → Inventory receipt
- Inventory: Transfers, Stock counts, Kardex, Opening balances
- Multi-currency: Global FX rates (auto-fetch), Business rates (offset), Auto-sync, Period-end revaluation
- CRM: Leads, Deals, Activities, Follow-ups, Web chat widget, AI assistant
- Notifications: In-app, Email, SMS, Telegram, Bale, Webhook, Push (Firebase)
- Workflow Engine: Visual builder, Triggers (CRUD/Scheduled/Webhook), Actions, Marketplace
- AI: Chat (OpenAI/Anthropic), Voice (STT/TTS/VAD), MCP server, Skills, CRM AI, Eval framework
- Telephony: Softphone (WebRTC), Media Edge, Asterisk/Issabel connector
- Integrations: Zohal (identity/vehicle/postal/banking inquiries), Basalam, WooCommerce, Payment gateways
- Support: Tickets, SLA, Operators, Billing, AI triage
- Admin: System settings, Monitoring, Firewall, Businesses, Users/Permissions, Storage plans, Announcements

## Technical
### Stack
- **Backend**: FastAPI (Python 3.11+), SQLAlchemy 2.0, PostgreSQL, Alembic, Redis, RQ, Uvicorn
- **Frontend**: Flutter Web (Dart 3.9), go_router, dio, flutter_secure_storage, Material Design
- **Infra**: Nginx, Systemd, Docker, Let's Encrypt SSL, PgBouncer (recommended)
- **AI/Voice**: faster-whisper, piper-tts, webrtcvad, websockets
- **Observability**: structlog, custom monitoring, health endpoints, performance tracking

### Modules (Backend)
- `app/core` — Settings, auth, cache, permissions, logging, queue, monitoring, i18n, calendar, rate-limit
- `app/services` — 20+ domain services (AI, workflow, PDF, tax, telephony, voice, CRM, support, etc.)
- `app/workers` — Notification moderation, background jobs
- `adapters/api/v1` — 100+ routers covering all domains
- `adapters/db` — SQLAlchemy models, session, activity log hooks
- `integrations` — Moadian (tax), Fanava, Basalam, Telegram, Bale, WooCommerce

### Frontend Structure
- `pages/` — Business (dashboard, accounting, inventory, CRM, settings), Admin, Auth, Profile, Public
- `widgets/` — 60+ widget categories (invoice, product, warehouse, CRM, zohal, workflow, report_template, etc.)
- `services/` — API client, notifications, telephony, voice, updates (Android/Windows)
- `models/` — Data models matching backend schemas

## Gaps
- **Mobile apps**: Flutter mobile targets exist (Android/iOS config) but not primary focus
- **Offline mode**: No explicit offline-first sync strategy for web
- **Multi-region**: Single-region deployment model (PostgreSQL primary)
- **Audit logging**: Activity logs exist but not immutable/tamper-evident
- **Plugin marketplace**: Workflow marketplace exists; broader plugin ecosystem not yet
- **BI/Analytics**: Reports exist but no embedded BI/dashboard builder for end-users

## Open Questions
- Timeline for native mobile app releases?
- Plan for horizontal scaling (read replicas, sharding)?
- Strategy for third-party plugin ecosystem beyond workflows?
- Roadmap for AI-powered insights (anomaly detection, forecasting)?