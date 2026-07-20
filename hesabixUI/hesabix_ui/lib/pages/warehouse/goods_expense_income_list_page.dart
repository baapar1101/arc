import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart' show HesabixDateUtils;
import '../../services/goods_expense_income_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../utils/snackbar_helper.dart';
import '../../widgets/data_table/data_table.dart';
import 'goods_expense_income_form_dialog.dart';

const String _kSection = 'goods_expense_income';

String docKindLabel(String? kind) {
  switch (kind) {
    case 'goods_expense':
      return 'کالای هزینه‌شده';
    case 'goods_income':
      return 'کالای درآمدشده';
    default:
      return kind ?? '-';
  }
}

String geiStatusLabel(String? status) {
  switch (status) {
    case 'draft_ops':
      return 'پیش‌نویس عملیاتی';
    case 'pending_accounting':
      return 'در انتظار حسابداری';
    case 'draft_accounting':
      return 'پیش‌نویس حسابداری';
    case 'posted':
      return 'قطعی';
    case 'cancelled':
      return 'ابطال شده';
    default:
      return status ?? '-';
  }
}

Color? geiStatusColor(String? status) {
  switch (status) {
    case 'posted':
      return Colors.green;
    case 'cancelled':
      return Colors.red;
    case 'pending_accounting':
      return Colors.orange;
    case 'draft_accounting':
      return Colors.blueGrey;
    default:
      return null;
  }
}

class GoodsExpenseIncomeListPage extends StatefulWidget {
  final int businessId;
  const GoodsExpenseIncomeListPage({super.key, required this.businessId});

  @override
  State<GoodsExpenseIncomeListPage> createState() => _GoodsExpenseIncomeListPageState();
}

class _GoodsExpenseIncomeListPageState extends State<GoodsExpenseIncomeListPage> {
  final _svc = GoodsExpenseIncomeService();
  final _searchCtrl = TextEditingController();
  CalendarController? get _calendarController => ApiClient.getCalendarController();

  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  Map<String, dynamic> _settings = <String, dynamic>{};
  int _page = 1;
  int _pageSize = 20;
  int _total = 0;
  bool _loading = false;
  bool _settingsLoaded = false;
  String? _docKindFilter;
  String? _statusFilter;

  AuthStore? get _auth => ApiClient.getAuthStore();
  bool get _canView => _auth?.hasBusinessPermission(_kSection, 'view') ?? false;
  bool get _canAdd => _auth?.hasBusinessPermission(_kSection, 'add') ?? false;
  bool get _canEdit => _auth?.hasBusinessPermission(_kSection, 'edit') ?? false;
  bool get _canDelete => _auth?.hasBusinessPermission(_kSection, 'delete') ?? false;
  bool get _canSubmit => _auth?.hasBusinessPermission(_kSection, 'submit') ?? false;
  bool get _canAllocate => _auth?.hasBusinessPermission(_kSection, 'allocate') ?? false;
  bool get _canPost => _auth?.hasBusinessPermission(_kSection, 'post') ?? false;
  bool get _canCancel => _auth?.hasBusinessPermission(_kSection, 'cancel') ?? false;

  bool get _isTwoStep => (_settings['workflow_mode'] as String?) == 'two_step';

  static const List<String> _editableStatuses = [
    'draft_ops',
    'pending_accounting',
    'draft_accounting',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _refresh();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final s = await _svc.getSettings(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _settings = s;
        _settingsLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _settingsLoaded = true);
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final res = await _svc.list(
        businessId: widget.businessId,
        page: _page,
        pageSize: _pageSize,
        docKind: _docKindFilter,
        status: _statusFilter,
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      );
      final items = List<Map<String, dynamic>>.from(
        (res['items'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? const [],
      );
      if (!mounted) return;
      setState(() {
        _rows = items;
        _total = (res['total'] as num?)?.toInt() ?? items.length;
      });
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: 'خطا در بارگذاری لیست: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({Map<String, dynamic>? doc, String? initialDocKind}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GoodsExpenseIncomeFormDialog(
        businessId: widget.businessId,
        documentId: doc?['id'] as int?,
        initialDocKind: initialDocKind,
        calendarController: _calendarController,
        settings: _settings,
      ),
    );
    if (result == true) {
      _refresh();
    }
  }

