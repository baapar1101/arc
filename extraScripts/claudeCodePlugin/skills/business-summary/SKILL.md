---
name: business-summary
description: Prepare a concise, evidence-based management overview of the connected Hesabix business. Use when the user asks for a business snapshot, management summary, or key financial and operational indicators.
argument-hint: [period or focus]
---

# Hesabix business summary

Prepare a useful overview for the business currently connected to Hesabix.

1. Discover the available Hesabix MCP tools and read-only permissions for this connection. The tool set depends on the signed-in user and business.
2. If the user did not specify a period, state the period used or ask a short clarification when the tools require one. Do not silently invent dates.
3. Gather evidence from relevant read-only financial, sales, purchasing, cash-flow, receivables/payables, and inventory tools. Prefer focused tools over broad data dumps. You can also use the `business_summary` MCP prompt or `hesabix://business/overview` resource when available.
4. Summarize the indicators, their period, currency/unit, and source. Separate directly returned values from calculations you derive.
5. Flag missing data, mismatched periods, and limitations. Never claim that a report was checked if no corresponding tool call succeeded.

Use the Hesabix tool named `ask_hesabix_agent` for a multi-step read-only question when the direct tool path is unclear. Do not use it to perform writes. This agent is analyzer-only.

## Accounting conventions

- Use the currency and units returned by Hesabix; never infer Rial versus Toman.
- Distinguish finalized invoices from pro forma documents when the report does so.
- A profit/loss figure should come from accounting/financial reporting, not from simply summing invoices.
- A cash-flow measure is not the same as revenue, and a customer balance is not the same as a period's sales.
- Give dates and ranges explicitly; preserve the calendar convention used in the tool response.

## Output

Start with the period and business context. Then give a short executive summary, key metrics with units and source, notable changes or risks supported by data, and any caveats. Keep recommendations clearly separated from factual findings.
