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
- Baseline workflow statuses include Backlog, To Do, In Progress, Blocked, Review, Done and Cancelled; custom business statuses can coexist without being replaced.

### UX delivered

- Project workspace now has Overview, Tasks, and Board tabs.
- Horizontal status columns use the existing glass visual system.
- Drag/drop works across columns and within the same column.
- Drop zones expose exact insertion positions.
- Each column supports quick task creation directly into that status.
- Clicking a board card opens the same Phase 2 task detail drawer/sheet.
- Board cards show assignees and due-date/overdue context.
- Board filters cover text search, priority, assignee, label and due state.
- Filtered drag/drop translates the visible drop zone back to the absolute unfiltered column index before calling the move API, so hidden cards keep stable ordering.

### Phase 4 endpoint

- `POST /api/v1/businesses/{business_id}/tasks/{task_id}/move`

### Phase 4 acceptance gate

- [x] Status columns are native task statuses.
- [x] Same-column reorder persists.
- [x] Cross-column movement persists.
- [x] Completion semantics follow destination status.
- [x] Board uses existing task editor.
- [x] Quick add works per column.
- [x] Blocked and Review baseline workflow states are available.
- [x] Board filtering works without changing the canonical task/status model.
- [x] Filtered drag/drop preserves absolute server ordering.


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

The main task screen exposes project, assignee, label, creator, priority, due preset,
completion and sorting controls.

Filter state is URL-backed. Search/status/project/assignee/label/creator/priority,
due preset/completion/sort and selected saved-view ID are serialized into the
`/business/{business_id}/tasks` query string. Opening a copied URL hydrates the
same normalized filter state before the first task request.

### Saved views

- New `task_saved_views` storage is business-scoped and user-owned.
- Shared views can be read by other business members.
- Only the owner can edit or delete a saved view.
- Saved views persist structured filter/sort JSON only; no SQL or executable expression is stored.
- The main task screen can snapshot, apply and delete saved views.
- Applying a saved view writes its normalized filters/sort into the URL; URL state remains independently reproducible even if the saved-view record later changes.

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
- [x] Creator filtering is exposed in the task UI.
- [x] URL state and saved-view state use the same normalized filter/sort fields.
- [x] Copied task URLs restore filter/sort state before loading results.


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
- Regression coverage validates Europe/London and America/New_York DST transitions, local-clock preservation, duration preservation, recurrence end bounds, invalid/noncanonical RRULE rejection, reminder rescheduling/removal, and idempotent next-occurrence generation.
- A focused GitHub Actions workflow runs the recurrence regression suite whenever the recurrence service or its tests change.

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
- [x] DST/timezone recurrence regression coverage.
- [x] Recurrence end-bound and invalid RRULE coverage.
- [x] Next-occurrence idempotency is regression-tested.
- [x] Relative reminder rescheduling/removal is regression-tested.


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


## Phase 10 — Timeline / Gantt

Implemented on 2026-09-26 using Leantime planning concepts and Vikunja dependency semantics.

### Data model

- Timeline uses existing task `start_at` and `due_at`; no Gantt-specific task table.
- Blocking edges come directly from existing `task_relations` where `relation_type = blocks`.
- Project timeline endpoint returns only scheduled task IDs/date bounds plus dependency edges.
- Full task metadata continues to come from the normal project task list, avoiding duplicate payloads.
- Milestone management remains owned by Phase 11; when Phase 11 milestone data is present, the Timeline consumes that canonical data directly rather than duplicating it.

### UX

- Project workspace now includes a fifth Timeline tab.
- Day, Week and Month zoom levels change pixels-per-day while preserving date accuracy.
- Fixed task-name column stays visible beside a horizontally scrollable time scale.
- Task bars render start/due duration and open the existing task drawer on click.
- Dependency edges are drawn as connector paths from blocking task end to blocked task start.
- A today marker is drawn on the time scale.
- Unscheduled task count is surfaced without inventing dates.
- Project milestones are passed into the Timeline and render as target-date markers on the same time scale.
- Timeline bounds include milestone start/target dates, so milestones outside task date ranges are not clipped.
- A dated milestone can keep the Timeline useful even when the project has no scheduled task bars yet.