  Future<void> _submitDoc(Map<String, dynamic> doc) async {
    try {
      await _svc.submit(businessId: widget.businessId, documentId: doc['id'] as int);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'سند به حسابداری ارسال شد');
      _refresh();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  Future<void> _allocateDoc(Map<String, dynamic> doc) async {
    try {
      await _svc.allocate(businessId: widget.businessId, documentId: doc['id'] as int);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'حساب اثر تخصیص یافت');
      _refresh();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  Future<void> _postDoc(Map<String, dynamic> doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('قطعی‌سازی سند'),
        content: Text('آیا از قطعی‌سازی سند ${doc['code']} مطمئن هستید؟ این عملیات حواله انبار و سند حسابداری ایجاد می‌کند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('قطعی‌سازی')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _svc.post(businessId: widget.businessId, documentId: doc['id'] as int);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'سند با موفقیت قطعی شد');
      _refresh();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  Future<void> _cancelDoc(Map<String, dynamic> doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ابطال سند'),
        content: Text('آیا از ابطال سند قطعی ${doc['code']} مطمئن هستید؟ حواله انبار و سند حسابداری مرتبط برگشت می‌خورد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ابطال'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _svc.cancel(businessId: widget.businessId, documentId: doc['id'] as int);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'سند ابطال شد');
      _refresh();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  Future<void> _deleteDoc(Map<String, dynamic> doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف سند'),
        content: Text('آیا از حذف سند ${doc['code']} مطمئن هستید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _svc.delete(businessId: widget.businessId, documentId: doc['id'] as int);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'سند حذف شد');
      _refresh();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  bool _isEditable(Map<String, dynamic> doc) => _editableStatuses.contains(doc['status']);

  DataTableConfig<Map<String, dynamic>> _buildTableConfig() {
    final actions = <DataTableAction>[
      DataTableAction(
        icon: Icons.edit,
        label: 'ویرایش / مشاهده',
        onTap: (item) => _openForm(doc: item as Map<String, dynamic>),
      ),
      if (_isTwoStep && _canSubmit)
        DataTableAction(
          icon: Icons.send,
          label: 'ارسال به حسابداری',
          onTap: (item) => _submitDoc(item as Map<String, dynamic>),
          enabled: (item) => (item as Map<String, dynamic>)['status'] == 'draft_ops',
        ),
      if (_canAllocate)
        DataTableAction(
          icon: Icons.account_tree,
          label: 'تخصیص حساب',
          onTap: (item) => _allocateDoc(item as Map<String, dynamic>),
          enabled: (item) => _editableStatuses.contains((item as Map<String, dynamic>)['status']),
        ),
      if (_canPost)
        DataTableAction(
          icon: Icons.check_circle_outline,
          label: 'قطعی‌سازی',
          onTap: (item) => _postDoc(item as Map<String, dynamic>),
          enabled: (item) => _editableStatuses.contains((item as Map<String, dynamic>)['status']),
        ),
      if (_canCancel)
        DataTableAction(
          icon: Icons.undo,
          label: 'ابطال',
          isDestructive: true,
          onTap: (item) => _cancelDoc(item as Map<String, dynamic>),
          enabled: (item) => (item as Map<String, dynamic>)['status'] == 'posted',
        ),
      if (_canDelete)
        DataTableAction(
          icon: Icons.delete,
          label: 'حذف',
          isDestructive: true,
          onTap: (item) => _deleteDoc(item as Map<String, dynamic>),
          enabled: (item) => _isEditable(item as Map<String, dynamic>),
        ),
    ];

    return DataTableConfig<Map<String, dynamic>>(
      endpoint: 'local_goods_expense_income',
      tableId: 'goods_expense_income_table',
      title: 'کالای هزینه‌شده / کالای درآمدشده',
      showSearch: false,
      showFilters: false,
      showColumnSearch: false,
      showExportButtons: false,
      showRowNumbers: true,
      enableSorting: false,
      enableGlobalSearch: false,
      enableHorizontalScroll: true,
      columns: [
        ActionColumn('actions', 'عملیات', actions: actions),
        TextColumn(
          'code',
          'شماره سند',
          formatter: (item) => (item as Map<String, dynamic>)['code']?.toString() ?? '-',
          width: ColumnWidth.medium,
        ),
        TextColumn(
          'doc_kind',
          'نوع سند',
          sortable: false,
          searchable: false,
          formatter: (item) => docKindLabel((item as Map<String, dynamic>)['doc_kind'] as String?),
          width: ColumnWidth.medium,
        ),
        CustomColumn(
          'status',
          'وضعیت',
          sortable: false,
          searchable: false,
          width: ColumnWidth.medium,
          builder: (item, index) {
            final m = item as Map<String, dynamic>;
            final status = m['status'] as String?;
            final color = geiStatusColor(status);
            return Chip(
              label: Text(geiStatusLabel(status)),
              backgroundColor: color?.withValues(alpha: 0.12),
              labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
              visualDensity: VisualDensity.compact,
            );
          },
        ),
        DateColumn(
          'document_date',
          'تاریخ سند',
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            final raw = m['document_date'] as String?;
            if (raw == null || raw.isEmpty) return '';
            final dt = DateTime.tryParse(raw);
            if (dt == null) return raw;
            return HesabixDateUtils.formatForDisplay(dt, _calendarController?.isJalali ?? true);
          },
          showTime: false,
          width: ColumnWidth.small,
        ),
        TextColumn(
          'person',
          'شخص',
          sortable: false,
          searchable: false,
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            final p = m['person'] as Map?;
            return p?['name']?.toString() ?? '-';
          },
          width: ColumnWidth.medium,
        ),
        TextColumn(
          'effect_account',
          'حساب اثر',
          sortable: false,
          searchable: false,
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            final a = m['effect_account'] as Map?;
            if (a == null) return '-';
            return '${a['code'] ?? ''} - ${a['name'] ?? ''}';
          },
          width: ColumnWidth.large,
        ),
        NumberColumn(
          'total_amount',
          'مبلغ کل',
          sortable: false,
          formatter: (item) => formatWithThousands((item as Map<String, dynamic>)['total_amount'] ?? 0),
          width: ColumnWidth.medium,
        ),
      ],
      onRowTap: (item) => _openForm(doc: item as Map<String, dynamic>),
      expandBodyHeightToFitRows: true,
    );
  }

  Widget _buildFiltersBar() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  labelText: 'جستجو (شماره سند / توضیحات)',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) {
                  _page = 1;
                  _refresh();
                },
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                initialValue: _docKindFilter,
                decoration: const InputDecoration(
                  labelText: 'نوع سند',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('همه')),
                  DropdownMenuItem(value: 'goods_expense', child: Text('کالای هزینه‌شده')),
                  DropdownMenuItem(value: 'goods_income', child: Text('کالای درآمدشده')),
                ],
                onChanged: (v) {
                  setState(() => _docKindFilter = v);
                  _page = 1;
                  _refresh();
                },
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                initialValue: _statusFilter,
                decoration: const InputDecoration(
                  labelText: 'وضعیت',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('همه')),
                  DropdownMenuItem(value: 'draft_ops', child: Text('پیش‌نویس عملیاتی')),
                  DropdownMenuItem(value: 'pending_accounting', child: Text('در انتظار حسابداری')),
                  DropdownMenuItem(value: 'draft_accounting', child: Text('پیش‌نویس حسابداری')),
                  DropdownMenuItem(value: 'posted', child: Text('قطعی')),
                  DropdownMenuItem(value: 'cancelled', child: Text('ابطال شده')),
                ],
                onChanged: (v) {
                  setState(() => _statusFilter = v);
                  _page = 1;
                  _refresh();
                },
              ),
            ),
            IconButton(
              tooltip: 'به‌روزرسانی',
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
            const Spacer(),
            if (_canAdd) ...[
              FilledButton.tonalIcon(
                onPressed: () => _openForm(initialDocKind: 'goods_expense'),
                icon: const Icon(Icons.remove_circle_outline),
                label: const Text('کالای هزینه‌شده'),
              ),
              FilledButton.icon(
                onPressed: () => _openForm(initialDocKind: 'goods_income'),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('کالای درآمدشده'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_canView) {
      return const Scaffold(
        body: Center(child: Text('دسترسی مشاهده این بخش را ندارید')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('کالای هزینه‌شده / کالای درآمدشده'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) context.pop();
          },
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverToBoxAdapter(child: _buildFiltersBar()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            sliver: SliverToBoxAdapter(
              child: _loading && _rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : DataTableWidget<Map<String, dynamic>>(
                      key: ValueKey('gei_table_$_page'),
                      calendarController: _calendarController,
                      config: _buildTableConfig(),
                      fromJson: (json) => json,
                      localRawItems: _rows,
                      localTotalCount: _total,
                      localCurrentPage: _page,
                      localPageSize: _pageSize,
                      onLocalPageChange: (p) {
                        setState(() => _page = p);
                        _refresh();
                      },
                      onLocalPageSizeChange: (s) {
                        setState(() {
                          _pageSize = s.clamp(1, 100);
                          _page = 1;
                        });
                        _refresh();
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
