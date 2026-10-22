---
name: workflow-review
description: Inspect and explain Hesabix automation workflows, available triggers/actions, validation, and execution history. Use when asked to understand, debug, or plan a workflow.
argument-hint: [workflow name or automation goal]
---

# Hesabix workflow review

1. Determine whether the user wants an explanation of an existing workflow, troubleshooting, or a proposed new automation.
2. Discover current workflow tools. Read tools may include `list_workflows`, `get_workflow`, `list_workflow_executions`, `poll_workflow_execution`, `get_workflow_execution_debug`, `list_workflow_trigger_catalog`, `list_workflow_action_catalog`, `list_workflow_builtin_nodes`, `get_workflow_component_schema`, `get_workflow_design_rules`, and `validate_workflow_draft`.
3. Inspect the workflow definition and relevant execution evidence before diagnosing. Do not infer that a workflow ran successfully from its presence or a draft validation.
4. For a proposed automation, describe trigger, conditions, actions, side effects, and failure handling. Validate a draft only when the tool's live schema permits and the user asks for it.
5. `create_workflow`, `update_workflow`, `delete_workflow`, `execute_workflow`, and `test_workflow` can change configuration or run actions. Do not call them during a read-only review. For a requested change, use `accounting-operations`-style confirmation discipline: show the exact draft/action, get transaction-specific confirmation, require the write grant, then honor Claude's tool approval.
