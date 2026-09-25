import 'package:flutter/material.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;

import '../../core/android_sms_bank_platform.dart';
import '../../core/api_client.dart';
import '../../services/sms_bank/sms_bank_assistant_service.dart';
import '../../services/sms_bank/sms_bank_models.dart';
import '../../services/sms_bank/sms_bank_pattern_engine.dart';
import '../../services/sms_bank/sms_bank_seed_patterns.dart';
import '../../services/system_notifications/system_notifications_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/invoice/bank_account_combobox_widget.dart';
import '../../widgets/business_subpage_back_leading.dart';

/// Android-only settings for SMS bank assistant.
class SmsBankAssistantSettingsPage extends StatefulWidget {
  final int businessId;

  const SmsBankAssistantSettingsPage({super.key, required this.businessId});

  @override
  State<SmsBankAssistantSettingsPage> createState() => _SmsBankAssistantSettingsPageState();
}

class _SmsBankAssistantSettingsPageState extends State<SmsBankAssistantSettingsPage> {
  final _service = createSmsBankAssistantService();
  bool _loading = true;
  bool _saving = false;
  bool _smsGranted = false;
  SmsBankSettings _settings = const SmsBankSettings();
  List<SmsBankPattern> _patterns = [];
  List<SmsBankEvent> _events = [];
  final _minAmountController = TextEditingController();
  final _sampleController = TextEditingController();
  final _sampleSenderController = TextEditingController(text: 'Tejarat');

  String? get _businessName {
    final current = ApiClient.getAuthStore()?.currentBusiness;
    if (current?.id == widget.businessId) return current?.name;
    return null;
  }

  bool get _enabledForThisBusiness => _settings.isBusinessEnabled(widget.businessId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _minAmountController.dispose();
    _sampleController.dispose();
    _sampleSenderController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final settings = await _service.getSettings();
    await _service.ensureSeedPatternsForBusiness(
      businessId: widget.businessId,
      businessName: _businessName,
    );
    final patterns = await _service.getPatterns(businessId: widget.businessId);
    final events = await _service.listEvents();
    final scopedEvents = events
        .where((e) => e.businessId == null || e.businessId == widget.businessId || e.needsBusinessChoice)
        .toList();
    final granted = await _service.hasSmsPermission();
    if (!mounted) return;
    setState(() {
      _settings = settings.copyWith(activeBusinessId: widget.businessId);
      _patterns = patterns;
      _events = scopedEvents;
      _smsGranted = granted;
      _minAmountController.text =
          settings.minAmount > 0 ? settings.minAmount.toStringAsFixed(0) : '';
      _loading = false;
    });
    // Keep soft hint without enabling this business automatically.
    if (settings.activeBusinessId != widget.businessId) {
      await _service.saveSettings(_settings);
    }
  }

