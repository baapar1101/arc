import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/workflow_editor_models.dart';
import '../../utils/workflow_basalam_guard.dart';

/// پالت node های قابل افزودن به workflow
class WorkflowNodePalette extends StatelessWidget {
  final List<WorkflowNodeMetadata> triggers;
  final List<WorkflowNodeMetadata> actions;
  final bool basalamPluginActive;
  final Function(WorkflowNodeType type, String key, String name) onNodeSelected;

  const WorkflowNodePalette({
    super.key,
    required this.triggers,
    required this.actions,
    this.basalamPluginActive = true,
    required this.onNodeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Drawer(
      width: 300,
      child: WorkflowNodePaletteContent(
        triggers: triggers,
        actions: actions,
        basalamPluginActive: basalamPluginActive,
        onNodeSelected: onNodeSelected,
      ),
    );
  }
}

/// محتوای پالت node ها (بدون Drawer wrapper)
class WorkflowNodePaletteContent extends StatefulWidget {
  final List<WorkflowNodeMetadata> triggers;
  final List<WorkflowNodeMetadata> actions;
  final bool basalamPluginActive;
  final Function(WorkflowNodeType type, String key, String name) onNodeSelected;

  const WorkflowNodePaletteContent({
    super.key,
    required this.triggers,
    required this.actions,
    this.basalamPluginActive = true,
    required this.onNodeSelected,
  });

  @override
  State<WorkflowNodePaletteContent> createState() => _WorkflowNodePaletteContentState();
}

class _WorkflowNodePaletteContentState extends State<WorkflowNodePaletteContent> {
  final TextEditingController _searchController = TextEditingController();
  WorkflowNodeType? _filterType;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<WorkflowNodeMetadata> _filterItems(
    List<WorkflowNodeMetadata> items,
    String query,
  ) {
    if (query.isEmpty) return items;

    return items.where((item) {
      final nameLower = item.name.toLowerCase();
      final descLower = item.description?.toLowerCase() ?? '';
      final keyLower = item.key.toLowerCase();
      final searchLower = query.toLowerCase();

      return nameLower.contains(searchLower) ||
          descLower.contains(searchLower) ||
          keyLower.contains(searchLower);
    }).toList();
  }

  List<WorkflowNodeMetadata> _getStaticConditionNodes() {
    return const [
      WorkflowNodeMetadata(
        key: 'condition.if',
        name: 'شرط IF',
        description: 'بررسی یک شرط و اجرای مسیر مناسب',
        type: WorkflowNodeType.condition,
      ),
      WorkflowNodeMetadata(
        key: 'condition.switch',
        name: 'شرط چندگانه (Switch)',
        description: 'بررسی چند شرط و انتخاب یک مسیر',
        type: WorkflowNodeType.condition,
      ),
      WorkflowNodeMetadata(
        key: 'condition.compare',
        name: 'مقایسه مقادیر',
        description: 'مقایسه دو مقدار (بزرگتر، کوچکتر، مساوی)',
        type: WorkflowNodeType.condition,
      ),
    ];
  }

