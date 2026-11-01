import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../services/office_automation_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';

class OaSettingsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const OaSettingsPage({super.key, required this.businessId, required this.authStore});

  @override
  State<OaSettingsPage> createState() => _OaSettingsPageState();
}

class _OaSettingsPageState extends State<OaSettingsPage> {
  final OfficeAutomationService _svc = OfficeAutomationService();
  final _incoming = TextEditingController();
  final _outgoing = TextEditingController();
  final _internal = TextEditingController();
  final _letterhead = TextEditingController();
  bool _loading = true;
  bool _enabled = true;
  String _calendar = 'jalali';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _incoming.dispose();
    _outgoing.dispose();
    _internal.dispose();
    _letterhead.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _svc.getSettings(businessId: widget.businessId);
      _enabled = data['enabled'] != false;
      _calendar = (data['numbering_calendar'] ?? 'jalali').toString();
      _incoming.text = (data['incoming_prefix'] ?? 'IN').toString();
      _outgoing.text = (data['outgoing_prefix'] ?? 'OUT').toString();
      _internal.text = (data['internal_prefix'] ?? 'INT').toString();
      _letterhead.text = (data['letterhead_file_id'] ?? '').toString();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    try {
      await _svc.updateSettings(
        businessId: widget.businessId,
        payload: {
          'enabled': _enabled,
          'numbering_calendar': _calendar,
          'incoming_prefix': _incoming.text.trim(),
          'outgoing_prefix': _outgoing.text.trim(),
          'internal_prefix': _internal.text.trim(),
          'letterhead_file_id': _letterhead.text.trim().isEmpty ? null : _letterhead.text.trim(),
        },
      );
      if (mounted) SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).save);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.oaSettings),
        actions: [IconButton(icon: const Icon(Icons.save_outlined), onPressed: _save)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(title: Text(t.oaEnabled), value: _enabled, onChanged: (v) => setState(() => _enabled = v)),
                DropdownButtonFormField<String>(
                  value: _calendar,
                  decoration: InputDecoration(labelText: t.oaNumberingCalendar),
                  items: [
                    DropdownMenuItem(value: 'jalali', child: Text(t.oaJalali)),
                    DropdownMenuItem(value: 'gregorian', child: Text(t.oaGregorian)),
                  ],
                  onChanged: (v) => setState(() => _calendar = v ?? 'jalali'),
                ),
                const SizedBox(height: 12),
                TextField(controller: _incoming, decoration: InputDecoration(labelText: t.oaIncomingPrefix)),
                const SizedBox(height: 8),
                TextField(controller: _outgoing, decoration: InputDecoration(labelText: t.oaOutgoingPrefix)),
                const SizedBox(height: 8),
                TextField(controller: _internal, decoration: InputDecoration(labelText: t.oaInternalPrefix)),
                const SizedBox(height: 8),
                TextField(controller: _letterhead, decoration: InputDecoration(labelText: t.oaLetterhead)),
              ],
            ),
    );
  }
}
