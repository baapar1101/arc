---
name: accounting-operations
description: Help carry out an explicitly requested Hesabix business operation such as creating or updating an accounting, inventory, CRM, workflow, or customer record. Use only when the user asks for a change, not for analysis or recommendations.
disable-model-invocation: true
argument-hint: [operation and details]
---

# Hesabix business operation protocol

This skill can lead to persistent business records or trigger external effects. Follow every step:

1. Confirm the requested operation and identify the connected business. Never select a different business on the user's behalf.
2. Discover the current authorized tool and its live input schema. Do not guess tool names, IDs, account codes, tax rules, dates, amounts, or currency.
3. Gather required details. Resolve units (Rial/Toman), tax, counterpart, item quantities, warehouse, workflow actions, external destination, and date from the user or Hesabix data. Do not invent missing values.
4. Before any write call, present a compact preview of the exact operation and material arguments, then ask the user to confirm. Do not treat this skill invocation, a prior general request, or MCP write scope as confirmation of the specific transaction.
5. Proceed only if Hesabix exposes the relevant write tool and the connection has the required `ai:tools:write` grant. Before sending a direct MCP write call, require Claude Code's transaction-specific approval after the preview. The server enforces scope and business permissions but does not independently verify this per-operation human confirmation. If either condition is missing, explain what is needed; never attempt to bypass it.
6. For workflows, connector calls, exports, executions, and other external effects, explain the destination and likely impact in the preview. After the call, report the actual result and returned record identifier. If the call fails or is ambiguous, do not retry a potentially non-idempotent write without checking whether it succeeded.

Never claim a transaction was created, paid, posted, or sent unless the tool confirms that result. Avoid irreversible actions such as deletion unless the user specifically requests that exact action and the client presents its approval prompt.
