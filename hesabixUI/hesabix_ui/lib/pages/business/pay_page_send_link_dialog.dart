import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/business_pay_page_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:share_plus/share_plus.dart';

Future<void> showPayPageSendLinkDialog({
  required BuildContext context,
  required int businessId,
  Map<String, dynamic>? settings,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PayPageSendLinkDialog(
      businessId: businessId,
      initialSettings: settings,
    ),
  );
}

class PayPageSendLinkDialog extends StatefulWidget {
  final int businessId;
  final Map<String, dynamic>? initialSettings;

  const PayPageSendLinkDialog({
    super.key,
    required this.businessId,
    this.initialSettings,
  });

  @override
  State<PayPageSendLinkDialog> createState() => _PayPageSendLinkDialogState();
}

class _PayPageSendLinkDialogState extends State<PayPageSendLinkDialog> {
  final _service = BusinessPayPageService();
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _sendSms = false;
  String? _error;
  Map<String, dynamic> _settings = const {};
  Map<String, dynamic>? _created;

  bool _asEnabledFlag(dynamic value) {
    if (value == true || value == 1) return true;
    if (value is String) {
      final s = value.trim().toLowerCase();
      return s == 'true' || s == '1';
    }
    return false;
  }

  bool get _featureOn {
    if (!_asEnabledFlag(_settings['is_enabled'])) return false;
    final username = _settings['username']?.toString().trim() ?? '';
    if (username.isEmpty) return false;
    // دادهٔ ویجت داشبورد ممکن است gateway_id نداشته باشد؛ نبود کلید یعنی هنوز از API کامل نیامده
    // یا همان وضعیت فعال منو است. فقط وقتی کلید هست و خالی است، غیرفعال حساب می‌شود.
    if (!_settings.containsKey('gateway_id')) return true;
    final gatewayId = _settings['gateway_id'];
    if (gatewayId == null) return false;
    if (gatewayId is num && gatewayId == 0) return false;
    if ('$gatewayId'.trim().isEmpty || '$gatewayId' == '0') return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    // همیشه از GET کامل تنظیمات را می‌گیریم. payload ویجت داشبورد ناقص است
    // (بدون gateway_id) و نباید جلوی بارگذاری را بگیرد.
    if (widget.initialSettings != null) {
      _settings = Map<String, dynamic>.from(widget.initialSettings!);
    }
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getSettings(widget.businessId);
      if (!mounted) return;
      setState(() {
        _settings = data;
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

  String? _validateName(String? v) {
    final t = AppLocalizations.of(context);
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    if (s.length > 30) return t.payPageInvalidName;
    if (!RegExp(r'^[\u0600-\u06FF\u0750-\u077Fa-zA-Z\s\u200c]+$').hasMatch(s)) {
      return t.payPageInvalidName;
    }
    return null;
  }

  String? _validateMobile(String? v) {
    final t = AppLocalizations.of(context);
    final s = (v ?? '').trim();
    if (s.isEmpty) {
      if (_sendSms) return t.payPageMobileRequiredForSms;
      return null;
    }
    if (!RegExp(r'^09\d{9}$').hasMatch(s)) return t.payPageInvalidMobile;
    return null;
  }

  String? _validateAmount(String? v) {
    final t = AppLocalizations.of(context);
    final raw = (v ?? '').trim();
    if (raw.isEmpty) return null;
    final n = parseFormattedDouble(raw);
    if (n == null || n <= 0) return t.payPageAmount;
    final minAmt = (_settings['min_amount'] as num?)?.toDouble() ?? 50000;
    if (n < minAmt) return t.payPageMinAmount;
    final maxAmt = (_settings['max_amount'] as num?)?.toDouble();
    if (maxAmt != null && n > maxAmt) return t.payPageMaxAmount;
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final t = AppLocalizations.of(context);
    if (_sendSms && _mobileCtrl.text.trim().isEmpty) {
      SnackBarHelper.showError(context, message: t.payPageMobileRequiredForSms);
      return;
    }
    setState(() => _submitting = true);
    try {
      final created = await _service.createRequest(
        widget.businessId,
        amount: parseFormattedDouble(_amountCtrl.text),
        name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        mobile: _mobileCtrl.text.trim().isEmpty ? null : _mobileCtrl.text.trim(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        sendSms: _sendSms,
      );
      if (!mounted) return;
      setState(() {
        _created = created;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  String? get _createdUrl {
    final u = _created?['public_url']?.toString();
    if (u != null && u.isNotEmpty) return u;
    final path = _created?['public_path']?.toString();
    if (path == null || path.isEmpty) return null;
    return Uri.base.origin + path;
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).payPageLinkCopied);
  }

  Future<void> _share(String url) async {
    await Share.share(url);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final currency = (_settings['currency_title'] ?? _settings['currency_code'] ?? '').toString();
    return AlertDialog(
      title: Text(t.payPageSendLink),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : _error != null
                ? Text(_error!, textAlign: TextAlign.center)
                : !_featureOn
                    ? Text(t.payPageSendLinkDisabled, textAlign: TextAlign.center)
                    : _created != null
                        ? _buildResult(t, theme)
                        : _buildForm(t, theme, currency),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(_created != null ? t.close : t.cancel),
        ),
        if (!_loading && _error == null && _featureOn && _created == null)
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: Text(_submitting ? '…' : t.payPageSendLink),
          ),
      ],
    );
  }

  Widget _buildForm(AppLocalizations t, ThemeData theme, String currency) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.payPageSendLinkHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: const [
                EnglishDigitsFormatter(),
                ThousandsSeparatorInputFormatter(),
              ],
              validator: _validateAmount,
              decoration: InputDecoration(
                labelText: t.payPageSendLinkAmountHint,
                helperText: currency.isEmpty ? t.payPageSendLinkAmountLockedHint : t.payPageCurrencyHint(currency),
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              maxLength: 30,
              validator: _validateName,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\u0600-\u06FF\u0750-\u077Fa-zA-Z\s\u200c]')),
              ],
              decoration: InputDecoration(
                labelText: t.payPageNameOptional,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mobileCtrl,
              keyboardType: TextInputType.phone,
              maxLength: 11,
              validator: _validateMobile,
              inputFormatters: [
                EnglishDigitsFormatter(),
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              decoration: InputDecoration(
                labelText: t.payPageMobileOptional,
                hintText: '09xxxxxxxxx',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _noteCtrl,
              maxLength: 1000,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: t.payPageNoteOptional,
                border: const OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.payPageSendSms),
              value: _sendSms,
              onChanged: (v) => setState(() => _sendSms = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(AppLocalizations t, ThemeData theme) {
    final url = _createdUrl ?? '';
    final smsSent = _created?['sms_sent'] == true;
    final smsError = _created?['sms_error']?.toString();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.payPageRequestCreated, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SelectableText(
          url,
          textDirection: TextDirection.ltr,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (_created?['amount_locked'] == true) ...[
          const SizedBox(height: 8),
          Text(t.payPageAmountLocked, style: theme.textTheme.bodySmall),
        ],
        if (_sendSms) ...[
          const SizedBox(height: 8),
          Text(
            smsSent ? t.payPageSmsSent : '${t.payPageSmsNotSent}${smsError == null || smsError.isEmpty ? '' : ': $smsError'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: smsSent ? theme.colorScheme.primary : theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: url.isEmpty ? null : () => _copy(url),
              icon: const Icon(Icons.copy),
              label: Text(t.payPageCopyLink),
            ),
            OutlinedButton.icon(
              onPressed: url.isEmpty ? null : () => _share(url),
              icon: const Icon(Icons.share),
              label: Text(t.payPageShareLink),
            ),
          ],
        ),
      ],
    );
  }
}
