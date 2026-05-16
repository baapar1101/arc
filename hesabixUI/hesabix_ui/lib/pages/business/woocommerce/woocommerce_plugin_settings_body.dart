import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/woocommerce_integration_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import 'woocommerce_arcwoc_plugin_panel.dart';
import 'woocommerce_l10n_format.dart';

/// فرم تنظیمات پل ووکامرس + پنل تنظیمات کلی افزونهٔ ArcWOC.
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
  bool _hasStoredBridgeToken = false;
  bool _tokenObscured = true;
  Map<String, dynamic>? _lastBridgeTest;

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
      _hasStoredBridgeToken = tok == '***' || tok.isNotEmpty;
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
          'bridge_token': _tokenCtl.text.trim().isEmpty
              ? '***'
              : _tokenCtl.text.trim(),
        },
      );
      if (mounted) {
        SnackBarHelper.showSuccess(
          context,
          message: t.woocommerceSettingsSavedSnackbar,
        );
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
    setState(() {
      _testing = true;
      _lastBridgeTest = null;
    });
    try {
      final data = await _svc.testBridge(businessId: widget.businessId);
      if (mounted) {
        setState(() => _lastBridgeTest = Map<String, dynamic>.from(data));
        SnackBarHelper.showSuccess(
          context,
          message: t.woocommerceConnectionTestSuccess,
        );
        await showDialog<void>(
          context: context,
          builder: (ctx) {
            final remote = data['remote'];
            return AlertDialog(
              title: Text(t.woocommerceConnectionTestDetailsTitle),
              content: SingleChildScrollView(
                child: SelectionArea(
                  child: Text(
                    remote == null ? '—' : _prettyJson(remote),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(MaterialLocalizations.of(ctx).closeButtonLabel),
                ),
              ],
            );
          },
        );
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

  String _prettyJson(Object? value) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(value);
    } catch (_) {
      return '$value';
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
          child: Text(
            t.woocommercePermissionDeniedBody,
            textAlign: TextAlign.center,
          ),
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
        Text(
          t.woocommerceSettingsPageSubtitle,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Text(
          t.woocommerceSettingsBridgeIntroTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          t.woocommerceSettingsBridgeIntroBody,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Chip(
            avatar: Icon(
              _hasStoredBridgeToken
                  ? Icons.verified_outlined
                  : Icons.warning_amber_outlined,
              size: 18,
              color: _hasStoredBridgeToken
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
            label: Text(
              _hasStoredBridgeToken
                  ? t.woocommerceBridgeTokenStored
                  : t.woocommerceBridgeTokenMissing,
            ),
          ),
        ),
        const SizedBox(height: 16),
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
            suffixIcon: IconButton(
              tooltip: _tokenObscured
                  ? t.woocommerceShowTokenTooltip
                  : t.woocommerceHideTokenTooltip,
              onPressed: () => setState(() => _tokenObscured = !_tokenObscured),
              icon: Icon(
                _tokenObscured
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          obscureText: _tokenObscured,
          textDirection: TextDirection.ltr,
        ),
        const SizedBox(height: 8),
        Text(
          t.woocommerceBridgeTokenHelp,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
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
        if (_lastBridgeTest != null && _lastBridgeTest!['remote'] != null) ...[
          const SizedBox(height: 16),
          Card.outlined(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.woocommerceConnectionHealthTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ..._bridgeHealthLines(context, t, _lastBridgeTest!['remote']),
                ],
              ),
            ),
          ),
        ],
        if (canManage) ...[
          const SizedBox(height: 20),
          Card.outlined(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(t.woocommerceSettingsOpeningInventoryLinkTitle),
              subtitle: Text(t.woocommerceSettingsOpeningInventoryLinkSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(
                context.businessPanelUrl(
                  widget.businessId,
                  'woocommerce/opening-inventory',
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 28),
        const Divider(),
        const SizedBox(height: 8),
        WooArcwocPluginSettingsPanel(
          businessId: widget.businessId,
          authStore: widget.authStore,
        ),
      ],
    );
  }

  List<Widget> _bridgeHealthLines(
    BuildContext context,
    AppLocalizations t,
    Object? remote,
  ) {
    if (remote is! Map) {
      return [Text('$remote')];
    }
    final m = Map<String, dynamic>.from(remote);
    final out = <Widget>[];
    for (final e in m.entries) {
      final title = wooBridgeFieldTitle(t, e.key);
      final val = wooBridgeFieldDisplayValue(t, e.key, e.value);
      out.add(Text('$title: $val', textDirection: TextDirection.ltr));
      out.add(const SizedBox(height: 4));
    }
    if (out.isEmpty) {
      out.add(
        SelectionArea(
          child: Text(
            _prettyJson(m),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      );
    }
    return out;
  }
}
