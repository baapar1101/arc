import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/task_optimistic_patch.dart';

const todo = TaskStatusModel(
  id: 1,
  key: 'todo',
  name: 'To Do',
  category: 'unstarted',
  isDefault: true,
  isClosed: false,
);

const progress = TaskStatusModel(
  id: 2,
  key: 'in_progress',
  name: 'In Progress',
  category: 'started',
  isDefault: false,
  isClosed: false,
);

const done = TaskStatusModel(
  id: 3,
  key: 'done',
  name: 'Done',
  category: 'completed',
  isDefault: false,
  isClosed: true,
);

TaskModel task({
  int id = 10,
  int statusId = 1,
  TaskStatusModel status = todo,
  double sortOrder = 1000,
  DateTime? completedAt,
}) =>
    TaskModel(
      id: id,
      businessId: 1,
      projectId: 7,
      projectName: 'CRM',
      statusId: statusId,
      status: status,
      title: 'Review invoice',
      description: 'Initial',
      priority: 'normal',
      sortOrder: sortOrder,
      completedAt: completedAt,
      assignees: const [],
      labels: const [],
      createdByUserId: 2,
    );

void main() {
  const statuses = [todo, progress, done];
  const assignees = [
    TaskAssigneeOption(
      userId: 4,
      name: 'Alex',
      role: 'member',
    ),
  ];
  const labels = [
    TaskLabelModel(
      id: 9,
      name: 'Urgent',
    ),
  ];

  test('patch applies visible task fields before server response', () {
    final result = applyTaskOptimisticPatch(
      task(),
      {
        'title': 'Review invoice now',
        'priority': 'high',
        'status_id': 2,
        'due_at': '2026-10-02T12:00:00Z',
        'assignee_user_ids': [4],
        'label_ids': [9],
      },
      statuses: statuses,
      projects: const [],
      assignees: assignees,
      labels: labels,
    );

    expect(result.title, 'Review invoice now');
    expect(result.priority, 'high');
    expect(result.statusId, 2);
    expect(result.status?.category, 'started');
    expect(result.dueAt, DateTime.parse('2026-10-02T12:00:00Z'));
    expect(result.assignees.single.userId, 4);
    expect(result.labels.single.id, 9);
    expect(result.completedAt, isNull);
  });

  test('complete and reopen mirror server status semantics', () {
    final completed = optimisticCompleteTask(task(), statuses);
    expect(completed.statusId, 3);
    expect(completed.isCompleted, isTrue);
    expect(completed.completedAt, isNotNull);

    final reopened = optimisticReopenTask(completed, statuses);
    expect(reopened.statusId, 1);
    expect(reopened.status?.isDefault, isTrue);
    expect(reopened.completedAt, isNull);
    expect(reopened.isCompleted, isFalse);
  });

  test('kanban move computes immediate target ordering', () {
    final source = task(id: 10, sortOrder: 1000);
    final targetA = task(
      id: 20,
      statusId: 2,
      status: progress,
      sortOrder: 1000,
    );
    final targetB = task(
      id: 21,
      statusId: 2,
      status: progress,
      sortOrder: 2000,
    );

    final moved = optimisticMoveTask(
      source,
      targetStatusId: 2,
      targetIndex: 1,
      allTasks: [source, targetA, targetB],
      statuses: statuses,
    );

    expect(moved.statusId, 2);
    expect(moved.sortOrder, greaterThan(targetA.sortOrder));
    expect(moved.sortOrder, lessThan(targetB.sortOrder));
    expect(moved.completedAt, isNull);
  });

  test('moving to completed status marks task complete immediately', () {
    final moved = optimisticMoveTask(
      task(),
      targetStatusId: 3,
      targetIndex: 0,
      allTasks: [task()],
      statuses: statuses,
    );

    expect(moved.statusId, 3);
    expect(moved.isCompleted, isTrue);
    expect(moved.completedAt, isNotNull);
  });
}
