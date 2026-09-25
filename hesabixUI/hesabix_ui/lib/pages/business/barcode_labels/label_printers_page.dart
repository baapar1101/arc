import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../models/barcode_label/label_printer_profile.dart';
import '../../../services/barcode_label_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/business_subpage_back_leading.dart';

/// مدیریت پروفایل‌های چاپگر رولی / Zebra / spooler سیستم.
class LabelPrintersPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const LabelPrintersPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<LabelPrintersPage> createState() => _LabelPrintersPageState();
}

class _LabelPrintersPageState extends State<LabelPrintersPage> {
  final _service = BarcodeLabelService();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  LabelPrinterSettings _settings = const LabelPrinterSettings();

  bool get _canEdit =>
      widget.authStore.hasBusinessPermission('barcode_labels', 'print') ||
      widget.authStore.hasBusinessPermission('barcode_labels', 'design');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await _service.getPrinterSettings(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _settings = s;
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

  Future<void> _persist(LabelPrinterSettings next) async {
    if (!_canEdit) return;
    setState(() => _saving = true);
    try {
      final saved = await _service.savePrinterSettings(
        businessId: widget.businessId,
        settings: next,
      );
      if (!mounted) return;
      setState(() {
        _settings = saved;
        _saving = false;
      });
      SnackBarHelper.show(context, message: AppLocalizations.of(context).barcodeLabelPrintersSaved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _addOrEdit([LabelPrinterProfile? existing]) async {
    if (!_canEdit) return;
    final result = await showGlassDialog<LabelPrinterProfile>(
      context: context,
      builder: (ctx) => _PrinterProfileDialog(initial: existing),
    );
    if (result == null || !mounted) return;
    final list = List<LabelPrinterProfile>.from(_settings.profiles);
    final idx = list.indexWhere((p) => p.id == result.id);
    if (idx >= 0) {
      list[idx] = result;
    } else {
      list.add(result);
    }
    var active = _settings.activeProfileId;
    active ??= result.id;
    await _persist(LabelPrinterSettings(profiles: list, activeProfileId: active));
  }

  Future<void> _delete(LabelPrinterProfile profile) async {
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).delete),
        content: Text(profile.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(context).cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.of(context).delete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final list = _settings.profiles.where((p) => p.id != profile.id).toList();
    final active = _settings.activeProfileId == profile.id
        ? (list.isNotEmpty ? list.first.id : null)
        : _settings.activeProfileId;
    await _persist(LabelPrinterSettings(profiles: list, activeProfileId: active));
  }

  Future<void> _setActive(String id) async {
    await _persist(LabelPrinterSettings(profiles: _settings.profiles, activeProfileId: id));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: businessSubpageBackLeading(context, widget.businessId),
        title: Text(t.barcodeLabelPrintersTitle),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (_canEdit)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: FilledButton.tonalIcon(
                onPressed: () => _addOrEdit(),
                icon: const Icon(Icons.add),
                label: Text(t.barcodeLabelPrinterAdd),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (kIsWeb)
                      Card(
                        color: cs.secondaryContainer.withValues(alpha: 0.5),
                        child: ListTile(
                          leading: const Icon(Icons.info_outline),
                          title: Text(t.barcodeLabelPrintersWebBanner),
                        ),
                      ),
                    Card(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                      child: ListTile(
                        leading: const Icon(Icons.science_outlined),
                        title: Text(t.barcodeLabelPrintersSpikeNote),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_settings.profiles.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Column(
                          children: [
                            Icon(Icons.print_disabled_outlined, size: 48, color: cs.outline),
                            const SizedBox(height: 12),
                            Text(t.barcodeLabelPrintersEmpty, textAlign: TextAlign.center),
                          ],
                        ),
                      )
                    else
                      ..._settings.profiles.map((p) {
                        final active = p.id == _settings.activeProfileId;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              active ? Icons.check_circle : Icons.print_outlined,
                              color: active ? cs.primary : null,
                            ),
                            title: Text(p.name),
                            subtitle: Text(
                              '${p.mode} · ${p.connection}'
                              '${p.host != null ? ' · ${p.host}:${p.port ?? 9100}' : ''}'
                              ' · ${p.labelWidthMm.toStringAsFixed(0)}×${p.labelHeightMm.toStringAsFixed(0)} mm'
                              '${p.enabled ? '' : ' · ${t.barcodeLabelPrinterDisabled}'}',
                            ),
                            isThreeLine: true,
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                if (!active && _canEdit)
                                  TextButton(
                                    onPressed: () => _setActive(p.id),
                                    child: Text(t.barcodeLabelPrinterSetActive),
                                  ),
                                if (_canEdit)
                                  IconButton(
                                    tooltip: t.edit,
                                    onPressed: () => _addOrEdit(p),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                if (_canEdit)
                                  IconButton(
                                    tooltip: t.delete,
                                    onPressed: () => _delete(p),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
    );
  }
}

class _PrinterProfileDialog extends StatefulWidget {
  final LabelPrinterProfile? initial;
  const _PrinterProfileDialog({this.initial});

  @override
  State<_PrinterProfileDialog> createState() => _PrinterProfileDialogState();
}

class _PrinterProfileDialogState extends State<_PrinterProfileDialog> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _w;
  late final TextEditingController _h;
  late final TextEditingController _dpi;
  late String _mode;
  late String _connection;
  late bool _enabled;
  late String _id;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _id = i?.id ?? 'p-${DateTime.now().millisecondsSinceEpoch}';
    _name = TextEditingController(text: i?.name ?? '');
    _host = TextEditingController(text: i?.host ?? '');
    _port = TextEditingController(text: '${i?.port ?? 9100}');
    _w = TextEditingController(text: '${i?.labelWidthMm ?? 50}');
    _h = TextEditingController(text: '${i?.labelHeightMm ?? 30}');
    _dpi = TextEditingController(text: '${i?.dpi ?? 203}');
    _mode = i?.mode ?? 'pdf_spooler';
    _connection = i?.connection ?? 'system_default';
    _enabled = i?.enabled ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _w.dispose();
    _h.dispose();
    _dpi.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      LabelPrinterProfile(
        id: _id,
        name: name,
        mode: _mode,
        connection: _connection,
        host: _host.text.trim().isEmpty ? null : _host.text.trim(),
        port: int.tryParse(_port.text.trim()),
        labelWidthMm: double.tryParse(_w.text.trim()) ?? 50,
        labelHeightMm: double.tryParse(_h.text.trim()) ?? 30,
        dpi: int.tryParse(_dpi.text.trim()) ?? 203,
        enabled: _enabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.initial == null ? t.barcodeLabelPrinterAdd : t.barcodeLabelPrinterEdit),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: t.barcodeLabelPrinterName, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _mode,
                decoration: InputDecoration(labelText: t.barcodeLabelPrinterMode, border: const OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'pdf_spooler', child: Text('PDF spooler')),
                  DropdownMenuItem(value: 'zpl', child: Text('ZPL (Zebra)')),
                  DropdownMenuItem(value: 'escpos', child: Text('ESC/POS')),
                ],
                onChanged: (v) => setState(() => _mode = v ?? 'pdf_spooler'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _connection,
                decoration: InputDecoration(labelText: t.barcodeLabelPrinterConnection, border: const OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'system_default', child: Text('System default')),
                  DropdownMenuItem(value: 'tcp', child: Text('TCP / LAN')),
                  DropdownMenuItem(value: 'usb', child: Text('USB')),
                  DropdownMenuItem(value: 'ble', child: Text('BLE')),
                ],
                onChanged: (v) => setState(() => _connection = v ?? 'system_default'),
              ),
              if (_connection == 'tcp') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _host,
                  decoration: InputDecoration(labelText: t.barcodeLabelPrinterHost, border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: t.barcodeLabelPrinterPort, border: const OutlineInputBorder()),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _w,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: t.barcodeLabelPrinterWidthMm, border: const OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _h,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: t.barcodeLabelPrinterHeightMm, border: const OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dpi,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: t.barcodeLabelPrinterDpi, border: const OutlineInputBorder()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.barcodeLabelPrinterEnabled),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _submit, child: Text(t.save)),
      ],
    );
  }
}
