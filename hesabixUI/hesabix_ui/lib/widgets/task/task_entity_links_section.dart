import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/task_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';

class TaskEntityLinksSection extends StatefulWidget {
  final int businessId;
  final TaskModel task;

  const TaskEntityLinksSection({
    super.key,
    required this.businessId,
    required this.task,
  });

  @override
  State<TaskEntityLinksSection> createState() => _TaskEntityLinksSectionState();
}

class _TaskEntityLinksSectionState extends State<TaskEntityLinksSection> {
  late final TaskService _service;
  final TextEditingController _searchController = TextEditingController();

  List<TaskEntityTypeModel> _types = const [];
  List<TaskEntityLinkModel> _links = const [];
  List<TaskLinkTargetModel> _targets = const [];

  String? _entityType;
  String _relationshipType = 'related';
  bool _loading = true;
  bool _searching = false;
  bool _mutating = false;
  String? _error;

  static const Map<String, String> _relationLabels = {
    'related': 'مرتبط',
    'customer': 'مشتری',
    'contact': 'مخاطب',
    'source': 'منبع',
    'regarding': 'درباره',
    'billing': 'مالی',
    'product': 'محصول',
    'follow_up': 'پیگیری',
  };

  @override
  void initState() {
    super.initState();
    _service = TaskService(ApiClient());
    _load();
  }

  @override
  void didUpdateWidget(covariant TaskEntityLinksSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _searchController.clear();
      _targets = const [];
      _load();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _service.listEntityTypes(businessId: widget.businessId),
        _service.listEntityLinks(
          businessId: widget.businessId,
          taskId: widget.task.id,
        ),
      ]);
      if (!mounted) return;
      final types = results[0] as List<TaskEntityTypeModel>;
      setState(() {
        _types = types;
        _links = results[1] as List<TaskEntityLinkModel>;
        _entityType ??= types.isEmpty ? null : types.first.key;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorExtractor.forContext(e, context);
      });
    }
  }

  Future<void> _search() async {
    final type = _entityType;
    if (type == null || _searching) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final items = await _service.searchEntityTargets(
        businessId: widget.businessId,
        entityType: type,
        search: _searchController.text,
      );
      if (!mounted) return;
      setState(() => _targets = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _link(TaskLinkTargetModel target) async {
    if (_mutating) return;
    setState(() {
      _mutating = true;
      _error = null;
    });
    try {
      await _service.addEntityLink(
        businessId: widget.businessId,
        taskId: widget.task.id,
        entityType: target.entityType,
        entityId: target.entityId,
        relationshipType: _relationshipType,
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _unlink(TaskEntityLinkModel link) async {
    if (_mutating) return;
    setState(() {
      _mutating = true;
      _error = null;
    });
    try {
      await _service.deleteEntityLink(
        businessId: widget.businessId,
        taskId: widget.task.id,
        linkId: link.id,
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  String _typeLabel(String key) {
    for (final item in _types) {
      if (item.key == key) return item.name;
    }
    return key;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'CRM / Accounting Links',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'بروزرسانی',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 19),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else ...[
          if (_links.isEmpty)
            Text(
              'هنوز هیچ موجودیت CRM یا حسابداری به این کار متصل نشده است.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            ..._links.map(
              (link) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link_rounded, size: 20),
                title: Text(
                  link.target.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    _typeLabel(link.entityType),
                    _relationLabels[link.relationshipType] ??
                        link.relationshipType,
                    if (link.target.subtitle?.trim().isNotEmpty == true)
                      link.target.subtitle!,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'حذف پیوند',
                  onPressed: _mutating ? null : () => _unlink(link),
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
              ),
            ),
          const SizedBox(height: 10),
          const Divider(),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _entityType,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'نوع موجودیت',
              isDense: true,
            ),
            items: _types
                .map(
                  (item) => DropdownMenuItem(
                    value: item.key,
                    child: Text(item.name),
                  ),
                )
                .toList(),
            onChanged: _mutating
                ? null
                : (value) {
                    setState(() {
                      _entityType = value;
                      _targets = const [];
                    });
                  },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _relationshipType,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'نوع ارتباط',
              isDense: true,
            ),
            items: _relationLabels.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: _mutating
                ? null
                : (value) => setState(
                      () => _relationshipType = value ?? 'related',
                    ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    labelText: 'جستجوی موجودیت',
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              IconButton.filledTonal(
                tooltip: 'جستجو',
                onPressed: _searching ? null : _search,
                icon: _searching
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded),
              ),
            ],
          ),
          if (_targets.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._targets.map(
              (target) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  target.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: target.subtitle == null
                    ? null
                    : Text(
                        target.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: FilledButton.tonalIcon(
                  onPressed: _mutating ? null : () => _link(target),
                  icon: const Icon(Icons.link_rounded, size: 17),
                  label: const Text('اتصال'),
                ),
              ),
            ),
          ],
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          GlassSurface(
            padding: const EdgeInsets.all(9),
            borderRadius: BorderRadius.circular(9),
            child: Text(
              _error!,
              style: TextStyle(color: scheme.error),
            ),
          ),
        ],
      ],
    );
  }
}
