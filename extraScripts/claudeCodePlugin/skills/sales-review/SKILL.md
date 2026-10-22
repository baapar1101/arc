---
name: sales-review
description: Analyze Hesabix sales, invoices, customers, and period-over-period trends using the connected business's available MCP tools. Use for sales reports, best customers, invoice questions, or sales performance.
argument-hint: [period, customer, or question]
---

# Hesabix sales review

1. Identify the exact date range, comparison period, and whether the user means sales invoices, cash received, or accounting revenue. Ask if this ambiguity changes the answer.
2. Discover and use the currently available read-only Hesabix tools. Common registry names include `get_sales_report`, `search_invoices`, `get_invoice_details`, `search_persons`, and `get_person_balance`; availability and schemas can vary by account.
3. Use the MCP `sales_review` prompt when helpful. Treat its instructions as a starting point and verify key figures with tool results.
4. Report gross/net/tax values only as labeled by the source. Do not assume that invoiced amounts equal collections or recognized revenue.
5. For comparisons, align equal-length periods and state the calculation. Do not extrapolate partial periods without labeling the estimate.

Include the period, currency/unit, relevant filters, source tool(s), and any data limitations. Do not create, edit, send, or delete invoices or customer records in this read-only review. If the user requests a write action, explain that it requires an appropriate Hesabix write grant and explicit review/approval in the client.
