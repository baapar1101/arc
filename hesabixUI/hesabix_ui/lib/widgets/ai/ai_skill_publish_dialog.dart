import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/services/wallet_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

/// دیالوگ انتشار مهارت AI در مارکت‌پلیس
class AISkillPublishDialog extends StatefulWidget {
  final int businessId;
  final int packageId;
  final String defaultTitle;

  const AISkillPublishDialog({
    super.key,
    required this.businessId,
    required this.packageId,
    required this.defaultTitle,
  });

  static Future<bool?> show(
    BuildContext context, {
    required int businessId,
    required int packageId,
    required String defaultTitle,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AISkillPublishDialog(
        businessId: businessId,
        packageId: packageId,
        defaultTitle: defaultTitle,
      ),
    );
  }

  @override
  State<AISkillPublishDialog> createState() => _AISkillPublishDialogState();
}

class _AISkillPublishDialogState extends State<AISkillPublishDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _shortCtrl = TextEditingController();
  final _longCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _versionCtrl = TextEditingController(text: '1.0.0');
  final _changelogCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final AIService _aiService = AIService(ApiClient());
  final WalletService _walletService = WalletService(ApiClient());

  bool _busy = false;
  bool _isFree = true;
  double _publisherSharePercent = 70;
  String? _currencySymbol;

  @override
  void initState() {
    super.initState();
    _titleCtrl.text = widget.defaultTitle;
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    try {
      final revenue = await _aiService.getPublisherRevenue(businessId: widget.businessId, take: 1);
      final wallet = await _walletService.getOverview(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _publisherSharePercent = (revenue['publisher_share_percent'] as num?)?.toDouble() ?? 70;
        _currencySymbol = wallet['base_currency_symbol']?.toString() ?? wallet['base_currency_code']?.toString();
      });
    } catch (_) {
      // optional metadata
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _shortCtrl.dispose();
    _longCtrl.dispose();
    _tagsCtrl.dispose();
    _versionCtrl.dispose();
    _changelogCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final tagsRaw = _tagsCtrl.text.trim();
      final tags = tagsRaw.isEmpty
          ? <String>[]
          : tagsRaw.split(RegExp(r'[،,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final price = _isFree ? null : double.tryParse(_priceCtrl.text.trim().replaceAll(',', ''));
      await _aiService.publishSkill(
        businessId: widget.businessId,
        packageId: widget.packageId,
        shortDescription: _shortCtrl.text.trim().isEmpty ? null : _shortCtrl.text.trim(),
        longDescription: _longCtrl.text.trim().isEmpty ? null : _longCtrl.text.trim(),
        tags: tags,
        versionLabel: _versionCtrl.text.trim().isEmpty ? '1.0.0' : _versionCtrl.text.trim(),
        changelog: _changelogCtrl.text.trim().isEmpty ? null : _changelogCtrl.text.trim(),
        priceAmount: price,
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'مهارت برای بررسی ارسال شد');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: ErrorExtractor.forContext(e, context),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = double.tryParse(_priceCtrl.text.trim().replaceAll(',', '')) ?? 0;
    final publisherEarning = _isFree ? 0.0 : price * _publisherSharePercent / 100;

    return AlertDialog(
      title: const Text('انتشار در مارکت‌پلیس'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'عنوان نمایشی'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'الزامی' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _shortCtrl,
                decoration: const InputDecoration(labelText: 'توضیح کوتاه'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _longCtrl,
                decoration: const InputDecoration(labelText: 'توضیح کامل'),
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tagsCtrl,
                decoration: const InputDecoration(labelText: 'برچسب‌ها (با کاما)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _versionCtrl,
                decoration: const InputDecoration(labelText: 'نسخه'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _changelogCtrl,
                decoration: const InputDecoration(labelText: 'تغییرات نسخه'),
                maxLines: 2,
              ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('رایگان'),
                value: _isFree,
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                          _isFree = v;
                          if (v) _priceCtrl.clear();
                        }),
              ),
              if (!_isFree) ...[
                TextFormField(
                  controller: _priceCtrl,
                  decoration: InputDecoration(
                    labelText: 'قیمت',
                    suffixText: _currencySymbol,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
                  validator: (v) {
                    if (_isFree) return null;
                    final p = double.tryParse((v ?? '').trim().replaceAll(',', ''));
                    if (p == null || p <= 0) return 'قیمت نامعتبر';
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  'سهم شما: ${publisherEarning.toStringAsFixed(0)} $_currencySymbol ($_publisherSharePercent٪)',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('ارسال برای بررسی'),
        ),
      ],
    );
  }
}
