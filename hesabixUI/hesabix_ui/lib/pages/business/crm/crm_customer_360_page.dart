import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
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
    final socialContacts = _list(data['social_contacts']);
    final openDeals = _list(data['open_deals']);
    final closedDeals = _list(data['closed_deals']);
    final tags = _list(data['tags']);
    final timeline = _list(data['timeline']);
    final tasksOpen = _list(data['tasks_open']);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPersonHeader(person, socialContacts),
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
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_box_outlined, size: 20),
                    title: Text(m['subject']?.toString() ?? 'وظیفه', overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      if (m['assigned_to_name'] != null) m['assigned_to_name'].toString(),
                      if (m['due_at'] != null) 'سررسید: ${_formatDate(m['due_at'], withTime: true)}',
                    ].join(' · ')),
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
      default:
        icon = Icons.history;
    }
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20),
      title: Text(e['title']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
      subtitle: Text(_formatDate(e['date'], withTime: true)),
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
