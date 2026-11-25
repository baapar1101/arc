import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../services/office_automation_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';

class OaExternalOrgsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const OaExternalOrgsPage({super.key, required this.businessId, required this.authStore});

  @override
  State<OaExternalOrgsPage> createState() => _OaExternalOrgsPageState();
}

class _OaExternalOrgsPageState extends State<OaExternalOrgsPage> {
  final OfficeAutomationService _svc = OfficeAutomationService();
  final _search = TextEditingController();
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  bool get _canAdmin =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('office_automation', 'admin');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await _svc.listExternalOrgs(
        businessId: widget.businessId,
        q: _search.text,
        includeInactive: true,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _edit({Map<String, dynamic>? existing}) async {
    final t = AppLocalizations.of(context);
    final fa = TextEditingController(text: '${(existing?['name_i18n'] as Map?)?['fa'] ?? existing?['title'] ?? ''}');
    final en = TextEditingController(text: '${(existing?['name_i18n'] as Map?)?['en'] ?? ''}');
    final code = TextEditingController(text: '${existing?['code'] ?? ''}');
    final email = TextEditingController(text: '${existing?['ece_email'] ?? ''}');
    final nid = TextEditingController(text: '${existing?['national_id'] ?? ''}');
    final phone = TextEditingController(text: '${existing?['phone'] ?? ''}');
    final address = TextEditingController(text: '${existing?['address'] ?? ''}');
    var active = existing?['is_active'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? t.oaNewExternalOrg : t.oaExternalOrgs),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(controller: fa, decoration: InputDecoration(labelText: t.persian)),
                  const SizedBox(height: 8),
                  TextField(controller: en, decoration: InputDecoration(labelText: t.english)),
                  const SizedBox(height: 8),
                  TextField(controller: code, decoration: InputDecoration(labelText: t.oaCode)),
                  const SizedBox(height: 8),
                  TextField(controller: email, decoration: InputDecoration(labelText: t.oaEceEmail)),
                  const SizedBox(height: 8),
                  TextField(controller: nid, decoration: InputDecoration(labelText: t.oaNationalId)),
                  const SizedBox(height: 8),
                  TextField(controller: phone, decoration: InputDecoration(labelText: t.phone)),
                  const SizedBox(height: 8),
                  TextField(controller: address, maxLines: 2, decoration: InputDecoration(labelText: t.address)),
                  SwitchListTile(
                    title: Text(t.active),
                    value: active,
                    onChanged: (v) => setLocal(() => active = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
          ],
        ),
      ),
    );
    final payload = {
      'name_i18n': {'fa': fa.text.trim(), 'en': en.text.trim()},
      if (code.text.trim().isNotEmpty) 'code': code.text.trim(),
      'ece_email': email.text.trim(),
      'national_id': nid.text.trim(),
      'phone': phone.text.trim(),
      'address': address.text.trim(),
      'is_active': active,
    };
    fa.dispose();
    en.dispose();
    code.dispose();
    email.dispose();
    nid.dispose();
    phone.dispose();
    address.dispose();
    if (ok != true) return;
    try {
      final id = oaId(existing?['id']);
      if (id == null) {
        await _svc.createExternalOrg(businessId: widget.businessId, payload: payload);
      } else {
        await _svc.updateExternalOrg(businessId: widget.businessId, orgId: id, payload: payload);
      }
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.oaExternalOrgs),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      floatingActionButton: _canAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(t.oaNewExternalOrg),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t.oaExternalOrgsHint,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(child: Text(t.oaEmptyExternalOrgs))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final row = _items[i];
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.apartment_outlined),
                              title: Text('${row['title'] ?? row['code']}'),
                              subtitle: Text(
                                [
                                  row['code'],
                                  row['ece_email'],
                                  row['national_id'],
                                  if (row['is_active'] == false) t.inactive,
                                ].where((e) => e != null && e.toString().isNotEmpty).join(' · '),
                              ),
                              trailing: _canAdmin ? const Icon(Icons.edit_outlined) : null,
                              onTap: _canAdmin ? () => _edit(existing: row) : null,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
