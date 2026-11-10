import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

/// جستجو و انتخاب فرصت فروش.
Future<Map<String, dynamic>?> showCrmDealPickerDialog(
  BuildContext context, {
  required int businessId,
  int? personId,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _CrmDealPickerDialog(businessId: businessId, personId: personId),
  );
}

class _CrmDealPickerDialog extends StatefulWidget {
  final int businessId;
  final int? personId;

  const _CrmDealPickerDialog({required this.businessId, this.personId});

  @override
  State<_CrmDealPickerDialog> createState() => _CrmDealPickerDialogState();
}

class _CrmDealPickerDialogState extends State<_CrmDealPickerDialog> {
  final CrmService _crm = CrmService(apiClient: ApiClient());
  final _q = TextEditingController();
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _items = [];
    });
    try {
      final data = await _crm.listDeals(
        businessId: widget.businessId,
        personId: widget.personId,
        search: q,
        limit: 30,
      );
      final raw = (data['items'] is List) ? data['items'] as List<dynamic> : <dynamic>[];
      if (!mounted) return;
      setState(() {
        _items = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context), isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(t.crmActivityPickDeal),
      content: SizedBox(
        width: 420,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _q,
              autofocus: true,
              decoration: InputDecoration(
                hintText: t.crmActivityDealSearchHint,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _loading ? null : _runSearch,
                ),
              ),
              onSubmitted: (_) => _runSearch(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? Center(
                          child: Text(
                            t.crmActivityDealSearchEmpty,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final m = _items[i];
                            final title = (m['title'] ?? '').toString();
                            final code = (m['code'] ?? '').toString();
                            final person = (m['person_name'] ?? '').toString();
                            final stage = (m['stage_name'] ?? '').toString();
                            return ListTile(
                              title: Text(title.isEmpty ? code : title),
                              subtitle: Text(
                                [code, person, stage].where((s) => s.isNotEmpty).join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(context, m),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.crmNotesClose)),
        FilledButton(onPressed: _loading ? null : _runSearch, child: Text(t.crmNotesApplySearch)),
      ],
    );
  }
}
