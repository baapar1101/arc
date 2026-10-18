---
name: receivables-review
description: Review Hesabix customer balances, receivables, payables, and cash movement using the connected business's authorized tools. Use for outstanding debt, who owes whom, collections, or payment reconciliation questions.
argument-hint: [customer, supplier, or period]
---

# Hesabix balances and cash review

1. Clarify whether the user asks about customer receivables, supplier payables, receipts/payments, or accounting balances. These are different measures.
2. Discover available read-only tools. Common names include `get_debtors_report`, `get_creditors_report`, `get_person_balance`, `search_receipts_payments`, and `get_cash_flow`.
3. Use the date range and person filters supported by the live tool schema. For balances “now”, do not impose a period filter unless the tool requires it.
4. Separate document totals from outstanding balances and cash movements. A payment can settle a balance without changing the invoice total.
5. Only calculate aging when the tool returns usable due/invoice dates and balances. State the aging buckets and method.

Show currency/unit, as-of date or period, source, and any limitations. Do not create, edit, or delete payments, receipts, or customer/supplier records during this review.
