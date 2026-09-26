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


## Phase 1 — Core Task Engine

Implemented on 2026-09-26.

### Backend operations

- Create/list/read/update/soft-delete task
- Complete and reopen task
- Business-scoped status bootstrap
- Priority and due date updates
- Existing-project validation
- Active business-member validation for assignees
- Multi-assignee persistence
- Search and basic filtering
- Domain activity events for create/update/assignment/complete/reopen/delete

### Phase 1 endpoints

- `GET /api/v1/businesses/{business_id}/task-statuses`
- `GET /api/v1/businesses/{business_id}/task-assignees`
- `GET /api/v1/businesses/{business_id}/tasks`
- `POST /api/v1/businesses/{business_id}/tasks`
- `GET /api/v1/businesses/{business_id}/tasks/{task_id}`
- `PATCH /api/v1/businesses/{business_id}/tasks/{task_id}`
- `DELETE /api/v1/businesses/{business_id}/tasks/{task_id}`
- `POST /api/v1/businesses/{business_id}/tasks/{task_id}/complete`
- `POST /api/v1/businesses/{business_id}/tasks/{task_id}/reopen`
- `PUT /api/v1/businesses/{business_id}/tasks/{task_id}/assignees`

### Flutter

The Task Management screen now supports:

- task list and search
- open/completed/status filtering
- create/edit glass dialog
- project, status, priority and assignee selection
- due date selection in a glass modal
- complete/reopen
- soft delete

Phase 2 will replace the edit-oriented interaction with the richer Plane-style task drawer/detail experience.


## Phase 2 — Task UX / Detail Drawer

Implemented on 2026-09-26 using Plane as the primary interaction benchmark.

### UX delivered

- Clicking a task now opens a dedicated task-detail surface instead of the compact create/edit form.
- Desktop: persistent-feeling frosted side drawer with full-height context.
- Mobile: the same editor is presented as a 92% height glass bottom sheet.
- Inline editable title and description.
- Inline status, priority, project, and due-date properties.
- Native multi-assignee editing with filter chips.
- Complete/reopen action directly from the detail surface.
- The list stays compact and context-preserving; creating a task still uses the quick-create dialog.
- The drawer loads a fresh task record before opening to reduce stale edits.
- Project pickers load all projects, not only active ones, so older task/project links remain editable.

Comments, attachments, and activity history remain intentionally outside this phase and are implemented in their later pipeline phases.


## Phase 2 — Task UX / Plane-style interaction

Implemented on 2026-09-26.

### Interaction model

- Desktop task detail opens in a persistent frosted-glass right drawer.
- Mobile task detail opens in a nearly full-height frosted-glass bottom sheet.
- Clicking a task never navigates away from the current list.
- Quick create accepts a task title directly from the list.
- Status can be changed inline from each task card.
- The detail panel edits title, description, project, status, priority, due date and multiple assignees.
- Complete/reopen and soft-delete are available directly in the detail panel.
- Parent list state is updated from API results without a full page navigation/reload.

### Acceptance gate

- [x] Quick task creation from list
- [x] Detail editing without page navigation
- [x] Inline status change
- [x] Multi-assignee UI
- [x] Complete/reopen
- [x] Desktop drawer
- [x] Mobile glass sheet
- [x] Existing glass design system remains authoritative


## Phase 2 — Task UX

Implemented with Plane as the primary interaction benchmark.

### Interaction changes

- One-line quick create: type a title and press Enter.
- Desktop task details open in a persistent glass side drawer; the list remains visible.
- Mobile task details use the same component in a near-full-height glass bottom sheet.
- Status can be changed directly from the task card.
- Status, priority, project, due date and assignees update inline inside the detail surface.
- Assignees are multi-select in the detail surface, matching the underlying multi-assignee domain.
- Title and description edit without navigation or a page reload.
- Complete/reopen and delete update local list state from API responses rather than re-fetching the whole page.

### Phase 2 acceptance gate

- [x] Quick task creation without a separate form.
- [x] Open/edit task while preserving list context.
- [x] Inline status changes.
- [x] Inline project/priority/due-date changes.
- [x] Multi-assignee editing.
- [x] Complete/reopen without page reload.
- [x] Responsive desktop drawer / mobile glass sheet.


## Phase 3 — Project Workspace

Implemented with Plane as the workspace benchmark while retaining the existing accounting Project entity.

- Dedicated project workspace route with Overview and Tasks.
- Native task progress, open/completed/overdue metrics, and financial summary.
- Project-scoped quick task creation and Phase 2 detail drawer.
- First-class project member management on `project_members`.
- Only active users of the same business can join a project.
- Existing Projects list opens the workspace instead of a read-only dialog.

### Phase 3 acceptance gate

