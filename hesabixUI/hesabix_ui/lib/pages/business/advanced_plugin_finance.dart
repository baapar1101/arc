part of 'advanced_plugins_page.dart';

class _Finance extends StatefulWidget {
  final AdvancedPluginsService api;
  final Map<String, dynamic> module;
  const _Finance({super.key, required this.api, required this.module});
  @override
  State<_Finance> createState() => _FinanceState();
}

class _FinanceState extends State<_Finance> {
  Map<String, dynamic>? data;
  String? error, message;
  bool busy = false, enabled = false;
  GlobalKey<_FieldsState> accountFields = GlobalKey<_FieldsState>();
  final recordId = TextEditingController();
  String get code => '${widget.module['code']}';
  bool get manager => widget.module['can_approve'] == true;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    recordId.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final next = await widget.api.finance(code);
      if (mounted) {
        setState(() {
          if (config['revision'] != _map(next['config'])['revision']) {
            accountFields = GlobalKey<_FieldsState>();
          }
          data = next;
          enabled = _map(next['config'])['enabled'] == true;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = _error(e));
    }
  }

  Future<void> run(Future<dynamic> Function() action, String success) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      await action();
      if (mounted) setState(() => message = success);
      await load();
    } catch (e) {
      if (mounted) setState(() => error = _error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Map<String, dynamic> get config => _map(data?['config']);
  Map<String, dynamic> definitions() => {
    for (final entry in _map(data?['roles']).entries)
      entry.key: {'label': entry.value, 'type': 'account'},
    if (code == 'contracting')
      'contract_side': {
        'label': 'جهت قرارداد',
        'type': 'choice',
        'choices': ['require_review', 'customer', 'supplier'],
      },
  };
  Future<void> saveConfig() async {
    final values = accountFields.currentState!.values();
    await run(
      () => widget.api.financeConfig(code, {
        'revision': config['revision'],
        'enabled': enabled,
        'accounts': {
          for (final key in _map(data?['roles']).keys) key: values[key],
        },
        'contract_side': code == 'contracting'
            ? values['contract_side']
            : 'require_review',
      }),
      'تنظیم حساب‌های مالی ذخیره شد. پیش‌نویس‌های قبلی پیش از تأیید دوباره کنترل می‌شوند.',
    );
  }

  Future<void> draft(int id) => run(
    () => widget.api.financeAction(code, 'drafts', {'record_id': id}),
    'پیش‌نویس ساخته یا همان رویداد قبلی بازیابی شد؛ هنوز سندی صادر نشده است.',
  );

  Future<void> decide(Map<String, dynamic> row, String action) async {
    Map<String, dynamic>? decision;
    final decisionFields = GlobalKey<_FieldsState>();
    final journal = _map(row['proposal']);
    final title = action == 'approve'
        ? 'تأیید مدیر و صدور سند'
        : action == 'reverse'
        ? 'برگشت سند با ثبت معکوس'
        : 'رد پیش‌نویس';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('رویداد ${row['id']} — ${journal['title']}'),
                Text(
                  'تاریخ ${journal['document_date']} · سال مالی ${journal['fiscal_year_id']} · ارز ${journal['currency_id']}',
                ),
                Text(
                  'بدهکار: ${journal['total_debit']} · بستانکار: ${journal['total_credit']}',
                ),
                const SizedBox(height: 12),
                for (final item in journal['lines'] as List? ?? [])
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        '${item['role']} — ${item['account_name']} (#${item['account_id']})\nبدهکار ${item['debit']} | بستانکار ${item['credit']}',
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  action == 'reverse'
                      ? 'سند اصلی حذف نمی‌شود؛ یک سند معکوس جدید به آن متصل می‌شود.'
                      : 'مبلغ، حساب‌ها، سال مالی و مبدأ در لحظه صدور دوباره بررسی می‌شوند. تغییر داده نیازمند بازسازی پیش‌نویس است.',
                ),
                ExpansionTile(
                  title: const Text('مبنای رویداد، مراجع و نسخه محاسبه'),
                  children: [
                    SelectableText(
                      const JsonEncoder.withIndent(
                        '  ',
                      ).convert(journal['inputs']),
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ),
                _Fields(
                  key: decisionFields,
                  api: widget.api,
                  code: code,
                  definitions: {
                    'reason': {
                      'label': 'دلیل و مستند تصمیم مدیر (حداقل ۵ نویسه)',
                      'type': 'text',
                      'required': true,
                    },
                    if (action == 'reverse')
                      'on_date': {
                        'label': 'تاریخ برگشت در سال مالی جاری',
                        'type': 'date',
                        'required': true,
                      },
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              decision = decisionFields.currentState?.values();
              Navigator.pop(ctx, true);
            },
            child: Text(title),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    final note = '${decision?['reason'] ?? ''}'.trim();
    if (note.length < 5) {
      setState(() => error = 'دلیل تصمیم مدیر باید حداقل ۵ نویسه باشد.');
      return;
    }
    final date = action == 'reverse' ? (decision?['on_date'] as String?) : null;
    await run(
      () => widget.api.financeAction(code, '${row['id']}/$action', {
        'revision': row['revision'],
        'input_hash': row['input_hash'],
        'confirmed': true,
        'reason': note,
        'on_date': ?date,
      }),
      action == 'approve'
          ? 'سند مالی با تأیید مدیر صادر شد.'
          : action == 'reverse'
          ? 'سند برگشت متوازن صادر شد؛ اصل سند محفوظ است.'
          : 'پیش‌نویس رد شد.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return Center(
        child: error != null ? Text(error!) : const CircularProgressIndicator(),
      );
    }
    final rows = (data!['items'] as List? ?? []).map(_map).toList();
    final candidates = (data!['candidates'] as List? ?? []).map(_map).toList();
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        Text('${data!['policy']}'),
        const SizedBox(height: 8),
        Text(
          'اسناد اصلی سپیدار مجدداً صادر نمی‌شوند. برای قیمت، بها و مالیات، فقط مبلغ تعدیل مستقل وارد کنید؛ نه مبلغ کل عملیات.',
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (message != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(message!)),
        if (manager)
          ExpansionTile(
            title: Text(
              'حساب‌ها و فعال‌سازی ثبت مالی · ${config['enabled'] == true ? 'فعال' : 'نیازمند تنظیم مدیر'}',
            ),
            children: [
              SwitchListTile(
                title: const Text(
                  'اجازه ساخت پیش‌نویس مالی (صدور همچنان فقط با تأیید مدیر)',
                ),
                value: enabled,
                onChanged: busy ? null : (v) => setState(() => enabled = v),
              ),
              _Fields(
                key: accountFields,
                api: widget.api,
                code: code,
                definitions: definitions(),
                initial: {
                  ..._map(config['accounts']),
                  'contract_side': config['contract_side'],
                },
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy ? null : saveConfig,
                child: const Text('ذخیره حساب‌های مالی'),
              ),
            ],
          )
        else
          const Text(
            'فقط مدیر دارای مجوز تأیید می‌تواند حساب‌ها را تنظیم یا سند صادر کند.',
          ),
        const Divider(height: 28),
        if (widget.module['can_write'] == true)
          ExpansionTile(
            title: Text(
              'ساخت پیش‌نویس از رویداد واجد شرایط (${candidates.length} مورد اخیر)',
            ),
            subtitle: Text(
              'نوع لازم: ${_map(_map(widget.module['kinds'])[data!['eligible_kind']])['label'] ?? data!['eligible_kind']}',
            ),
            children: [
              if (candidates.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'رویداد محلی واجد شرایطی وجود ندارد. استهلاک/صورت‌وضعیت را محاسبه و ذخیره کنید؛ یا در تب داده‌ها یک تعدیل مستند بسازید.',
                  ),
                ),
              for (final c in candidates)
                ListTile(
                  title: Text('${c['title']}'),
                  subtitle: Text('#${c['id']} · ${c['date']} · ${c['amount']}'),
                  trailing: OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => draft((c['id'] as num).toInt()),
                    child: const Text('پیش‌نویس'),
                  ),
                ),
              TextField(
                controller: recordId,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'شناسه رویداد قدیمی‌تر (اختیاری)',
                  border: OutlineInputBorder(),
                ),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        final id = int.tryParse(recordId.text);
                        if (id != null) draft(id);
                      },
                child: const Text('ساخت / بازیابی پیش‌نویس با شناسه'),
              ),
            ],
          ),
        Row(
          children: [
            const Expanded(
              child: Text(
                '۱۰۰ پیش‌نویس و سند اخیر',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              onPressed: busy ? null : load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'هیچ سند یا پیش‌نویس مالی ثبت نشده است. فعال‌سازی یا همگام‌سازی به‌تنهایی سند ایجاد نمی‌کند.',
            ),
          ),
        for (final row in rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '#${row['id']} — ${_map(row['proposal'])['title']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'وضعیت: ${{'draft': 'منتظر تأیید مدیر', 'posted': 'صادرشده', 'rejected': 'ردشده', 'reversed': 'برگشت‌شده'}[row['state']] ?? row['state']} · نسخه ${row['revision']}',
                  ),
                  Text(
                    'تاریخ ${_map(row['proposal'])['document_date']} · جمع ${_map(row['proposal'])['total_debit']}',
                  ),
                  if (row['document_id'] != null)
                    Text(
                      'سند اصلی ADP-${row['id']} (#${row['document_id']}) · مدیر تأییدکننده ${row['approved_by_user_id']}',
                    ),
                  if (row['reversal_document_id'] != null)
                    Text(
                      'سند برگشت ADPR-${row['id']} (#${row['reversal_document_id']})',
                    ),
                  if (row['decision_reason'] != null)
                    Text('دلیل: ${row['decision_reason']}'),
                  ExpansionTile(
                    title: const Text('مشاهده ردیف‌ها و نسخه تأیید'),
                    children: [
                      for (final line
                          in _map(row['proposal'])['lines'] as List? ?? [])
                        ListTile(
                          title: Text(
                            '${line['role']} — ${line['account_name']}',
                          ),
                          subtitle: Text(
                            'بدهکار ${line['debit']} | بستانکار ${line['credit']}',
                          ),
                        ),
                      SelectableText(
                        'Hash: ${row['input_hash']}',
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.module['can_write'] == true &&
                          ['draft', 'rejected'].contains(row['state']))
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => run(
                                  () => widget.api.financeAction(
                                    code,
                                    '${row['id']}/refresh',
                                    {'revision': row['revision']},
                                  ),
                                  'پیش‌نویس با داده فعلی بازسازی شد؛ تأیید جدید لازم است.',
                                ),
                          child: const Text('بازسازی با داده فعلی'),
                        ),
                      if (manager && row['state'] == 'draft') ...[
                        FilledButton(
                          onPressed: busy ? null : () => decide(row, 'approve'),
                          child: const Text('بررسی، تأیید و صدور'),
                        ),
                        OutlinedButton(
                          onPressed: busy ? null : () => decide(row, 'reject'),
                          child: const Text('رد پیش‌نویس'),
                        ),
                      ],
                      if (manager && row['state'] == 'posted')
                        OutlinedButton(
                          onPressed: busy ? null : () => decide(row, 'reverse'),
                          child: const Text('بررسی و برگشت سند'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
