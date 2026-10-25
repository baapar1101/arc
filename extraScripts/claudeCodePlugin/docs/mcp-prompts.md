# Hesabix MCP prompts and resource

This file transcribes the prompt/resource interface currently implemented by `hesabixAPI/app/services/ai/ai_mcp_service.py`. Recheck that source when updating the plugin.

## Prompts exposed by `prompts/list`

The server currently defines 14 prompts. The live list is filtered by the categories of tools visible to the connection, so a prompt can be absent for a particular user or OAuth grant. `business_summary` is available when the connection has any visible tool.

| Name | Current description | User argument |
|---|---|---|
| `business_summary` | خلاصهٔ وضعیت و شاخص‌های مدیریتی؛ نیازمند دست‌کم یک ابزار قابل مشاهده. | Optional `request` string, maximum 2,000 characters. |
| `sales_review` | مرور فروش، فاکتورها، دریافت‌ها و روندهای قابل مشاهده؛ دستهٔ `financial`، `invoices`، `checks` یا `accounting`. | Optional `request` string, maximum 2,000 characters. |
| `inventory_review` | مرور موجودی، کالاهای کم‌موجود و اسناد انبار؛ دستهٔ `warehouse`. | Optional `request` string, maximum 2,000 characters. |
| `receivables_review` | مرور ماندهٔ مشتریان و دریافت‌ها؛ دستهٔ مالی. | Optional `request` string, maximum 2,000 characters. |
| `payables_review` | مرور ماندهٔ تأمین‌کنندگان و پرداخت‌ها؛ دستهٔ مالی. | Optional `request` string, maximum 2,000 characters. |
| `payroll_review` | مرور دوره‌ها و اجرای حقوق، بدون نمایش غیرضروری اطلاعات حساس؛ دستهٔ `payroll`. | Optional `request` string, maximum 2,000 characters. |
| `crm_review` | مرور سرنخ‌ها، فرصت‌ها، فعالیت‌ها و قیف فروش؛ دستهٔ `crm`. | Optional `request` string, maximum 2,000 characters. |
| `repair_review` | مرور سفارش‌های تعمیر و اثرهای احتمالی تغییر وضعیت؛ دستهٔ `repair`. | Optional `request` string, maximum 2,000 characters. |
| `warranty_review` | مرور کدها و وضعیت گارانتی با محافظت از اطلاعات تماس و توکن رهگیری؛ دستهٔ `warranty`. | Optional `request` string, maximum 2,000 characters. |
| `production_review` | مرور سفارش تولید، مواد، lot و بهای تمام‌شده؛ دستهٔ `production`. | Optional `request` string, maximum 2,000 characters. |
| `distribution_review` | مرور مسیر، بازدید، مرجوعی، موجودی خودرو و تسویه؛ دستهٔ `distribution`. | Optional `request` string, maximum 2,000 characters. |
| `invoice_draft` | گردآوری اطلاعات و آماده‌سازی ورودی پیش‌نویس فاکتور؛ دستهٔ `invoices`. | Optional `request` string, maximum 2,000 characters. |
| `tax_review` | بررسی کارپوشه و خطاهای مالیاتی؛ دستهٔ `tax`. | Optional `request` string, maximum 2,000 characters. |
| `warehouse_document` | گردآوری اطلاعات و آماده‌سازی ورودی پیش‌نویس حواله؛ دستهٔ `warehouse`. | Optional `request` string, maximum 2,000 characters. |

## Prompt body behavior

`prompts/get` uses these Persian titles:

- Titles are generated from the matching entries in `_PROMPT_CATALOG` in `ai_mcp_service.py`.

The generated user message limits the analysis to the connected business and visible tools, instructs the model to disclose unavailable data and avoid guessed identifiers, and says not to change records unless the user explicitly requested the change in the current conversation. A non-empty `request` argument is appended as the user's additional request. Prompts are guidance, not authorization.

## Resource exposed by `resources/list`

| URI | Name | Description | MIME |
|---|---|---|---|
| `hesabix://business/overview` | نمای کلی کسب‌وکار | اطلاعات پایه کسب‌وکاری که این اتصال به آن محدود است. | `application/json` |
| `hesabix://mcp/capabilities` | قابلیت‌های مجاز اتصال | ابزارهای قابل مشاهده برای همین کاربر و اتصال، شامل دسته، نوع اثر، مجوزهای لازم و schema ورودی. | `application/json` |

The overview resource returns the connected business's name, type, and field. The capabilities resource returns the live visible tool catalog, tool count, and category counts. Both are tenant-pinned; treat business details and tool capabilities as connection-specific data.

## Server-provided tool

`ask_hesabix_agent` is exposed only for credentials without a per-tool allowlist (for example, legacy/manual bearer connections). It is hidden for OAuth grants with an explicit tool allowlist, so OAuth clients must use the tools they selected. When present, it accepts a required `query` string and runs in Analyzer mode using read-only tools; it is not an action/transaction executor. Always inspect the live `tools/list` or capabilities resource instead of assuming it exists.

## Skill and agent mapping

| Plugin component | Prompt/resource/tool to use | Scope of work |
|---|---|---|
| `business-summary` skill | `business_summary`, overview and capabilities resources; `ask_hesabix_agent` only when listed | Business snapshot. Use the visible direct read tools and cite tool evidence. |
| `sales-review` skill | `sales_review` | Sales and invoice analysis only; distinguish invoicing from cash collection. |
| `inventory-review` skill | `inventory_review`, overview resource | Inventory, movement, and valuation analysis. |
| `receivables-review` skill | `receivables_review` | Uses the live authorized read tools and reports unavailable data. |
| `reports-analysis` skill | No dedicated MCP prompt exists | Uses live report tools and canonical accounting reports. |
| `crm-review` skill | `crm_review` | Uses read-only CRM tools and current schemas. |
| `workflow-review` skill | No dedicated MCP prompt exists | Reviews workflows; does not run or change them. |
| `integrations-review` skill | No dedicated MCP prompt exists | Reads connected-channel state; generic connectors can still have external side effects. |
| `financial-analyst` agent | Direct read-only MCP tools; `ask_hesabix_agent` only when listed | Analysis only; never calls a write-scope tool. |
| `accounting-operations` skill / `accounting-guide` agent | No dedicated MCP prompt exists | Explicitly requested write workflows; require specific preview, user confirmation, write grant, and client approval. |

## Write confirmation boundary

The server enforces the granted `ai:tools:write` scope, selected-tool allowlist (for OAuth), current business membership, per-tool business permissions, and input schema. A direct `tools/call` for an authorized write tool executes the handler; the server does not run the chat approval flow or independently verify that a human confirmed that exact operation. Therefore the MCP client must show the exact action and material arguments and wait for an affirmative, transaction-specific user confirmation before sending a write call. A write-scope grant is not confirmation for a particular transaction. Do not send an approval boolean in tool arguments as a substitute; such arguments are not a trusted confirmation channel.

Prompts are guidance, not authorization. The live server and account permissions remain authoritative.