### Phase 10 endpoint

- `GET /api/v1/businesses/{business_id}/projects/{project_id}/timeline`

### Phase 10 acceptance gate

- [x] Task bars.
- [x] Day/week/month zoom.
- [x] Today marker.
- [x] Blocking dependency connectors.
- [x] Unscheduled task visibility.
- [x] Canonical project milestone markers are integrated.
- [x] Milestone dates participate in Timeline bounds.
- [x] No duplicate Gantt persistence model.


## Phase 11 — Milestones

Implemented on 2026-09-26 using the Phase 0 milestone entity and Leantime-style milestone planning.

### Domain

- `project_milestones` is the canonical project milestone table.
- Tasks link through existing `tasks.milestone_id`.
- Milestones are business- and project-scoped.
- Optional `owner_id` is a foreign key to an active member of the same business and uses `ON DELETE SET NULL`.
- Milestone create/update rejects owners who are not active business members.
- Task assignment rejects milestones from another project.
- Moving a task to another project clears an incompatible milestone unless a valid replacement is supplied.
- Deleting a milestone uses the existing `ON DELETE SET NULL` task link behavior.
- Milestone progress is derived from assigned task completion; no duplicated progress field is stored.

### UX

- Project workspace now has a Milestones tab.
- Milestone target dates are also visible in the Timeline/Gantt view using the same canonical milestone records.
- Milestones support create, edit, owner assignment, status changes, dates and delete.
- Milestone cards show the owner when assigned; the editor reuses the existing business-member/assignee options.
- Each milestone card shows assigned/completed task counts and derived progress.
- Task drawer can assign or clear a milestone dynamically based on its selected project.
- Timeline shows milestone target dates as vertical markers/diamonds.

### Phase 11 endpoints

- `GET /api/v1/businesses/{business_id}/projects/{project_id}/milestones`
- `POST /api/v1/businesses/{business_id}/projects/{project_id}/milestones`
- `PATCH /api/v1/businesses/{business_id}/projects/{project_id}/milestones/{milestone_id}`
- `DELETE /api/v1/businesses/{business_id}/projects/{project_id}/milestones/{milestone_id}`

### Phase 11 acceptance gate

- [x] Milestone CRUD.
- [x] Optional milestone ownership with server-side membership validation.
- [x] Task-to-milestone assignment.
- [x] Project-scope validation.
- [x] Derived task completion progress.
- [x] Gantt target markers.


## Phase 12 — Cycles / Sprints

Implemented on 2026-09-26 using Plane-style cycle planning over the Phase 0 cycle tables.

### Domain

- `project_cycles` is the canonical sprint/cycle entity.
- Task membership uses `project_cycle_tasks`.
- Cycle status supports planned, active, completed and cancelled.
- Start/end dates are optional and validated when both exist.
- Task membership is many-to-many as represented by the Phase 0 schema.
- A task can only join cycles belonging to its own project.
- Cycle progress is derived from linked task completion; no progress value is duplicated.

### UX

- Project workspace now includes a Cycles tab.
- Cycles support create/edit/delete, goal, status and dates.
- Cycle cards show linked/completed task counts and derived progress.
- Task drawer exposes multi-select Cycle/Sprint membership.
- Task cycle changes append an immutable `cycles_changed` activity event.

### Phase 12 endpoints

- `GET/POST /api/v1/businesses/{business_id}/projects/{project_id}/cycles`
- `PATCH/DELETE /api/v1/businesses/{business_id}/projects/{project_id}/cycles/{cycle_id}`
- `GET/PUT /api/v1/businesses/{business_id}/tasks/{task_id}/cycles`

### Phase 12 acceptance gate

