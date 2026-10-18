---
name: integrations-review
description: Inspect Hesabix-connected sales channels and external integrations such as WooCommerce or Basalam, including sync status and conflicts. Use when asked about connected marketplace or e-commerce data.
argument-hint: [integration or sync issue]
---

# Hesabix integrations review

1. Identify which connected integration and business are in scope. Never assume a connector is configured or enabled.
2. Discover authorized tools at runtime. Possible read tools include `list_woocommerce_orders`, `list_woocommerce_products`, `list_basalam_synced_invoices`, `list_basalam_product_conflicts`, `get_basalam_overview`, and `list_basalam_dead_letter`. The generic `invoke_business_connector` can contact a configured external endpoint and must be treated as externally observable, even if its catalog write scope is read.
3. Before invoking a generic connector, inspect its live schema and configuration context. Tell the user which external system will be contacted when that is material. Never send secrets, broad customer exports, or unrelated business data in connector parameters.
4. Distinguish the source system's state from Hesabix's synchronized copy. State timestamps and sync errors when available.
5. Keep the review read-only. Do not retry a sync, execute a connector mutation, or modify a marketplace record unless explicitly requested and properly authorized.
