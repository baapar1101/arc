import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../models/quick_link_tile_models.dart';
import '../../../services/business_dashboard_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';

const double _kMinTileTouchSize = 48;
const double _kMobileEditorBreakpoint = 600;

int _gridColumnCountForWidth(double maxWidth) {
  if (maxWidth < 340) return 1;
  if (maxWidth < 600) return 2;
  if (maxWidth < 900) return 3;
  return 4;
}

IconData _iconFromKey(String name) {
  switch (name) {
    case 'note_add':
      return Icons.note_add;
    case 'receipt_long':
      return Icons.receipt_long;
    case 'payments':
      return Icons.payments;
    case 'people':
      return Icons.people;
    case 'inventory_2':
      return Icons.inventory_2;
    case 'description':
      return Icons.description;
    case 'account_balance':
      return Icons.account_balance;
    case 'swap_horiz':
      return Icons.swap_horiz;
    case 'assessment':
      return Icons.assessment;
    case 'account_balance_wallet':
      return Icons.account_balance_wallet;
    case 'request_quote':
      return Icons.request_quote;
    case 'warehouse':
      return Icons.warehouse;
    case 'local_shipping':
      return Icons.local_shipping;
    case 'point_of_sale':
      return Icons.point_of_sale;
    case 'settings':
      return Icons.settings;
    case 'hub':
      return Icons.hub;
    case 'link':
    default:
      return Icons.open_in_new;
  }
}

/// ویرایش میانبرها: روی موبایل [showModalBottomSheet]، روی دسکتاپ [showDialog]
Future<void> showQuickLinksEditorDialog({
  required BuildContext context,
  required int businessId,
  required BusinessDashboardService service,
  required VoidCallback onSaved,
}) async {
  final w = MediaQuery.sizeOf(context).width;
  final useSheet = w < _kMobileEditorBreakpoint;

  if (useSheet) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          minChildSize: 0.45,
          maxChildSize: 0.98,
          builder: (dCtx, scrollController) {
            return _QuickLinksEditorView(
              businessId: businessId,
              service: service,
              onSaved: onSaved,
              isMobileSheet: true,
              sheetScrollController: scrollController,
              onRequestClose: () => Navigator.of(dCtx).pop(),
            );
          },
        );
      },
    );
  } else {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640, minWidth: 400, minHeight: 360),
            child: _QuickLinksEditorView(
              businessId: businessId,
              service: service,
              onSaved: onSaved,
              isMobileSheet: false,
              onRequestClose: () => Navigator.of(ctx).pop(),
            ),
          ),
        );
      },
    );
  }
}

class _QuickLinksEditorView extends StatefulWidget {
  final int businessId;
  final BusinessDashboardService service;
  final VoidCallback onSaved;
  final bool isMobileSheet;
  final ScrollController? sheetScrollController;
  final VoidCallback onRequestClose;

  const _QuickLinksEditorView({
    required this.businessId,
    required this.service,
    required this.onSaved,
    required this.isMobileSheet,
    this.sheetScrollController,
    required this.onRequestClose,
  });

  @override
  State<_QuickLinksEditorView> createState() => _QuickLinksEditorViewState();
}