- [x] Cycle CRUD.
- [x] Project-scoped cycle validation.
- [x] Many-to-many task membership.
- [x] Derived progress.
- [x] Cycle membership in the task drawer.
- [x] Cycle workspace tab.


## Phase 13 — Time Tracking

Implemented on 2026-09-26 using Leantime-style task time tracking over the Phase 0 `task_time_entries` table.

### Domain

- The existing partial unique index remains authoritative: one active timer per business/user.
- Timers and manual entries are business- and task-scoped.
- Timer stop calculates immutable elapsed seconds for the entry.
- Manual entries accept start/end or start + duration.
- Completed entries can be edited or deleted by the entry owner or business owner.
- Active entries must be stopped before editing/deleting.
- Start/stop/manual/edit/delete operations append task activity events.
- Billable is stored per time entry; no financial posting is performed in this phase.

### UX

- Task drawer now includes Time Tracking.
- Users can start/stop a live timer with second-by-second elapsed display.
- Starting another timer is blocked while any timer in the same business is active for that user.
- Manual time registration supports date, end time, duration, note and billable flag.
- Task drawer shows recent time entries and total logged time.
- Project workspace includes a Timesheet tab with project totals, billable totals, user rollups, task rollups and entry history.

### Phase 13 endpoints

- `GET /api/v1/businesses/{business_id}/time-entries`
- `GET /api/v1/businesses/{business_id}/timer/active`
- `POST /api/v1/businesses/{business_id}/tasks/{task_id}/timer/start`
- `POST /api/v1/businesses/{business_id}/timer/stop`
- `POST /api/v1/businesses/{business_id}/tasks/{task_id}/time-entries`
- `PATCH/DELETE /api/v1/businesses/{business_id}/time-entries/{entry_id}`

### Phase 13 acceptance gate

- [x] One active timer per business/user.
- [x] Start/stop live timer.
- [x] Manual time entry.
- [x] Billable flag.
- [x] Owner/author edit-delete authorization.
- [x] Task drawer time UI.
- [x] Project Timesheet rollups.


## Phase 14 — CRM Entity Linking

Implemented on 2026-09-27 as a Hesabix-native integration phase.

### Native link domain

- Reuses Phase 0 `task_entity_links`; no new migration.
- Supported tenant-verifiable entity types:
  - `person` — customer/contact/person
  - `lead` — CRM lead
  - `deal` — CRM sales opportunity
  - `crm_activity` — legacy CRM activity/follow-up
  - `document` — accounting document/invoice/proforma/document
  - `product` — product/service
- Support tickets are intentionally excluded because the current support ticket model has no `business_id`; linking them generically would weaken tenant isolation.
- Every new link validates the target entity against the task's business.
- Relationship types are constrained to structured values such as related, customer, contact, regarding, billing, product and follow-up.
- Link add/remove operations append immutable task activity events.
- Generic links can survive later deletion of the target; the task UI marks such references as deleted instead of corrupting task history.

### Bidirectional access

- Task drawer can search real business entities and add/remove links.
- Reverse lookup returns first-class tasks linked to any supported entity.
- CRM Lead record exposes linked first-class tasks with quick create + complete/reopen.
- CRM Deal record exposes linked first-class tasks with quick create + complete/reopen.
- Customer 360 exposes first-class tasks linked to the Person/customer.
- Legacy CRM Activity tasks remain separate and are explicitly labeled as such in the UI.

### Phase 14 endpoints

- `GET /api/v1/businesses/{business_id}/task-link-entity-types`
- `GET /api/v1/businesses/{business_id}/task-link-targets`
- `GET/POST /api/v1/businesses/{business_id}/tasks/{task_id}/entity-links`
- `DELETE /api/v1/businesses/{business_id}/tasks/{task_id}/entity-links/{link_id}`
- `GET /api/v1/businesses/{business_id}/entities/{entity_type}/{entity_id}/tasks`

### Phase 14 acceptance gate