- [x] Existing Project remains canonical.
- [x] Project workspace exists.
- [x] Task progress is derived from native tasks.
- [x] Project-scoped task creation/editing works.
- [x] Team membership can be managed.
- [x] Financial and operational project context are visible together.


## Phase 4 — Kanban

Implemented on 2026-09-26 using Plane as the primary workflow benchmark and
Focalboard only as an interaction reference.

### Native board model

- Columns are existing business-scoped `task_statuses`; there is no board-column table.
- Cards are existing `tasks`.
- Persistent card order uses `tasks.sort_order`.
- Move API accepts a target status and insertion index; the server computes a fractional sort value.
- Dense ordering is renormalized only when adjacent fractional positions become too close.
- Moving into a completed status sets completion time; moving out clears it.

### UX delivered

- Project workspace now has Overview, Tasks, and Board tabs.
- Horizontal status columns use the existing glass visual system.
- Drag/drop works across columns and within the same column.
- Drop zones expose exact insertion positions.
- Each column supports quick task creation directly into that status.
- Clicking a board card opens the same Phase 2 task detail drawer/sheet.
- Board cards show assignees and due-date/overdue context.

### Phase 4 endpoint

- `POST /api/v1/businesses/{business_id}/tasks/{task_id}/move`

### Phase 4 acceptance gate

- [x] Status columns are native task statuses.
- [x] Same-column reorder persists.
- [x] Cross-column movement persists.
- [x] Completion semantics follow destination status.
- [x] Board uses existing task editor.
- [x] Quick add works per column.


## Phase 5 — Subtasks & Dependencies

Implemented on 2026-09-26 using Vikunja task-relation semantics as the primary benchmark.

### Hierarchy

- `parent_task_id` is the only hierarchical parent/subtask relation.
- Creating a subtask inherits the parent project.
- Parent and child must remain in the same project.
- Self-parenting and ancestor cycles are rejected server-side.
- Changing a task's project is blocked when it would break existing child hierarchy.

### Semantic relations

- `task_relations` remains separate from hierarchy.
- Supported relation types: `blocks`, `related`, `duplicates`.
- Symmetric duplicate entries are rejected for related/duplicate relations.
- Blocking relations are graph-checked before insertion so dependency cycles cannot be created.
- Incoming `blocks` is rendered as “blocked by”; inverse meaning is derived rather than stored twice.

### UX

- Task detail drawer now shows parent, direct subtasks, and semantic relations.
- Subtasks can be created inline from the existing glass drawer.
- New subtasks immediately appear in the parent task list / project board state.
- Dependency/relation creation uses the currently loaded task set as candidates.
- Relation removal and structure refresh do not navigate away from the task context.

### Phase 5 endpoints

- `GET /api/v1/businesses/{business_id}/tasks/{task_id}/structure`
- `POST /api/v1/businesses/{business_id}/tasks/{task_id}/subtasks`
- `POST /api/v1/businesses/{business_id}/tasks/{task_id}/relations`
- `DELETE /api/v1/businesses/{business_id}/tasks/{task_id}/relations/{relation_id}`

### Phase 5 acceptance gate

- [x] Parent/subtask hierarchy is native.
- [x] Parent cycles are prevented.
- [x] Dependency cycles are prevented.
- [x] Hierarchy and dependencies remain separate concepts.
- [x] Drawer exposes subtasks and dependencies without page navigation.


## Phase 6 — Comments & Activity

Implemented on 2026-09-26 using Plane's work-item conversation/activity pattern.

### Comments

- Comments are native `task_comments`, scoped by business and task.
- Comments support create, edit and soft-delete.
- Only the comment author or business owner can edit/delete a comment.
- Comment mutations append activity events; comments themselves are not used as the audit trail.

### Activity

- `task_activity_events` remains append-only and immutable.
- The feed exposes actor, event type, structured event metadata and timestamp.
- Existing task operations already feed this stream: create/update, assignment, completion/reopen,
  Kanban movement, subtask creation, relation mutations, and comment actions.
- Activity is rendered read-only in the task drawer.

### UX

- Existing task drawer now includes a Comments & Activity section.
- Comment creation, editing and deletion stay inside task context.
- Activity presents actor/action/time without navigating away.
- Refresh is section-local; task list and board are not reloaded.

### Phase 6 endpoints

- `GET /api/v1/businesses/{business_id}/tasks/{task_id}/comments`
- `POST /api/v1/businesses/{business_id}/tasks/{task_id}/comments`
- `PATCH /api/v1/businesses/{business_id}/tasks/{task_id}/comments/{comment_id}`
- `DELETE /api/v1/businesses/{business_id}/tasks/{task_id}/comments/{comment_id}`
- `GET /api/v1/businesses/{business_id}/tasks/{task_id}/activity`

### Phase 6 acceptance gate