  Future<void> _persistSettings(SmsBankSettings next) async {
    setState(() {
      _settings = next;
      _saving = true;
    });
    try {
      await _service.saveSettings(next);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleEnabled(bool value) async {
    if (value) {
      final ok = await _service.ensureSmsPermission(requestIfNeeded: true);
      if (!ok) {
        if (mounted) {
          SnackBarHelper.showError(
            context,
            message: 'برای فعال‌سازی، مجوز دسترسی به پیامک لازم است',
          );
        }
        setState(() => _smsGranted = false);
        return;
      }
      setState(() => _smsGranted = true);
      try {
        await createSystemNotificationsService().ensurePermission(requestIfNeeded: true);
      } catch (_) {}
      await _service.ensureSeedPatternsForBusiness(
        businessId: widget.businessId,
        businessName: _businessName,
      );
      await _persistSettings(
        _settings.withBusinessEnabled(widget.businessId, true).copyWith(
              activeBusinessId: widget.businessId,
            ),
      );
      await _load();
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: 'دستیار پیامک برای این کسب‌وکار فعال شد',
        );
      }
    } else {
      await _persistSettings(_settings.withBusinessEnabled(widget.businessId, false));
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: 'تشخیص پیامک برای این کسب‌وکار خاموش شد',
        );
      }
    }
  }

  Future<void> _savePatterns(List<SmsBankPattern> patterns) async {
    final scoped = patterns
        .map(
          (p) => p.copyWith(
            businessId: widget.businessId,
            businessName: p.businessName ?? _businessName,
          ),
        )
        .toList();
    setState(() => _patterns = scoped);
    await _service.savePatternsForBusiness(widget.businessId, scoped);
  }

  Future<void> _openPatternEditor({SmsBankPattern? existing}) async {
    final result = await showDialog<SmsBankPattern>(
      context: context,
      builder: (ctx) => SmsBankPatternEditorDialog(
        businessId: widget.businessId,
        businessName: _businessName,
        initial: existing,
      ),
    );
    if (result == null) return;
    final list = List<SmsBankPattern>.from(_patterns);
    final idx = list.indexWhere((e) => e.id == result.id);
    if (idx >= 0) {
      list[idx] = result;
    } else {
      list.insert(0, result);
    }
    await _savePatterns(list);
  }

  Future<void> _testSample() async {
    final body = _sampleController.text.trim();
    if (body.isEmpty) {
      SnackBarHelper.showError(context, message: 'متن پیامک نمونه را وارد کنید');
      return;
    }
    final sender = _sampleSenderController.text.trim();
    final match = await _service.testMatch(
      body: body,
      sender: sender,
      patterns: _patterns,
      preferredBusinessId: widget.businessId,
    );
    if (!mounted) return;
    if (!match.matched) {
      SnackBarHelper.showError(context, message: 'هیچ الگویی با این پیامک جور نشد');
      return;
    }
    final dir = match.direction == SmsBankDirection.credit
        ? 'واریز'
        : match.direction == SmsBankDirection.debit
            ? 'برداشت'
            : 'نامشخص';
    final amb = match.needsBusinessChoice ? ' · نیاز به انتخاب کسب‌وکار' : '';
    SnackBarHelper.show(
      context,
      message:
          'تطبیق: $dir ${formatWithThousands(match.amount)} ریال'
          '${match.patternName != null ? ' · ${match.patternName}' : ''}'
          '${match.bankAccountName != null ? ' · ${match.bankAccountName}' : ''}'
          '$amb',
    );
  }

  Future<void> _simulateSample() async {
    final body = _sampleController.text.trim();
    if (body.isEmpty) return;
    if (!_enabledForThisBusiness) {
      SnackBarHelper.showError(context, message: 'ابتدا قابلیت را برای این کسب‌وکار فعال کنید');
      return;
    }
    final event = await _service.processIncomingSms(
      sender: _sampleSenderController.text.trim().isEmpty
          ? 'Tejarat'
          : _sampleSenderController.text.trim(),
      body: body,
      notify: true,
      preferredBusinessId: widget.businessId,
    );
    if (!mounted) return;
    if (event == null) {
      SnackBarHelper.showError(context, message: 'شبیه‌سازی نتیجه‌ای نداشت (الگو/حداقل مبلغ)');
      return;
    }
    await _load();
    if (!mounted) return;
    SnackBarHelper.show(context, message: 'رویداد ساخته شد — از نوتیفیکیشن یا صندوق ثبت کنید');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!supportsAndroidSmsBankAssistant) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('دستیار پیامک بانکی'),
          leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'این قابلیت فقط در نسخهٔ اندروید در دسترس است و در وب فعال نمی‌شود.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('دستیار پیامک بانکی'),
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Card(
                  child: SwitchListTile(
                    value: _enabledForThisBusiness,
                    onChanged: _toggleEnabled,
                    title: const Text('فعال‌سازی برای این کسب‌وکار'),
                    subtitle: Text(
                      _smsGranted
                          ? 'فقط الگوها و حساب‌های بانکی همین کسب‌وکار در تشخیص شرکت می‌کنند'
                              '${_settings.enabledBusinessIds.length > 1 ? ' · ${_settings.enabledBusinessIds.length} کسب‌وکار فعال' : ''}'
                          : 'مجوز پیامک هنوز داده نشده — با روشن کردن درخواست می‌شود',
                    ),
                    secondary: Icon(
                      Icons.sms_outlined,
                      color: _enabledForThisBusiness ? theme.colorScheme.primary : null,
                    ),
                  ),
                ),
                if (_settings.enabledBusinessIds.length > 1) ...[
                  const SizedBox(height: 8),
                  Card(
                    color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
                    child: const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('چند کسب‌وکار فعال است'),
                      subtitle: Text(
                        'اگر پیامک با الگوهای چند کسب‌وکار جور شود، هنگام ثبت از شما پرسیده می‌شود متعلق به کدام است.',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('نحوهٔ اطلاع‌رسانی'),
                        subtitle: const Text('حتی وقتی برنامه بسته است، رویداد در پس‌زمینه پردازش می‌شود'),
                      ),
                      RadioListTile<SmsBankInterruptMode>(
                        value: SmsBankInterruptMode.notification,
                        groupValue: _settings.interruptMode,
                        onChanged: !_enabledForThisBusiness
                            ? null
                            : (v) {
                                if (v == null) return;
                                _persistSettings(_settings.copyWith(interruptMode: v));
                              },
                        title: const Text('نوتیفیکیشن با دکمهٔ ثبت سریع (پیشنهادی)'),
                      ),
                      RadioListTile<SmsBankInterruptMode>(
                        value: SmsBankInterruptMode.autoOpen,
                        groupValue: _settings.interruptMode,
                        onChanged: !_enabledForThisBusiness
                            ? null
                            : (v) {
                                if (v == null) return;
                                _persistSettings(_settings.copyWith(interruptMode: v));
                              },
                        title: const Text('باز شدن خودکار صفحهٔ ثبت پس از ورود به برنامه'),
                      ),
                      SwitchListTile(
                        value: _settings.vibrate,
                        onChanged: !_enabledForThisBusiness
                            ? null
                            : (v) => _persistSettings(_settings.copyWith(vibrate: v)),
                        title: const Text('لرزش / صدا همراه نوتیفیکیشن'),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: TextField(
                          controller: _minAmountController,
                          enabled: _enabledForThisBusiness,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'حداقل مبلغ برای اطلاع (ریال)',
                            helperText: 'خالی = همهٔ مبالغ',
                            border: OutlineInputBorder(),
                          ),
                          onEditingComplete: () {
                            final v = double.tryParse(
                                  _minAmountController.text.replaceAll(',', ''),
                                ) ??
                                0;
                            _persistSettings(_settings.copyWith(minAmount: v));
                          },
                        ),
                      ),
                      SwitchListTile(
                        value: _settings.quietHoursEnabled,
                        onChanged: !_enabledForThisBusiness
                            ? null
                            : (v) {
                                if (v) {
                                  _persistSettings(
                                    _settings.copyWith(quietStartHour: 23, quietEndHour: 7),
                                  );
                                } else {
                                  _persistSettings(_settings.copyWith(clearQuiet: true));
                                }
                              },
                        title: const Text('ساعات سکوت'),
                        subtitle: Text(
                          _settings.quietHoursEnabled
                              ? 'از ${_settings.quietStartHour}:00 تا ${_settings.quietEndHour}:00 فقط در صندوق ذخیره می‌شود'
                              : 'خاموش',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'الگوهای این کسب‌وکار',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _openPatternEditor,
                      icon: const Icon(Icons.add),
                      label: const Text('الگوی جدید'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._patterns.map((p) {
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        p.enabled ? Icons.pattern : Icons.pattern_outlined,
                        color: p.enabled ? theme.colorScheme.primary : null,
                      ),
                      title: Text(p.name),
                      subtitle: Text(
                        [
                          if (p.bankAccountName != null) p.bankAccountName!,
                          if (p.senderHints.isNotEmpty) 'فرستنده: ${p.senderHints.join('، ')}',
                          if (p.isSeed) 'پیش‌فرض',
                        ].where((e) => e.isNotEmpty).join(' · '),
                      ),
                      trailing: Switch(
                        value: p.enabled,
                        onChanged: (v) async {
                          final list = List<SmsBankPattern>.from(_patterns);
                          final i = list.indexWhere((e) => e.id == p.id);
                          if (i < 0) return;
                          list[i] = p.copyWith(enabled: v, updatedAt: DateTime.now());
                          await _savePatterns(list);
                        },
                      ),
                      onTap: () => _openPatternEditor(existing: p),
                      onLongPress: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('حذف الگو؟'),
                            content: Text('«${p.name}» حذف شود؟'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await _savePatterns(_patterns.where((e) => e.id != p.id).toList());
                        }
                      },
                    ),
                  );
                }),
                const SizedBox(height: 16),
                Text(
                  'آزمایش با پیامک نمونه',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _sampleSenderController,
                  decoration: const InputDecoration(
                    labelText: 'فرستنده (برای تست واقعی‌تر)',
                    hintText: 'مثلاً Tejarat یا بانک ملت',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _sampleController,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'متن یک پیامک بانکی را اینجا بچسبانید…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _testSample,
                        child: const Text('تست تطبیق'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _simulateSample,
                        child: const Text('شبیه‌سازی رویداد'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'صندوق رویدادها',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (_events.isEmpty)
                  const Card(
                    child: ListTile(
                      title: Text('رویدادی ثبت نشده'),
                      subtitle: Text('پس از دریافت پیامک بانکی، اینجا ظاهر می‌شود'),
                    ),
                  )
                else
                  ..._events.take(30).map((e) {
                    final dir = e.direction == SmsBankDirection.credit
                        ? 'واریز'
                        : e.direction == SmsBankDirection.debit
                            ? 'برداشت'
                            : 'تراکنش';
                    final biz = e.needsBusinessChoice
                        ? 'نیاز به انتخاب کسب‌وکار'
                        : (e.businessName ?? (e.businessId != null ? 'کسب‌وکار #${e.businessId}' : ''));
                    return Card(
                      child: ListTile(
                        title: Text('$dir ${formatWithThousands(e.amount)} ریال'),
                        subtitle: Text(
                          [
                            if (biz.isNotEmpty) biz,
                            e.bankAccountName ?? e.patternName ?? e.sender,
                            e.status.wireName,
                          ].where((x) => x.toString().isNotEmpty).join(' · '),
                        ),
                        dense: true,
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

class SmsBankPatternEditorDialog extends StatefulWidget {
  final int businessId;
  final String? businessName;
  final SmsBankPattern? initial;

  const SmsBankPatternEditorDialog({
    super.key,
    required this.businessId,
    this.businessName,
    this.initial,
  });

  @override
  State<SmsBankPatternEditorDialog> createState() => _SmsBankPatternEditorDialogState();
}

class _SmsBankPatternEditorDialogState extends State<SmsBankPatternEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _hints;
  late final TextEditingController _template;
  late final TextEditingController _sample;
  String? _bankId;
  String? _bankName;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _name = TextEditingController(text: i?.name ?? '');
    _hints = TextEditingController(text: i?.senderHints.join('، ') ?? '');
    _template = TextEditingController(text: i?.template ?? '');
    _sample = TextEditingController();
    _bankId = i?.bankAccountId?.toString();
    _bankName = i?.bankAccountName;
  }

  @override
  void dispose() {
    _name.dispose();
    _hints.dispose();
    _template.dispose();
    _sample.dispose();
    super.dispose();
  }

  void _runTest() {
    final match = SmsBankPatternEngine.testTemplate(
      template: _template.text,
      sampleBody: _sample.text,
      senderHints: _parseHints(_hints.text),
    );
    setState(() {
      if (!match.matched) {
        _testResult = 'تطبیق نشد — الگو یا نمونه را اصلاح کنید';
      } else {
        final dir = match.direction == SmsBankDirection.credit
            ? 'واریز'
            : match.direction == SmsBankDirection.debit
                ? 'برداشت'
                : 'نامشخص';
        _testResult =
            'موفق: $dir ${formatWithThousands(match.amount)} ریال'
            '${match.accountMask != null ? ' · حساب ${match.accountMask}' : ''}';
      }
    });
  }

  void _learnFromSample() {
    final sample = _sample.text;
    if (sample.trim().isEmpty) {
      SnackBarHelper.showError(context, message: 'ابتدا پیامک نمونه را وارد کنید');
      return;
    }
    // Auto-detect amount-like numbers and suggest wrapping first big number as {amount}
    final amountRe = RegExp(r'[+\-]?\d{1,3}(?:,\d{3})+|[+\-]?\d{4,}');
    final matches = amountRe.allMatches(sample).toList();
    if (matches.isEmpty) {
      SnackBarHelper.showError(context, message: 'مبلغی در نمونه پیدا نشد');
      return;
    }
    final markers = <String, String>{
      'amount': matches.first.group(0)!,
    };
    // Optional balance: last amount-like if different
    if (matches.length > 1) {
      markers['balance'] = matches.last.group(0)!;
    }
    for (final word in ['برداشت', 'واریز', 'واريز']) {
      if (sample.contains(word)) {
        markers['direction'] = word;
        break;
      }
    }
    final accountRe = RegExp(r'[\d×xX*]{4,}[\d×xX*\-.]*');
    final acc = accountRe.firstMatch(sample);
    if (acc != null) markers['account'] = acc.group(0)!;

    final template = SmsBankPatternEngine.buildTemplateFromMarkers(sample, markers);
    setState(() {
      _template.text = template;
      _testResult = 'الگو از روی نمونه ساخته شد — تست کنید و در صورت نیاز ویرایش کنید';
    });
  }

  List<String> _parseHints(String raw) {
    return raw
        .split(RegExp(r'[،,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      SnackBarHelper.showError(context, message: 'نام الگو لازم است');
      return;
    }
    if (_template.text.trim().isEmpty) {
      SnackBarHelper.showError(context, message: 'قالب الگو خالی است');
      return;
    }
    final pattern = SmsBankPattern(
      id: widget.initial?.id ?? SmsBankSeedPatterns.newId(),
      name: name,
      enabled: widget.initial?.enabled ?? true,
      senderHints: _parseHints(_hints.text),
      template: _template.text,
      bankAccountId: int.tryParse(_bankId ?? ''),
      bankAccountName: _bankName,
      businessId: widget.businessId,
      businessName: widget.businessName ?? widget.initial?.businessName,
      isSeed: widget.initial?.isSeed ?? false,
      updatedAt: DateTime.now(),
    );
    Navigator.pop(context, pattern);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'الگوی جدید' : 'ویرایش الگو'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'نام الگو',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _hints,
                decoration: const InputDecoration(
                  labelText: 'راهنمای فرستنده (با ویرگول)',
                  hintText: 'مثلاً تجارت، Tejarat',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              BankAccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccountId: _bankId,
                label: 'حساب بانکی مرتبط',
                hintText: 'این نوع پیامک مربوط به کدام حساب است؟',
                onChanged: (opt) {
                  setState(() {
                    _bankId = opt?.id;
                    _bankName = opt?.name;
                  });
                },
              ),
              const SizedBox(height: 4),
              Text(
                _bankName == null
                    ? 'حساب بانکی مقصد این نوع پیامک را انتخاب کنید'
                    : 'انتخاب‌شده: $_bankName',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sample,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'پیامک نمونه (برای ساخت/تست الگو)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _learnFromSample,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('ساخت الگو از نمونه'),
                  ),
                  OutlinedButton(
                    onPressed: _runTest,
                    child: const Text('تست قالب'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _template,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'قالب الگو',
                  helperText:
                      'جایگاه‌ها: {amount} {amount_signed} {direction} {balance} {account} {date} {time} {channel} {any}',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 8),
                Text(_testResult!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _save, child: const Text('ذخیره')),
      ],
    );
  }
}