- [x] No duplicate CRM ownership model.
- [x] Cross-business entity links are rejected server-side.
- [x] Task drawer supports searchable entity linking.
- [x] Reverse entity-to-task lookup.
- [x] Customer/Lead/Deal record surfaces expose first-class linked tasks.
- [x] Legacy CRM tasks remain operational and semantically separate.


## Phase 15 — Notifications

Implemented on 2026-09-27 by reusing Hesabix's existing multi-channel notification stack.

### Delivery architecture

- No task-specific notification inbox or provider stack was introduced.
- Task domain events feed the existing `NotificationService`, notification outbox, in-app announcements and user channel settings.
- When Redis/RQ is available, task mutations enqueue delivery jobs so email/in-app delivery is outside task CRUD.
- When Redis is disabled or unavailable, mutation paths fall back to **in-app only**; external provider I/O never blocks task writes.
- In-app notifications include task/project deep links through the existing announcement navigation resolver.
- Existing user channel preferences continue to govern delivery.

### Immediate domain events

- `task.assigned` — newly assigned users; actor excluded.
- `task.comment_added` — task assignees + creator; commenting actor excluded.
- `task.dependency_resolved` — when a blocking task transitions to completed, recipients of dependent tasks are notified.
- `task.project_member_added` — newly added project member; actor excluded.

### Scheduled conditions

A leader-only five-minute scanner is registered in `app/main.py` using the existing background-job lock.

- `task.reminder` — unsent Phase 8 reminders whose trigger time has arrived.
- `task.due_soon` — first notification when an active task enters the next 24-hour due window.
- `task.overdue` — first notification after an active task passes its due time.
- Reminder delivery uses `task_reminders.sent_at` for idempotency.
- Due-soon/overdue use immutable task-activity marker events, so multi-worker restarts do not repeatedly notify.
- Completed/cancelled/deleted tasks are excluded from scheduled alerts.

### Scope decisions

- Structured mentions are not fabricated from comment text in this phase. A future mention feature should persist explicit mentioned user IDs instead of guessing names with regex.
- Notification templates remain optional: event contexts always include a fallback subject/message, so the events work before admin templates are created.

### Phase 15 acceptance gate

- [x] Assignment notifications.
- [x] Comment notifications.
- [x] Dependency-resolved notifications.
- [x] Project-member notifications.
- [x] Reminder delivery.
- [x] Due-soon alerts.
- [x] Overdue alerts.
- [x] Existing notification preferences/channels reused.
- [x] Background scanner is leader-only and idempotent.


## Phase 16 — Attachments

Implemented on 2026-09-27 using the existing Hesabix FileStorage subsystem.

### Storage architecture

- No binary content is stored in SQL task rows.
- Each task upload is a normal FileStorage record with:
  - `module_context = tasks`
  - `context_id = task_id`
  - the owning `business_id`
- `task_attachments.file_storage_id` links task metadata to FileStorage.
- Existing storage configuration, local/FTP backend handling, maximum-file-size checks, business storage plans and storage-usage accounting are reused.
- A maximum of 50 attachments per task is enforced.
- Removing an attachment soft-deletes the FileStorage item and releases its storage usage.
- Attachment add/remove actions append immutable task activity events.

### UX

- The existing glass task drawer contains an Attachments section.
- Cross-platform file selection uses the project's existing `file_picker`.
- Download uses the existing `BytesExportService`, preserving browser/native save behavior.
- File name, size, uploader and upload time are shown in the task context.

### Phase 16 endpoints

- `GET /api/v1/businesses/{business_id}/tasks/{task_id}/attachments`
- `POST /api/v1/businesses/{business_id}/tasks/{task_id}/attachments`
- `GET /api/v1/businesses/{business_id}/tasks/{task_id}/attachments/{attachment_id}/download`
- `DELETE /api/v1/businesses/{business_id}/tasks/{task_id}/attachments/{attachment_id}`

