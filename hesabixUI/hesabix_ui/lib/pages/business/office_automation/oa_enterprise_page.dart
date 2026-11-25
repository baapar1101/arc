import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../services/office_automation_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/office_automation/oa_ui.dart';

class OaEnterprisePage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const OaEnterprisePage({super.key, required this.businessId, required this.authStore});

  @override
  State<OaEnterprisePage> createState() => _OaEnterprisePageState();
}

class _OaEnterprisePageState extends State<OaEnterprisePage> {
  final OfficeAutomationService _svc = OfficeAutomationService();
  bool _loading = true;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _reviews = [];
  List<Map<String, dynamic>> _dueDocuments = [];
  List<Map<String, dynamic>> _policies = [];
  List<Map<String, dynamic>> _providers = [];

  bool get _canAdmin =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('office_automation', 'admin');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final branches = await _svc.listBranches(businessId: widget.businessId);
      final reviews = await _svc.listRetentionReviews(businessId: widget.businessId);
      final dueDocuments = await _svc.listRetentionDocuments(businessId: widget.businessId);
      final policies = await _svc.listRetentionPolicies(businessId: widget.businessId);
      final providers = await _svc.listSignatureProviders(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _reviews = reviews;
        _dueDocuments = dueDocuments;
        _policies = policies;
        _providers = providers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _createProvider() async {
    if (!_canAdmin) return;
    final t = AppLocalizations.of(context);
    final code = TextEditingController();
    final name = TextEditingController();
    final endpoint = TextEditingController();
    final token = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.oaCreateProvider),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: code, decoration: InputDecoration(labelText: t.oaProviderCode)),
            TextField(controller: name, decoration: InputDecoration(labelText: t.oaProviderName)),
            TextField(controller: endpoint, decoration: InputDecoration(labelText: t.oaProviderEndpoint)),
            TextField(controller: token, obscureText: true, decoration: InputDecoration(labelText: t.oaProviderToken)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.oaCreateProvider)),
        ],
      ),
    );
    final chosenCode = code.text.trim();
    final chosenName = name.text.trim();
    final chosenEndpoint = endpoint.text.trim();
    final chosenToken = token.text.trim();
    code.dispose();
    name.dispose();
    endpoint.dispose();
    token.dispose();
    if (accepted != true || chosenCode.isEmpty || chosenName.isEmpty) return;
    try {
      await _svc.createSignatureProvider(
        businessId: widget.businessId,
        code: chosenCode,
        name: chosenName,
        endpointUrl: chosenEndpoint,
        accessToken: chosenToken,
      );
      if (mounted) SnackBarHelper.showSuccess(context, message: t.oaCreateProvider);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _createBranch() async {
    if (!_canAdmin) return;
    final t = AppLocalizations.of(context);
    final code = TextEditingController();
    final name = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.oaCreateBranch),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: code, decoration: InputDecoration(labelText: t.oaBranchCode)),
            TextField(controller: name, decoration: InputDecoration(labelText: t.oaBranchName)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.oaCreateBranch)),
        ],
      ),
    );
    final chosenCode = code.text.trim();
    final chosenName = name.text.trim();
    code.dispose();
    name.dispose();
    if (accepted != true || chosenCode.isEmpty || chosenName.isEmpty) return;
    try {
      await _svc.createBranch(businessId: widget.businessId, code: chosenCode, name: chosenName);
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _savePolicy() async {
    if (!_canAdmin) return;
    final t = AppLocalizations.of(context);
    var confidentiality = 'normal';
    final days = TextEditingController(text: '365');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(t.oaRetentionPolicy),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.oaRetentionKeepsLetters),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: confidentiality,
                items: [
                  for (final value in const ['normal', 'confidential', 'highly_confidential', 'secret'])
                    DropdownMenuItem(value: value, child: Text(oaConfidentialityLabel(t, value))),
                ],
                onChanged: (value) => setLocal(() => confidentiality = value ?? 'normal'),
              ),
              TextField(controller: days, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t.oaRetainDays)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
          ],
        ),
      ),
    );
    final retainDays = int.tryParse(days.text.trim()) ?? 0;
    days.dispose();
    if (accepted != true || retainDays < 1) return;
    try {
      await _svc.saveRetentionPolicy(businessId: widget.businessId, confidentiality: confidentiality, retainDays: retainDays);
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _holdDocument(int documentId) async {
    try {
      await _svc.holdDocumentRetention(businessId: widget.businessId, documentId: documentId);
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _hold(int letterId) async {
    try {
      await _svc.holdLetterRetention(businessId: widget.businessId, letterId: letterId);
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.oaEnterprise)),
      floatingActionButton: _canAdmin
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'oa-provider',
                  onPressed: _createProvider,
                  icon: const Icon(Icons.verified_outlined),
                  label: Text(t.oaCreateProvider),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  heroTag: 'oa-branch',
                  onPressed: _createBranch,
                  icon: const Icon(Icons.account_tree_outlined),
                  label: Text(t.oaCreateBranch),
                ),
              ],
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(t.oaProviderSignatureNote),
                const SizedBox(height: 12),
                OaSectionCard(
                  title: t.oaBranches,
                  child: _branches.isEmpty
                      ? Text(t.oaNoBranches)
                      : Column(
                          children: [
                            for (final row in _branches) ListTile(contentPadding: EdgeInsets.zero, title: Text(row['title']?.toString() ?? ''), subtitle: Text(row['code']?.toString() ?? '')),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                OaSectionCard(
                  title: t.oaSignatureProviders,
                  child: _providers.isEmpty
                      ? Text(t.oaNoSignatureProviders)
                      : Column(
                          children: [
                            for (final row in _providers)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(row['name']?.toString() ?? ''),
                                subtitle: Text(row['live'] == true ? t.oaProviderLive : t.oaProviderManual),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                OaSectionCard(
                  title: t.oaRetentionPolicy,
                  actions: _canAdmin ? [TextButton(onPressed: _savePolicy, child: Text(t.oaRetentionPolicy))] : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.oaRetentionKeepsLetters),
                      const SizedBox(height: 8),
                      if (_policies.isEmpty)
                        Text(t.oaNoRetentionPolicies)
                      else
                        for (final row in _policies)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(oaConfidentialityLabel(t, '${row['confidentiality'] ?? 'normal'}')),
                            subtitle: Text('${row['retain_days'] ?? ''}'),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OaSectionCard(
                  title: t.oaRetentionDue,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_reviews.isEmpty)
                        Text(t.oaNoRetentionDue)
                      else
                        for (final row in _reviews)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(row['number']?.toString() ?? ''),
                            subtitle: Text(row['retain_until']?.toString() ?? ''),
                            trailing: _canAdmin && oaId(row['letter_id']) != null
                                ? TextButton(onPressed: () => _hold(oaId(row['letter_id'])!), child: Text(t.oaHoldLetter))
                                : null,
                          ),
                      const SizedBox(height: 12),
                      Text(t.oaRetentionDocuments, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(t.oaHoldDocumentKeepsFile),
                      if (_dueDocuments.isEmpty)
                        Text(t.oaNoRetentionDue)
                      else
                        for (final row in _dueDocuments)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(row['title']?.toString() ?? ''),
                            subtitle: Text(row['retain_until']?.toString() ?? ''),
                            trailing: _canAdmin && oaId(row['document_id']) != null
                                ? TextButton(onPressed: () => _holdDocument(oaId(row['document_id'])!), child: Text(t.oaHoldDocument))
                                : null,
                          ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
