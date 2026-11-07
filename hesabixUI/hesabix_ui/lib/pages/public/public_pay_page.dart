import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/config/app_config.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/public_pay_page_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:url_launcher/url_launcher.dart';

class PublicPayPage extends StatefulWidget {
  final String username;
  final String? requestToken;
  final Map<String, String> paymentReturnQuery;

  const PublicPayPage({
    super.key,
    required this.username,
    this.requestToken,
    this.paymentReturnQuery = const {},
  });

  @override
  State<PublicPayPage> createState() => _PublicPayPageState();
}

class _PublicPayPageState extends State<PublicPayPage> {
  final _service = PublicPayPageService();
  final _amountCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _payBusy = false;
  String? _error;
  Map<String, dynamic>? _payload;
  bool _useJalali = true;
  bool _calendarReady = false;
  String? _receiptStatus;
  String? _receiptRef;
  String? _receiptTx;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_calendarReady) {
      _calendarReady = true;
      _useJalali = Localizations.localeOf(context).languageCode == 'fa';
    }
  }

  Future<void> _bootstrap() async {
    await _fetch();
    final ps = widget.paymentReturnQuery['payment_status'];
    if (ps == 'success' || ps == 'failed') {
      if (!mounted) return;
      setState(() {
        _receiptStatus = ps;
        _receiptRef = widget.paymentReturnQuery['ref'];
        _receiptTx = widget.paymentReturnQuery['tx_id'];
      });
    }
  }

  bool get _amountLocked => _payload?['amount_locked'] == true;

  void _applyRequestPrefill(Map<String, dynamic> data) {
    final amt = data['request_amount'];
    if (amt != null && _amountCtrl.text.trim().isEmpty) {
      final n = (amt is num) ? amt.toDouble() : double.tryParse('$amt');
      if (n != null) {
        _amountCtrl.text = n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2);
      }
    }
    final name = data['request_name']?.toString() ?? '';
    if (name.isNotEmpty && _nameCtrl.text.trim().isEmpty) _nameCtrl.text = name;
    final mobile = data['request_mobile']?.toString() ?? '';
    if (mobile.isNotEmpty && _mobileCtrl.text.trim().isEmpty) _mobileCtrl.text = mobile;
    final note = data['request_note']?.toString() ?? '';
    if (note.isNotEmpty && _noteCtrl.text.trim().isEmpty) _noteCtrl.text = note;
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.fetch(widget.username, token: widget.requestToken);
      final redirect = data['redirect_to']?.toString();
      if (redirect != null && redirect.isNotEmpty && redirect != widget.username) {
        final tok = widget.requestToken;
        if (mounted) {
          if (tok != null && tok.isNotEmpty) {
            context.go('/public/pay/${Uri.encodeComponent(redirect)}/t/${Uri.encodeComponent(tok)}');
          } else {
            context.go('/public/pay/${Uri.encodeComponent(redirect)}');
          }
        }
        return;
      }
      if (!mounted) return;
      _applyRequestPrefill(data);
      setState(() {
        _payload = data;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.userMessage(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.userMessage(e);
        _loading = false;
      });
    }
  }

  String _logoUrl() {
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base/api/v1/public/pay/${Uri.encodeComponent(widget.username)}/logo';
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
    if (s.isEmpty) return null;
    if (!RegExp(r'^09\d{9}$').hasMatch(s)) return t.payPageInvalidMobile;
    return null;
  }

  String? _validateAmount(String? v) {
    final t = AppLocalizations.of(context);
    final n = parseFormattedDouble(v ?? '');
    if (n == null || n <= 0) return t.payPageAmount;
    final minAmt = (_payload?['min_amount'] as num?)?.toDouble() ?? 50000;
    if (n < minAmt) return t.payPageMinAmount;
    final maxAmt = (_payload?['max_amount'] as num?)?.toDouble();
    if (maxAmt != null && n > maxAmt) return t.payPageMaxAmount;
    return null;
  }

  Future<void> _pay() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = parseFormattedDouble(_amountCtrl.text);
    if (amount == null) return;
    setState(() => _payBusy = true);
    try {
      final started = await _service.start(
        username: widget.username,
        amount: amount,
        name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        mobile: _mobileCtrl.text.trim().isEmpty ? null : _mobileCtrl.text.trim(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        requestToken: widget.requestToken ?? _payload?['request_token']?.toString(),
      );
      final url = started['payment_url']?.toString();
      if (url == null || url.isEmpty) {
        if (!mounted) return;
        throw Exception(AppLocalizations.of(context).payPageReceiptFailed);
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _payBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.businessSettingsPayPage),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : _buildBody(t, theme),
    );
  }

  Widget _calendarToggle(AppLocalizations t) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment<bool>(value: true, label: Text(t.jalali)),
          ButtonSegment<bool>(value: false, label: Text(t.gregorian)),
        ],
        selected: {_useJalali},
        onSelectionChanged: (set) => setState(() => _useJalali = set.first),
      ),
    );
  }

  Widget _buildBody(AppLocalizations t, ThemeData theme) {
    final data = _payload ?? {};
    final enabled = data['is_enabled'] == true;
    final title = (data['display_title'] ?? data['business_name'] ?? '').toString();
    final intro = (data['intro_text'] ?? '').toString();
    final showLogo = data['show_logo'] == true;
    final currency = (data['currency_title'] ?? data['currency_code'] ?? '').toString();

    if (_receiptStatus == 'success') {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _calendarToggle(t),
          const SizedBox(height: 12),
          _receiptCard(t, theme, title, showLogo, success: true),
        ],
      );
    }
    if (_receiptStatus == 'failed') {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _calendarToggle(t),
          const SizedBox(height: 12),
          _receiptCard(t, theme, title, showLogo, success: false),
          const SizedBox(height: 16),
          if (enabled) _formCard(t, theme, currency),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _calendarToggle(t),
        const SizedBox(height: 12),
        if (showLogo)
          Center(
            child: Image.network(
              _logoUrl(),
              height: 88,
              errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          t.payPagePayTo(title),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (intro.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(intro, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 20),
        if (!enabled)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(t.payPageDisabled, textAlign: TextAlign.center),
            ),
          )
        else
          _formCard(t, theme, currency),
      ],
    );
  }

  Widget _formCard(AppLocalizations t, ThemeData theme, String currency) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (currency.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(t.payPageCurrencyHint(currency), style: theme.textTheme.bodySmall),
                ),
              if (_amountLocked)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(t.payPageAmountLocked, style: theme.textTheme.bodySmall),
                ),
              TextFormField(
                controller: _amountCtrl,
                readOnly: _amountLocked,
                keyboardType: TextInputType.number,
                inputFormatters: const [
                  EnglishDigitsFormatter(),
                  ThousandsSeparatorInputFormatter(),
                ],
                validator: _validateAmount,
                decoration: InputDecoration(
                  labelText: t.payPageAmount,
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
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: t.payPageNoteOptional,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _payBusy ? null : _pay,
                icon: _payBusy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.payment),
                label: Text(_payBusy ? '…' : t.payPagePayButton),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _receiptCard(AppLocalizations t, ThemeData theme, String title, bool showLogo, {required bool success}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error_outline,
              size: 48,
              color: success ? theme.colorScheme.primary : theme.colorScheme.error,
            ),
            const SizedBox(height: 8),
            Text(t.payPageReceiptTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(success ? t.payPageReceiptSuccess : t.payPageReceiptFailed, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(t.payPagePayTo(title), textAlign: TextAlign.center),
            if ((_receiptRef ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${t.payPageTrackingRef}: $_receiptRef'),
            ],
            if ((_receiptTx ?? '').isNotEmpty) Text('TX: $_receiptTx'),
            const SizedBox(height: 8),
            Text(HesabixDateUtils.formatDateTime(DateTime.now(), _useJalali)),
          ],
        ),
      ),
    );
  }
}