class _QuickLinksEditorViewState extends State<_QuickLinksEditorView> {
  bool _loading = true;
  String? _error;
  List<QuickLinkStoredItem> _items = [];
  List<QuickLinkPresetOption> _presets = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.service.getQuickLinksRaw(widget.businessId),
        widget.service.getQuickLinkPresets(widget.businessId),
      ]);
      final raw = results[0] as Map<String, dynamic>;
      final presets = results[1] as List<QuickLinkPresetOption>;
      final arr = (raw['items'] as List?) ?? const [];
      final parsed = arr
          .map((e) => QuickLinkStoredItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = parsed;
        _presets = presets;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    try {
      final messenger = ScaffoldMessenger.maybeOf(context);
      await widget.service.putQuickLinks(
        widget.businessId,
        _items.map((e) => e.toJson()).toList(),
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      widget.onSaved();
      if (messenger != null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('میانبرها ذخیره شد'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
      widget.onRequestClose();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  void _addPreset(QuickLinkPresetOption p) {
    final exists = _items.any((e) => e.kind == 'preset' && e.presetId == p.id);
    if (exists) {
      HapticFeedback.selectionClick();
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _items = [
        ..._items,
        QuickLinkStoredItem(
          id: const Uuid().v4(),
          kind: 'preset',
          presetId: p.id,
        ),
      ];
    });
  }

  void _openPresetsWithSearch() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _PresetSearchSheet(
          presets: _presets,
          onSelect: (p) {
            _addPreset(p);
            Navigator.of(ctx).pop();
          },
        );
      },
    );
  }

  void _addExternal() {
    HapticFeedback.selectionClick();
    final cTitle = TextEditingController();
    final cUrl = TextEditingController();
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => LayoutBuilder(
        builder: (context, c) {
          return AlertDialog(
            title: const Text('لینک خارجی'),
            content: SizedBox(
              width: c.maxWidth < 400 ? null : 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: cTitle,
                      decoration: const InputDecoration(
                        labelText: 'عنوان',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: cUrl,
                      decoration: const InputDecoration(
                        labelText: 'آدرس',
                        hintText: 'https://...',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
              FilledButton(
                onPressed: () async {
                  final url = cUrl.text.trim();
                  if (!url.startsWith('http://') && !url.startsWith('https://')) {
                    SnackBarHelper.showError(ctx, message: 'فقط آدرس http یا https');
                    return;
                  }
                  final uri = Uri.tryParse(url);
                  if (uri == null) {
                    SnackBarHelper.showError(ctx, message: 'آدرس نامعتبر');
                    return;
                  }
                  if (!context.mounted) return;
                  setState(() {
                    _items = [
                      ..._items,
                      QuickLinkStoredItem(
                        id: const Uuid().v4(),
                        kind: 'external',
                        title: cTitle.text.trim().isEmpty ? 'لینک' : cTitle.text.trim(),
                        url: url,
                      ),
                    ];
                  });
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx);
                },
                child: const Text('افزودن'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _itemLabel(QuickLinkStoredItem it) {
    if (it.kind == 'preset') {
      final m = {for (final p in _presets) p.id: p.title};
      return m[it.presetId] ?? it.presetId ?? '';
    }
    return it.title ?? it.url ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = widget.isMobileSheet
        ? const EdgeInsets.fromLTRB(16, 4, 16, 8)
        : const EdgeInsets.fromLTRB(0, 0, 0, 0);

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: SingleChildScrollView(
          child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
        ),
      );
    } else {
      final actionButtons = widget.isMobileSheet
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: _openPresetsWithSearch,
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  label: const Text('افزودن از پیش‌فرض‌های برنامه'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _addExternal,
                  icon: const Icon(Icons.link, size: 20),
                  label: const Text('لینک وب'),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openPresetsWithSearch,
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    label: const Text('پیش‌فرض برنامه'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addExternal,
                    icon: const Icon(Icons.link, size: 20),
                    label: const Text('لینک وب'),
                  ),
                ),
              ],
            );

      Widget listBlock() {
        if (_items.isEmpty) {
          return Center(
            child: Text(
              'هنوز کاشیی اضافه نکرده‌اید.\nبا دکمه‌های بالا اضافه کنید.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          );
        }
        return Semantics(
          label: 'فهرست میانبرها، برای مرتب‌سازی بکشید',
          child: ReorderableListView.builder(
            scrollController: widget.sheetScrollController,
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            buildDefaultDragHandles: false,
            itemCount: _items.length,
            onReorder: (a, b) {
              HapticFeedback.selectionClick();
              setState(() {
                if (b > a) b--;
                final x = _items.removeAt(a);
                _items.insert(b, x);
              });
            },
            itemBuilder: (context, index) {
              final it = _items[index];
              final label = _itemLabel(it);
              return ListTile(
                key: ValueKey('ql_edit_${it.id}'),
                minVerticalPadding: 12,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                leading: ReorderableDragStartListener(
                  index: index,
                  child: Semantics(
                    label: 'جابه‌جایی: $label',
                    child: IconButton(
                      icon: const Icon(Icons.drag_handle, size: 24),
                      onPressed: null,
                    ),
                  ),
                ),
                title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Semantics(
                  label: 'حذف $label',
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _items = List<QuickLinkStoredItem>.from(_items)..removeAt(index);
                      });
                    },
                  ),
                ),
              );
            },
          ),
        );
      }

      if (widget.isMobileSheet) {
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: padding,
              child: Row(
                children: [
                  Expanded(
                    child: Text('ویرایش دسترسی سریع', style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      widget.onRequestClose();
                    },
                    icon: const Icon(Icons.close),
                    tooltip: 'بستن',
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 0),
              child: actionButtons,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding.left),
              child: Text(
                'برای مرتب‌سازی کاشی‌ها را بکشید',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                child: listBlock(),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        widget.onRequestClose();
                      },
                      child: const Text('بستن'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _items.isEmpty ? null : _save,
                      child: const Text('ذخیره'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      } else {
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('ویرایش دسترسی سریع', style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      widget.onRequestClose();
                    },
                    icon: const Icon(Icons.close),
                    tooltip: 'بستن',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: actionButtons,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'بکشید تا ترتیب عوض شود',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: listBlock(),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      widget.onRequestClose();
                    },
                    child: const Text('بستن'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _items.isEmpty ? null : _save,
                    child: const Text('ذخیره'),
                  ),
                ],
              ),
            ),
          ],
        );
      }
    }

    if (widget.isMobileSheet) {
      return Material(color: theme.colorScheme.surface, child: body);
    }
    return body;
  }
}

class _PresetSearchSheet extends StatefulWidget {
  final List<QuickLinkPresetOption> presets;
  final void Function(QuickLinkPresetOption) onSelect;

