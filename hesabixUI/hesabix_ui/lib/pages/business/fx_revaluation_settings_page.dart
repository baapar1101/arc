import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/permission_guard.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/business_api_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/business_subpage_back_leading.dart';

/// سیاست تسعیر فاکتور (لحظه مرجع نرخ، رفتار در نبود نرخ) — در businesses.fx_revaluation_policy ذخیره می‌شود.
class FxRevaluationSettingsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const FxRevaluationSettingsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<FxRevaluationSettingsPage> createState() => _FxRevaluationSettingsPageState();
}

class _FxRevaluationSettingsPageState extends State<FxRevaluationSettingsPage> {
  bool _loading = true;
  bool _saving = false;
  String _asOfSource = 'document_date';
  String _dateEffective = 'end_of_day';
  String _whenNoRate = 'block';

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _canEdit => widget.authStore.hasBusinessPermission('settings', 'business');

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final b = await BusinessApiService.getBusiness(widget.businessId);
      final raw = b.fxRevaluationPolicy;
      if (raw != null && raw.isNotEmpty) {
        setState(() {
          _asOfSource = (raw['as_of_source'] as String?) ?? 'document_date';
          _dateEffective = (raw['document_date_effective'] as String?) ?? 'end_of_day';
          _whenNoRate = (raw['when_no_rate'] as String?) ?? 'block';
        });
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(context, message: t.fxRevaluationSettingsLoadError(ErrorExtractor.forContext(e, context)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_canEdit) return;
    setState(() => _saving = true);
    try {
      await ApiClient().put(
        '/api/v1/businesses/${widget.businessId}',
        data: {
          'fx_revaluation_policy': {
            'as_of_source': _asOfSource,
            'document_date_effective': _dateEffective,
            'when_no_rate': _whenNoRate,
          },
        },
      );
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(context, message: t.savedSuccessfully);
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(context, message: t.fxRevaluationSettingsSaveError(ErrorExtractor.forContext(e, context)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!widget.authStore.hasBusinessPermission('settings', 'business')) {
      return PermissionGuard.buildAccessDeniedPage();
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(t.fxRevaluationSettingsTitle),
        leading: businessSubpageBackLeading(context, widget.businessId),
        actions: [
          if (_canEdit)
            TextButton(
              onPressed: _loading || _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(t.save),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(t.fxRevaluationSettingsIntro),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _asOfSource,
                  decoration: InputDecoration(
                    labelText: t.fxRevaluationAsOfSourceLabel,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'document_date',
                      child: Text(t.fxRevaluationAsOfSourceDocumentDate),
                    ),
                    DropdownMenuItem(
                      value: 'registered_at',
                      child: Text(t.fxRevaluationAsOfSourceRegisteredAt),
                    ),
                  ],
                  onChanged: _canEdit
                      ? (v) {
                          if (v != null) setState(() => _asOfSource = v);
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                if (_asOfSource == 'document_date')
                  DropdownButtonFormField<String>(
                    value: _dateEffective,
                    decoration: InputDecoration(
                      labelText: t.fxRevaluationDateEffectiveLabel,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'start_of_day',
                        child: Text(t.fxRevaluationTimeStartOfDay),
                      ),
                      DropdownMenuItem(
                        value: 'noon',
                        child: Text(t.fxRevaluationTimeNoon),
                      ),
                      DropdownMenuItem(
                        value: 'end_of_day',
                        child: Text(t.fxRevaluationTimeEndOfDay),
                      ),
                    ],
                    onChanged: _canEdit
                        ? (v) {
                            if (v != null) setState(() => _dateEffective = v);
                          }
                        : null,
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _whenNoRate,
                  decoration: InputDecoration(
                    labelText: t.fxRevaluationWhenNoRateLabel,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'block',
                      child: Text(t.fxRevaluationWhenNoRateBlock),
                    ),
                    DropdownMenuItem(
                      value: 'allow_without_fx',
                      child: Text(t.fxRevaluationWhenNoRateAllow),
                    ),
                  ],
                  onChanged: _canEdit
                      ? (v) {
                          if (v != null) setState(() => _whenNoRate = v);
                        }
                      : null,
                ),
                const SizedBox(height: 20),
                Text(
                  t.fxRevaluationSettingsFooterNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}
