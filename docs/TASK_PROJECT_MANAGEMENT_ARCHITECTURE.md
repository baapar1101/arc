# Task & Project Management — Phase 0 Architecture

Status: **implemented foundation**  
Date: 2026-09-26

## Benchmark mapping

| Concern | Benchmark | Native Hesabix implementation |
|---|---|---|
| Project/work-item hierarchy and board-ready states | Plane | Existing `projects` table + new first-class `tasks` and `task_statuses` |
| Task semantics, relations, reminders, recurrence | Vikunja | `tasks`, `task_relations`, `task_reminders`, RFC 5545-style recurrence fields |
| Team membership | Plane | `project_members` |
| Multi-assignee work | Plane/Vikunja | `task_assignees` |
| Labels | Plane/Vikunja | `task_labels` + `task_label_links` |
| Activity/audit feed | Plane | immutable `task_activity_events` |
| Milestones / planning dates | Leantime | `project_milestones` + optional task milestone |
| Cycles / sprints | Plane + Leantime | `project_cycles` + `project_cycle_tasks` |
| Time tracking | Leantime | `task_time_entries` with one-active-timer invariant |
| CRM/accounting/support linkage | Native CRM | generic `task_entity_links` |

The benchmark projects are references only. The implementation is native to this repository and its existing Python/FastAPI/SQLAlchemy + Flutter architecture.

## Existing modules preserved

- The existing accounting `Project` model remains the canonical project entity.
- Financial documents continue using their existing optional `project_id`.
- CRM `CrmActivity` tasks/follow-ups are **not** replaced in Phase 0.
- AI session todos remain transient AI-agent execution state and are unrelated to business tasks.

A later CRM integration phase will link first-class tasks to CRM entities without overloading `crm_activities`.

## New domain tables

- `project_members`
- `task_statuses`
- `tasks`
- `task_assignees`
- `task_labels`
- `task_label_links`
- `task_relations`
- `task_comments`
- `task_attachments`
- `task_reminders`
- `task_activity_events`
- `project_milestones`
- `project_cycles`
- `project_cycle_tasks`
- `task_time_entries`
- `task_entity_links`

## Key invariants

1. Every task belongs to exactly one business through `business_id`.
2. A task can optionally belong to one existing project.
3. Project/business consistency must be validated in the service layer before writes.
4. Subtasks use `parent_task_id`; dependencies use `task_relations`. These are deliberately separate.
5. Multi-user assignment uses `task_assignees`, not a single assignee column.
6. Statuses and labels are business-scoped and reusable.
7. A task relation cannot point to itself. Cycle detection for parent/dependency graphs belongs in the domain service implemented in later phases.
8. Task activity events are append-only domain events. They are not reconstructed from timestamps.
9. Recurrence fields use RRULE-compatible text so Phase 8 can implement calendar-safe recurrence instead of a limited “every N days” model.
10. Dates use timezone-aware database columns.
11. Association/detail rows carry explicit `business_id` tenant scope even when it can be derived from a task/project.
12. At most one active time timer is allowed per business/user.
13. Task attachments can reference the existing shared `file_storage` subsystem.
14. Milestones and cycles remain planning entities; they are not overloaded as task statuses.
15. Generic entity links use text `entity_type` + `entity_id` so CRM/accounting/support modules can attach tasks without schema churn.

## Deletion policy

- `tasks.deleted_at`: soft delete by default.
- `task_comments.deleted_at`: soft delete.
- Child association/event rows cascade only on an explicit hard delete of a task.
- Deleting a project sets a task's `project_id` to NULL, preserving task history.
- Deleting users removes membership/assignment links where appropriate while preserving authored task/event history with nullable user references.

## Authorization boundary

No task CRUD endpoint is exposed in Phase 0.

When Phase 1 adds APIs:
- every query/write must be scoped by `business_id`;
- existing business-access dependencies remain the outer authorization boundary;
- project membership can narrow access later without replacing business permissions;
- client-side visibility is not considered authorization.

## Performance/indexing

The foundation includes indexes for the expected hot paths:

- business + due/deleted
- business + project + position
- business + status + position
- assignee + task
- task + comment/event time
- reminder user + due time
- dependency reverse lookup

## Phase 0 acceptance gate

- [x] Reuses existing project model; no duplicate project domain.
- [x] First-class task schema exists.
- [x] Foreign-key delete behavior is explicit.
- [x] Soft-delete policy is explicit.
- [x] Business isolation is a required task column.
- [x] Board ordering and future recurrence are represented without schema rework.
- [x] CRM work queue remains operational and separate.
- [x] Flutter has a visible Task Management foundation page.
- [x] Milestones and cycles are represented.
- [x] Time-entry schema and one-active-timer guard exist.
- [x] Generic CRM/accounting/support entity links exist.
- [x] Task association/detail tables carry explicit tenant scope.
- [x] Task attachments can link to the existing shared file-storage record.
- [ ] CRUD/service/API implementation — Phase 1.
- [ ] Task drawer/editor UX — Phase 2.


## Deployment after Phase 0 completion

The Phase 0 completion is an additive Alembic revision and is safe to apply after
the initial Phase 0 migration:

```bash
git pull origin master
cd hesabixAPI
alembic upgrade head
```

The completion revision is `20260926_000002_task_management_phase0_completion`.
It backfills `business_id` from the owning project/task before enforcing NOT NULL
tenant scope, so an already-applied initial Phase 0 migration can be upgraded in place.
