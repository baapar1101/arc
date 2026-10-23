import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:uuid/uuid.dart';
import '../../config/brand_config.dart';
import '../../core/api_client.dart';
import '../../services/platform_admin_service.dart';
import '../../utils/error_extractor.dart';
import '../../theme/brand_logo.dart';

/// The route and every API endpoint are restricted to platform superadmins.
class PlatformManagementPage extends StatefulWidget {
  const PlatformManagementPage({super.key});
  @override
  State<PlatformManagementPage> createState() => _PlatformManagementPageState();
}

class _PlatformManagementPageState extends State<PlatformManagementPage> {
  final _service = PlatformAdminService(ApiClient());
  final _search = TextEditingController();
  int _tab = 0, _skip = 0, _total = 0, _auditSkip = 0, _auditTotal = 0;
  bool _loading = true, _busy = false;
  String? _error;
  Map<String, dynamic> _overview = {}, _branding = {}, _advanced = {};
  Map<String, dynamic>? _wallet;
  List<Map<String, dynamic>> _wallets = [], _audit = [];
  static const _labels = [
    'نمای کلی',
    'کیف پول کسب‌وکارها',
    'نام و لوگو',
    'تنظیمات پیشرفته',
    'تاریخچه تغییرات',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String money(dynamic v) =>
      NumberFormat.decimalPattern('fa').format(num.tryParse('$v') ?? 0);
  List<Map<String, dynamic>> maps(dynamic value) => (value as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  void notify(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_tab == 0) {
        _overview = await _service.get('overview');
      } else if (_tab == 1) {
        final result = await _service.get(
          'wallets',
          query: {'q': _search.text.trim(), 'skip': _skip, 'limit': 25},
        );
        _wallets = maps(result['items']);
        _total = result['total'] as int? ?? 0;
      } else if (_tab == 2) {
        final result = await ApiClient().get<Map<String, dynamic>>(
          '/api/v1/platform/branding',
        );
        _branding = Map<String, dynamic>.from(
          result.data?['data'] as Map? ?? {},
        );
      } else if (_tab == 3) {
        _advanced = await _service.get('advanced');
      } else {
        final result = await _service.get('audit', query: {'skip': _auditSkip});
        _audit = maps(result['items']);
        _auditTotal = result['total'] as int? ?? 0;
      }
    } catch (e) {
      if (mounted) _error = ErrorExtractor.forContext(e, context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openWallet(int id) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _wallet = await _service.get('wallets/$id');
    } catch (e) {
      if (mounted) _error = ErrorExtractor.forContext(e, context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _write(Future<void> Function() action) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) notify('تغییرات با ثبت سابقه ذخیره شد.');
      return true;
    } catch (e) {
      if (mounted) notify(ErrorExtractor.forContext(e, context));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _card(Widget child) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
  Widget _heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(subtitle),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت پلتفرم'),
        actions: [
          IconButton(
            onPressed: _busy
                ? null
                : () {
                    _wallet = null;
                    _load();
                  },
            icon: const Icon(Icons.refresh),
            tooltip: 'تازه‌سازی',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: const Row(
              children: [
                Icon(Icons.verified_user_outlined),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'کنترل سراسری پلتفرم • فقط مدیر ارشد • تمام تغییرات با هویت مدیر و دلیل ثبت می‌شوند.',
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: List.generate(
                _labels.length,
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(_labels[i]),
                    selected: i == _tab,
                    onSelected: _busy
                        ? null
                        : (_) {
                            _tab = i;
                            _wallet = null;
                            _load();
                          },
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('تلاش دوباره'),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1250),
                        child: switch (_tab) {
                          0 => _overviewView(),
                          1 => _wallet == null ? _walletList() : _walletView(),
                          2 => _brandingView(),
                          3 => _advancedView(),
                          _ => _auditView(),
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _overviewView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        'اتاق کنترل پلتفرم',
        'نمای یکپارچه کسب‌وکارها و اعتبار؛ مبالغ بر حسب ${_overview['currency'] ?? 'IRR'} هستند.',
      ),
      Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (final entry in {
            'کسب‌وکارها': 'businesses',
            'کاربران': 'users',
            'کیف پول‌ها': 'wallets',
            'تعلیق‌شده': 'suspended_wallets',
            'موجودی قابل استفاده': 'available_balance',
            'در انتظار تسویه': 'pending_balance',
            'درخواست تسویه باز': 'pending_payouts',
          }.entries)
            SizedBox(
              width: 270,
              child: _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.key),
                    const SizedBox(height: 14),
                    Text(
                      money(_overview[entry.value]),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 20),
      _card(
        const ListTile(
          leading: Icon(Icons.shield_outlined),
          title: Text('داده حساس، ویرایش کنترل‌شده'),
          subtitle: Text(
            'رمزها، کلیدهای سرویس و دفتر حسابداری در این پنل ویرایش خام ندارند. اصلاح اعتبار، تراکنش داخلی ثبت می‌کند و انتقال بانکی یا تسویه واقعی نیست.',
          ),
        ),
      ),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          OutlinedButton.icon(
            onPressed: () => context.go('/user/profile/system-settings'),
            icon: const Icon(Icons.settings),
            label: const Text('تمام تنظیمات سیستم'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                context.go('/user/profile/system-settings/wallet-payouts'),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('درخواست‌های تسویه'),
          ),
        ],
      ),
    ],
  );

  Widget _walletList() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        'کیف پول همهٔ کسب‌وکارها',
        'مانده قابل استفاده و مانده در انتظار تسویه مستقل‌اند. اصلاح مستقیم مانده در انتظار مجاز نیست.',
      ),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              onSubmitted: (_) {
                _skip = 0;
                _load();
              },
              decoration: const InputDecoration(
                labelText: 'نام کسب‌وکار، ایمیل مالک یا شناسه',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: () {
              _skip = 0;
              _load();
            },
            child: const Text('جستجو'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      if (_wallets.isEmpty) _card(const Text('کسب‌وکاری یافت نشد.')),
      for (final wallet in _wallets)
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${wallet['business_name']} • #${wallet['business_id']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Chip(
                    label: Text(
                      wallet['status'] == 'suspended'
                          ? 'برداشت تعلیق‌شده'
                          : wallet['status'] == 'active'
                          ? 'فعال'
                          : 'بدون کیف پول',
                    ),
                  ),
                ],
              ),
              Text(
                '${wallet['owner_email'] ?? '—'}',
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('قابل استفاده: ${money(wallet['available_balance'])}'),
                  Text('در انتظار: ${money(wallet['pending_balance'])}'),
                  FilledButton.tonalIcon(
                    onPressed: () => _openWallet(wallet['business_id'] as int),
                    icon: const Icon(Icons.tune),
                    label: const Text('مدیریت و تراکنش‌ها'),
                  ),
                ],
              ),
            ],
          ),
        ),
      _pagination(_skip, _total, 25, (skip) {
        _skip = skip;
        _load();
      }),
    ],
  );

  Widget _pagination(
    int skip,
    int total,
    int size,
    void Function(int) change,
  ) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        onPressed: skip > 0
            ? () => change((skip - size).clamp(0, total))
            : null,
        icon: const Icon(Icons.chevron_right),
        tooltip: 'صفحه قبل',
      ),
      Text(
        '${total == 0 ? 0 : skip + 1}–${(skip + size).clamp(0, total)} از $total',
      ),
      IconButton(
        onPressed: skip + size < total ? () => change(skip + size) : null,
        icon: const Icon(Icons.chevron_left),
        tooltip: 'صفحه بعد',
      ),
    ],
  );

  Widget _walletView() {
    final wallet = _wallet!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _busy
                ? null
                : () {
                    _wallet = null;
                    _load();
                  },
            icon: const Icon(Icons.arrow_back),
            label: const Text('همهٔ کیف پول‌ها'),
          ),
        ),
        _heading(
          '${wallet['business_name']} • #${wallet['business_id']}',
          'قابل استفاده: ${money(wallet['available_balance'])} | در انتظار تسویه: ${money(wallet['pending_balance'])}',
        ),
        _WalletEditor(
          key: ValueKey(
            '${wallet['business_id']}:${wallet['available_balance']}:${wallet['status']}',
          ),
          wallet: wallet,
          busy: _busy,
          saveControls: (data) => _write(() async {
            final result = await _service.put(
              'wallets/${wallet['business_id']}/controls',
              data,
            );
            if (mounted) setState(() => _wallet = result);
          }),
          adjust: (data) => _write(() async {
            await _service.adjust(wallet['business_id'] as int, data);
            await _openWallet(wallet['business_id'] as int);
          }),
        ),
        const SizedBox(height: 20),
        _heading(
          '۵۰ تراکنش آخر',
          'تراکنش‌های قبلی از این بخش قابل حذف یا بازنویسی نیستند.',
        ),
        for (final tx in maps(wallet['transactions']))
          _card(
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: Text(
                '${money(tx['amount'])} • ${tx['type']} • ${tx['status']}',
              ),
              subtitle: Text(
                '#${tx['id']} | ${tx['created_at']}\n${tx['description'] ?? ''}',
              ),
            ),
          ),
      ],
    );
  }

  Widget _brandingView() => _BrandingEditor(
    key: ValueKey(jsonEncode(_branding)),
    data: _branding,
    busy: _busy,
    save: (data) => _write(() async {
      _branding = await _service.put('branding', data);
      await BrandConfig.refresh();
    }),
    upload: () async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final file = result.files.single;
      if (file.size > 2 * 1024 * 1024 || file.bytes == null) {
        notify('یک تصویر حداکثر ۲ مگابایتی انتخاب کنید.');
        return;
      }
      await _write(() async {
        _branding = await _service.logo(
          file.bytes!,
          file.name,
          'به‌روزرسانی لوگوی پلتفرم',
        );
        await BrandConfig.refresh();
      });
    },
  );

  Widget _advancedView() => _AdvancedEditor(
    key: ValueKey(jsonEncode(_advanced)),
    data: _advanced,
    busy: _busy,
    save: (data) => _write(() async {
      _advanced = await _service.put('advanced', data);
    }),
  );

  Widget _auditView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        'ردپای تغییرات مدیریتی',
        'چه کسی، چه زمانی و با چه دلیلی؛ مقادیر قبل و بعد بدون نمایش رمز و کلید سرویس.',
      ),
      if (_audit.isEmpty)
        _card(const Text('هنوز تغییری از این پنل ثبت نشده است.')),
      for (final event in _audit)
        _card(
          ExpansionTile(
            title: Text('${event['reason']}'),
            subtitle: Text(
              '${event['actor_email'] ?? 'مدیر'} • ${event['created_at']}\n${event['entity']} #${event['entity_id']}',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  'قبل:\n${const JsonEncoder.withIndent('  ').convert(event['before'])}\n\nبعد:\n${const JsonEncoder.withIndent('  ').convert(event['after'])}',
                  textDirection: TextDirection.ltr,
                ),
              ),
            ],
          ),
        ),
      _pagination(_auditSkip, _auditTotal, 30, (skip) {
        _auditSkip = skip;
        _load();
      }),
    ],
  );
}

