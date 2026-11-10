import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/crm/crm_next_action_banner.dart';
import 'package:hesabix_ui/widgets/crm/crm_section_card.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';
import 'package:hesabix_ui/services/telephony/telephony_session_controller.dart';
import 'package:intl/intl.dart';
import 'package:hesabix_ui/core/hesabix_back.dart';

/// نمای ۳۶۰ درجه مشتری: خلاصه، ارتباطات، معاملات، برچسب‌ها و تایم‌لاین
class CrmCustomer360Page extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final int? initialPersonId;

  const CrmCustomer360Page({
    super.key,
    required this.businessId,
    required this.authStore,
    this.initialPersonId,
  });

  @override
  State<CrmCustomer360Page> createState() => _CrmCustomer360PageState();
}

class _CrmCustomer360PageState extends State<CrmCustomer360Page> {
  final CrmService _crmService = CrmService(apiClient: ApiClient());
  Person? _selectedPerson;
  int? _personId;
  Map<String, dynamic>? _data;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _personId = widget.initialPersonId;
    if (_personId != null) {
      _selectedPerson = _minimalPerson(_personId!, null);
      _load();
    }
  }

  Person _minimalPerson(int id, String? name) {
    return Person(
      id: id,
      businessId: widget.businessId,
      aliasName: name?.trim().isNotEmpty == true ? name! : 'مشتری',
      personTypes: [PersonType.customer],
      createdAt: DateTime(2020, 1, 1),
      updatedAt: DateTime(2020, 1, 1),
    );
  }

  Future<void> _load() async {
    final pid = _personId;
    if (pid == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _crmService.getCustomer360(businessId: widget.businessId, personId: pid);
      if (!mounted) return;
      setState(() {
        _data = data;
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

  String _formatDate(dynamic iso, {bool withTime = false}) {
    final s = iso?.toString();
    if (s == null || s.isEmpty) return '';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    return DateFormat(withTime ? 'yyyy/MM/dd HH:mm' : 'yyyy/MM/dd').format(dt);
  }

  String _money(dynamic v) => NumberFormat('#,##0').format((v as num?) ?? 0);

  @override
  Widget build(BuildContext context) {
    if (!widget.authStore.canReadSection('crm')) {
      return AccessDeniedPage(message: 'شما دسترسی لازم برای مشاهده CRM را ندارید');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('نمای ۳۶۰ مشتری'),
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        actions: [
          if (_personId != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _load,
              tooltip: 'بروزرسانی',
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: PersonComboboxWidget(
              businessId: widget.businessId,
              label: 'مشتری',
              hintText: 'جست‌وجو و انتخاب مشتری',
              isRequired: false,
              personTypes: [PersonType.customer.persianName],
              selectedPerson: _selectedPerson,
              onChanged: (p) {
                setState(() {
                  _selectedPerson = p;
                  _personId = p?.id;
                  _data = null;
                });
                if (p?.id != null) _load();
              },
            ),
          ),
          if (_personId != null && widget.authStore.hasBusinessPermission('crm', 'write'))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => context.go('/business/${widget.businessId}/crm/deals?openAdd=1'),
                      icon: const Icon(Icons.trending_up, size: 18),
                      label: const Text('فرصت جدید'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/business/${widget.businessId}/crm/activities?openAdd=1'),
                      icon: const Icon(Icons.add_task, size: 18),
                      label: const Text('ثبت فعالیت'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/business/${widget.businessId}/crm/notes-calendar'),
                      icon: const Icon(Icons.calendar_month_outlined, size: 18),
                      label: const Text('یادداشت'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_personId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text('برای مشاهده نمای ۳۶۰، یک مشتری انتخاب کنید.'),
          ],
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
            TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('تلاش مجدد')),
          ],
        ),
      );
    }
    final data = _data;
    if (data == null) return const SizedBox.shrink();

    final person = data['person'] is Map ? Map<String, dynamic>.from(data['person'] as Map) : <String, dynamic>{};
    final summary = data['summary'] is Map ? Map<String, dynamic>.from(data['summary'] as Map) : <String, dynamic>{};
    final financial = data['financial'] is Map ? Map<String, dynamic>.from(data['financial'] as Map) : <String, dynamic>{};
    final socialContacts = _list(data['social_contacts']);
    final openDeals = _list(data['open_deals']);
    final closedDeals = _list(data['closed_deals']);
    final tags = _list(data['tags']);
    final timeline = _list(data['timeline']);
    final tasksOpen = _list(data['tasks_open']);
    final recentCalls = _list(data['recent_calls']);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPersonHeader(person, socialContacts),
          const SizedBox(height: 16),
          if (data['next_action'] is Map) ...[
            CrmNextActionBanner(
              action: Map<String, dynamic>.from(data['next_action'] as Map),
              businessId: widget.businessId,
            ),
            const SizedBox(height: 16),
          ],
          _buildFinancial(financial),
          const SizedBox(height: 16),
          _buildCommercial(financial),
          const SizedBox(height: 16),
          _buildSummary(summary),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            CrmSectionCard(
              title: 'برچسب‌ها',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: tags.map((t) {
                  final m = Map<String, dynamic>.from(t as Map);
                  return _tagChip(m['name']?.toString() ?? '', m['color']?.toString());
                }).toList(),
              ),
            ),
          ],
          if (openDeals.isNotEmpty) ...[
            const SizedBox(height: 16),
            CrmSectionCard(
              title: 'فرصت‌های باز',
              child: Column(children: openDeals.map((d) => _dealTile(d, closed: false)).toList()),
            ),
          ],
          if (closedDeals.isNotEmpty) ...[
            const SizedBox(height: 16),
            CrmSectionCard(
              title: 'فرصت‌های بسته‌شده',
              child: Column(children: closedDeals.map((d) => _dealTile(d, closed: true)).toList()),
            ),
          ],
          if (tasksOpen.isNotEmpty) ...[
            const SizedBox(height: 16),
            CrmSectionCard(
              title: 'وظایف باز',
              child: Column(
                children: tasksOpen.map((t) {
                  final m = Map<String, dynamic>.from(t as Map);
                  final taskId = (m['id'] as num?)?.toInt();
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_box_outlined, size: 20),
                    title: Text(m['subject']?.toString() ?? 'وظیفه', overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      if (m['assigned_to_name'] != null) m['assigned_to_name'].toString(),
                      if (m['due_at'] != null) 'سررسید: ${_formatDate(m['due_at'], withTime: true)}',
                    ].join(' · ')),
                    trailing: const Icon(Icons.chevron_left, size: 18),
                    onTap: taskId == null
                        ? null
                        : () => context.go('/business/${widget.businessId}/crm/activities?activityId=$taskId'),
                  );
                }).toList(),
              ),
            ),
          ],
          if (recentCalls.isNotEmpty) ...[
            const SizedBox(height: 16),
            CrmSectionCard(
              title: 'تماس‌ها',
              child: Column(
                children: recentCalls.map((raw) {
                  final m = Map<String, dynamic>.from(raw as Map);
                  final dir = m['direction']?.toString() ?? '';
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      dir == 'inbound' ? Icons.call_received_rounded : Icons.call_made_rounded,
                      size: 20,
                    ),
                    title: Text(m['peer_number']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      dir,
                      m['status']?.toString() ?? '',
                      if (m['duration_sec'] != null) '${m['duration_sec']} ثانیه',
                      _formatDate(m['started_at'], withTime: true),
                    ].where((e) => e.toString().trim().isNotEmpty).join(' · ')),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          CrmSectionCard(
            title: 'تایم‌لاین',
            child: timeline.isEmpty
                ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('رویدادی ثبت نشده است.'))
                : Column(children: timeline.take(40).map((e) => _timelineTile(Map<String, dynamic>.from(e as Map))).toList()),
          ),
        ],
      ),
    );
  }

  List<dynamic> _list(dynamic v) => v is List ? v : <dynamic>[];

  Widget _buildPersonHeader(Map<String, dynamic> person, List<dynamic> contacts) {
    final name = [person['first_name'], person['last_name']].where((e) => e != null && e.toString().isNotEmpty).join(' ');
    final displayName = (person['alias_name']?.toString().isNotEmpty == true)
        ? person['alias_name'].toString()
        : (name.isNotEmpty ? name : (person['company_name']?.toString() ?? 'مشتری'));
    final theme = Theme.of(context);
    final contactRows = <Widget>[];
    void addContact(IconData icon, String? value, {bool callEnabled = false}) {
      if (value != null && value.isNotEmpty) {
        contactRows.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
              if (callEnabled)
                IconButton(
                  tooltip: 'تماس',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.phone_forwarded_rounded, size: 18, color: theme.colorScheme.primary),
                  onPressed: () async {
                    final session = TelephonySessionStore.instance.controller;
                    session.bindBusiness(widget.businessId, pluginActive: true);
                    try {
                      await session.clickToCall(
                        destination: value,
                        personId: person['id'] is int ? person['id'] as int : int.tryParse('${person['id']}'),
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('در حال برقراری تماس…')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                ),
            ],
          ),
        ));
      }
    }

    addContact(Icons.phone, person['mobile']?.toString(), callEnabled: true);
    addContact(Icons.phone_outlined, person['phone']?.toString(), callEnabled: true);
    addContact(Icons.email_outlined, person['email']?.toString());
    addContact(Icons.location_on_outlined, [person['province'], person['city'], person['address']]
        .where((e) => e != null && e.toString().isNotEmpty)
        .join('، '));
    for (final c in contacts) {
      final m = Map<String, dynamic>.from(c as Map);
      addContact(Icons.link, '${m['custom_label'] ?? m['platform_key'] ?? ''}: ${m['value'] ?? ''}');
    }

    return CrmSectionCard(
      title: 'اطلاعات مشتری',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(Icons.person, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    if (person['company_name'] != null && person['company_name'].toString().isNotEmpty)
                      Text(person['company_name'].toString(), style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          ...contactRows,
        ],
      ),
    );
  }

  Widget _buildFinancial(Map<String, dynamic> financial) {
    final status = financial['status']?.toString() ?? 'بدون تراکنش';
    final exact = financial['open_invoices_exact'] != false;
    final openCount = financial['open_invoices_count'] ?? 0;
    final invoices = financial['open_invoices'] is List ? financial['open_invoices'] as List : const [];
    final cs = Theme.of(context).colorScheme;
    return CrmSectionCard(
      title: 'وضعیت مالی',
      subtitle: exact ? 'مانده از دفتر حسابداری' : 'مانده از دفتر؛ فاکتورهای باز از ۱۰۰ فاکتور فروش اخیر',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _moneyChip('مانده', '${_money(financial['balance'])} · $status', cs),
              _moneyChip('بدهکار', _money(financial['total_debit']), cs),
              _moneyChip('بستانکار', _money(financial['total_credit']), cs),
              _moneyChip('فاکتور باز', '$openCount', cs),
            ],
          ),
          if (invoices.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...invoices.map((raw) {
              final row = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(row['code']?.toString() ?? 'فاکتور'),
                subtitle: Text(row['document_date']?.toString() ?? ''),
                trailing: Text('${_money(row['remaining'])} مانده'),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _moneyChip(String label, String value, ColorScheme cs) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }

  Widget _buildCommercial(Map<String, dynamic> financial) {
    final raw = financial['commercial'];
    if (raw is! Map) return const SizedBox.shrink();
    final commercial = Map<String, dynamic>.from(raw);
    if (commercial['error'] != null) {
      return const CrmSectionCard(
        title: 'عمق فروش',
        child: Text('خلاصه فروش از فاکتورها خوانده نشد.'),
      );
    }
    final mixed = commercial['mixed_currency'] == true;
    final truncated = commercial['documents_truncated'] == true;
    final currencies = commercial['currencies'] is List ? commercial['currencies'] as List : const [];
    final repeats = commercial['repeat_products'] is List ? commercial['repeat_products'] as List : const [];
    final receipts = commercial['receipts'] is List ? commercial['receipts'] as List : const [];
    final openDocs = commercial['open_documents'] is List ? commercial['open_documents'] as List : const [];
    final margin = commercial['margin_amount'];
    final marginLabel = margin == null
        ? 'بهای ثبت‌شده‌ای نیست'
        : commercial['margin_complete'] == true
            ? _money(margin)
            : '${_money(margin)} · ناقص';
    return CrmSectionCard(
      title: 'عمق فروش',
      subtitle: truncated
          ? 'از ۳۰۰ فاکتور اخیر؛ ارزهای مختلف جمع نشده‌اند'
          : 'فروش و برگشت از فاکتور. مانده همان مانده دفتر است',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mixed)
            ...currencies.map((item) {
              final row = item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{};
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${row['currency_title'] ?? row['currency_code'] ?? 'ارز ${row['currency_id']}'} : فروش ${_money(row['sales_total'])}، برگشت ${_money(row['returns_total'])}، خالص ${_money(row['net_sales'])}، حاشیه ${row['margin_amount'] == null ? 'ندارد' : _money(row['margin_amount'])}'),
              );
            })
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _moneyChip('فروش قطعی', _money(commercial['sales_total']), Theme.of(context).colorScheme),
                _moneyChip('برگشت', _money(commercial['returns_total']), Theme.of(context).colorScheme),
                _moneyChip('خالص', _money(commercial['net_sales']), Theme.of(context).colorScheme),
                _moneyChip('حاشیه', marginLabel, Theme.of(context).colorScheme),
              ],
            ),
          if (openDocs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('اسناد باز', style: Theme.of(context).textTheme.titleSmall),
            ...openDocs.map((item) => _documentTile(item, openInvoice: true)),
          ],
          if (receipts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('دریافت‌های متصل', style: Theme.of(context).textTheme.titleSmall),
            ...receipts.map((item) => _documentTile(item, openInvoice: false)),
          ],
          if (repeats.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('خرید تکراری', style: Theme.of(context).textTheme.titleSmall),
            ...repeats.map((item) {
              final row = item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{};
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(row['product_name']?.toString() ?? 'کالا ${row['product_id']}'),
                subtitle: Text('${row['invoice_count']} فاکتور · آخرین ${row['last_document_date'] ?? ''}'),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _documentTile(Object? item, {required bool openInvoice}) {
    final row = item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{};
    final id = (row['id'] as num?)?.toInt();
    final amount = openInvoice ? row['remaining'] : row['amount'];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(row['code']?.toString() ?? (openInvoice ? 'فاکتور' : 'دریافت')),
      subtitle: Text(row['document_date']?.toString() ?? ''),
      trailing: Text(amount == null ? '' : _money(amount)),
      onTap: id == null
          ? null
          : () => context.push(
                openInvoice
                    ? '/business/${widget.businessId}/invoice/$id/edit'
                    : '/business/${widget.businessId}/receipts-payments?documentId=$id',
              ),
    );
  }

  Widget _buildSummary(Map<String, dynamic> summary) {
    final items = <(String, String, IconData)>[
      ('فرصت‌های باز', '${summary['open_deals_count'] ?? 0}', Icons.trending_up),
      ('فرصت‌های بسته', '${summary['closed_deals_count'] ?? 0}', Icons.check_circle),
      ('مبلغ باز', _money(summary['open_deals_amount']), Icons.account_balance_wallet_outlined),
      ('مبلغ بسته', _money(summary['closed_deals_amount']), Icons.account_balance_wallet),
      ('وظایف باز', '${summary['open_tasks_count'] ?? 0}', Icons.task_alt),
      ('فعالیت‌ها', '${summary['activities_count'] ?? 0}', Icons.history),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 12.0;
        final nCols = box.maxWidth < 420 ? 2 : (box.maxWidth < 760 ? 3 : 6);
        final cardW = (box.maxWidth - gap * (nCols - 1)) / nCols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: items
              .map((e) => SizedBox(
                    width: cardW,
                    child: Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surfaceContainerLowest,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(e.$3, size: 22, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(height: 8),
                            Text(e.$2, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                            Text(e.$1, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _dealTile(dynamic d, {required bool closed}) {
    final m = Map<String, dynamic>.from(d as Map);
    final id = (m['id'] as num?)?.toInt();
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(closed ? Icons.check_circle_outline : Icons.trending_up, size: 20),
      title: Text(m['title']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
      subtitle: Text([
        if (m['stage_name'] != null) m['stage_name'].toString(),
        '${_money(m['amount'])} ریال',
      ].join(' · ')),
      trailing: const Icon(Icons.chevron_left, size: 18),
      onTap: id == null ? null : () => context.go('/business/${widget.businessId}/crm/deals/$id'),
    );
  }

  void _openTimeline(Map<String, dynamic> e) {
    final id = (e['ref_id'] as num?)?.toInt();
    if (id == null) return;
    final type = e['type']?.toString() ?? '';
    final businessId = widget.businessId;
    switch (type) {
      case 'deal':
        context.go('/business/$businessId/crm/deals/$id');
      case 'lead':
        context.go('/business/$businessId/crm/leads/$id');
      case 'activity':
      case 'task':
        context.go('/business/$businessId/crm/activities?activityId=$id');
      case 'note':
        context.go('/business/$businessId/crm/notes-calendar?noteId=$id');
      case 'document':
        final docType = e['document_type']?.toString() ?? '';
        if (docType.startsWith('invoice')) {
          context.go('/business/$businessId/invoice/$id/edit');
        }
      default:
        return;
    }
  }

  Widget _timelineTile(Map<String, dynamic> e) {
    final type = e['type']?.toString() ?? '';
    IconData icon;
    switch (type) {
      case 'deal':
        icon = Icons.trending_up;
        break;
      case 'lead':
        icon = Icons.contact_phone_outlined;
        break;
      case 'task':
        icon = Icons.check_box_outlined;
        break;
      case 'note':
        icon = Icons.sticky_note_2_outlined;
        break;
      case 'document':
        icon = Icons.receipt_long_outlined;
        break;
      case 'call':
        icon = Icons.call_outlined;
        break;
      default:
        icon = Icons.history;
    }
    final docType = e['document_type']?.toString() ?? '';
    final opens = switch (type) {
      'deal' || 'lead' || 'activity' || 'task' || 'note' => (e['ref_id'] as num?) != null,
      'document' => docType.startsWith('invoice') && (e['ref_id'] as num?) != null,
      _ => false,
    };
    final contextLabel = e['context']?.toString() ?? '';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20),
      title: Text(e['title']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (contextLabel.isNotEmpty) contextLabel,
          _formatDate(e['date'], withTime: true),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: opens ? const Icon(Icons.chevron_left, size: 18) : null,
      onTap: opens ? () => _openTimeline(e) : null,
    );
  }

  Widget _tagChip(String name, String? colorHex) {
    Color? col;
    if (colorHex != null && colorHex.isNotEmpty) {
      try {
        col = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    return Chip(
      label: Text(name, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
      backgroundColor: (col ?? Theme.of(context).colorScheme.primary).withValues(alpha: 0.15),
      side: BorderSide(color: (col ?? Theme.of(context).colorScheme.primary).withValues(alpha: 0.4)),
    );
  }
}
