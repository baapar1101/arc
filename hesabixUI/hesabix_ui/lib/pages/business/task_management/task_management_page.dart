import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';

/// Phase 0 shell for the native task/project-management module.
///
/// CRUD intentionally starts in Phase 1. This page makes the completed
/// architecture foundation visible without pretending unfinished actions work.
class TaskManagementPage extends StatelessWidget {
  final int businessId;

  const TaskManagementPage({
    super.key,
    required this.businessId,
  });

  @override
  Widget build(BuildContext context) {
    final padding = ResponsiveHelper.getPadding(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت کارها'),
        leading: IconButton(
          tooltip: 'بازگشت به پروژه‌ها',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/business/${businessId}/projects'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(padding, 16, padding, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassSurface(
                padding: const EdgeInsets.all(20),
                child: Wrap(
                  spacing: 20,
                  runSpacing: 18,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        Icons.task_alt_rounded,
                        size: 30,
                        color: scheme.primary,
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Task & Project Management',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'مرحله ۰ تکمیل شد: مدل دامنه، روابط، ایندکس‌ها و سیاست حذف آماده‌اند. '
                            'ایجاد و ویرایش تسک در مرحله ۱ فعال می‌شود.',
                          ),
                        ],
                      ),
                    ),
                    Chip(
                      avatar: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Phase 0 · Foundation Ready'),
                      side: BorderSide(
                        color: scheme.primary.withValues(alpha: 0.28),
                      ),
                      backgroundColor: scheme.primary.withValues(alpha: 0.08),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 760;
                  final cards = [
                    _BenchmarkCard(
                      title: 'Plane',
                      subtitle: 'Project / Work Item architecture',
                      icon: Icons.view_kanban_outlined,
                      points: const [
                        'وضعیت‌های قابل گروه‌بندی',
                        'عضویت تیم پروژه',
                        'آمادگی برای Board و Views',
                      ],
                    ),
                    _BenchmarkCard(
                      title: 'Vikunja',
                      subtitle: 'Task domain semantics',
                      icon: Icons.account_tree_outlined,
                      points: const [
                        'Subtask و Dependency جدا',
                        'Reminder و Recurrence-ready',
                        'Label و Multi-assignee',
                      ],
                    ),
                  ];

                  if (stacked) {
                    return Column(
                      children: [
                        cards[0],
                        const SizedBox(height: 12),
                        cards[1],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 12),
                      Expanded(child: cards[1]),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              GlassSurface(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.schema_outlined),
                        SizedBox(width: 8),
                        Text(
                          'زیرساخت آماده',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const [
                        _FoundationChip('Existing Projects'),
                        _FoundationChip('Task Core'),
                        _FoundationChip('Statuses'),
                        _FoundationChip('Multi-assignee'),
                        _FoundationChip('Labels'),
                        _FoundationChip('Subtasks'),
                        _FoundationChip('Dependencies'),
                        _FoundationChip('Comments'),
                        _FoundationChip('Attachments'),
                        _FoundationChip('Reminders'),
                        _FoundationChip('Recurrence-ready'),
                        _FoundationChip('Activity Events'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GlassSurface(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.arrow_forward_rounded, color: scheme.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'مرحله بعد: Core Task Engine',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'CRUD، تکمیل/بازگشایی، اولویت، وضعیت، تخصیص کاربر و تاریخ سررسید '
                            'روی همین مدل دامنه پیاده‌سازی خواهد شد.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BenchmarkCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> points;

  const _BenchmarkCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...points.map(
            (point) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 7),
                  Expanded(child: Text(point)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FoundationChip extends StatelessWidget {
  final String label;

  const _FoundationChip(this.label);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(
        Icons.check_circle_rounded,
        size: 17,
        color: scheme.primary,
      ),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: scheme.surface.withValues(alpha: 0.34),
      side: BorderSide(
        color: scheme.outlineVariant.withValues(alpha: 0.55),
      ),
    );
  }
}
