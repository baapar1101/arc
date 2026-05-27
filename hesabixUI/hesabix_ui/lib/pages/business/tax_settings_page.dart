import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/tax_settings_model.dart';
import '../../services/tax_settings_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/business_subpage_back_leading.dart';
import '../../widgets/marketplace/moadian_plugin_gate.dart';
import '../../utils/web/web_utils.dart' as web_utils;

class TaxSettingsPage extends StatefulWidget {
  final int businessId;

  const TaxSettingsPage({super.key, required this.businessId});

  @override
  State<TaxSettingsPage> createState() => _TaxSettingsPageState();
}

class _TaxSettingsPageState extends State<TaxSettingsPage> {
  final _service = TaxSettingsService();
  final _connectionFormKey = GlobalKey<FormState>();
  final _taxMemoryIdController = TextEditingController();
  final _economicCodeController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final _publicKeyController = TextEditingController();
  final _certificateController = TextEditingController();
  final _certificateRequestController = TextEditingController();

  bool _sandboxMode = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  TaxSettingsModel? _settings;
  TaxDataQualityReport? _dataQuality;
  bool _dataQualityLoading = false;
  String? _dataQualityError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _taxMemoryIdController.dispose();
    _economicCodeController.dispose();
    _privateKeyController.dispose();
    _publicKeyController.dispose();
    _certificateController.dispose();
    _certificateRequestController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.fetchSettings(widget.businessId);
      _settings = data;
      _taxMemoryIdController.text = data.taxMemoryId ?? '';
      _economicCodeController.text = data.economicCode ?? '';
      _privateKeyController.text = data.privateKey ?? '';
      _publicKeyController.text = data.publicKey ?? '';
      _certificateController.text = data.certificate ?? '';
      _certificateRequestController.text = data.certificateRequest ?? '';
      _sandboxMode = data.sandboxMode;
    } catch (e) {
      _error = ErrorExtractor.forContext(e, context);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        _loadDataQuality();
      }
    }
  }

  Future<void> _loadDataQuality() async {
    if (!mounted) return;
    setState(() {
      _dataQualityLoading = true;
      _dataQualityError = null;
    });
    try {
      final report = await _service.fetchDataQuality(widget.businessId);
      if (!mounted) return;
      setState(() {
        _dataQuality = report;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dataQualityError = ErrorExtractor.forContext(e, context);
      });
    } finally {
      if (mounted) {
        setState(() {
          _dataQualityLoading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    if (!(_connectionFormKey.currentState?.validate() ?? false)) {
      return;
    }
    final memoryId = _normalizeTaxMemoryId(_taxMemoryIdController.text);
    final economicCode = _convertDigitsToEnglish(
      _economicCodeController.text.trim(),
    );
    final privateKey = _privateKeyController.text.trim();

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final current =
          _settings ?? TaxSettingsModel(businessId: widget.businessId);
      final payload = current.copyWith(
        taxMemoryId: memoryId,
        economicCode: economicCode,
        privateKey: privateKey,
        publicKey: _publicKeyController.text.trim().isEmpty
            ? null
            : _publicKeyController.text.trim(),
        certificate: _certificateController.text.trim().isEmpty
            ? null
            : _certificateController.text.trim(),
        certificateRequest: _certificateRequestController.text.trim().isEmpty
            ? null
            : _certificateRequestController.text.trim(),
        sandboxMode: _sandboxMode,
      );
      final saved = await _service.saveSettings(
        businessId: widget.businessId,
        settings: payload,
      );
      if (!mounted) return;
      setState(() {
        _settings = saved;
      });
      SnackBarHelper.show(context, message: t.taxSettingsSaved);
    } catch (e) {
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
      });
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _testConnection() async {
    final t = AppLocalizations.of(context);
    
    setState(() {
      _saving = true;
      _error = null;
    });
    
    try {
      final result = await _service.testConnection(widget.businessId);
      
      if (!mounted) return;
      
      final status = result['status']?.toString() ?? '';
      final message = result['message']?.toString();
      final sandboxMode = result['sandbox_mode'] as bool? ?? false;
      final warnings = _parseWarningMaps(result['warnings']);
      final identityCheck = result['identity_check'] is Map
          ? Map<String, dynamic>.from(result['identity_check'] as Map)
          : null;
      final auth = result['auth'] is Map
          ? Map<String, dynamic>.from(result['auth'] as Map)
          : null;
      final jwtClaims = auth?['jwt_claims'] is Map
          ? Map<String, dynamic>.from(auth!['jwt_claims'] as Map)
          : null;

      final isOk = status == 'connected';
      final isIdentityIssue = status == 'identity_mismatch';

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(
                isOk
                    ? Icons.check_circle
                    : isIdentityIssue
                        ? Icons.gpp_bad
                        : Icons.warning_amber,
                color: isOk
                    ? Colors.green
                    : isIdentityIssue
                        ? Colors.red
                        : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(t.taxTestConnectionResultTitle)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message ?? t.taxTestConnectionDone),
                  if (jwtClaims != null && jwtClaims.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      t.taxTestConnectionJwtTitle,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 6),
                    if (jwtClaims['sub'] != null)
                      Text('${t.taxTestConnectionJwtSub}: ${jwtClaims['sub']}'),
                    if (jwtClaims['taxpayerId'] != null)
                      Text(
                        '${t.taxTestConnectionJwtTaxpayer}: ${jwtClaims['taxpayerId']}',
                      ),
                    if (auth?['tax_memory_id_match'] == false)
                      Text(
                        t.taxTestConnectionMemoryMismatch,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    if (auth?['economic_code_match'] == false)
                      Text(
                        t.taxTestConnectionEconomicMismatch,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                  ],
                  if (identityCheck != null) ...[
                    const SizedBox(height: 12),
                    _buildIdentityCheckSection(context, t, identityCheck),
                  ],
                  if (warnings.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      t.taxConfigurationWarningsTitle,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 6),
                    ...warnings.map((w) => _buildWarningTile(context, w)),
                  ],
                  if (sandboxMode) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber, color: Colors.orange),
                          const SizedBox(width: 8),
                          Expanded(child: Text(t.taxSandboxModeActive)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.close),
            ),
          ],
        ),
      );
      
      if (isOk) {
        SnackBarHelper.show(context, message: t.taxTestConnectionSuccess);
      } else if (isIdentityIssue) {
        SnackBarHelper.showError(context, message: t.taxTestConnectionIdentityFailed);
      } else {
        SnackBarHelper.showWarning(context, message: t.taxTestConnectionWithWarnings);
      }
      
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: 'خطا در تست اتصال: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  List<Map<String, String>> _parseWarningMaps(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (e) => {
            'code': e['code']?.toString() ?? '',
            'level': e['level']?.toString() ?? 'warning',
            'message': e['message']?.toString() ?? '',
          },
        )
        .toList();
  }

  Widget _buildWarningTile(BuildContext context, Map<String, String> warning) {
    final level = warning['level'] ?? 'warning';
    final color = level == 'error'
        ? Theme.of(context).colorScheme.error
        : level == 'info'
            ? Theme.of(context).colorScheme.primary
            : Colors.orange.shade800;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            level == 'error' ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(warning['message'] ?? '')),
        ],
      ),
    );
  }

  Widget _buildIdentityCheckSection(
    BuildContext context,
    AppLocalizations t,
    Map<String, dynamic> identityCheck,
  ) {
    final status = identityCheck['status']?.toString() ?? '';
    final msg = identityCheck['message']?.toString() ?? '';
    final failures = identityCheck['recent_failures'];
    final isFailed = status == 'failed';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.taxIdentityCheckTitle,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isFailed ? Theme.of(context).colorScheme.error : null,
              ),
        ),
        const SizedBox(height: 6),
        Text(msg),
        if (failures is List && failures.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...failures.take(5).map((item) {
            if (item is! Map) return const SizedBox.shrink();
            final code = item['code']?.toString() ?? item['invoice_id']?.toString() ?? '';
            final err = item['tax_error_message']?.toString() ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $code${err.isNotEmpty ? ': $err' : ''}'),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildConfigurationWarningsBanner(AppLocalizations t) {
    final warnings = _settings?.configurationWarnings ?? const [];
    final identity = _settings?.identityCheck;
    if (warnings.isEmpty && identity == null) {
      return const SizedBox.shrink();
    }

    final hasError = identity?.isFailed == true ||
        warnings.any((w) => w.level == 'error');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasError
            ? Theme.of(context).colorScheme.errorContainer.withOpacity(0.5)
            : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasError
              ? Theme.of(context).colorScheme.error
              : Colors.orange.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasError ? Icons.gpp_bad : Icons.warning_amber,
                color: hasError
                    ? Theme.of(context).colorScheme.error
                    : Colors.orange.shade800,
              ),
              const SizedBox(width: 8),
              Text(
                t.taxConfigurationWarningsTitle,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          if (identity != null && identity.message != null) ...[
            const SizedBox(height: 8),
            Text(
              identity.message!,
              style: TextStyle(
                color: identity.isFailed
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
          ],
          const SizedBox(height: 8),
          ...warnings.map(
            (w) => _buildWarningTile(
              context,
              {'code': w.code, 'level': w.level, 'message': w.message},
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateKeys() async {
    final t = AppLocalizations.of(context);
    final result = await showDialog<_GenerateKeysRequest>(
      context: context,
      builder: (context) => _GenerateKeysDialog(
        t: t,
        initialPersonType: _settings?.suggestedPersonType ?? 'legal',
      ),
    );
    if (result == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final generated = await _service.generateKeys(
        businessId: widget.businessId,
        personType: result.personType,
        nationalId: result.nationalId,
        nameFa: result.nameFa,
        nameEn: result.nameEn,
        email: result.email,
      );
      if (!mounted) return;
      _privateKeyController.text = generated.privateKey;
      _publicKeyController.text = generated.publicKey;
      if (generated.csr != null && generated.csr!.trim().isNotEmpty) {
        _certificateRequestController.text = generated.csr!;
      }
      if (!mounted) return;
      if (generated.csr == null || generated.csr!.trim().isEmpty) {
        SnackBarHelper.showWarning(context, message: t.taxGenerateKeysCsrMissing);
      } else {
        SnackBarHelper.show(context, message: t.taxKeysGenerated);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _copyToClipboard(String value) {
    if (value.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    final t = AppLocalizations.of(context);
    SnackBarHelper.show(context, message: t.copied);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return MoadianPluginGate(
      businessId: widget.businessId,
      child: DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.taxIntegrationTitle),
          leading: businessSubpageBackLeading(context, widget.businessId),
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          bottom: TabBar(
            tabs: [
              Tab(
                text: t.taxSettingsTabConnection,
                icon: const Icon(Icons.cloud_sync_outlined),
              ),
              Tab(
                text: t.taxSettingsTabDataQuality,
                icon: const Icon(Icons.fact_check_outlined),
              ),
              Tab(
                text: t.taxSettingsTabGuide,
                icon: const Icon(Icons.menu_book_outlined),
              ),
            ],
          ),
        ),
        body: _buildBody(t, cs),
      ),
    ),
    );
  }

  Widget _buildBody(AppLocalizations t, ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(t.reload),
            ),
          ],
        ),
      );
    }
    return TabBarView(
      children: [
        _buildSetupTab(t, cs),
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _buildDataQualitySection(t, cs),
        ),
        _buildGuideTab(t, cs),
      ],
    );
  }

  Widget _buildSetupTab(AppLocalizations t, ColorScheme cs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final isWide = availableWidth >= 900;
        final double columnWidth = isWide
            ? (availableWidth - 16) / 2
            : availableWidth;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: availableWidth,
                child: _buildConfigurationWarningsBanner(t),
              ),
              SizedBox(
                width: availableWidth,
                child: _buildConnectionCard(t, cs),
              ),
              SizedBox(width: availableWidth, child: _buildKeysCard(t, cs)),
              SizedBox(
                width: columnWidth,
                child: _buildActionsAndGenerateCard(t, cs),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConnectionCard(AppLocalizations t, ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _connectionFormKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCardHeader(
                icon: Icons.settings_input_component_outlined,
                title: t.taxSettingsTabConnection,
                subtitle: t.taxIntegrationSubtitle,
                cs: cs,
              ),
              const SizedBox(height: 8),
              if (_settings?.updatedAt != null)
                Text(
                  t.taxLastUpdated(
                    DateFormat(
                      'yyyy/MM/dd HH:mm',
                    ).format(_settings!.updatedAt!.toLocal()),
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              const SizedBox(height: 16),
              _buildTextField(
                label: t.taxMemoryIdLabel,
                controller: _taxMemoryIdController,
                validator: (value) {
                  if (value == null || _normalizeTaxMemoryId(value).isEmpty) {
                    return t.taxMemoryIdRequired;
                  }
                  final normalized = _normalizeTaxMemoryId(value);
                  if (!_isAlphaNumericOnly(normalized)) {
                    return '${t.taxMemoryIdLabel} ${t.invalid}';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _buildTextField(
                label: t.taxEconomicCodeLabel,
                controller: _economicCodeController,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return t.taxEconomicCodeRequired;
                  }
                  final normalized = _convertDigitsToEnglish(value.trim());
                  if (!_isDigitsOnly(normalized)) {
                    return '${t.taxEconomicCodeLabel} ${t.invalid}';
                  }
                  return null;
                },
              ),
              const Divider(height: 32),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.taxSandboxModeLabel),
                subtitle: Text(t.taxSandboxModeSubtitle),
                value: _sandboxMode,
                onChanged: (value) => setState(() => _sandboxMode = value),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeysCard(AppLocalizations t, ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              icon: Icons.vpn_key_outlined,
              title: t.taxSettingsTabKeys,
              subtitle: t.taxGenerateKeys,
              cs: cs,
            ),
            const SizedBox(height: 16),
            _buildKeyField(
              label: t.taxPrivateKeyLabel,
              controller: _privateKeyController,
              downloadFileName: 'private_key.txt',
            ),
            const SizedBox(height: 12),
            _buildKeyField(
              label: t.taxPublicKeyLabel,
              controller: _publicKeyController,
              downloadFileName: 'public_key.txt',
            ),
            const SizedBox(height: 12),
            _buildKeyField(
              label: t.taxCertificateLabel,
              controller: _certificateController,
              downloadFileName: 'certificate.pem',
            ),
            const SizedBox(height: 12),
            _buildKeyField(
              label: t.taxCertificateRequestLabel,
              controller: _certificateRequestController,
              downloadFileName: 'certificate_request.csr',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsAndGenerateCard(AppLocalizations t, ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 520;
            Widget wrapButton(Widget button) {
              return isCompact
                  ? SizedBox(width: double.infinity, child: button)
                  : button;
            }

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.start,
              children: [
                wrapButton(
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(t.save),
                  ),
                ),
                wrapButton(
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: Text(t.reload),
                  ),
                ),
                wrapButton(
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _generateKeys,
                    icon: const Icon(Icons.vpn_key),
                    label: Text(t.taxGenerateKeys),
                  ),
                ),
                wrapButton(
                  FilledButton.tonalIcon(
                    onPressed: (_saving || _settings == null) ? null : _testConnection,
                    icon: const Icon(Icons.network_check),
                    label: Text(t.taxTestConnectionButton),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: validator,
    );
  }

  Widget _buildKeyField({
    required String label,
    required TextEditingController controller,
    required String downloadFileName,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: TextFormField(
                controller: controller,
                expands: true,
                minLines: null,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.file_download),
                        tooltip: AppLocalizations.of(context).downloadTemplate,
                        onPressed: hasText
                            ? () =>
                                  _downloadKeyFile(value.text, downloadFileName)
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: AppLocalizations.of(context).copyLink,
                        onPressed: hasText
                            ? () => _copyToClipboard(value.text)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadKeyFile(String content, String filename) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    final safeName = filename.isEmpty ? 'key.txt' : filename;
    final bytes = utf8.encode(trimmed);

    try {
      if (kIsWeb) {
        await web_utils.saveBytesAsFileWeb(
          bytes,
          safeName,
          mimeType: 'text/plain',
        );
      } else {
        await FileSaver.instance.saveFile(
          name: safeName,
          bytes: Uint8List.fromList(bytes),
          ext: _extractExtension(safeName),
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  String _extractExtension(String filename) {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == filename.length - 1) {
      return 'txt';
    }
    return filename.substring(dotIndex + 1);
  }

  String _convertDigitsToEnglish(String input) {
    if (input.isEmpty) return input;
    const persianDigits = {
      '۰': '0',
      '۱': '1',
      '۲': '2',
      '۳': '3',
      '۴': '4',
      '۵': '5',
      '۶': '6',
      '۷': '7',
      '۸': '8',
      '۹': '9',
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9',
    };

    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(persianDigits[char] ?? char);
    }
    return buffer.toString();
  }

  String _normalizeTaxMemoryId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    final englishDigits = _convertDigitsToEnglish(trimmed);
    // Allow users to paste with spaces/dashes; store a clean ID.
    final compact = englishDigits.replaceAll(RegExp(r'[\s\-]'), '');
    return compact;
  }

  bool _isDigitsOnly(String input) {
    if (input.isEmpty) return false;
    return RegExp(r'^[0-9]+$').hasMatch(input);
  }

  bool _isAlphaNumericOnly(String input) {
    if (input.isEmpty) return false;
    return RegExp(r'^[a-zA-Z0-9]+$').hasMatch(input);
  }

  Widget _buildDataQualitySection(AppLocalizations t, ColorScheme cs) {
    final theme = Theme.of(context);
    final report = _dataQuality;
    final groups = report == null
        ? const <_DataQualityGroup>[]
        : _composeDataQualityGroups(t, report);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.taxDataQualityTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.taxDataQualitySubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _dataQualityLoading ? null : _loadDataQuality,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(t.taxDataQualityReload),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_dataQualityLoading)
              const Center(child: CircularProgressIndicator())
            else if (_dataQualityError != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.taxDataQualityFetchError(_dataQualityError!),
                    style: TextStyle(color: cs.error),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _loadDataQuality,
                    icon: const Icon(Icons.refresh),
                    label: Text(t.reload),
                  ),
                ],
              )
            else if (report == null)
              Text(t.taxDataQualityNoData)
            else ...[
              _buildDataQualitySummary(t, cs, report),
              const SizedBox(height: 16),
              _buildDataQualityOverview(context, cs, groups),
              const SizedBox(height: 16),
              if (groups.every((group) => group.totalIssues == 0))
                Text(
                  t.taxDataQualityNoIssues,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.primary,
                  ),
                )
              else
                _buildIssuePanels(context, t, cs, groups),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGuideTab(AppLocalizations t, ColorScheme cs) {
    final sections = _buildGuideSteps(t);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildGuideIntro(t, cs),
          const SizedBox(height: 16),
          for (final section in sections) ...[
            _buildGuideSectionCard(section, cs),
            const SizedBox(height: 16),
          ],
          _buildGuideResources(t, cs),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildDataQualitySummary(
    AppLocalizations t,
    ColorScheme cs,
    TaxDataQualityReport report,
  ) {
    final products = report.products;
    final persons = report.persons;
    final totalProductIssues =
        products.missingTaxCode + products.missingTaxUnit;
    final totalPersonIssues =
        persons.missingNationalId + persons.missingEconomicId;
    final totalIssues = totalProductIssues + totalPersonIssues;
    final hasNoIssues = totalIssues == 0;
    final formattedIssues = NumberFormat.decimalPattern().format(totalIssues);
    final bgColor = hasNoIssues ? cs.secondaryContainer : cs.errorContainer;
    final fgColor = hasNoIssues ? cs.onSecondaryContainer : cs.onErrorContainer;
    final icon = hasNoIssues
        ? Icons.check_circle_outline
        : Icons.warning_amber_outlined;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: fgColor, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasNoIssues
                      ? t.taxDataQualityNoIssues
                      : t.taxValidationIssuesDescription,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: fgColor),
                ),
                const SizedBox(height: 4),
                Text(
                  hasNoIssues
                      ? t.taxDataQualitySubtitle
                      : '$formattedIssues مورد نیازمند اصلاح',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: fgColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataQualityOverview(
    BuildContext context,
    ColorScheme cs,
    List<_DataQualityGroup> groups,
  ) {
    if (groups.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: groups.map((group) {
        final hasIssues = group.totalIssues > 0;
        final bgColor = hasIssues ? cs.errorContainer : cs.secondaryContainer;
        final fgColor = hasIssues
            ? cs.onErrorContainer
            : cs.onSecondaryContainer;
        return SizedBox(
          width: 280,
          child: Card(
            color: bgColor,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: fgColor.withOpacity(0.2),
                    foregroundColor: fgColor,
                    child: Icon(group.icon),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: fgColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          NumberFormat.decimalPattern().format(
                            group.totalIssues,
                          ),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: fgColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildIssuePanels(
    BuildContext context,
    AppLocalizations t,
    ColorScheme cs,
    List<_DataQualityGroup> groups,
  ) {
    final theme = Theme.of(context);
    return Column(
      children: groups.map((group) {
        final hasIssues = group.totalIssues > 0;
        return Card(
          child: ExpansionTile(
            key: PageStorageKey(group.id),
            maintainState: true,
            leading: CircleAvatar(
              backgroundColor: hasIssues
                  ? cs.errorContainer
                  : cs.secondaryContainer,
              foregroundColor: hasIssues
                  ? cs.onErrorContainer
                  : cs.onSecondaryContainer,
              child: Icon(group.icon),
            ),
            title: Text(group.title),
            subtitle: Text(
              hasIssues
                  ? t.taxValidationIssuesDescription
                  : t.taxDataQualityNoIssues,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _buildMetricChips(context, cs, group.metrics),
              const SizedBox(height: 16),
              _buildSampleList(context, cs, group.samples, group.emptyMessage),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMetricChips(
    BuildContext context,
    ColorScheme cs,
    List<_DataQualityMetric> metrics,
  ) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: metrics.map((metric) {
        final hasIssues = metric.value > 0;
        final bgColor = hasIssues ? cs.errorContainer : cs.secondaryContainer;
        final fgColor = hasIssues
            ? cs.onErrorContainer
            : cs.onSecondaryContainer;
        return SizedBox(
          width: 220,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  style: theme.textTheme.bodyMedium?.copyWith(color: fgColor),
                ),
                const SizedBox(height: 6),
                Text(
                  NumberFormat.decimalPattern().format(metric.value),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: fgColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSampleList(
    BuildContext context,
    ColorScheme cs,
    List<_DataQualitySampleTileData> samples,
    String emptyMessage,
  ) {
    final theme = Theme.of(context);
    if (samples.isEmpty) {
      return Text(
        emptyMessage,
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      );
    }

    final height = _sampleListHeight(samples.length);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Scrollbar(
          thumbVisibility: samples.length > 5,
          child: SizedBox(
            height: height,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: samples.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final sample = samples[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  title: Text(sample.title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (sample.subtitle != null &&
                          sample.subtitle!.trim().isNotEmpty)
                        Text(
                          sample.subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ...sample.metaLines.map(
                        (line) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(line, style: theme.textTheme.bodySmall),
                        ),
                      ),
                      if (sample.tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: sample.tags
                              .map(
                                (tag) => Chip(
                                  label: Text(tag),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: cs.primaryContainer,
                                  labelStyle: theme.textTheme.bodySmall
                                      ?.copyWith(color: cs.onPrimaryContainer),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  double _sampleListHeight(int length) {
    if (length <= 0) return 0;
    const minHeight = 160.0;
    const maxHeight = 360.0;
    const rowHeight = 72.0;
    final target = rowHeight * length;
    return target.clamp(minHeight, maxHeight).toDouble();
  }

  List<_DataQualityGroup> _composeDataQualityGroups(
    AppLocalizations t,
    TaxDataQualityReport report,
  ) {
    final products = report.products;
    final persons = report.persons;

    _DataQualitySampleTileData _mapProductSample(
      TaxDataQualityProductSample sample,
    ) {
      final title = (sample.name?.trim().isNotEmpty ?? false)
          ? sample.name!.trim()
          : (sample.code?.isNotEmpty ?? false)
          ? sample.code!
          : '-';
      final subtitle =
          (sample.code?.isNotEmpty ?? false) && sample.code != title
          ? sample.code
          : null;
      final metaLines = <String>[
        '${t.taxDataQualityTaxCodeLabel}: ${sample.taxCode?.isNotEmpty == true ? sample.taxCode : '-'}',
        '${t.taxDataQualityTaxUnitLabel}: ${sample.taxUnitCode ?? sample.taxUnitName ?? sample.taxUnitId?.toString() ?? '-'}',
      ];
      final tags = <String>[
        if (sample.productMainUnit?.isNotEmpty == true) sample.productMainUnit!,
      ];
      return _DataQualitySampleTileData(
        title: title,
        subtitle: subtitle,
        metaLines: metaLines,
        tags: tags,
      );
    }

    _DataQualitySampleTileData _mapPersonSample(
      TaxDataQualityPersonSample sample,
    ) {
      final title = (sample.name?.trim().isNotEmpty ?? false)
          ? sample.name!.trim()
          : (sample.code?.isNotEmpty ?? false)
          ? sample.code!
          : '-';
      final subtitle =
          (sample.code?.isNotEmpty ?? false) && sample.code != title
          ? sample.code
          : null;
      final metaLines = <String>[
        '${t.taxDataQualityNationalIdLabel}: ${sample.nationalId?.isNotEmpty == true ? sample.nationalId : '-'}',
        '${t.taxDataQualityEconomicIdLabel}: ${sample.economicId?.isNotEmpty == true ? sample.economicId : '-'}',
      ];
      final tags = <String>[
        ...?sample.personTypes
            ?.whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty),
      ];
      return _DataQualitySampleTileData(
        title: title,
        subtitle: subtitle,
        metaLines: metaLines,
        tags: tags,
      );
    }

    return [
      _DataQualityGroup(
        id: 'products',
        title: t.taxDataQualityProductsHeader,
        icon: Icons.inventory_2_outlined,
        metrics: [
          _DataQualityMetric(
            label: t.taxDataQualityMissingTaxCode,
            value: products.missingTaxCode,
          ),
          _DataQualityMetric(
            label: t.taxDataQualityMissingTaxUnit,
            value: products.missingTaxUnit,
          ),
        ],
        samples: products.samples.map(_mapProductSample).toList(),
        emptyMessage: t.taxDataQualityNoSamples,
      ),
      _DataQualityGroup(
        id: 'persons',
        title: t.taxDataQualityPersonsHeader,
        icon: Icons.people_outline,
        metrics: [
          _DataQualityMetric(
            label: t.taxDataQualityMissingNationalId,
            value: persons.missingNationalId,
          ),
          _DataQualityMetric(
            label: t.taxDataQualityMissingEconomicId,
            value: persons.missingEconomicId,
          ),
        ],
        samples: persons.samples.map(_mapPersonSample).toList(),
        emptyMessage: t.taxDataQualityNoSamples,
      ),
    ];
  }

  Widget _buildCardHeader({
    required IconData icon,
    required String title,
    String? subtitle,
    required ColorScheme cs,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: cs.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGuideIntro(AppLocalizations t, ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.taxGuideIntroTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              t.taxGuideIntroDescription,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              t.taxGuidePrereqTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _buildGuideBullet(t.taxGuidePrereqItem1, cs),
            _buildGuideBullet(t.taxGuidePrereqItem2, cs),
            _buildGuideBullet(t.taxGuidePrereqItem3, cs),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideSectionCard(_TaxGuideStep section, ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(section.title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              section.description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (final bullet in section.bullets) _buildGuideBullet(bullet, cs),
            if (section.assetPaths.isNotEmpty) ...[
              const SizedBox(height: 12),
              Column(
                children: section.assetPaths
                    .map(
                      (path) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(path, fit: BoxFit.cover),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGuideResources(AppLocalizations t, ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              icon: Icons.map_outlined,
              title: t.taxGuideResourcesTitle,
              cs: cs,
            ),
            const SizedBox(height: 12),
            _buildGuideBullet(t.taxGuideResourcesWorkspace, cs),
            _buildGuideBullet(t.taxGuideResourcesProducts, cs),
            _buildGuideBullet(t.taxGuideResourcesSupport, cs),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideBullet(String text, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  List<_TaxGuideStep> _buildGuideSteps(AppLocalizations t) {
    return [
      _TaxGuideStep(
        title: t.taxGuideStep1Title,
        description: t.taxGuideStep1Description,
        bullets: [
          t.taxGuideStep1Bullet1,
          t.taxGuideStep1Bullet2,
          t.taxGuideStep1Bullet3,
        ],
        assetPaths: const [
          'assets/images/moadian/1.jpg',
          'assets/images/moadian/2.jpg',
          'assets/images/moadian/3.jpg',
        ],
      ),
      _TaxGuideStep(
        title: t.taxGuideStep2Title,
        description: t.taxGuideStep2Description,
        bullets: [
          t.taxGuideStep2Bullet1,
          t.taxGuideStep2Bullet2,
          t.taxGuideStep2Bullet3,
        ],
        assetPaths: const ['assets/images/moadian/4.jpg'],
      ),
      _TaxGuideStep(
        title: t.taxGuideStep3Title,
        description: t.taxGuideStep3Description,
        bullets: [
          t.taxGuideStep3Bullet1,
          t.taxGuideStep3Bullet2,
          t.taxGuideStep3Bullet3,
        ],
        assetPaths: const ['assets/images/moadian/5.jpg'],
      ),
      _TaxGuideStep(
        title: t.taxGuideStep4Title,
        description: t.taxGuideStep4Description,
        bullets: [
          t.taxGuideStep4Bullet1,
          t.taxGuideStep4Bullet2,
          t.taxGuideStep4Bullet3,
        ],
      ),
      _TaxGuideStep(
        title: t.taxGuideStep5Title,
        description: t.taxGuideStep5Description,
        bullets: [
          t.taxGuideStep5Bullet1,
          t.taxGuideStep5Bullet2,
          t.taxGuideStep5Bullet3,
        ],
        assetPaths: const ['assets/images/moadian/6.jpg'],
      ),
      _TaxGuideStep(
        title: t.taxGuideStep6Title,
        description: t.taxGuideStep6Description,
        bullets: [
          t.taxGuideStep6Bullet1,
          t.taxGuideStep6Bullet2,
          t.taxGuideStep6Bullet3,
        ],
        assetPaths: const [
          'assets/images/moadian/7.jpg',
          'assets/images/moadian/8.jpg',
        ],
      ),
      _TaxGuideStep(
        title: t.taxGuideStep7Title,
        description: t.taxGuideStep7Description,
        bullets: [
          t.taxGuideStep7Bullet1,
          t.taxGuideStep7Bullet2,
          t.taxGuideStep7Bullet3,
        ],
      ),
    ];
  }
}

class _GenerateKeysRequest {
  final String personType;
  final String nationalId;
  final String? nameFa;
  final String? nameEn;
  final String? email;

  _GenerateKeysRequest({
    required this.personType,
    required this.nationalId,
    this.nameFa,
    this.nameEn,
    this.email,
  });
}

class _DataQualityGroup {
  final String id;
  final String title;
  final IconData icon;
  final List<_DataQualityMetric> metrics;
  final List<_DataQualitySampleTileData> samples;
  final String emptyMessage;

  const _DataQualityGroup({
    required this.id,
    required this.title,
    required this.icon,
    required this.metrics,
    required this.samples,
    required this.emptyMessage,
  });

  int get totalIssues => metrics.fold(
    0,
    (previousValue, element) => previousValue + element.value,
  );
}

class _DataQualityMetric {
  final String label;
  final int value;

  const _DataQualityMetric({required this.label, required this.value});
}

class _DataQualitySampleTileData {
  final String title;
  final String? subtitle;
  final List<String> metaLines;
  final List<String> tags;

  const _DataQualitySampleTileData({
    required this.title,
    this.subtitle,
    required this.metaLines,
    this.tags = const [],
  });
}

class _TaxGuideStep {
  final String title;
  final String description;
  final List<String> bullets;
  final List<String> assetPaths;

  const _TaxGuideStep({
    required this.title,
    required this.description,
    required this.bullets,
    this.assetPaths = const [],
  });
}

class _GenerateKeysDialog extends StatefulWidget {
  final AppLocalizations t;
  final String initialPersonType;

  const _GenerateKeysDialog({
    required this.t,
    this.initialPersonType = 'legal',
  });

  @override
  State<_GenerateKeysDialog> createState() => _GenerateKeysDialogState();
}

class _GenerateKeysDialogState extends State<_GenerateKeysDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nationalIdController = TextEditingController();
  final _nameFaController = TextEditingController();
  final _nameEnController = TextEditingController();
  final _emailController = TextEditingController();
  late String _personType;

  @override
  void initState() {
    super.initState();
    _personType = widget.initialPersonType == 'natural' ? 'natural' : 'legal';
  }

  @override
  void dispose() {
    _nationalIdController.dispose();
    _nameFaController.dispose();
    _nameEnController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final isLegal = _personType == 'legal';

    return AlertDialog(
      title: Text(t.taxGenerateKeys),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _personType,
                items: [
                  DropdownMenuItem(
                    value: 'natural',
                    child: Text(t.taxPersonTypeNatural),
                  ),
                  DropdownMenuItem(
                    value: 'legal',
                    child: Text(t.taxPersonTypeLegal),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _personType = value);
                },
                decoration: InputDecoration(labelText: t.taxPersonTypeLabel),
              ),
              const SizedBox(height: 8),
              Text(
                t.taxGenerateKeysCsrHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nationalIdController,
                decoration: InputDecoration(
                  labelText: isLegal
                      ? t.taxNationalIdLegalLabel
                      : t.taxNationalIdLabel,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return t.requiredField;
                  }
                  final digits = value.replaceAll(RegExp(r'\D'), '');
                  if (_personType == 'natural' && digits.length != 10) {
                    return t.taxNationalIdNaturalInvalid;
                  }
                  if (_personType == 'legal' && digits.length != 11) {
                    return t.taxNationalIdLegalInvalid;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameFaController,
                decoration: InputDecoration(
                  labelText: isLegal
                      ? t.taxLegalNameFaLabel
                      : t.taxNaturalNameFaLabel,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return t.requiredField;
                  }
                  return null;
                },
              ),
              if (isLegal) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameEnController,
                  decoration: InputDecoration(labelText: t.taxLegalNameEnLabel),
                  validator: (value) {
                    if (_personType == 'legal' &&
                        (value == null || value.trim().isEmpty)) {
                      return t.requiredField;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(labelText: t.taxLegalEmailLabel),
                  validator: (value) {
                    if (_personType == 'legal' &&
                        (value == null || value.trim().isEmpty)) {
                      return t.requiredField;
                    }
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _GenerateKeysRequest(
                personType: _personType,
                nationalId: _nationalIdController.text.trim(),
                nameFa: _nameFaController.text.trim().isEmpty
                    ? null
                    : _nameFaController.text.trim(),
                nameEn: _nameEnController.text.trim().isEmpty
                    ? null
                    : _nameEnController.text.trim(),
                email: _emailController.text.trim().isEmpty
                    ? null
                    : _emailController.text.trim(),
              ),
            );
          },
          child: Text(t.create),
        ),
      ],
    );
  }
}
