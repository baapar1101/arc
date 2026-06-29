import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart';
import '../../../services/payroll_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/date_input_field.dart';
import 'payroll_calendar_utils.dart';
import 'payroll_department_form_dialog.dart';
import 'payroll_employee_form_dialog.dart';
import 'payroll_employee_import_dialog.dart';
import 'payroll_item_edit_dialog.dart';
import 'payroll_ui.dart';

/// داشبورد اصلی حقوق و دستمزد.
class PayrollMainPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const PayrollMainPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<PayrollMainPage> createState() => _PayrollMainPageState();
}

class _PayrollMainPageState extends State<PayrollMainPage> with SingleTickerProviderStateMixin {
  final PayrollService _svc = PayrollService();
  late TabController _tabController;

  bool _loading = true;
  Map<String, dynamic> _dashboard = const {};
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _runs = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _periods = [];
  List<Map<String, dynamic>> _departments = [];

  bool get _canManage =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('payroll', 'manage');

  bool get _canOperate =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('payroll', 'operate');

  bool get _isJalali => widget.calendarController.isJalali;

  @override
  void initState() {
    super.initState();
    widget.calendarController.addListener(_onCalendarChanged);
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadAll();
  }

  void _onCalendarChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.calendarController.removeListener(_onCalendarChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _svc.getDashboard(businessId: widget.businessId),
        _svc.listItems(businessId: widget.businessId),
        _svc.listEmployees(businessId: widget.businessId),
        _svc.listRuns(businessId: widget.businessId),
        _svc.listItemCategories(businessId: widget.businessId),
        _svc.listPeriods(businessId: widget.businessId),
        _svc.listDepartments(businessId: widget.businessId),
      ]);
      if (!mounted) return;
      setState(() {
        _dashboard = Map<String, dynamic>.from(results[0] as Map);
        _items = List<Map<String, dynamic>>.from(results[1] as List);
        _employees = List<Map<String, dynamic>>.from(results[2] as List);
        _runs = List<Map<String, dynamic>>.from(results[3] as List);
        _categories = List<Map<String, dynamic>>.from(results[4] as List);
        _periods = List<Map<String, dynamic>>.from(results[5] as List);
        _departments = List<Map<String, dynamic>>.from(results[6] as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.payrollMenu),
        actions: [
          IconButton(
            tooltip: t.payrollReportsTitle,
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () => context.go(
              context.businessPanelUrl(widget.businessId, 'payroll/reports'),
            ),
          ),
          if (_canManage)
            IconButton(
              tooltip: t.payrollSettingsTab,
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.go(
                context.businessPanelUrl(widget.businessId, 'settings/payroll'),
              ),
            ),
          IconButton(
            tooltip: t.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: t.payrollRunsTab, icon: const Icon(Icons.receipt_long_outlined)),
            Tab(text: t.payrollPeriodsTab, icon: const Icon(Icons.calendar_month_outlined)),
            Tab(text: t.payrollItemsTab, icon: const Icon(Icons.list_alt_outlined)),
            Tab(text: t.payrollEmployeesTab, icon: const Icon(Icons.people_outline)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: Column(
                children: [
                  _SummaryCards(dashboard: _dashboard, t: t),
                  Expanded(
                    child: TabBarView(
                    controller: _tabController,
                    children: [
                      _RunsTab(
                        runs: _runs,
                        t: t,
                        businessId: widget.businessId,
                        canOperate: _canOperate,
                        isJalali: _isJalali,
                        onChanged: _loadAll,
                      ),
                      _PeriodsTab(
                        periods: _periods,
                        t: t,
                        businessId: widget.businessId,
                        canOperate: _canOperate,
                        calendarController: widget.calendarController,
                        onChanged: _loadAll,
                      ),
                      _ItemsTab(
                        items: _items,
                        t: t,
                        canManage: _canManage,
                        businessId: widget.businessId,
                        categories: _categories,
                        onChanged: _loadAll,
                      ),
                      _EmployeesTab(
                        employees: _employees,
                        departments: _departments,
                        t: t,
                        canManage: _canManage,
                        businessId: widget.businessId,
                        calendarController: widget.calendarController,
                        onChanged: _loadAll,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      floatingActionButton: _canOperate && _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => context.go(
                context.businessPanelUrl(widget.businessId, 'payroll/new'),
              ),
              icon: const Icon(Icons.add),
              label: Text(t.payrollCreateRun),
            )
          : (_canOperate && _tabController.index == 1
              ? FloatingActionButton.extended(
                  onPressed: () => _PeriodsTab.showCreateDialog(
                    context,
                    widget.businessId,
                    widget.calendarController,
                    _loadAll,
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(t.payrollAddPeriod),
                )
              : null),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  final Map<String, dynamic> dashboard;
  final AppLocalizations t;

  const _SummaryCards({required this.dashboard, required this.t});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = (dashboard['pending_approvals'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 520;
              final cards = [
                PayrollUi.statCard(
                  context: context,
                  label: t.payrollDashboardActiveEmployees,
                  value: PayrollUi.formatCount(dashboard['active_employees'] ?? 0),
                  icon: Icons.people_outline,
                  color: theme.colorScheme.primary,
                ),
                PayrollUi.statCard(
                  context: context,
                  label: t.payrollItemsTab,
                  value: PayrollUi.formatCount(dashboard['active_items'] ?? 0),
                  icon: Icons.list_alt_outlined,
                  color: theme.colorScheme.tertiary,
                ),
                PayrollUi.statCard(
                  context: context,
                  label: t.payrollDashboardDraftRuns,
                  value: PayrollUi.formatCount(dashboard['draft_runs'] ?? 0),
                  icon: Icons.edit_note_outlined,
                  color: theme.colorScheme.secondary,
                ),
              ];
              if (isNarrow) {
                return Column(
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      cards[i],
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            },
          ),
          if (pending > 0) ...[
            const SizedBox(height: 12),
            PayrollUi.infoBanner(
              context: context,
              message: '${t.payrollDashboardPendingApprovals}: ${PayrollUi.formatCount(pending)}',
              icon: Icons.pending_actions,
              backgroundColor: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
          ],
        ],
      ),
    );
  }
}

class _RunsTab extends StatelessWidget {
  final List<Map<String, dynamic>> runs;
  final AppLocalizations t;
  final int businessId;
  final bool canOperate;
  final bool isJalali;
  final VoidCallback onChanged;

  const _RunsTab({
    required this.runs,
    required this.t,
    required this.businessId,
    required this.canOperate,
    required this.isJalali,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (runs.isEmpty) {
      return PayrollUi.emptyState(
        context: context,
        icon: Icons.receipt_long_outlined,
        title: t.payrollNoRunsYet,
        subtitle: canOperate ? t.payrollCreateRun : null,
      );
    }
    return ListView.separated(
      padding: PayrollUi.pagePadding,
      itemCount: runs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final run = runs[i];
        final id = (run['id'] as num).toInt();
        final status = run['status'] as String?;
        return PayrollUi.listTileCard(
          context: context,
          leading: Icon(Icons.receipt_long_outlined, color: PayrollUi.runStatusColor(context, status)),
          title: Text('${run['title'] ?? run['code'] ?? ''}'),
          subtitle: Text(
            PayrollCalendarUtils.formatRunDate(run['run_date'], isJalali),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              PayrollUi.statusChip(
                context,
                PayrollUi.runStatusLabel(t, status),
                color: PayrollUi.runStatusColor(context, status),
              ),
              const SizedBox(height: 6),
              Text(
                PayrollUi.formatMoney(run['net_total']),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          onTap: () => context.go(context.businessPanelUrl(businessId, 'payroll/$id')),
        );
      },
    );
  }
}

class _PeriodsTab extends StatelessWidget {
  final List<Map<String, dynamic>> periods;
  final AppLocalizations t;
  final int businessId;
  final bool canOperate;
  final CalendarController calendarController;
  final VoidCallback onChanged;

  const _PeriodsTab({
    required this.periods,
    required this.t,
    required this.businessId,
    required this.canOperate,
    required this.calendarController,
    required this.onChanged,
  });

  static Future<void> showCreateDialog(
    BuildContext context,
    int businessId,
    CalendarController calendarController,
    VoidCallback onChanged,
  ) async {
    final t = AppLocalizations.of(context);
    final isJalali = calendarController.isJalali;
    final defaults = PayrollCalendarUtils.defaultDisplayYearMonth(isJalali);
    final yearCtrl = TextEditingController(text: '${defaults.year}');
    final monthCtrl = TextEditingController(text: '${defaults.month}');
    final titleCtrl = TextEditingController();
    DateTime? startDate;
    DateTime? endDate;
    final result = await PayrollUi.showFormDialog<bool>(
      context: context,
      title: t.payrollAddPeriod,
      icon: Icons.calendar_month_outlined,
      maxWidth: 480,
      content: StatefulBuilder(
        builder: (ctx, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: yearCtrl,
                    keyboardType: TextInputType.number,
                    decoration: PayrollUi.fieldDecoration(ctx, t.payrollPeriodYear, prefixIcon: Icons.date_range),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: monthCtrl,
                    keyboardType: TextInputType.number,
                    decoration: PayrollUi.fieldDecoration(ctx, t.payrollPeriodMonth, prefixIcon: Icons.calendar_view_month),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleCtrl,
              decoration: PayrollUi.fieldDecoration(ctx, t.payrollRunTitle, prefixIcon: Icons.title),
            ),
            const SizedBox(height: 12),
            DateInputField(
              value: startDate,
              calendarController: calendarController,
              labelText: t.payrollPeriodStartDate,
              onChanged: (d) => setDialogState(() => startDate = d),
            ),
            const SizedBox(height: 12),
            DateInputField(
              value: endDate,
              calendarController: calendarController,
              labelText: t.payrollPeriodEndDate,
              onChanged: (d) => setDialogState(() => endDate = d),
            ),
          ],
        ),
      ),
      actionsBuilder: (dialogCtx) => [
        TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: Text(t.cancel)),
        FilledButton(onPressed: () => Navigator.pop(dialogCtx, true), child: Text(t.save)),
      ],
    );
    if (result != true) {
      yearCtrl.dispose();
      monthCtrl.dispose();
      titleCtrl.dispose();
      return;
    }
    try {
      final displayYear = int.tryParse(yearCtrl.text.trim()) ?? defaults.year;
      final displayMonth = int.tryParse(monthCtrl.text.trim()) ?? defaults.month;
      final apiYm = PayrollCalendarUtils.toApiYearMonth(displayYear, displayMonth, isJalali);
      await PayrollService().createPeriod(
        businessId: businessId,
        payload: {
          'year': apiYm.year,
          'month': apiYm.month,
          if (titleCtrl.text.trim().isNotEmpty) 'title': titleCtrl.text.trim(),
          if (startDate != null) 'start_date': HesabixDateUtils.formatForApiDate(startDate!),
          if (endDate != null) 'end_date': HesabixDateUtils.formatForApiDate(endDate!),
        },
      );
      onChanged();
    } catch (e) {
      if (context.mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      yearCtrl.dispose();
      monthCtrl.dispose();
      titleCtrl.dispose();
    }
  }

  Future<void> _closePeriod(BuildContext context, Map<String, dynamic> period) async {
    final id = (period['id'] as num).toInt();
    final confirm = await PayrollUi.showConfirmDialog(
      context: context,
      title: t.payrollClosePeriod,
      message: t.payrollClosePeriodConfirm,
      icon: Icons.lock_outline,
      destructive: true,
    );
    if (confirm != true) return;
    try {
      await PayrollService().closePeriod(businessId: businessId, periodId: id);
      if (context.mounted) {
        SnackBarHelper.showSuccess(context, message: t.payrollPeriodClosed);
      }
      onChanged();
    } catch (e) {
      if (context.mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  String _statusLabel(String? status) => PayrollUi.periodStatusLabel(t, status);

  @override
  Widget build(BuildContext context) {
    final isJalali = calendarController.isJalali;
    if (periods.isEmpty) {
      return PayrollUi.emptyState(
        context: context,
        icon: Icons.calendar_month_outlined,
        title: t.payrollNoPeriodsYet,
        subtitle: canOperate ? t.payrollAddPeriod : null,
      );
    }
    return ListView.separated(
      padding: PayrollUi.pagePadding,
      itemCount: periods.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final period = periods[i];
        final isOpen = period['status'] != 'closed';
        final status = period['status'] as String?;
        return PayrollUi.listTileCard(
          context: context,
          accentColor: isOpen ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
          leading: Icon(
            isOpen ? Icons.lock_open_outlined : Icons.lock_outline,
            color: isOpen ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
          ),
          title: Text(PayrollCalendarUtils.periodTitle(period, isJalali)),
          subtitle: Text(
            [
              PayrollCalendarUtils.formatPeriodYearMonth(
                (period['year'] as num).toInt(),
                (period['month'] as num).toInt(),
                isJalali,
              ),
              if (period['start_date'] != null)
                PayrollCalendarUtils.formatRunDate(period['start_date'], isJalali),
              if (period['end_date'] != null)
                PayrollCalendarUtils.formatRunDate(period['end_date'], isJalali),
            ].where((s) => s.isNotEmpty).join(' · '),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PayrollUi.statusChip(
                context,
                _statusLabel(status),
                color: isOpen ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
                icon: isOpen ? Icons.lock_open : Icons.lock,
              ),
              if (canOperate && isOpen) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: t.payrollClosePeriod,
                  onPressed: () => _closePeriod(context, period),
                  icon: const Icon(Icons.lock_outline),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ItemsTab extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> categories;
  final AppLocalizations t;
  final bool canManage;
  final int businessId;
  final VoidCallback onChanged;

  const _ItemsTab({
    required this.items,
    required this.categories,
    required this.t,
    required this.canManage,
    required this.businessId,
    required this.onChanged,
  });

  String _kindLabel(String? kind) => PayrollUi.itemKindLabel(t, kind);

  Future<void> _editItem(BuildContext context, Map<String, dynamic>? existing) async {
    final payload = await PayrollItemEditDialog.show(
      context,
      businessId: businessId,
      existing: existing,
      categories: categories,
    );
    if (payload == null) return;
    final svc = PayrollService();
    try {
      if (existing != null) {
        await svc.updateItem(
          businessId: businessId,
          itemId: (existing['id'] as num).toInt(),
          payload: payload,
        );
      } else {
        await svc.createItem(businessId: businessId, payload: payload);
      }
      onChanged();
    } catch (e) {
      if (context.mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (canManage)
          PayrollUi.toolbar(
            actions: [
              PayrollUi.actionButton(
                onPressed: () => _editItem(context, null),
                icon: Icons.add,
                label: t.payrollAddItem,
                filled: true,
              ),
            ],
          ),
        Expanded(
          child: items.isEmpty
              ? PayrollUi.emptyState(
                  context: context,
                  icon: Icons.list_alt_outlined,
                  title: t.payrollNoItemsYet,
                  subtitle: canManage ? t.payrollAddItem : null,
                )
              : ListView.separated(
                  padding: PayrollUi.pagePadding,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final kind = item['item_kind'] as String?;
                    final hasAccount = item['account_id'] != null;
                    return PayrollUi.listTileCard(
                      context: context,
                      leading: Icon(
                        hasAccount ? Icons.account_balance_outlined : Icons.link_off,
                        color: hasAccount
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                      ),
                      title: Text('${item['name'] ?? ''}'),
                      subtitle: Text('${item['code'] ?? ''}'),
                      trailing: PayrollUi.kindChip(context, _kindLabel(kind), kind),
                      onTap: canManage ? () => _editItem(context, item) : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EmployeesTab extends StatelessWidget {
  final List<Map<String, dynamic>> employees;
  final List<Map<String, dynamic>> departments;
  final AppLocalizations t;
  final bool canManage;
  final int businessId;
  final CalendarController calendarController;
  final VoidCallback onChanged;

  const _EmployeesTab({
    required this.employees,
    required this.departments,
    required this.t,
    required this.canManage,
    required this.businessId,
    required this.calendarController,
    required this.onChanged,
  });

  bool get _isJalali => calendarController.isJalali;

  Future<void> _addEmployee(BuildContext context) async {
    final payload = await PayrollEmployeeFormDialog.show(
      context,
      businessId: businessId,
      calendarController: calendarController,
      departments: departments,
    );
    if (payload == null) return;
    try {
      await PayrollService().createEmployee(businessId: businessId, payload: payload);
      onChanged();
    } catch (e) {
      if (context.mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  Future<void> _editEmployee(BuildContext context, Map<String, dynamic> emp) async {
    final payload = await PayrollEmployeeFormDialog.show(
      context,
      businessId: businessId,
      calendarController: calendarController,
      departments: departments,
      existing: emp,
    );
    if (payload == null) return;
    try {
      await PayrollService().updateEmployee(
        businessId: businessId,
        employeeId: (emp['id'] as num).toInt(),
        payload: payload,
      );
      onChanged();
    } catch (e) {
      if (context.mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  Future<void> _editDepartment(BuildContext context, Map<String, dynamic>? existing) async {
    final payload = await PayrollDepartmentFormDialog.show(context, existing: existing);
    if (payload == null) return;
    final svc = PayrollService();
    try {
      if (existing != null) {
        await svc.updateDepartment(
          businessId: businessId,
          departmentId: (existing['id'] as num).toInt(),
          payload: payload,
        );
      } else {
        await svc.createDepartment(businessId: businessId, payload: payload);
      }
      onChanged();
    } catch (e) {
      if (context.mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  Future<void> _importEmployees(BuildContext context) async {
    final ok = await PayrollEmployeeImportDialog.show(context, businessId: businessId);
    if (ok == true) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canManage)
          PayrollUi.sectionCard(
            context: context,
            title: t.payrollDepartmentsTab,
            icon: Icons.apartment_outlined,
            trailing: TextButton.icon(
              onPressed: () => _editDepartment(context, null),
              icon: const Icon(Icons.add_business_outlined, size: 18),
              label: Text(t.payrollAddDepartment),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: departments.isEmpty
                ? Text(
                    t.payrollAddDepartment,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  )
                : SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: departments.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final d = departments[i];
                        return FilterChip(
                          label: Text('${d['name'] ?? d['code']}'),
                          selected: d['is_active'] != false,
                          onSelected: canManage ? (_) => _editDepartment(context, d) : null,
                        );
                      },
                    ),
                  ),
          ),
        if (canManage)
          PayrollUi.toolbar(
            actions: [
              PayrollUi.actionButton(
                onPressed: () => _importEmployees(context),
                icon: Icons.upload_file_outlined,
                label: t.importFromExcel,
              ),
              PayrollUi.actionButton(
                onPressed: () => _addEmployee(context),
                icon: Icons.person_add_outlined,
                label: t.payrollAddEmployee,
                filled: true,
              ),
            ],
          ),
        Expanded(
          child: employees.isEmpty
              ? PayrollUi.emptyState(
                  context: context,
                  icon: Icons.people_outline,
                  title: t.payrollNoEmployeesYet,
                  subtitle: canManage ? t.payrollAddEmployee : null,
                )
              : ListView.separated(
                  padding: PayrollUi.pagePadding,
                  itemCount: employees.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final emp = employees[i];
                    final code = '${emp['employee_code'] ?? '?'}';
                    final hireLabel = emp['hire_date'] != null
                        ? PayrollCalendarUtils.formatRunDate(emp['hire_date'], _isJalali)
                        : null;
                    final deptId = (emp['department_id'] as num?)?.toInt();
                    String? deptName;
                    if (deptId != null) {
                      for (final d in departments) {
                        if ((d['id'] as num?)?.toInt() == deptId) {
                          deptName = '${d['name'] ?? d['code']}';
                          break;
                        }
                      }
                    }
                    return PayrollUi.listTileCard(
                      context: context,
                      leading: Text(
                        code.isNotEmpty ? code.substring(0, 1) : '?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: Text('${emp['person_name'] ?? emp['employee_code'] ?? ''}'),
                      subtitle: Text(
                        [
                          if ('${emp['job_title'] ?? ''}'.isNotEmpty) '${emp['job_title']}',
                          if (deptName != null) deptName,
                          code,
                          if (hireLabel != null) '${t.payrollHireDate}: $hireLabel',
                        ].join(' · '),
                      ),
                      trailing: emp['base_salary'] != null
                          ? Text(
                              PayrollUi.formatMoney(emp['base_salary']),
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                            )
                          : null,
                      onTap: canManage ? () => _editEmployee(context, emp) : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