typedef SavePlatform = Future<bool> Function(Map<String, dynamic> data);
String? requiredText(String? v) =>
    v == null || v.trim().isEmpty ? 'این مقدار الزامی است.' : null;
String normalizeDigits(String input) {
  var result = input.trim();
  for (var i = 0; i < 10; i++) {
    result = result
        .replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], '$i')
        .replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i');
  }
  return result;
}

Widget platformField(
  TextEditingController controller,
  String label, {
  String? Function(String?)? validator,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: TextFormField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator: validator ?? requiredText,
  ),
);

class _WalletEditor extends StatefulWidget {
  final Map<String, dynamic> wallet;
  final bool busy;
  final SavePlatform saveControls, adjust;
  const _WalletEditor({
    super.key,
    required this.wallet,
    required this.busy,
    required this.saveControls,
    required this.adjust,
  });
  @override
  State<_WalletEditor> createState() => _WalletEditorState();
}

class _WalletEditorState extends State<_WalletEditor> {
  final _form = GlobalKey<FormState>(), _adjustForm = GlobalKey<FormState>();
  final _threshold = TextEditingController(),
      _reserve = TextEditingController(),
      _reason = TextEditingController(),
      _amount = TextEditingController(),
      _adjustReason = TextEditingController();
  late String _status, _mode, _frequency;
  int? _bank;
  bool _debit = false;
  String? _requestId;
  Map<String, dynamic>? _pendingAdjustment;
  @override
  void initState() {
    super.initState();
    final settings = widget.wallet['settings'] as Map;
    _status = widget.wallet['status'] == 'suspended' ? 'suspended' : 'active';
    _mode = '${settings['mode'] ?? 'manual'}';
    _frequency = '${settings['frequency'] ?? 'daily'}';
    _threshold.text = '${settings['threshold_amount'] ?? '0'}';
    _reserve.text = '${settings['min_reserve'] ?? '0'}';
    _bank = settings['default_bank_account_id'] as int?;
  }

