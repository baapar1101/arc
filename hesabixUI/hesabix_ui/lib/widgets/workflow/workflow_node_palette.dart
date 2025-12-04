import 'package:flutter/material.dart';
import '../../models/workflow_editor_models.dart';

/// پالت node های قابل افزودن به workflow
class WorkflowNodePalette extends StatelessWidget {
  final List<WorkflowNodeMetadata> triggers;
  final List<WorkflowNodeMetadata> actions;
  final Function(WorkflowNodeType type, String key, String name) onNodeSelected;

  const WorkflowNodePalette({
    super.key,
    required this.triggers,
    required this.actions,
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
        onNodeSelected: onNodeSelected,
      ),
    );
  }
}

/// محتوای پالت node ها (بدون Drawer wrapper)
class WorkflowNodePaletteContent extends StatefulWidget {
  final List<WorkflowNodeMetadata> triggers;
  final List<WorkflowNodeMetadata> actions;
  final Function(WorkflowNodeType type, String key, String name) onNodeSelected;

  const WorkflowNodePaletteContent({
    super.key,
    required this.triggers,
    required this.actions,
    required this.onNodeSelected,
  });

  @override
  State<WorkflowNodePaletteContent> createState() => _WorkflowNodePaletteContentState();
}

class _WorkflowNodePaletteContentState extends State<WorkflowNodePaletteContent> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  WorkflowNodeType? _filterType;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<WorkflowNodeMetadata> _filterItems(List<WorkflowNodeMetadata> items) {
    if (_searchQuery.isEmpty) return items;
    
    return items.where((item) {
      final nameLower = item.name.toLowerCase();
      final descLower = item.description?.toLowerCase() ?? '';
      final keyLower = item.key.toLowerCase();
      final searchLower = _searchQuery.toLowerCase();
      
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
        description: 'تکرار روی آرایه یا لیست (⚠️ در حال توسعه)',
        type: WorkflowNodeType.loop,
      ),
      WorkflowNodeMetadata(
        key: 'loop.while',
        name: 'حلقه While',
        description: 'تکرار تا زمانی که شرط برقرار است (⚠️ در حال توسعه)',
        type: WorkflowNodeType.loop,
      ),
      WorkflowNodeMetadata(
        key: 'loop.for',
        name: 'حلقه For',
        description: 'تکرار با تعداد مشخص (⚠️ در حال توسعه)',
        type: WorkflowNodeType.loop,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final filteredTriggers = _filterItems(widget.triggers);
    final filteredActions = _filterItems(widget.actions);
    final filteredLoops = _filterItems(_getStaticLoopNodes());
    final filteredConditions = _filterItems(_getStaticConditionNodes());

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
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'جستجو...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
              const SizedBox(height: 8),
              // Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('همه'),
                      selected: _filterType == null,
                      onSelected: (selected) {
                        setState(() {
                          _filterType = null;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Triggers'),
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
                      label: const Text('Actions'),
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
                      label: const Text('Loops'),
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
                      label: const Text('Conditions'),
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
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Triggers Section
              if (_filterType == null || _filterType == WorkflowNodeType.trigger)
                _buildSection(
                  context,
                  title: 'Trigger ها',
                  icon: Icons.bolt,
                  color: Colors.green,
                  items: filteredTriggers,
                  type: WorkflowNodeType.trigger,
                ),
              // Actions Section
              if (_filterType == null || _filterType == WorkflowNodeType.action)
                _buildSection(
                  context,
                  title: 'Action ها',
                  icon: Icons.play_arrow,
                  color: theme.colorScheme.primary,
                  items: filteredActions,
                  type: WorkflowNodeType.action,
                ),
              // Loop Section
              if (_filterType == null || _filterType == WorkflowNodeType.loop)
                _buildSection(
                  context,
                  title: 'Loop ها',
                  icon: Icons.loop,
                  color: Colors.purple,
                  items: filteredLoops,
                  type: WorkflowNodeType.loop,
                ),
              // Condition Section
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
    final isLoop = type == WorkflowNodeType.loop;
    final isInDevelopment = item.description?.contains('⚠️') ?? false;

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
      title: Row(
        children: [
          Expanded(
            child: Text(
              item.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (isInDevelopment)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange, width: 1),
              ),
              child: Text(
                'در حال توسعه',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.orange.shade700,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
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
                  color: isInDevelopment 
                      ? Colors.orange.shade700 
                      : theme.colorScheme.onSurfaceVariant,
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
        ],
      ),
      trailing: Icon(
        Icons.drag_handle,
        color: theme.colorScheme.onSurfaceVariant,
        size: 20,
      ),
      onTap: () {
        if (isInDevelopment) {
          // نمایش هشدار برای نودهای در حال توسعه
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('⚠️ در حال توسعه'),
              content: Text(
                'این نود هنوز به طور کامل پیاده‌سازی نشده است. '
                'لطفاً فقط برای تست استفاده کنید.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('انصراف'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onNodeSelected(type, item.key, item.name);
                  },
                  child: const Text('ادامه'),
                ),
              ],
            ),
          );
        } else {
          widget.onNodeSelected(type, item.key, item.name);
        }
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


