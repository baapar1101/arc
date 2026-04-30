import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_store.dart';
import '../../core/business_named_route_locations.dart';
import '../../core/business_nav.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../services/workflow_marketplace_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

/// مخزن ورک‌فلو: مرور و نصب
class WorkflowMarketplacePage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const WorkflowMarketplacePage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<WorkflowMarketplacePage> createState() => _WorkflowMarketplacePageState();
}

class _WorkflowMarketplacePageState extends State<WorkflowMarketplacePage> with SingleTickerProviderStateMixin {
  final WorkflowMarketplaceService _service = WorkflowMarketplaceService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  late TabController _tabController;

  bool _loading = true;
  bool _busy = false;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _load();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
    _load();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _busy = true;
    });
    try {
      final mine = _tabController.index == 1;
      final Map<String, dynamic> raw;
      if (mine) {
        raw = await _service.listMyPackages(
          businessId: widget.businessId,
          skip: 0,
          take: 100,
        );
      } else {
        raw = await _service.listPackages(
          skip: 0,
          take: 100,
          search: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
          tag: _tagController.text.trim().isEmpty ? null : _tagController.text.trim(),
        );
      }
      final list = (raw['items'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      if (!mounted) return;
      setState(() {
        _items = list;
      });
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message:
            '${AppLocalizations.of(context).workflowMarketplaceError}: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _openDetail(Map<String, dynamic> summary) async {
    final t = AppLocalizations.of(context);
    final rawId = summary['id'];
    if (rawId == null) return;
    final packageId = rawId is int ? rawId : int.tryParse(rawId.toString());
    if (packageId == null) return;
    setState(() => _busy = true);
    try {
      final detail = await _service.getPackage(packageId);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          final canInstall = widget.authStore.hasBusinessPermission('workflows', 'add') ||
              widget.authStore.hasBusinessPermission('workflows', 'edit');
          final nameCtrl = TextEditingController();
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.65,
              minChildSize: 0.35,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(detail['title']?.toString() ?? '', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      if (detail['short_description'] != null &&
                          detail['short_description'].toString().trim().isNotEmpty)
                        Text(detail['short_description'].toString()),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Chip(
                            label: Text('${t.workflowMarketplaceVersion}: ${detail['version_label'] ?? '-'}'),
                          ),
                          Chip(
                            label: Text('${t.workflowMarketplaceInstallCount}: ${detail['install_count'] ?? 0}'),
                          ),
                          if (detail['publisher_display_name'] != null)
                            Chip(
                              label: Text(
                                '${t.workflowMarketplacePublisher}: ${detail['publisher_display_name']}',
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(t.workflowMarketplaceLongDescriptionLabel, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Text(
                        (detail['long_description'] ?? detail['short_description'] ?? '-').toString(),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (detail['changelog'] != null && detail['changelog'].toString().trim().isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(t.workflowMarketplaceChangelog, style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Text(detail['changelog'].toString()),
                      ],
                      if (canInstall) ...[
                        const SizedBox(height: 20),
                        TextField(
                          controller: nameCtrl,
                          decoration: InputDecoration(
                            labelText: t.workflowMarketplaceNameAfterInstall,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () async {
                                      Navigator.of(ctx).pop();
                                      await _installPackage(
                                        packageId: packageId,
                                        name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
                                      );
                                    },
                            icon: const Icon(Icons.download_done_outlined),
                            label: Text(t.workflowMarketplaceInstall),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: '${t.workflowMarketplaceError}: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _installPackage({required int packageId, String? name}) async {
    final t = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final data = await _service.install(
        businessId: widget.businessId,
        packageId: packageId,
        name: name,
      );
      final wf = data['workflow'];
      if (wf is! Map) {
        throw StateError('invalid response');
      }
      final wfMap = Map<String, dynamic>.from(wf);
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.workflowMarketplaceInstalled);
      final wfId = wfMap['id'];
      if (wfId is int) {
        BusinessNamedRoutes.goNamed(
          context,
          businessId: widget.businessId,
          routeName: 'business_edit_workflow',
          pathParameters: {
            'business_id': widget.businessId.toString(),
            'workflow_id': wfId.toString(),
          },
          extra: wfMap,
        );
      } else {
        context.go(context.businessPanelUrl(widget.businessId, 'workflows'));
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: '${t.workflowMarketplaceError}: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.workflowMarketplaceTitle),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: t.workflowMarketplaceBrowseTab),
            Tab(text: t.workflowMarketplaceMyPublished),
          ],
        ),
        actions: [
          IconButton(
            tooltip: t.workflowRefresh,
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_tabController.index == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: t.workflowMarketplaceSearchHint,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _busy ? null : _load,
                      ),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tagController,
                    decoration: InputDecoration(
                      labelText: t.workflowMarketplaceTagFilterHint,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(child: Text(t.workflowMarketplaceEmpty))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          itemBuilder: (context, i) {
                            final item = _items[i];
                            final pub = item['published_at']?.toString();
                            final parsed = pub == null ? null : DateTime.tryParse(pub)?.toLocal();
                            final dateStr = parsed == null
                                ? '-'
                                : HesabixDateUtils.formatDateTime(parsed, widget.calendarController.isJalali);
                            final tags = (item['tags'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                title: Text(item['title']?.toString() ?? ''),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (item['short_description'] != null &&
                                        item['short_description'].toString().trim().isNotEmpty)
                                      Text(item['short_description'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${t.workflowMarketplacePublisher}: ${item['publisher_display_name'] ?? '-'} · '
                                      '${t.workflowMarketplacePublishedAt}: $dateStr · '
                                      '${t.workflowMarketplaceInstallCount}: ${item['install_count'] ?? 0}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    if (tags.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Wrap(
                                          spacing: 4,
                                          runSpacing: 4,
                                          children: tags.map((t) => Chip(label: Text(t), visualDensity: VisualDensity.compact)).toList(),
                                        ),
                                      ),
                                  ],
                                ),
                                isThreeLine: true,
                                trailing: const Icon(Icons.chevron_left),
                                onTap: () => _openDetail(item),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