### Phase 16 acceptance gate

- [x] Native upload.
- [x] Tenant-scoped listing/download/delete.
- [x] Central FileStorage integration.
- [x] Storage plan/quota accounting reused.
- [x] Cross-platform download UX.
- [x] Activity feed events for attachment add/remove.


## Phase 17 — Permissions

Implemented on 2026-09-28 using the existing business-permission JSON plus project-member roles.

### Business permission section

The new `projects` section supports:
- `view`
- `project_create`
- `project_edit`
- `project_delete`
- `manage_members`
- `task_create`
- `task_edit`
- `task_delete`
- `task_assign`
- `time_log`
- `time_view_team`

Existing businesses remain backward compatible: if a member has no `projects`
section at all, legacy project/task access remains enabled. Once the owner saves
an explicit `projects` block, those permissions become authoritative.

### Project roles

- Viewer: project/task read access.
- Member: task create/edit and own time logging.
- Manager: project edit, member management, assignment, task deletion and team time.
- Owner: manager capabilities plus project deletion.

Business-wide permissions may grant broader access; project roles can grant
scoped access to individual projects.

### Server enforcement

- Project and task routers use automatic authorization dependencies.
- Project lists/search/active pickers are filtered to accessible project IDs.
- Task lists are filtered to accessible projects plus personal unprojected tasks.
- Task collection creation checks `task_create`.
- Team time degrades to self-only when `time_view_team` is absent.
- Reverse CRM entity task lookups are filtered by task visibility.
- The Flutter permission editor exposes the granular project section.
- UI buttons reflect business permissions, but server authorization remains authoritative.

### Phase 17 acceptance gate

- [x] Business project/task permission section.
- [x] Backward-compatible rollout.
- [x] Project role matrix.
- [x] Server-side route guards.
- [x] Project/task list visibility filtering.
- [x] Own-vs-team time enforcement.
- [x] Permission editor and action visibility.


## Phase 18 — Dashboard / Analytics

Implemented on 2026-09-28 using Plane/Leantime dashboard concepts with transparent native metrics.

### Dashboard scope

The business Task module can toggle between the existing task list and a
permission-aware analytics dashboard.

The dashboard exposes:
- open tasks
- due today
- overdue
- completed in the last 7 days
- unassigned work
- logged time in the last 7 days
- current user's open work
- status distribution
- project completion / overdue progress
- assignee workload
- active milestones
- active cycles
- recent completions
- billable vs total logged time

### Permission behavior

- Task/project metrics use the Phase 17 visibility scope.
- Restricted members see project metrics only for projects they can access.
- Team time is shown only with `time_view_team`; otherwise time totals are self-only.
- The API returns an explicit scope descriptor so the UI does not imply broader coverage.

### Metric design

There is deliberately no opaque “project health score.” Progress, overdue work,
workload and time are displayed as independent inspectable metrics.

### Phase 18 endpoint

- `GET /api/v1/businesses/{business_id}/task-dashboard`

### Phase 18 acceptance gate

- [x] Permission-aware aggregate API.
- [x] Summary KPIs.
- [x] My-work queue.
- [x] Project progress.
- [x] Workload view.
- [x] Milestone/cycle progress.
- [x] 7-day time metrics.
- [x] No unexplained synthetic score.


## Phase 19 — Templates & Automation

Implemented on 2026-09-28 using native task/project data plus the existing Hesabix Workflow engine.

### Template model

- New `task_project_templates` stores a business-scoped project blueprint.
- Project defaults and task specifications are structured JSON; instantiated tasks are normal native tasks.
- Template task keys are local identifiers used only to rebuild parent/subtask hierarchy.
- Task specifications can carry status key, priority, relative start/due offsets, estimate, assignees, labels and recurrence settings.
- A template can contain up to 500 tasks.
- Project dates are relative to a chosen base date, so the same template can be reused later.

### Native workflows

