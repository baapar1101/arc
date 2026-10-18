---
name: reports-analysis
description: Find and analyze Hesabix accounting and financial reports, including balances, cash flow, taxes, report templates, and business data queries. Use when the user asks for a formal report or accounting position.
argument-hint: [report type and period]
---

# Hesabix reports analysis

1. Clarify report type, accounting basis, fiscal year, date interval, and currency where relevant.
2. Discover live report tools and schemas. Common registered names include `list_available_reports`, `get_report`, `get_financial_summary`, `get_cash_flow`, `get_opening_balance`, `get_tax_settings`, `search_tax_workspace`, and `get_tax_data_quality`. Exact access depends on the business and user's Hesabix permissions.
3. Prefer the accounting report that directly answers the question. Do not reconstruct profit and loss, trial balance, or tax totals from invoice sums if a canonical report is available.
4. Report the accounting period, basis/filters, currency, source, and whether the result is actual, draft, or derived as indicated by Hesabix.
5. For tax-law or filing advice, report only the system data and settings. Do not infer current legal treatment from the data; flag missing jurisdiction or tax evidence.

Avoid exporting or changing records unless the user explicitly asks; export tools require write scope despite being read-like in intent because they produce a data artifact.