  List<WorkflowNodeMetadata> _getStaticLoopNodes() {
    return const [
      WorkflowNodeMetadata(
        key: 'loop.for_each',
        name: 'حلقه For Each',
        description: 'تکرار روی آرایه یا لیست',
        type: WorkflowNodeType.loop,
      ),
      WorkflowNodeMetadata(
        key: 'loop.while',
        name: 'حلقه While',
        description: 'تکرار تا زمانی که شرط برقرار است',
        type: WorkflowNodeType.loop,
      ),
      WorkflowNodeMetadata(
        key: 'loop.for',
        name: 'حلقه For',
        description: 'تکرار با بازه عددی مشخص',
        type: WorkflowNodeType.loop,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.view_list, color: theme.colorScheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Text(
                'Node ها',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
        // Search Box
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).workflowPaletteSearch,
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: ListenableBuilder(
                      listenable: _searchController,
                      builder: (context, _) {
                        if (_searchController.text.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchController.clear(),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: Text(AppLocalizations.of(context).workflowPaletteAll),
                      selected: _filterType == null,
                      onSelected: (selected) {
                        setState(() {
                          _filterType = null;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(AppLocalizations.of(context).workflowPaletteTriggers),
                      avatar: const Icon(Icons.bolt, size: 16),
                      selected: _filterType == WorkflowNodeType.trigger,
                      onSelected: (selected) {
                        setState(() {
                          _filterType = selected ? WorkflowNodeType.trigger : null;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(AppLocalizations.of(context).workflowPaletteActions),
                      avatar: const Icon(Icons.play_arrow, size: 16),
                      selected: _filterType == WorkflowNodeType.action,
                      onSelected: (selected) {
                        setState(() {
                          _filterType = selected ? WorkflowNodeType.action : null;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(AppLocalizations.of(context).workflowPaletteLoops),
                      avatar: const Icon(Icons.loop, size: 16),
                      selected: _filterType == WorkflowNodeType.loop,
                      onSelected: (selected) {
                        setState(() {
                          _filterType = selected ? WorkflowNodeType.loop : null;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(AppLocalizations.of(context).workflowPaletteConditions),
                      avatar: const Icon(Icons.code, size: 16),
                      selected: _filterType == WorkflowNodeType.condition,
                      onSelected: (selected) {
                        setState(() {
                          _filterType = selected ? WorkflowNodeType.condition : null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: ListenableBuilder(
            listenable: _searchController,
            builder: (context, _) {
              final q = _searchController.text;
              final filteredTriggers = _filterItems(widget.triggers, q);
              final filteredActions = _filterItems(widget.actions, q);
              final filteredLoops = _filterItems(_getStaticLoopNodes(), q);
              final filteredConditions = _filterItems(_getStaticConditionNodes(), q);

              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (_filterType == null || _filterType == WorkflowNodeType.trigger)
                    _buildSection(
                      context,
                      title: 'Trigger ها',
                      icon: Icons.bolt,
                      color: Colors.green,
                      items: filteredTriggers,
                      type: WorkflowNodeType.trigger,
                    ),
                  if (_filterType == null || _filterType == WorkflowNodeType.action)
                    _buildSection(
                      context,
                      title: 'Action ها',
                      icon: Icons.play_arrow,
                      color: theme.colorScheme.primary,
                      items: filteredActions,
                      type: WorkflowNodeType.action,
                    ),
                  if (_filterType == null || _filterType == WorkflowNodeType.loop)
                    _buildSection(
                      context,
                      title: 'Loop ها',
                      icon: Icons.loop,
                      color: Colors.purple,
                      items: filteredLoops,
                      type: WorkflowNodeType.loop,
                    ),
                  if (_filterType == null || _filterType == WorkflowNodeType.condition)
                    _buildSection(
                      context,
                      title: 'Condition ها',
                      icon: Icons.code,
                      color: Colors.orange,
                      items: filteredConditions,
                      type: WorkflowNodeType.condition,
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required List<WorkflowNodeMetadata> items,
    required WorkflowNodeType type,
  }) {
    final theme = Theme.of(context);
    final isExpanded = true; // در آینده می‌توان stateful کرد

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        initiallyExpanded: isExpanded,
        children: items.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'هیچ ${title.toLowerCase()}ی یافت نشد',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ]
            : items.map((item) {
                return _buildPaletteItem(context, item, type, color);
              }).toList(),
      ),
    );
  }

  Widget _buildPaletteItem(
    BuildContext context,
    WorkflowNodeMetadata item,
    WorkflowNodeType type,
    Color color,
  ) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          _getIconForType(type),
          color: color,
          size: 20,
        ),
      ),
      title: Text(
        item.name,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.description != null && item.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                item.description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          // نمایش اطلاعات اضافی برای triggerها
          if (type == WorkflowNodeType.trigger)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 12, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    _getTriggerInfo(item.key),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          if (!widget.basalamPluginActive &&
              workflowMetadataKeyReferencesBasalam(item.key))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: Colors.amber.shade800),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).workflowBasalamPluginInactivePalette,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.amber.shade900,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      trailing: Icon(
        Icons.drag_handle,
        color: theme.colorScheme.onSurfaceVariant,
        size: 20,
      ),
      onTap: () {
        widget.onNodeSelected(type, item.key, item.name);
      },
    );
  }

  /// دریافت اطلاعات trigger برای نمایش
  String _getTriggerInfo(String triggerKey) {
    switch (triggerKey) {
      case 'invoice.sales.created':
      case 'invoice.purchase.created':
      case 'invoice.created':
        return 'بعد از ایجاد فاکتور فعال می‌شود';
      case 'document.created':
        return 'بعد از ایجاد سند حسابداری فعال می‌شود';
      case 'receipt_payment.created':
        return 'بعد از ثبت دریافت/پرداخت فعال می‌شود';
      case 'receipt_payment.updated':
        return 'بعد از ویرایش سند دریافت/پرداخت فعال می‌شود';
      case 'person.created':
        return 'بعد از ایجاد شخص جدید فعال می‌شود';
      case 'inventory.low':
        return 'زمانی که موجودی کم شود فعال می‌شود';
      case 'check.due_date':
        return 'زمانی که چک به سررسید برسد فعال می‌شود';
      case 'scheduled':
        return 'بر اساس زمان‌بندی (cron) فعال می‌شود';
      case 'webhook':
        return 'از طریق webhook خارجی فعال می‌شود';
      case 'crm.chat.conversation.started':
        return 'بعد از ثبت مکالمه جدید در ویجت چت وب';
      case 'crm.chat.message.received':
        return 'وقتی بازدیدکننده در چت وب پیام بفرستد';
      case 'crm.chat.message.sent':
        return 'وقتی عامل یا سیستم در چت وب پیام بفرستد';
      case 'crm.chat.conversation.assigned':
        return 'وقتی مسئول مکالمه چت وب عوض شود';
      case 'crm.chat.conversation.resolved':
        return 'وقتی مکالمه چت وب به حل‌شده برود';
      case 'crm.chat.conversation.reopened':
        return 'وقتی مکالمه حل‌شده دوباره باز شود';
      default:
        return 'رویداد سیستم';
    }
  }

  IconData _getIconForType(WorkflowNodeType type) {
    switch (type) {
      case WorkflowNodeType.trigger:
        return Icons.bolt;
      case WorkflowNodeType.action:
        return Icons.play_arrow;
      case WorkflowNodeType.condition:
        return Icons.code;
      case WorkflowNodeType.loop:
        return Icons.loop;
    }
  }
}