  const _PresetSearchSheet({
    required this.presets,
    required this.onSelect,
  });

  @override
  State<_PresetSearchSheet> createState() => _PresetSearchSheetState();
}

class _PresetSearchSheetState extends State<_PresetSearchSheet> {
  final _q = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() => _filter = _q.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filter.isEmpty
        ? widget.presets
        : widget.presets
            .where(
              (p) =>
                  p.title.toLowerCase().contains(_filter) ||
                  p.id.toLowerCase().contains(_filter),
            )
            .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (context, sc) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('انتخاب میانبر', style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _q,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'جست‌وجو…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                autofocus: true,
                textInputAction: TextInputAction.search,
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: sc,
                padding: const EdgeInsets.only(bottom: 24, left: 8, right: 8),
                itemCount: filtered.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final p = filtered[i];
                  return ListTile(
                    minVerticalPadding: 12,
                    leading: Icon(_iconFromKey(p.icon), color: theme.colorScheme.primary),
                    title: Text(p.title),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onSelect(p);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// بدنه ویجت دسترسی سریع (داده از batch: `items` لیست)
class QuickLinksDashboardBody extends StatelessWidget {
  final int businessId;
  final dynamic data;
  final bool editMode;
  final VoidCallback onRefresh;
  final VoidCallback onOpenEditor;

  const QuickLinksDashboardBody({
    super.key,
    required this.businessId,
    required this.data,
    required this.editMode,
    required this.onRefresh,
    required this.onOpenEditor,
  });

  Future<void> _onTap(BuildContext context, QuickLinkResolvedItem it) async {
    HapticFeedback.lightImpact();
    if (it.kind == 'external' && (it.url != null && it.url!.isNotEmpty)) {
      final u = Uri.tryParse(it.url!);
      if (u == null) return;
      if (!await canLaunchUrl(u)) {
        if (context.mounted) {
          SnackBarHelper.showError(context, message: 'باز کردن این لینک ممکن نیست');
        }
        return;
      }
      await launchUrl(u, mode: LaunchMode.externalApplication);
      return;
    }
    final name = it.routeName;
    if (name == null || name.isEmpty) return;
    try {
      if (!context.mounted) return;
      context.goNamed(
        name,
        pathParameters: {'business_id': businessId.toString()},
      );
    } catch (_) {
      if (context.mounted) {
        SnackBarHelper.showError(context, message: 'مسیر قابل باز شدن نیست');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Map<String, dynamic> payload = (data is Map<String, dynamic>) ? data as Map<String, dynamic> : const {};
    if (payload['error'] != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Text('${payload['error']}', textAlign: TextAlign.center),
        ),
      );
    }
    final raw = payload['items'];
    final list = (raw is List) ? raw : const <dynamic>[];
    final items = <QuickLinkResolvedItem>[];
    for (final e in list) {
      if (e is Map<String, dynamic>) {
        items.add(QuickLinkResolvedItem.fromJson(e));
      } else if (e is Map) {
        items.add(QuickLinkResolvedItem.fromJson(Map<String, dynamic>.from(e)));
      }
    }

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.widgets_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                'هنوز میانبری اضافه نکرده‌اید',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                'در حالت ویرایش چیدمان، کاشی‌های دسترسی سریع را اضافه و مرتب کنید.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (editMode) ...[
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onOpenEditor();
                  },
                  child: const Text('ویرایش میانبرها'),
                ),
              ] else
                const SizedBox(height: 4),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final cols = _gridColumnCountForWidth(maxW);
        const spacing = 8.0;
        final listLength = items.length;
        const mainExtent = 60.0;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (editMode)
                Semantics(
                  label: 'ویرایش کاشی‌های دسترسی سریع',
                  button: true,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onOpenEditor();
                      },
                      icon: const Icon(Icons.tune, size: 20),
                      label: const Text('ویرایش کاشی‌ها'),
                    ),
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: spacing,
                      crossAxisSpacing: spacing,
                      mainAxisExtent: mainExtent,
                    ),
                    itemCount: listLength,
                    itemBuilder: (context, i) {
                      final it = items[i];
                      return _QuickLinkTile(
                        key: ValueKey('qltile_${it.id}'),
                        item: it,
                        onTap: () => _onTap(context, it),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickLinkTile extends StatelessWidget {
  final QuickLinkResolvedItem item;
  final VoidCallback onTap;

  const _QuickLinkTile({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = item.title;
    return Semantics(
      label: t,
      button: true,
      hint: item.kind == 'external' ? 'باز کردن در مرورگر' : 'رفتن به بخش مرتبط',
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 48,
            minHeight: _kMinTileTouchSize,
            maxWidth: 400,
          ),
          child: Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _iconFromKey(item.icon),
                      size: 24,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.start,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (item.kind == 'external')
                      Icon(Icons.open_in_new, size: 16, color: theme.colorScheme.outline),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
