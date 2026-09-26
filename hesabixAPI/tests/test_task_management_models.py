from adapters.db.models.task_management import (
    Milestone,
    ProjectCycle,
    ProjectCycleTask,
    ProjectMember,
    Task,
    TaskActivity,
    TaskAssignee,
    TaskAttachment,
    TaskComment,
    TaskEntityLink,
    TaskLabel,
    TaskLabelLink,
    TaskRelation,
    TaskReminder,
    TaskStatus,
    TaskTimeEntry,
)


def test_phase_zero_tables_are_registered() -> None:
    expected = {
        "project_members",
        "task_statuses",
        "tasks",
        "task_assignees",
        "task_labels",
        "task_label_links",
        "task_relations",
        "task_comments",
        "task_attachments",
        "task_reminders",
        "task_activity_events",
        "project_milestones",
        "project_cycles",
        "project_cycle_tasks",
        "task_time_entries",
        "task_entity_links",
    }
    actual = {
        ProjectMember.__table__.name,
        TaskStatus.__table__.name,
        Task.__table__.name,
        TaskAssignee.__table__.name,
        TaskLabel.__table__.name,
        TaskLabelLink.__table__.name,
        TaskRelation.__table__.name,
        TaskComment.__table__.name,
        TaskAttachment.__table__.name,
        TaskReminder.__table__.name,
        TaskActivity.__table__.name,
        Milestone.__table__.name,
        ProjectCycle.__table__.name,
        ProjectCycleTask.__table__.name,
        TaskTimeEntry.__table__.name,
        TaskEntityLink.__table__.name,
    }
    assert actual == expected


def test_task_core_columns_cover_pipeline_contract() -> None:
    columns = set(Task.__table__.columns.keys())
    assert {
        "business_id",
        "project_id",
        "parent_task_id",
        "status_id",
        "milestone_id",
        "title",
        "description",
        "priority",
        "sort_order",
        "start_at",
        "due_at",
        "completed_at",
        "estimated_minutes",
        "recurrence_rule",
        "recurrence_timezone",
        "recurrence_end_at",
        "created_by_user_id",
        "archived_at",
        "deleted_at",
    }.issubset(columns)


def test_task_detail_tables_are_explicitly_business_scoped() -> None:
    scoped = (
        ProjectMember,
        TaskAssignee,
        TaskLabelLink,
        TaskRelation,
        TaskComment,
        TaskAttachment,
        TaskReminder,
        TaskActivity,
        ProjectCycleTask,
        TaskTimeEntry,
        TaskEntityLink,
    )
    for model in scoped:
        assert "business_id" in model.__table__.columns.keys(), model.__name__


def test_generic_entity_link_is_domain_agnostic() -> None:
    columns = set(TaskEntityLink.__table__.columns.keys())
    assert {"business_id", "task_id", "entity_type", "entity_id", "relationship_type"}.issubset(columns)


def test_time_tracking_has_one_active_timer_guard() -> None:
    indexes = {index.name: index for index in TaskTimeEntry.__table__.indexes}
    active = indexes["uq_task_time_entries_active_user"]
    assert active.unique is True
    assert {column.name for column in active.columns} == {"business_id", "user_id"}
    assert active.dialect_options["postgresql"]["where"] is not None


def test_task_attachment_reuses_shared_file_storage() -> None:
    assert "file_storage_id" in TaskAttachment.__table__.columns.keys()
    fk_targets = {
        fk.target_fullname
        for fk in TaskAttachment.__table__.c.file_storage_id.foreign_keys
    }
    assert "file_storage.id" in fk_targets


def test_soft_delete_and_planning_fields_are_distinct() -> None:
    assert Task.__table__.c.deleted_at.nullable is True
    assert Task.__table__.c.archived_at.nullable is True
    assert Task.__table__.c.milestone_id.nullable is True