  @override
  void dispose() {
    for (final c in [_threshold, _reserve, _reason, _amount, _adjustReason]) {
      c.dispose();
    }
    super.dispose();
  }

  String? positive(String? v) {
    final n = num.tryParse(normalizeDigits(v ?? ''));
    return n == null || !n.isFinite || n < 0
        ? 'مبلغ معتبر و غیرمنفی وارد کنید.'
        : null;
  }

  Future<void> _adjust() async {
    if (!(_adjustForm.currentState?.validate() ?? false)) return;
    final amount = normalizeDigits(_amount.text);
    final delta = '${_debit ? '-' : ''}$amount';
    final data = {
      'delta': delta,
      'expected_balance': '${widget.wallet['available_balance']}',
      'reason': _adjustReason.text.trim(),
    };
    if (_pendingAdjustment == null ||
        jsonEncode(data) != jsonEncode(_pendingAdjustment)) {
      _requestId = const Uuid().v4();
      _pendingAdjustment = data;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأیید اصلاح اعتبار'),
        content: Text(
          '${widget.wallet['business_name']} (#${widget.wallet['business_id']})\n${_debit ? 'کاهش' : 'افزایش'} $amount\nعلت: ${_adjustReason.text}\n\nاین عملیات انتقال بانکی نیست؛ تراکنش اصلاح داخلی و سابقه ثبت خواهد شد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأیید اصلاح'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.adjust({...data, 'request_id': _requestId});
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _adjustForm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'اصلاح اعتبار داخلی',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'مانده در انتظار تسویه دست‌نخورده می‌ماند. علت الزامی است؛ ارسال مجدد همان درخواست دوباره اعمال نمی‌شود.',
                ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('افزایش اعتبار'),
                      icon: Icon(Icons.add),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('کاهش اعتبار'),
                      icon: Icon(Icons.remove),
                    ),
                  ],
                  selected: {_debit},
                  onSelectionChanged: widget.busy
                      ? null
                      : (v) => setState(() => _debit = v.single),
                ),
                const SizedBox(height: 16),
                platformField(
                  _amount,
                  'مبلغ در ارز پایه کیف پول',
                  validator: (v) {
                    final error = positive(v);
                    return error ??
                        ((num.tryParse(normalizeDigits(v ?? '')) ?? 0) <= 0
                            ? 'مبلغ باید مثبت باشد.'
                            : null);
                  },
                ),
                platformField(
                  _adjustReason,
                  'دلیل اصلاح (حداقل ۵ حرف)',
                  validator: (v) => (v?.trim().length ?? 0) < 5
                      ? 'دلیل کامل وارد کنید.'
                      : null,
                ),
                FilledButton.icon(
                  onPressed: widget.busy ? null : _adjust,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('بررسی و تأیید اصلاح'),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'کنترل برداشت و تنظیمات تسویه',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('تعلیق برداشت و خرید'),
                  subtitle: const Text(
                    'واریز تأییدشده و آزادسازی تسویه قبلی متوقف نمی‌شود.',
                  ),
                  value: _status == 'suspended',
                  onChanged: widget.busy
                      ? null
                      : (v) => setState(
                          () => _status = v ? 'suspended' : 'active',
                        ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _mode,
                  decoration: const InputDecoration(labelText: 'روش تسویه'),
                  items: const [
                    DropdownMenuItem(value: 'manual', child: Text('دستی')),
                    DropdownMenuItem(value: 'auto', child: Text('خودکار')),
                  ],
                  onChanged: widget.busy
                      ? null
                      : (v) => setState(() => _mode = v!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _frequency,
                  decoration: const InputDecoration(labelText: 'دوره تسویه'),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('روزانه')),
                    DropdownMenuItem(value: 'weekly', child: Text('هفتگی')),
                  ],
                  onChanged: widget.busy
                      ? null
                      : (v) => setState(() => _frequency = v!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _bank,
                  decoration: const InputDecoration(
                    labelText: 'حساب بانکی همین کسب‌وکار',
                  ),
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text('بدون حساب پیش‌فرض'),
                    ),
                    for (final b in (widget.wallet['bank_accounts'] as List))
                      DropdownMenuItem<int>(
                        value: b['id'] as int,
                        child: Text('${b['name']}'),
                      ),
                  ],
                  onChanged: widget.busy
                      ? null
                      : (v) => setState(() => _bank = v),
                ),
                const SizedBox(height: 16),
                platformField(
                  _threshold,
                  'حداقل مبلغ تسویه',
                  validator: positive,
                ),
                platformField(
                  _reserve,
                  'ذخیره حداقل در کیف پول',
                  validator: positive,
                ),
                platformField(
                  _reason,
                  'دلیل تغییر کنترل‌ها (حداقل ۵ حرف)',
                  validator: (v) => (v?.trim().length ?? 0) < 5
                      ? 'دلیل کامل وارد کنید.'
                      : null,
                ),
                FilledButton.icon(
                  onPressed: widget.busy
                      ? null
                      : () {
                          if (_form.currentState?.validate() ?? false) {
                            widget.saveControls({
                              'status': _status,
                              'mode': _mode,
                              'frequency': _frequency,
                              'threshold_amount': normalizeDigits(
                                _threshold.text,
                              ),
                              'min_reserve': normalizeDigits(_reserve.text),
                              'default_bank_account_id': _bank,
                              'reason': _reason.text.trim(),
                            });
                          }
                        },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('ذخیره کنترل‌ها'),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _BrandingEditor extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool busy;
  final SavePlatform save;
  final Future<void> Function() upload;
  const _BrandingEditor({
    super.key,
    required this.data,
    required this.busy,
    required this.save,
    required this.upload,
  });
  @override
  State<_BrandingEditor> createState() => _BrandingEditorState();
}

