import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../models/barcode_label/label_design_v1.dart';
import '../../../services/barcode_label_service.dart';
import '../../../services/bytes_export/bytes_export_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/barcode_label/label_excel_print_dialog.dart';
import '../../../widgets/barcode_label/label_serial_print_dialog.dart';
import '../../../widgets/barcode_label/render/label_pdf_renderer.dart';
import '../../../widgets/business_subpage_back_leading.dart';

/// Ú¯Ø§Ù„Ø±ÛŒ Ùˆ Ù…Ø¯ÛŒØ±ÛŒØª Ø·Ø±Ø­â€ŒÙ‡Ø§ÛŒ Ø¨Ø±Ú†Ø³Ø¨ Ø¨Ø§Ø±Ú©Ø¯.
class LabelTemplatesPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const LabelTemplatesPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<LabelTemplatesPage> createState() => _LabelTemplatesPageState();
}

class _LabelTemplatesPageState extends State<LabelTemplatesPage> {
  final _service = BarcodeLabelService();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  String _statusFilter = 'all';
  List<LabelTemplateSummary> _items = const [];
  List<LabelPreset> _presets = const [];

  bool get _canDesign =>
      widget.authStore.hasBusinessPermission('barcode_labels', 'design');

  bool get _canPrint =>
      widget.authStore.hasBusinessPermission('barcode_labels', 'print') ||
      widget.authStore.hasBusinessPermission('barcode_labels', 'design') ||
      widget.authStore.hasBusinessPermission('barcode_labels', 'view');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.listTemplates(
        businessId: widget.businessId,
        status: _statusFilter,
        q: _searchCtrl.text,
      );
      final presets = await _service.listPresets(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _openCreateSheet() async {
    if (!_canDesign) return;
    final t = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.barcodeLabelCreateTitle, style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  t.barcodeLabelCreateSubtitle,
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.crop_square_outlined),
                  title: Text(t.barcodeLabelBlankCanvas),
                  subtitle: Text(t.barcodeLabelBlankCanvasHint),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.go(context.businessPanelUrl(widget.businessId, 'barcode-labels/studio/new'));
                  },
                ),
                const Divider(),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(ctx).height * 0.45,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _presets.length,
                    itemBuilder: (_, i) {
                      final p = _presets[i];
                      return ListTile(
                        leading: Icon(Icons.auto_awesome_mosaic_outlined,
                            color: Theme.of(ctx).colorScheme.primary),
                        title: Text(p.name),
                        subtitle: Text(
                          '${p.widthMm.toStringAsFixed(0)}Ã—${p.heightMm.toStringAsFixed(0)} mm'
                          '${p.description != null ? ' â€” ${p.description}' : ''}',
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _createFromPreset(p);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _createFromPreset(LabelPreset preset) async {
    try {
      final created = await _service.createFromPreset(
        businessId: widget.businessId,
        presetCode: preset.code,
      );
      if (!mounted) return;
      context.go(
        context.businessPanelUrl(widget.businessId, 'barcode-labels/studio/${created.id}'),
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _setDefault(LabelTemplateSummary item) async {
    try {
      await _service.setDefault(businessId: widget.businessId, templateId: item.id);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).barcodeLabelDefaultSet);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _publish(LabelTemplateSummary item) async {
    try {
      await _service.publishTemplate(businessId: widget.businessId, templateId: item.id);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).barcodeLabelPublished);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _duplicate(LabelTemplateSummary item) async {
    try {
      final created = await _service.duplicateTemplate(
        businessId: widget.businessId,
        templateId: item.id,
      );
      if (!mounted) return;
      context.go(
        context.businessPanelUrl(widget.businessId, 'barcode-labels/studio/${created.id}'),
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _previewPdf(LabelTemplateSummary item) async {
    final t = AppLocalizations.of(context);
    try {
      final detail = await _service.getTemplate(
        businessId: widget.businessId,
        templateId: item.id,
      );
      final sample = await _service.sampleContext(businessId: widget.businessId);
      final bytes = await LabelPdfRenderer.render(
        design: detail.design,
        sheet: detail.sheet,
        contexts: [sample, sample, sample],
      );
      if (!mounted) return;
      final result = await BytesExportService.export(
        bytes: bytes,
        filename: 'label-preview-${item.id}.pdf',
        mimeType: 'application/pdf',
      );
      if (!mounted) return;
      BytesExportService.showFeedback(context, result, successOverride: t.labelPdfSaved);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.barcodeLabelsMenu),
        leading: businessSubpageBackLeading(context, widget.businessId),
        actions: [
          IconButton(
            tooltip: t.barcodeLabelPrintersTitle,
            onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'barcode-labels/printers')),
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: t.refresh,
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _canDesign
          ? FloatingActionButton.extended(
              onPressed: _openCreateSheet,
              icon: const Icon(Icons.add),
              label: Text(t.barcodeLabelNewTemplate),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_canPrint) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => LabelExcelPrintDialog.show(
                          context,
                          businessId: widget.businessId,
                        ),
                        icon: const Icon(Icons.table_chart_outlined),
                        label: Text(t.barcodeLabelExcelPrintTitle),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => LabelSerialPrintDialog.show(
                          context,
                          businessId: widget.businessId,
                        ),
                        icon: const Icon(Icons.format_list_numbered_outlined),
                        label: Text(t.barcodeLabelSerialPrintTitle),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 720;
                    final search = SearchBar(
                      controller: _searchCtrl,
                      hintText: t.barcodeLabelSearchHint,
                      leading: const Icon(Icons.search),
                      onSubmitted: (_) => _reload(),
                      trailing: [
                        if (_searchCtrl.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              _reload();
                            },
                          ),
                      ],
                    );
                    final filters = SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: 'all', label: Text(t.barcodeLabelFilterAll)),
                        ButtonSegment(value: 'published', label: Text(t.barcodeLabelFilterPublished)),
                        ButtonSegment(value: 'draft', label: Text(t.barcodeLabelFilterDraft)),
                      ],
                      selected: {_statusFilter},
                      onSelectionChanged: (s) {
                        setState(() => _statusFilter = s.first);
                        _reload();
                      },
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          search,
                          const SizedBox(height: 10),
                          filters,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: search),
                        const SizedBox(width: 12),
                        filters,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(t, cs)),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations t, ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _reload, child: Text(t.retry)),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.qr_code_scanner_rounded, size: 72, color: cs.primary.withValues(alpha: 0.7)),
                const SizedBox(height: 16),
                Text(t.barcodeLabelEmptyTitle, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  t.barcodeLabelEmptyBody,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (_canDesign) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _openCreateSheet,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(t.barcodeLabelStartWithPreset),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final cross = wide ? 3 : (constraints.maxWidth >= 600 ? 2 : 1);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: wide ? 1.35 : 1.45,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) => _TemplateCard(
            item: _items[index],
            canDesign: _canDesign,
            onOpen: () => context.go(
              context.businessPanelUrl(widget.businessId, 'barcode-labels/studio/${_items[index].id}'),
            ),
            onPreview: () => _previewPdf(_items[index]),
            onPublish: () => _publish(_items[index]),
            onDefault: () => _setDefault(_items[index]),
            onDuplicate: () => _duplicate(_items[index]),
          ),
        );
      },
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final LabelTemplateSummary item;
  final bool canDesign;
  final VoidCallback onOpen;
  final VoidCallback onPreview;
  final VoidCallback onPublish;
  final VoidCallback onDefault;
  final VoidCallback onDuplicate;

  const _TemplateCard({
    required this.item,
    required this.canDesign,
    required this.onOpen,
    required this.onPreview,
    required this.onPublish,
    required this.onDefault,
    required this.onDuplicate,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sizeLabel = (item.canvasWidthMm != null && item.canvasHeightMm != null)
        ? '${item.canvasWidthMm!.toStringAsFixed(0)}Ã—${item.canvasHeightMm!.toStringAsFixed(0)} mm'
        : 'â€”';

    Color statusColor;
    String statusText;
    switch (item.status) {
      case 'published':
        statusColor = cs.primary;
        statusText = t.barcodeLabelFilterPublished;
        break;
      case 'archived':
        statusColor = cs.outline;
        statusText = t.barcodeLabelFilterArchived;
        break;
      default:
        statusColor = cs.tertiary;
        statusText = t.barcodeLabelFilterDraft;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [
                          cs.primary.withValues(alpha: 0.18),
                          cs.tertiary.withValues(alpha: 0.12),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(Icons.qr_code_2_rounded, color: cs.primary),
                  ),
                  const Spacer(),
                  if (item.isDefault)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(Icons.star_rounded, size: 16, color: cs.primary),
                        label: Text(t.barcodeLabelDefaultBadge),
                      ),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'preview':
                          onPreview();
                          break;
                        case 'publish':
                          onPublish();
                          break;
                        case 'default':
                          onDefault();
                          break;
                        case 'duplicate':
                          onDuplicate();
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'preview', child: Text(t.barcodeLabelPreviewPdf)),
                      if (canDesign && item.status == 'draft')
                        PopupMenuItem(value: 'publish', child: Text(t.barcodeLabelPublish)),
                      if (canDesign && item.status == 'published' && !item.isDefault)
                        PopupMenuItem(value: 'default', child: Text(t.barcodeLabelSetDefault)),
                      if (canDesign)
                        PopupMenuItem(value: 'duplicate', child: Text(t.barcodeLabelDuplicate)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                item.description?.trim().isNotEmpty == true ? item.description! : sizeLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusText,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('v${item.version}', style: Theme.of(context).textTheme.labelSmall),
                  const Spacer(),
                  Text(sizeLabel, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