- Any project workspace can be saved as a template.
- The Projects page has a template manager and can instantiate a template as a new project.
- Instantiation can target an existing project through the API.
- New projects inherit template defaults while receiving a new code/name/start date.
- Parent/subtask hierarchy is reconstructed in dependency order.
- Optional CRM entity parameters can link all generated tasks to a Person, Lead, Deal, CRM Activity, Document or Product.

### Workflow automation

The existing Workflow ActionRegistry now exposes:
- `task_template_instantiate` — “ایجاد پروژه/کارها از قالب”

Because Workflow editor actions are metadata-driven, this action appears in the
existing workflow palette/config UI automatically. It can consume trigger/node
references for project name/code, person ID, CRM entity link and other inputs.

This allows existing workflow triggers (CRM, person, documents, schedules, etc.)
to generate a native project and task plan without a second automation engine.

### Phase 19 endpoints

- `GET/POST /api/v1/businesses/{business_id}/task-templates`
- `PATCH/DELETE /api/v1/businesses/{business_id}/task-templates/{template_id}`
- `POST /api/v1/businesses/{business_id}/projects/{project_id}/task-template-snapshot`
- `POST /api/v1/businesses/{business_id}/task-templates/{template_id}/instantiate`

### Phase 19 migration

- `20260928_000004_task_project_templates`

### Phase 19 acceptance gate

- [x] Save project as template.
- [x] Relative date offsets.
- [x] Subtask hierarchy reconstruction.
- [x] Assignee/label/status reuse.
- [x] Instantiate into new or existing project.
- [x] Optional CRM entity linkage.
- [x] Existing Workflow engine action integration.
- [x] No parallel automation engine.


## Phase 20 — UX / Performance / Polish

Implemented on 2026-09-28 as the final benchmark/polish pass.

### Command workflow

- Task module includes a command palette available from the AppBar or Ctrl/Cmd+K.
- Palette actions cover new task, Dashboard/List switching, Due Today, Overdue, clear filters and multi-select mode.
- Alt+D toggles Dashboard/List.
- Alt+S toggles selection mode.
- Escape exits selection mode.

### Bulk operations

- Multi-select mode reuses the leading checkbox position to avoid competing controls.
- Long-press enters selection mode on touch devices.
- Loaded tasks can be select-all.
- Bulk status and priority updates use dedicated bounded backend endpoints.
- Bulk delete permission-checks every task and remains soft-delete.
- Bulk requests are capped at 200 task IDs.

### Undo

- Single and bulk deletes expose Undo through the existing root Snackbar/overlay system.
- Undo restores the same task record; IDs, comments, files, links, activity and task relationships remain intact.
- Restore itself is permission checked.

### Large lists

- Task loading uses server-side pages of 100 records.
- “Load more” appends subsequent pages without re-fetching previously loaded rows.
- Filter changes reset pagination to page 1.
- This bounds initial Flutter widget creation even for large task sets.

### Existing polished behavior retained

- Quick create.
- Inline status changes.
- Native glass task drawer.
- Responsive desktop/mobile detail surfaces.
- Kanban drag/drop.
- Calendar drag rescheduling.
- Gantt/Timeline.
- Saved views.
- Analytics dashboard.

### Realtime note

The current repository does not expose a task realtime/WebSocket transport.
Phase 20 does not mislabel polling as realtime; live task sync can be added later
when a supported task event channel exists.

### Phase 20 endpoints

- `POST /api/v1/businesses/{business_id}/tasks/bulk-update`
- `POST /api/v1/businesses/{business_id}/tasks/bulk-delete`
- `POST /api/v1/businesses/{business_id}/tasks/restore`

### Phase 20 acceptance gate

- [x] Command palette.
- [x] Keyboard shortcuts.
- [x] Multi-select.
- [x] Bulk status/priority/delete.
- [x] Soft-delete Undo.
- [x] Bounded server pagination/load-more.
- [x] Responsive glass interaction model retained.
- [x] No fake realtime claim.