- [x] Comments are tenant-scoped.
- [x] Comment edit/delete is authorization-checked server-side.
- [x] Activity events are immutable.
- [x] Existing task operations are visible in the feed.
- [x] Comments and activity share the existing glass task drawer.


## Phase 7 — Labels, Filters & Saved Views

Implemented on 2026-09-26 using Plane's filtering/custom-view model as the benchmark.

### Labels

- Reuses Phase 0 business-scoped `task_labels` and `task_label_links`.
- Tasks support multiple labels.
- Labels can be created and assigned inline in the existing task drawer.
- Task cards expose assigned labels.
- Label assignment appends a structured activity event.

### Filtering

The native task query now supports:
- search
- status
- project
- assignee
- priority
- label
- creator
- due-date range
- completion state
- structured sort field/direction

The main task screen exposes project, assignee, label, priority, due preset,
completion and sorting controls.

### Saved views

- New `task_saved_views` storage is business-scoped and user-owned.
- Shared views can be read by other business members.
- Only the owner can edit or delete a saved view.
- Saved views persist structured filter/sort JSON only; no SQL or executable expression is stored.
- The main task screen can snapshot, apply and delete saved views.

### Phase 7 endpoints

- `GET/POST /api/v1/businesses/{business_id}/task-labels`
- `PATCH/DELETE /api/v1/businesses/{business_id}/task-labels/{label_id}`
- `PUT /api/v1/businesses/{business_id}/tasks/{task_id}/labels`
- `GET/POST /api/v1/businesses/{business_id}/task-views`
- `PATCH/DELETE /api/v1/businesses/{business_id}/task-views/{view_id}`

### Phase 7 migration

- `20260926_000003_task_saved_views`

### Phase 7 acceptance gate

- [x] Multiple labels per task.
- [x] Label filtering.
- [x] Multi-dimensional task filtering.
- [x] Structured sorting.
- [x] User-owned saved views.
- [x] Optional shared views.
- [x] Saved views contain structured JSON only.


## Phase 8 — Recurrence & Reminders

Implemented on 2026-09-26 using Vikunja's recurrence/reminder semantics as the benchmark.

### Recurrence

- Recurrence uses the Phase 0 `recurrence_rule`, `recurrence_timezone`, and `recurrence_end_at` fields.
- Rules are validated with RFC 5545-compatible RRULE parsing.
- UI provides safe presets: daily, weekdays, weekly, monthly, yearly; custom rules remain API-compatible.
- COUNT/UNTIL inside RRULE are rejected so recurrence termination has one canonical field: `recurrence_end_at`.
- Business display timezone is used by default and stored with the recurring task.
- Completing a recurring task creates exactly one next occurrence.
- Next occurrence generation is idempotent via the immutable activity stream.
- Project, parent hierarchy, milestone, priority, description, estimate, assignees and labels are copied.
- Moving a recurring task into a completed Kanban column triggers the same recurrence behavior.

### Reminders

- Reminders use native `task_reminders`.
- Supported relative anchors are start and due dates with minute offsets.
- Date edits automatically recalculate pending relative reminders.
- Removing an anchor date removes pending reminders that depend on it.
- Reminder delivery is intentionally deferred to Phase 15 notifications; Phase 8 owns schedule semantics only.

### Phase 8 endpoints

- `GET /api/v1/businesses/{business_id}/tasks/{task_id}/reminders`
- `POST /api/v1/businesses/{business_id}/tasks/{task_id}/reminders`
- `DELETE /api/v1/businesses/{business_id}/tasks/{task_id}/reminders/{reminder_id}`

### Phase 8 acceptance gate

- [x] RRULE recurrence is validated.
- [x] Timezone is explicit and business-aware.
- [x] Completion creates one next occurrence only.
- [x] Start and due dates are editable.
- [x] Relative reminders can be created and removed.
- [x] Reminder times follow date changes.


## Phase 9 — Calendar

Implemented on 2026-09-26 as a native task view with no new persistence entity.

### Calendar semantics

- Calendar renders existing `start_at` / `due_at` task dates.
- Tasks with a start and due range appear on each covered day.
- Undated tasks stay out of the calendar until scheduled.
- Month, Week, Day and Agenda modes share the same task data.
- Project workspace Calendar is the fourth project view after Overview, Tasks and Board.

### Rescheduling

- Task cards are draggable.
- Month/week/day cells are drop targets.
- Dropping a task onto another day shifts both start and due by the same day delta, preserving duration.
- A previously undated task receives a 17:00 due time on the target day.
- Server remains authoritative because every drop persists through the existing task update endpoint.
- Relative reminders from Phase 8 automatically follow moved task dates.

### Phase 9 acceptance gate

- [x] Month view.
- [x] Week view.
- [x] Day view.
- [x] Agenda view.
- [x] Drag-to-reschedule.
- [x] Multi-day task rendering.
- [x] No separate calendar-event entity.
