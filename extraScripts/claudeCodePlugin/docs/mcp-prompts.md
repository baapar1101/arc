# Hesabix MCP prompts and resource

This file transcribes the prompt/resource interface currently implemented by `hesabixAPI/app/services/ai/ai_mcp_service.py`. Recheck that source when updating the plugin.

## Prompts exposed by `prompts/list`

| Name | Current description | User argument |
|---|---|---|
| `business_summary` | تهیهٔ خلاصه مدیریتی از وضعیت کسب‌وکار با ابزارهای مجاز. | Optional `request` string, maximum 2,000 characters. |
| `sales_review` | بررسی روند فروش و نکات قابل پیگیری در کسب‌وکار جاری. | Optional `request` string, maximum 2,000 characters. |
| `inventory_review` | مرور وضعیت موجودی و شناسایی موارد نیازمند توجه. | Optional `request` string, maximum 2,000 characters. |

## Prompt body behavior

`prompts/get` uses these Persian titles:

- `business_summary`: «خلاصه مدیریتی کسب‌وکار»
- `sales_review`: «مرور فروش»
- `inventory_review`: «مرور موجودی»

The generated user message asks Claude to prepare the requested review for the business pinned to this MCP connection, use only available Hesabix tools, avoid requesting data from another business, explicitly disclose unavailable data, and not execute a modifying operation unless the user explicitly asks in the same conversation and the relevant tool is authorized. A non-empty `request` argument is appended as the user's additional request.

## Resource exposed by `resources/list`

| URI | Name | Description | MIME |
|---|---|---|---|
| `hesabix://business/overview` | نمای کلی کسب‌وکار | اطلاعات پایه کسب‌وکاری که این اتصال به آن محدود است. | `application/json` |

The resource currently returns the connected business's name, type, and field. It is tenant-pinned and should be treated as business-sensitive data.

## Server-provided tool

The server always adds `ask_hesabix_agent`, described as a multi-step question to the Hesabix agent, which selects and combines authorized, read-only tools for the connected business. Its input is a required `query` string. The agent runs in Analyzer mode; do not treat it as an action/transaction executor.

## Skill and agent mapping

| Plugin component | Prompt/resource/tool to use | Scope of work |
|---|---|---|
| `business-summary` skill | `business_summary`, overview resource, `ask_hesabix_agent` | Business snapshot. It can combine the individual read-only domains but must cite tool evidence. |
| `sales-review` skill | `sales_review` | Sales and invoice analysis only; distinguish invoicing from cash collection. |
| `inventory-review` skill | `inventory_review`, overview resource | Inventory, movement, and valuation analysis. |
| `receivables-review` skill | No dedicated MCP prompt exists | Uses the live authorized read tools; do not claim a `receivables_review` prompt exists. |
| `reports-analysis` skill | No dedicated MCP prompt exists | Uses live report tools and canonical accounting reports. |
| `crm-review` skill | No dedicated MCP prompt exists | Uses read-only CRM tools and current schemas. |
| `workflow-review` skill | No dedicated MCP prompt exists | Reviews workflows; does not run or change them. |
| `integrations-review` skill | No dedicated MCP prompt exists | Reads connected-channel state; generic connectors can still have external side effects. |
| `financial-analyst` agent | `ask_hesabix_agent` and direct read-only MCP tools | Analysis only; never calls a write-scope tool. |
| `accounting-operations` skill / `accounting-guide` agent | No dedicated MCP prompt exists | Explicitly requested write workflows; require specific preview, user confirmation, write grant, and client approval. |

Prompts are guidance, not authorization. The live server and account permissions remain authoritative.
