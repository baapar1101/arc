import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/business_nav.dart';
import '../../services/advanced_plugins_service.dart';

Map<String, dynamic> _map(dynamic x) =>
    Map<String, dynamic>.from(x as Map? ?? {});
String _error(Object e) => e.toString().replaceFirst('Exception: ', '');
const _choices = {
  'none': 'بدون روش',
  'straight_line': 'خط مستقیم',
  'declining': 'نزولی',
  'progressive': 'پلکانی',
  'fifo': 'اولین وارده، اولین صادره (FIFO)',
  'salary': 'حقوق',
  'bonus': 'عیدی',
  'require_review': 'تا بررسی مدیر، تعدیل مبدأ اعمال نشود',
  'discount_then_addition': 'ابتدا تخفیف، سپس افزوده',
  'parallel_on_base': 'تخفیف و افزوده هر دو روی قیمت پایه',
};

class AdvancedPluginsPage extends StatefulWidget {
  final int businessId;
  final String? initialCode;
  const AdvancedPluginsPage({
    super.key,
    required this.businessId,
    this.initialCode,
  });
  @override
  State<AdvancedPluginsPage> createState() => _AdvancedPluginsPageState();
}

class _AdvancedPluginsPageState extends State<AdvancedPluginsPage> {
  late final api = AdvancedPluginsService(widget.businessId);
  List<Map<String, dynamic>> modules = [];
  String? selected, error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    selected = widget.initialCode;
    load();
  }

  Future<void> load() async {
    try {
      final out = await api.overview();
      if (!mounted) return;
      setState(() {
        modules = (out['items'] as List? ?? []).map(_map).toList();
        selected ??= modules.firstOrNull?['code'] as String?;
        error = null;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = _error(e);
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!),
            TextButton(onPressed: load, child: const Text('تلاش دوباره')),
          ],
        ),
      );
    }
    final current = modules.where((m) => m['code'] == selected).firstOrNull;
    if (current == null) {
      return const Center(child: Text('افزونه‌ای پیدا نشد.'));
    }
    final allowed =
        current['licensed'] == true &&
        (current['can_view'] == true || current['can_settings'] == true);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'بازگشت به داشبورد',
                onPressed: () => context.go(
                  context.businessPanelUrl(widget.businessId, 'dashboard'),
                ),
                icon: const Icon(Icons.arrow_back),
              ),
              const Expanded(
                child: Text(
                  'افزونه‌های تخصصی',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'تازه‌سازی',
                onPressed: load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: modules
                .map(
                  (m) => ChoiceChip(
                    label: Text(
                      '${m['name']}${m['licensed'] == true ? '' : ' · نصب نشده'}',
                    ),
                    selected: selected == m['code'],
                    onSelected: (_) =>
                        setState(() => selected = m['code'] as String),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Text('${current['description']}'),
          const SizedBox(height: 8),
          if (!allowed)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 48),
                    const Text(
                      'مجوز فعال افزونه و دسترسی بخش برای ورود لازم است.',
                    ),
                    TextButton(
                      onPressed: () => context.go(
                        context.businessPanelUrl(
                          widget.businessId,
                          'plugin-marketplace',
                        ),
                      ),
                      child: const Text('بازار افزونه‌ها'),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: DefaultTabController(
                key: ValueKey(selected),
                length: 4,
                child: Column(
                  children: [
                    const TabBar(
                      isScrollable: true,
                      tabs: [
                        Tab(text: 'داده‌ها و سوابق'),
                        Tab(text: 'عملیات و محاسبات'),
                        Tab(text: 'تنظیمات و اتصال'),
                        Tab(text: 'ردپای تغییرات'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          if (current['can_view'] == true)
                            _Records(
                              key: ValueKey('records-$selected'),
                              api: api,
                              module: current,
                              onChanged: load,
                            )
                          else
                            const Center(
                              child: Text(
                                'مجوز مشاهده داده‌های این افزونه لازم است.',
                              ),
                            ),
                          if (current['can_view'] == true)
                            _Operations(
                              key: ValueKey('ops-$selected'),
                              api: api,
                              module: current,
                            )
                          else
                            const Center(
                              child: Text('مجوز مشاهده برای محاسبات لازم است.'),
                            ),
                          _Settings(
                            key: ValueKey(
                              'settings-$selected-${_map(current['settings'])['revision']}',
                            ),
                            api: api,
                            module: current,
                            onChanged: load,
                            businessId: widget.businessId,
                          ),
                          _Audit(
                            key: ValueKey('audit-$selected'),
                            api: api,
                            module: current,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Records extends StatefulWidget {
  final AdvancedPluginsService api;
  final Map<String, dynamic> module;
  final VoidCallback onChanged;
  const _Records({
    super.key,
    required this.api,
    required this.module,
    required this.onChanged,
  });
  @override
  State<_Records> createState() => _RecordsState();
}

class _RecordsState extends State<_Records> {
  late String kind;
  final search = TextEditingController();
  List<Map<String, dynamic>> rows = [];
  int total = 0, skip = 0;
  bool busy = true, archived = false;
  String? error;
  Map<String, dynamic> get kinds => _map(widget.module['kinds']);
  String get code => '${widget.module['code']}';
  @override
  void initState() {
    super.initState();
    final counts = _map(widget.module['counts']);
    kind =
        kinds.keys.where((k) => (counts[k] as num? ?? 0) > 0).firstOrNull ??
        kinds.keys.first;
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final out = await widget.api.records(
        code,
        kind: kind,
        q: search.text.trim(),
        skip: skip,
        archived: archived,
      );
      if (!mounted) return;
      setState(() {
        rows = (out['items'] as List? ?? []).map(_map).toList();
        total = (out['total'] as num? ?? 0).toInt();
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = _error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> form([Map<String, dynamic>? row]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _RecordForm(
        api: widget.api,
        module: widget.module,
        kind: kind,
        row: row,
      ),
    );
    if (changed == true && mounted) {
      await load();
      widget.onChanged();
    }
  }

  Future<void> detail(Map<String, dynamic> row) async {
    try {
      final full = await widget.api.detail(code, (row['id'] as num).toInt());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${full['title']}'),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'شناسه ${full['id']} · نسخه ${full['revision']} · ${full['managed'] == true ? 'تحت مدیریت سپیدار' : 'ثبت محلی'}',
                  ),
                  if (full['source_table'] != null)
                    Text(
                      '${full['source_database']} / ${full['source_table']} / ${full['source_key']}',
                      textDirection: TextDirection.ltr,
                    ),
                  const Divider(),
                  ...{...full, ..._map(full['data'])}.entries
                      .where(
                        (e) =>
                            _map(kinds[kind])['fields'] is Map &&
                            _map(
                              _map(kinds[kind])['fields'],
                            ).containsKey(e.key) &&
                            e.value != null,
                      )
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: SelectableText(
                            '${_map(_map(kinds[kind])['fields'])[e.key]['label']}: ${e.value}',
                          ),
                        ),
                      ),
                  if (full['source_payload'] != null)
                    ExpansionTile(
                      title: const Text('اصل داده و جزئیات مبدأ'),
                      children: [
                        SelectableText(
                          const JsonEncoder.withIndent(
                            '  ',
                          ).convert(full['source_payload']),
                          textDirection: TextDirection.ltr,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('بستن'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_error(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                initialValue: kind,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'نوع اطلاعات',
                  border: OutlineInputBorder(),
                ),
                items: kinds.entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(
                          '${_map(e.value)['label']} (${_map(widget.module['counts'])[e.key] ?? 0})',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      kind = v;
                      skip = 0;
                    });
                  }
                  load();
                },
              ),
            ),
            SizedBox(
              width: 230,
              child: TextField(
                controller: search,
                onSubmitted: (_) {
                  skip = 0;
                  load();
                },
                decoration: InputDecoration(
                  labelText: 'جستجو',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () {
                      skip = 0;
                      load();
                    },
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
            ),
            FilterChip(
              label: const Text('نمایش بایگانی'),
              selected: archived,
              onSelected: (v) {
                setState(() => archived = v);
                skip = 0;
                load();
              },
            ),
            if (widget.module['can_write'] == true &&
                _map(kinds[kind])['local'] == true)
              FilledButton.icon(
                onPressed: () => form(),
                icon: const Icon(Icons.add),
                label: const Text('ثبت جدید'),
              ),
          ],
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      Expanded(
        child: busy
            ? const Center(child: CircularProgressIndicator())
            : rows.isEmpty
            ? const Center(
                child: Text(
                  'رکوردی از این نوع وجود ندارد؛ دادهٔ فرضی ساخته نمی‌شود.',
                ),
              )
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return ListTile(
                    leading: Icon(
                      row['managed'] == true
                          ? Icons.sync_lock
                          : Icons.edit_note,
                    ),
                    title: Text('${row['title']}'),
                    subtitle: Text(
                      '${row['code'] ?? ''} · ${row['status']} ${row['amount'] != null ? ' · مبلغ ${row['amount']}' : ''}${row['quantity'] != null ? ' · مقدار ${row['quantity']}' : ''}\n${row['source_table'] ?? 'ثبت محلی'}',
                    ),
                    onTap: () => detail(row),
                    trailing:
                        widget.module['can_write'] == true &&
                            row['managed'] != true
                        ? IconButton(
                            tooltip: 'ویرایش / بایگانی',
                            onPressed: () => form(row),
                            icon: const Icon(Icons.edit_outlined),
                          )
                        : const Icon(Icons.chevron_left),
                  );
                },
              ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'صفحه قبل',
            onPressed: skip > 0
                ? () {
                    skip = (skip - 50).clamp(0, total);
                    load();
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
          Text(
            '${skip + 1 > total ? total : skip + 1}–${(skip + rows.length).clamp(0, total)} از $total',
          ),
          IconButton(
            tooltip: 'صفحه بعد',
            onPressed: skip + 50 < total
                ? () {
                    skip += 50;
                    load();
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
        ],
      ),
    ],
  );
}

class _Fields extends StatefulWidget {
  final AdvancedPluginsService api;
  final String code;
  final Map<String, dynamic> definitions, initial;
  final bool compact;
  const _Fields({
    super.key,
    required this.api,
    required this.code,
    required this.definitions,
    this.initial = const {},
    this.compact = false,
  });
  @override
  State<_Fields> createState() => _FieldsState();
}

class _FieldsState extends State<_Fields> {
  final controllers = <String, TextEditingController>{};
  final checks = <String, bool>{};
  @override
  void initState() {
    super.initState();
    for (final e in widget.definitions.entries) {
      final spec = _map(e.value),
          value = widget.initial[e.key] ?? spec['default'];
      controllers[e.key] = TextEditingController(text: value?.toString() ?? '');
      checks[e.key] = value == true;
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> values() => {
    for (final e in widget.definitions.entries)
      e.key: _map(e.value)['type'] == 'boolean'
          ? checks[e.key]
          : controllers[e.key]!.text.trim().isEmpty
          ? null
          : controllers[e.key]!.text.trim(),
  };
  Future<void> reference(String key, Map<String, dynamic> spec) async {
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ReferenceDialog(
        api: widget.api,
        code: widget.code,
        type: '${spec['type']}',
      ),
    );
    if (selected != null && mounted) {
      setState(() => controllers[key]!.text = '${selected['id']}');
    }
  }

  Widget input(String key, Map<String, dynamic> spec) {
    final c = controllers[key]!,
        type = spec['type'],
        label = '${spec['label']}${spec['required'] == true ? ' *' : ''}';
    if (type == 'boolean') {
      return CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: checks[key],
        onChanged: (v) => setState(() => checks[key] = v ?? false),
      );
    }
    if (type == 'choice') {
      final choices = (spec['choices'] as List? ?? [])
          .map((e) => '$e')
          .toList();
      return DropdownButtonFormField<String>(
        initialValue: choices.contains(c.text) ? c.text : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: choices
            .map(
              (v) => DropdownMenuItem(value: v, child: Text(_choices[v] ?? v)),
            )
            .toList(),
        onChanged: (v) => c.text = v ?? '',
      );
    }
    final ref = [
      'parent',
      'product',
      'person',
      'warehouse',
      'currency',
    ].contains(type);
    return TextFormField(
      controller: c,
      validator: (v) => spec['required'] == true && (v ?? '').trim().isEmpty
          ? 'این فیلد الزامی است'
          : null,
      keyboardType: type == 'decimal' || type == 'integer' || ref
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        helperText: type == 'date'
            ? 'تاریخ میلادی YYYY-MM-DD'
            : ref
            ? 'جستجو و انتخاب مرجع بومی'
            : null,
        suffixIcon: ref
            ? IconButton(
                tooltip: 'جستجوی مرجع',
                onPressed: () => reference(key, spec),
                icon: const Icon(Icons.search),
              )
            : type == 'date'
            ? IconButton(
                tooltip: 'انتخاب تاریخ',
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.tryParse(c.text) ?? DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    c.text = picked.toIso8601String().substring(0, 10);
                  }
                },
                icon: const Icon(Icons.calendar_today_outlined),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const advanced = {
      'code',
      'amount',
      'quantity',
      'start_date',
      'end_date',
      'currency_id',
      'product_id',
      'person_id',
      'parent_id',
    };
    Widget group(bool hidden) => LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 12,
        runSpacing: 16,
        children: widget.definitions.entries
            .where((e) => !widget.compact || advanced.contains(e.key) == hidden)
            .map(
              (e) => SizedBox(
                width: constraints.maxWidth > 600
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth,
                child: input(e.key, _map(e.value)),
              ),
            )
            .toList(),
      ),
    );
    if (!widget.compact) return group(false);
    return Column(
      children: [
        group(false),
        const SizedBox(height: 12),
        ExpansionTile(
          title: const Text('مبالغ، تاریخ‌ها و پیوندهای بومی'),
          initiallyExpanded: [
            'conditional_pricing',
            'inventory_trace_cost',
          ].contains(widget.code),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: group(true),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReferenceDialog extends StatefulWidget {
  final AdvancedPluginsService api;
  final String code, type;
  const _ReferenceDialog({
    required this.api,
    required this.code,
    required this.type,
  });
  @override
  State<_ReferenceDialog> createState() => _ReferenceDialogState();
}

class _ReferenceDialogState extends State<_ReferenceDialog> {
  final search = TextEditingController();
  List<Map<String, dynamic>> rows = [];
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final data = await widget.api.references(
        widget.code,
        widget.type,
        search.text.trim(),
      );
      if (mounted) {
        setState(() {
          rows = data;
          error = null;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = _error(e);
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('انتخاب مرجع'),
    content: SizedBox(
      width: 560,
      height: 420,
      child: Column(
        children: [
          TextField(
            controller: search,
            onSubmitted: (_) => load(),
            decoration: InputDecoration(
              labelText: 'نام یا بخشی از عنوان',
              suffixIcon: IconButton(
                onPressed: load,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (error != null) Text(error!),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, i) => ListTile(
                      title: Text('${rows[i]['label']}'),
                      subtitle: Text('شناسه ${rows[i]['id']}'),
                      onTap: () => Navigator.pop(context, rows[i]),
                    ),
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('انصراف'),
      ),
    ],
  );
}

class _RecordForm extends StatefulWidget {
  final AdvancedPluginsService api;
  final Map<String, dynamic> module;
  final String kind;
  final Map<String, dynamic>? row;
  const _RecordForm({
    required this.api,
    required this.module,
    required this.kind,
    this.row,
  });
  @override
  State<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<_RecordForm> {
  final fields = GlobalKey<_FieldsState>(), form = GlobalKey<FormState>();
  bool saving = false;
  String? error;
  String status = 'active';
  @override
  void initState() {
    super.initState();
    status = '${widget.row?['status'] ?? 'active'}';
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await widget.api.saveRecord(
        '${widget.module['code']}',
        widget.kind,
        {
          ...fields.currentState!.values(),
          'status': status,
          if (widget.row != null) 'revision': widget.row!['revision'],
        },
        id: (widget.row?['id'] as num?)?.toInt(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = _error(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      '${widget.row == null ? 'ثبت' : 'ویرایش'} ${_map(_map(widget.module['kinds'])[widget.kind])['label']}',
    ),
    content: SizedBox(
      width: 760,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            children: [
              _Fields(
                key: fields,
                api: widget.api,
                code: '${widget.module['code']}',
                definitions: _map(
                  _map(_map(widget.module['kinds'])[widget.kind])['fields'],
                ),
                initial: {...(widget.row ?? {}), ..._map(widget.row?['data'])},
                compact: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'وضعیت'),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('فعال')),
                  DropdownMenuItem(value: 'draft', child: Text('پیش‌نویس')),
                  DropdownMenuItem(
                    value: 'archived',
                    child: Text('بایگانی (قابل بازگشت)'),
                  ),
                ],
                onChanged: (v) => status = v ?? 'active',
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context, false),
        child: const Text('انصراف'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'در حال ذخیره…' : 'ذخیره'),
      ),
    ],
  );
}

class _Operations extends StatefulWidget {
  final AdvancedPluginsService api;
  final Map<String, dynamic> module;
  const _Operations({super.key, required this.api, required this.module});
  @override
  State<_Operations> createState() => _OperationsState();
}

class _OperationsState extends State<_Operations> {
  GlobalKey<_FieldsState> fields = GlobalKey<_FieldsState>();
  final form = GlobalKey<FormState>();
  late String action;
  Map<String, dynamic>? output;
  String? error;
  bool busy = false;
  Map<String, dynamic> get actions => _map(widget.module['operations']);
  @override
  void initState() {
    super.initState();
    action = actions.keys.first;
  }

  Future<void> run() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.api.operation(
        '${widget.module['code']}',
        action,
        fields.currentState!.values(),
      );
      if (mounted) setState(() => output = data);
    } catch (e) {
      if (mounted) setState(() => error = _error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 16),
    children: [
      const Text(
        'محاسبات قابل توضیح؛ هیچ سند مالی، موجودی یا تراکنش کیف‌پول خودکار ایجاد نمی‌شود.',
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        initialValue: action,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'عملیات',
          border: OutlineInputBorder(),
        ),
        items: actions.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text('${_map(e.value)['label']}'),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v != null) {
            setState(() {
              action = v;
              fields = GlobalKey<_FieldsState>();
              output = null;
              error = null;
            });
          }
        },
      ),
      const SizedBox(height: 16),
      Form(
        key: form,
        child: _Fields(
          key: fields,
          api: widget.api,
          code: '${widget.module['code']}',
          definitions: _map(_map(actions[action])['fields']),
        ),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(
          onPressed:
              busy ||
                  (action.endsWith('_save') &&
                      widget.module['can_write'] != true) ||
                  (action == 'approve_tax_table' &&
                      widget.module['can_settings'] != true)
              ? null
              : run,
          icon: const Icon(Icons.calculate_outlined),
          label: Text(busy ? 'در حال محاسبه…' : 'اجرا'),
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (output != null) ...[
        const Divider(height: 30),
        Text(
          '${output!['title']}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: (output!['metrics'] as List? ?? [])
              .map(
                (m) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m['label']}'),
                        SelectableText(
                          '${m['value']}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        for (final warning in output!['warnings'] as List? ?? [])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('• $warning'),
          ),
        if (output!['saved_record_id'] != null)
          Text(
            'شناسه ذخیره‌شده: ${output!['saved_record_id']} ${output!['unchanged'] == true ? '(بدون تغییر تکراری)' : ''}',
          ),
        for (final row in output!['rows'] as List? ?? [])
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: SelectableText(
                _map(
                  row,
                ).entries.map((e) => '${e.key}: ${e.value}').join('  |  '),
              ),
            ),
          ),
      ],
    ],
  );
}

class _Settings extends StatefulWidget {
  final AdvancedPluginsService api;
  final Map<String, dynamic> module;
  final VoidCallback onChanged;
  final int businessId;
  const _Settings({
    super.key,
    required this.api,
    required this.module,
    required this.onChanged,
    required this.businessId,
  });
  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  final fields = GlobalKey<_FieldsState>();
  late bool enabled, sync;
  bool saving = false;
  String? message;
  Map<String, dynamic> get config => _map(widget.module['settings']);
  @override
  void initState() {
    super.initState();
    enabled = config['enabled'] == true;
    sync = config['sync_enabled'] == true;
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      await widget.api.saveSettings('${widget.module['code']}', {
        'revision': config['revision'] ?? 0,
        'enabled': enabled,
        'sync_enabled': sync,
        'options': fields.currentState!.values(),
      });
      if (mounted) {
        setState(() => message = 'تنظیمات ذخیره شد.');
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) setState(() => message = _error(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.module['can_settings'] != true) {
      return const Center(child: Text('مجوز تنظیمات این افزونه لازم است.'));
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        SwitchListTile(
          title: const Text('افزونه فعال باشد'),
          value: enabled,
          onChanged: (v) => setState(() => enabled = v),
        ),
        SwitchListTile(
          title: const Text('همگام‌سازی لایو از سپیدار'),
          subtitle: const Text(
            'از اتصال امن موجود و Snapshot کامل استفاده می‌کند؛ تغییر رکورد واردشده باید در سپیدار انجام شود.',
          ),
          value: sync,
          onChanged: (v) => setState(() => sync = v),
        ),
        Text(
          'آخرین همگام‌سازی: ${config['last_synced_at'] ?? 'هنوز اجرا نشده'}',
        ),
        if (config['sync_summary'] != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('نتیجه آخر: ${config['sync_summary']}'),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => context.go(
              context.businessPanelUrl(widget.businessId, 'settings/sepidar'),
            ),
            icon: const Icon(Icons.sync),
            label: const Text('مدیریت اتصال و اجرای سپیدار'),
          ),
        ),
        const Divider(height: 24),
        _Fields(
          key: fields,
          api: widget.api,
          code: '${widget.module['code']}',
          definitions: _map(widget.module['options']),
          initial: _map(config['options']),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? 'در حال ذخیره…' : 'ذخیره تنظیمات'),
          ),
        ),
        if (message != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(message!)),
      ],
    );
  }
}

class _Audit extends StatelessWidget {
  final AdvancedPluginsService api;
  final Map<String, dynamic> module;
  const _Audit({super.key, required this.api, required this.module});
  @override
  Widget build(BuildContext context) {
    if (module['can_settings'] != true) {
      return const Center(
        child: Text('مجوز تنظیمات برای مشاهده ردپای تغییرات لازم است.'),
      );
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: api.audit('${module['code']}'),
      builder: (context, s) {
        if (s.hasError) return Center(child: Text(_error(s.error!)));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          children: s.data!
              .map(
                (r) => ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(
                    '${r['action']} — رکورد ${r['record_id'] ?? 'تنظیمات'}',
                  ),
                  subtitle: Text(
                    '${r['created_at']} · کاربر ${r['actor_user_id'] ?? 'سیستم'}\n${r['details']}',
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}