class _BrandingEditorState extends State<_BrandingEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _fa, _en, _tagline;
  final _reason = TextEditingController();
  @override
  void initState() {
    super.initState();
    _fa = TextEditingController(
      text: '${widget.data['name_fa'] ?? ''}'.isEmpty
          ? BrandConfig.appNameFa
          : '${widget.data['name_fa']}',
    );
    _en = TextEditingController(
      text: '${widget.data['name_en'] ?? ''}'.isEmpty
          ? BrandConfig.appNameEn
          : '${widget.data['name_en']}',
    );
    _tagline = TextEditingController(text: '${widget.data['tagline'] ?? ''}');
  }

  @override
  void dispose() {
    for (final c in [_fa, _en, _tagline, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('هویت پلتفرم', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'نام و لوگوی داخل اپ بدون بیلد مجدد تغییر می‌کنند. آیکن نصب‌شده سیستم‌عامل و صفحه بارگذاری اولیه مستقل از این تنظیم‌اند.',
            ),
            const SizedBox(height: 24),
            const Center(child: BrandLogo(width: 100, height: 80)),
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton.icon(
                onPressed: widget.busy ? null : widget.upload,
                icon: const Icon(Icons.upload_file),
                label: const Text(
                  'انتخاب لوگو (PNG / JPG / WebP، حداکثر ۲ MB)',
                ),
              ),
            ),
            const SizedBox(height: 24),
            platformField(_fa, 'نام فارسی'),
            platformField(_en, 'نام انگلیسی'),
            platformField(_tagline, 'شعار کوتاه', validator: (_) => null),
            platformField(
              _reason,
              'دلیل تغییر نام (حداقل ۵ حرف)',
              validator: (v) =>
                  (v?.trim().length ?? 0) < 5 ? 'دلیل کامل وارد کنید.' : null,
            ),
            FilledButton.icon(
              onPressed: widget.busy
                  ? null
                  : () {
                      if (_form.currentState?.validate() ?? false) {
                        widget.save({
                          'name_fa': _fa.text.trim(),
                          'name_en': _en.text.trim(),
                          'tagline': _tagline.text.trim(),
                          'reason': _reason.text.trim(),
                        });
                      }
                    },
              icon: const Icon(Icons.save_outlined),
              label: const Text('ذخیره هویت پلتفرم'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AdvancedEditor extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool busy;
  final SavePlatform save;
  const _AdvancedEditor({
    super.key,
    required this.data,
    required this.busy,
    required this.save,
  });
  @override
  State<_AdvancedEditor> createState() => _AdvancedEditorState();
}

class _AdvancedEditorState extends State<_AdvancedEditor> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final Map<String, TextEditingController> _fields = {};
  late bool _support, _legacy;
  static const labels = {
    'max_file_size': 'حداکثر حجم فایل (مگابایت)',
    'max_users': 'حداکثر کاربران (صفر = بدون سقف)',
    'mcp_oauth_session_days': 'اعتبار نشست اتصال MCP (روز)',
    'default_timezone': 'منطقه زمانی پیش‌فرض',
    'support_tickets_disabled_message': 'پیام توقف پشتیبانی',
    'legacy_api_import_disabled_message': 'پیام توقف ورود اطلاعات قدیمی',
  };
  @override
  void initState() {
    super.initState();
    for (final key in labels.keys) {
      _fields[key] = TextEditingController(text: '${widget.data[key] ?? ''}');
    }
    _support = widget.data['support_tickets_enabled'] == true;
    _legacy = widget.data['legacy_api_import_enabled'] == true;
  }

  @override
  void dispose() {
    _reason.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'تنظیمات سراسری منتخب',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'این مقادیر به تنظیمات واقعی سرویس متصل‌اند. تغییر آن‌ها روی همهٔ کاربران اثر دارد؛ رمزها و تنظیمات شبکه در ویرایشگر عمومی نمایش داده نمی‌شوند.',
            ),
            const SizedBox(height: 24),
            for (final entry in labels.entries)
              platformField(
                _fields[entry.key]!,
                entry.value,
                validator: (v) {
                  if (entry.key.endsWith('_message')) return null;
                  if ([
                    'max_file_size',
                    'max_users',
                    'mcp_oauth_session_days',
                  ].contains(entry.key)) {
                    return int.tryParse(normalizeDigits(v ?? '')) == null
                        ? 'عدد صحیح وارد کنید.'
                        : null;
                  }
                  return requiredText(v);
                },
              ),
            SwitchListTile(
              title: const Text('پشتیبانی کاربران فعال باشد'),
              value: _support,
              onChanged: widget.busy
                  ? null
                  : (v) => setState(() => _support = v),
            ),
            SwitchListTile(
              title: const Text('ورود از حسابیکس قدیمی فعال باشد'),
              value: _legacy,
              onChanged: widget.busy
                  ? null
                  : (v) => setState(() => _legacy = v),
            ),
            const SizedBox(height: 16),
            platformField(
              _reason,
              'دلیل تغییر سراسری (حداقل ۵ حرف)',
              validator: (v) =>
                  (v?.trim().length ?? 0) < 5 ? 'دلیل کامل وارد کنید.' : null,
            ),
            FilledButton.icon(
              onPressed: widget.busy
                  ? null
                  : () {
                      if (_form.currentState?.validate() ?? false) {
                        widget.save({
                          for (final e in _fields.entries)
                            e.key:
                                [
                                  'max_file_size',
                                  'max_users',
                                  'mcp_oauth_session_days',
                                ].contains(e.key)
                                ? int.parse(normalizeDigits(e.value.text))
                                : e.value.text.trim(),
                          'support_tickets_enabled': _support,
                          'legacy_api_import_enabled': _legacy,
                          'reason': _reason.text.trim(),
                        });
                      }
                    },
              icon: const Icon(Icons.save_outlined),
              label: const Text('ذخیره تنظیمات پیشرفته'),
            ),
          ],
        ),
      ),
    ),
  );
}
