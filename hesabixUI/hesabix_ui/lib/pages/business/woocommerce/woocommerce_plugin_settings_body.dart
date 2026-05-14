import 'package:flutter/material.dart';

import '../../../core/auth_store.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/woocommerce_integration_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';

/// فرم تنظیمات پل ووکامرس (آدرس فروشگاه، توکن، تست اتصال).
class WoocommercePluginSettingsBody extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const WoocommercePluginSettingsBody({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<WoocommercePluginSettingsBody> createState() =>
      _WoocommercePluginSettingsBodyState();
}

class _WoocommercePluginSettingsBodyState
    extends State<WoocommercePluginSettingsBody> {
  final WoocommerceIntegrationService _svc = WoocommerceIntegrationService();

  final _storeUrlCtl = TextEditingController();
  final _tokenCtl = TextEditingController();

  bool _loadingSettings = true;
  bool _saving = false;
  bool _testing = false;

  bool _canWooCommerceView() {
    if (widget.authStore.currentBusiness?.isOwner == true) return true;
    return widget.authStore.hasBusinessPermission('woocommerce', 'view');
  }

  bool _canWooCommerceManage() {
    if (widget.authStore.currentBusiness?.isOwner == true) return true;
    return widget.authStore.hasBusinessPermission('woocommerce', 'manage');
  }

  @override
  void initState() {
    super.initState();
    if (_canWooCommerceView()) {
      _loadSettings();
    } else {
      _loadingSettings = false;
    }
  }

  @override
  void dispose() {
    _storeUrlCtl.dispose();
    _tokenCtl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    if (!_canWooCommerceView()) return;
    setState(() => _loadingSettings = true);
    try {
      final m = await _svc.getSettings(businessId: widget.businessId);
      _storeUrlCtl.text = (m['store_base_url'] ?? '').toString();
      final tok = (m['bridge_token'] ?? '').toString();
      _tokenCtl.text = tok == '***' ? '' : tok;
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingSettings = false);
    }
  }

  Future<void> _saveSettings() async {
    final t = AppLocalizations.of(context);
    if (!_canWooCommerceManage()) return;
    setState(() => _saving = true);
    try {
      await _svc.updateSettings(
        businessId: widget.businessId,
        payload: <String, dynamic>{
          'store_base_url': _storeUrlCtl.text.trim(),
          'bridge_token': _tokenCtl.text.trim().isEmpty ? '***' : _tokenCtl.text.trim(),
        },
      );
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: t.woocommerceSettingsSavedSnackbar);
      }
      await _loadSettings();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testBridge() async {
    final t = AppLocalizations.of(context);
    if (!_canWooCommerceView()) return;
    setState(() => _testing = true);
    try {
      await _svc.testBridge(businessId: widget.businessId);
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: t.woocommerceConnectionTestSuccess);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (!_canWooCommerceView()) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t.woocommercePermissionDeniedBody, textAlign: TextAlign.center),
        ),
      );
    }
    if (_loadingSettings) {
      return const Center(child: CircularProgressIndicator());
    }
    final canManage = _canWooCommerceManage();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t.woocommerceSettingsBridgeIntroTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(t.woocommerceSettingsBridgeIntroBody, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),
        if (!canManage)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              t.woocommerceManagePermissionHint,
              style: TextStyle(color: theme.colorScheme.tertiary),
            ),
          ),
        TextField(
          controller: _storeUrlCtl,
          readOnly: !canManage,
          decoration: InputDecoration(
            labelText: t.woocommerceStoreUrlLabel,
            hintText: t.woocommerceStoreUrlHint,
            border: const OutlineInputBorder(),
          ),
          textDirection: TextDirection.ltr,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tokenCtl,
          readOnly: !canManage,
          decoration: InputDecoration(
            labelText: t.woocommerceBridgeTokenLabel,
            border: const OutlineInputBorder(),
          ),
          obscureText: true,
          textDirection: TextDirection.ltr,
        ),
        const SizedBox(height: 8),
        Text(
          t.woocommerceBridgeTokenHelp,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: (!canManage || _saving) ? null : _saveSettings,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(t.woocommerceSaveButton),
            ),
            OutlinedButton.icon(
              onPressed: _testing ? null : _testBridge,
              icon: _testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: Text(t.woocommerceTestConnectionButton),
            ),
          ],
        ),
      ],
    );
  }
}
