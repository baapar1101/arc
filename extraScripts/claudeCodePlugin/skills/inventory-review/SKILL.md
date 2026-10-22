---
name: inventory-review
description: Review Hesabix stock levels, valuation, product movement, and low-stock risks for the connected business. Use for inventory, warehouse, product availability, or stock valuation questions.
argument-hint: [warehouse, product, or period]
---

# Hesabix inventory review

1. Clarify the warehouse, product, and “as of” date if they materially affect the request.
2. Discover current read-only tools. Common registry names include `get_inventory_status`, `get_inventory_valuation`, `get_product_kardex`, `search_products`, and `get_product_info`, subject to per-user authorization.
3. Use `hesabix://business/overview` for business context and `inventory_review` MCP prompt where useful.
4. Distinguish quantity on hand, available quantity, reserved quantity, and valuation if the source exposes them. Do not combine quantities across warehouses unless requested and compatible.
5. Explain the valuation basis only when returned by Hesabix. Do not estimate a cost basis from sales prices.

Report the date, warehouse/filter, units, source tools, and missing fields. This review is read-only: do not create warehouse documents, adjust stock, or edit products.
