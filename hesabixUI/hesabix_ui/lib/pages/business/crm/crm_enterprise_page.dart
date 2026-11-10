import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/core/hesabix_back.dart';
import 'package:hesabix_ui/models/business_user_model.dart';
import 'package:hesabix_ui/services/business_user_service.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/services/person_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_section_card.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';

/// سازمان فروش: سهمیه، مدیر، صف سرنخ و مجوز رکورد.
class CrmEnterprisePage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const CrmEnterprisePage({super.key, required this.businessId, required this.authStore});

  @override
  State<CrmEnterprisePage> createState() => _CrmEnterprisePageState();
}

class _CrmEnterprisePageState extends State<CrmEnterprisePage> {
  final CrmService _crm = CrmService(apiClient: ApiClient());
  final PersonService _persons = PersonService(apiClient: ApiClient());
  late final BusinessUserService _users = BusinessUserService(ApiClient());

  bool _loading = true;
  String? _error;
  bool _aclEnabled = false;
  List<BusinessUser> _members = [];
  List<Map<String, dynamic>> _organizations = [];
  List<Map<String, dynamic>> _quotas = [];
  List<Map<String, dynamic>> _managerLinks = [];
  List<Map<String, dynamic>> _queues = [];
  List<Map<String, dynamic>> _recordGrants = [];
  List<Map<String, dynamic>> _currencies = [];
  Map<String, dynamic> _rollup = {};

  final _orgName = TextEditingController();
  final _personSearch = TextEditingController();
  final _quotaAmount = TextEditingController();
  final _periodStart = TextEditingController();
  final _periodEnd = TextEditingController();
  final _queueName = TextEditingController();
  final _leadSearch = TextEditingController();
  final _recordSearch = TextEditingController();

  int? _billingPersonId;
  String? _billingPersonName;
  final List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _personHits = [];
  List<Map<String, dynamic>> _leadHits = [];
  List<Map<String, dynamic>> _recordHits = [];
  int? _selectedLeadId;
  String? _selectedLeadName;
  int? _selectedRecordId;
  String? _selectedRecordName;
  int? _selectedCurrencyId;
  String _aclEntityType = 'lead';
  String _aclAccess = 'view';
  int? _aclUserId;
  int? _assignQueueId;
  int? _quotaUserId;
  int? _managerId;
  int? _memberId;
  final Set<int> _queueMembers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _orgName.dispose();
    _personSearch.dispose();
    _quotaAmount.dispose();
    _periodStart.dispose();
    _periodEnd.dispose();
    _queueName.dispose();
    _leadSearch.dispose();
    _recordSearch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = widget.authStore.currentUserId;
      List<BusinessUser> members = [];
      List<Map<String, dynamic>> currencies = [];
      try {
        members = (await _users.getBusinessUsers(widget.businessId)).users;
      } catch (_) {
        members = [];
      }
      try {
        currencies = await CurrencyService(ApiClient()).listBusinessCurrencies(businessId: widget.businessId);
      } catch (_) {
        currencies = [];
      }
      final results = await Future.wait([
        _crm.listOrganizations(businessId: widget.businessId),
        _crm.listQuotas(businessId: widget.businessId),
        _crm.listLeadQueues(businessId: widget.businessId),
        _crm.getAutomationSettings(businessId: widget.businessId),
        if (userId != null) _crm.managerRollup(businessId: widget.businessId, managerUserId: userId),
      ]);
      final grants = await _crm.listRecordAccess(businessId: widget.businessId);
      final managerLinks = await _crm.listManagerLinks(businessId: widget.businessId);
      if (!mounted) return;
      final settings = results[3] as Map<String, dynamic>;
      setState(() {
        _members = members;
        _organizations = results[0] as List<Map<String, dynamic>>;
        _quotas = results[1] as List<Map<String, dynamic>>;
        _managerLinks = managerLinks;
        _queues = results[2] as List<Map<String, dynamic>>;
        _currencies = currencies;
        _selectedCurrencyId ??= _defaultCurrencyId(currencies);
        _aclEnabled = settings['record_acl_enabled'] == true;
        _recordGrants = grants;
        _rollup = userId == null ? {} : results[4] as Map<String, dynamic>;
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

  Future<void> _searchPersons(String value) async {
    final term = value.trim();
    if (term.length < 2) {
      setState(() => _personHits = []);
      return;
    }
    try {
      final data = await _persons.getPersons(businessId: widget.businessId, search: term, limit: 8);
      final items = data['items'];
      if (!mounted) return;
      setState(() {
        _personHits = items is List ? items.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : [];
      });
    } catch (_) {
      if (mounted) setState(() => _personHits = []);
    }
  }

  Future<void> _saveOrganizationContacts(
    Map<String, dynamic> org,
    List<int> contactIds,
    String success, {
    bool clearPending = false,
  }) async {
    final orgId = (org['id'] as num?)?.toInt();
    if (orgId == null) return;
    try {
      await _crm.updateOrganizationContacts(businessId: widget.businessId, organizationId: orgId, contactIds: contactIds);
      if (clearPending) _contacts.clear();
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: success);
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  List<int> _extraContactIds(Map<String, dynamic> org) {
    final ids = <int>[];
    final raw = org['contacts'];
    if (raw is! List) return ids;
    for (final item in raw.whereType<Map>()) {
      final id = (item['id'] as num?)?.toInt();
      if (id != null) ids.add(id);
    }
    return ids;
  }

  Future<void> _addContactsToOrganization(Map<String, dynamic> org) async {
    if (_contacts.isEmpty) return;
    final ids = _extraContactIds(org).toSet();
    for (final contact in _contacts) {
      final id = contact['id'];
      if (id is int) ids.add(id);
    }
    await _saveOrganizationContacts(org, ids.toList(), 'مخاطبان سازمان به‌روز شد', clearPending: true);
  }

  Future<void> _removeOrganizationContact(Map<String, dynamic> org, int personId) async {
    final ids = _extraContactIds(org).where((id) => id != personId).toList();
    await _saveOrganizationContacts(org, ids, 'مخاطب از سازمان برداشته شد');
  }

  Future<void> _createOrganization() async {
    if (_orgName.text.trim().isEmpty || _billingPersonId == null) {
      SnackBarHelper.showWarning(context, message: 'نام سازمان و شخص صورتحساب لازم است');
      return;
    }
    try {
      await _crm.createOrganization(
        businessId: widget.businessId,
        name: _orgName.text.trim(),
        billingPersonId: _billingPersonId!,
        contactIds: _contacts.map((item) => item['id'] as int).toList(),
      );
      _orgName.clear();
      _contacts.clear();
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'سازمان ثبت شد');
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _createQuota() async {
    final amount = double.tryParse(_quotaAmount.text.replaceAll(',', ''));
    final currencyId = _selectedCurrencyId;
    if (_quotaUserId == null || amount == null || currencyId == null || _periodStart.text.trim().isEmpty || _periodEnd.text.trim().isEmpty) {
      SnackBarHelper.showWarning(context, message: 'کاربر، دوره، مبلغ و ارز سهمیه را کامل کنید');
      return;
    }
    try {
      await _crm.createQuota(
        businessId: widget.businessId,
        userId: _quotaUserId!,
        periodStart: _periodStart.text.trim(),
        periodEnd: _periodEnd.text.trim(),
        amount: amount,
        currencyId: currencyId,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'سهمیه ثبت شد');
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _setManager() async {
    if (_managerId == null || _memberId == null) {
      SnackBarHelper.showWarning(context, message: 'مدیر و عضو را انتخاب کنید');
      return;
    }
    try {
      await _crm.setManager(businessId: widget.businessId, managerUserId: _managerId!, memberUserId: _memberId!);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'ارتباط مدیر ذخیره شد');
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _createQueue() async {
    if (_queueName.text.trim().isEmpty || _queueMembers.isEmpty) {
      SnackBarHelper.showWarning(context, message: 'نام صف و حداقل یک عضو لازم است');
      return;
    }
    try {
      await _crm.createLeadQueue(businessId: widget.businessId, name: _queueName.text.trim(), memberIds: _queueMembers.toList());
      _queueName.clear();
      _queueMembers.clear();
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'صف سرنخ ساخته شد');
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _toggleAcl(bool value) async {
    try {
      await _crm.setRecordAclEnabled(businessId: widget.businessId, enabled: value);
      if (!mounted) return;
      setState(() => _aclEnabled = value);
      SnackBarHelper.showSuccess(context, value ? 'مجوز سطح رکورد فعال شد' : 'مجوز سطح رکورد خاموش شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authStore.canReadSection('crm')) {
      return AccessDeniedPage(message: 'شما دسترسی لازم برای مشاهده CRM را ندارید');
    }
    final canWrite = widget.authStore.hasBusinessPermission('crm', 'write');
    return Scaffold(
      appBar: AppBar(
        title: const Text('سازمان فروش'),
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'بروزرسانی')],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      CrmSectionCard(
                        title: 'مجوز سطح رکورد',
                        subtitle: 'تا وقتی خاموش است، فهرست‌های فعلی مثل قبل دیده می‌شوند. با روشن شدن، هر کاربر فقط رکورد خودش، ساخته‌شده توسط خودش، زیرمجموعه و صف بدون مسئول را می‌بیند.',
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('اعمال مجوز روی سرنخ و فرصت'),
                          value: _aclEnabled,
                          onChanged: canWrite ? _toggleAcl : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _rollupCard(),
                      const SizedBox(height: 12),
                      _organizationCard(canWrite),
                      const SizedBox(height: 12),
                      _quotaCard(canWrite),
                      const SizedBox(height: 12),
                      _managerCard(canWrite),
                      const SizedBox(height: 12),
                      _queueCard(canWrite),
                      const SizedBox(height: 12),
                      _assignmentCard(canWrite),
                      const SizedBox(height: 12),
                      _aclCard(canWrite),
                    ],
                  ),
                ),
    );
  }

  Widget _rollupCard() {
    final rows = _rollup['open_by_currency'];
    final items = rows is List ? rows : const [];
    return CrmSectionCard(
      title: 'جمع تیم شما',
      subtitle: 'فرصت‌های باز شما و زیرمجموعه‌ها، جدا برای هر ارز',
      child: items.isEmpty
          ? const Text('فرصت بازی برای این تیم ثبت نشده است.')
          : Column(
              children: [
                for (final row in items.whereType<Map>())
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_currencyLabel(row['currency_id'])),
                    subtitle: Text('${row['deal_count']} فرصت'),
                    trailing: Text('${row['amount']}'),
                  ),
              ],
            ),
    );
  }

  Widget _organizationCard(bool canWrite) {
    return CrmSectionCard(
      title: 'سازمان‌ها',
      subtitle: 'شخص صورتحساب طرف‌حساب حسابداری است. فرصت فقط به همان شخص یا مخاطبان سازمان وصل می‌شود.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_organizations.isEmpty) const Text('هنوز سازمانی ثبت نشده است.'),
          for (final org in _organizations) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(org['name']?.toString() ?? '', style: Theme.of(context).textTheme.titleSmall),
                      ),
                      if (canWrite && _contacts.isNotEmpty)
                        TextButton(onPressed: () => _addContactsToOrganization(org), child: const Text('افزودن مخاطب')),
                      if (canWrite)
                        IconButton(
                          tooltip: 'حذف سازمان',
                          icon: const Icon(Icons.close),
                          onPressed: () => _deleteOrganization(org),
                        ),
                    ],
                  ),
                  Text('شخص صورتحساب: ${org['billing_person_name'] ?? org['billing_person_id'] ?? ''}'),
                  if (org['contacts'] is List && (org['contacts'] as List).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final contact in (org['contacts'] as List).whereType<Map>())
                          Chip(
                            label: Text(contact['name']?.toString() ?? ''),
                            onDeleted: canWrite && contact['id'] is num
                                ? () => _removeOrganizationContact(org, (contact['id'] as num).toInt())
                                : null,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (canWrite) ...[
            TextField(controller: _orgName, decoration: const InputDecoration(labelText: 'نام سازمان')),
            TextField(
              controller: _personSearch,
              decoration: const InputDecoration(labelText: 'جست‌وجوی شخص'),
              onChanged: _searchPersons,
            ),
            if (_billingPersonName != null) Text('شخص صورتحساب: $_billingPersonName'),
            if (_contacts.isNotEmpty)
              Wrap(
                spacing: 8,
                children: [
                  for (final contact in _contacts)
                    Chip(
                      label: Text(_personLabel(contact)),
                      onDeleted: () => setState(() => _contacts.remove(contact)),
                    ),
                ],
              ),
            for (final person in _personHits)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(_personLabel(person)),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _billingPersonId = person['id'] as int?;
                        _billingPersonName = _personLabel(person);
                        _personHits = [];
                      }),
                      child: const Text('صورتحساب'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        final id = person['id'];
                        if (id is int && _contacts.every((item) => item['id'] != id)) {
                          _contacts.add(person);
                        }
                        _personHits = [];
                      }),
                      child: const Text('مخاطب'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _createOrganization, child: const Text('ثبت سازمان')),
          ],
        ],
      ),
    );
  }

  Widget _quotaCard(bool canWrite) {
    return CrmSectionCard(
      title: 'سهمیه',
      subtitle: 'تحقق فقط از فرصت‌های برده‌شده همان کاربر و همان ارز در دوره حساب می‌شود.',
      child: Column(
        children: [
          if (_quotas.isEmpty) const Align(alignment: AlignmentDirectional.centerStart, child: Text('سهمیه‌ای ثبت نشده است.')),
          for (final quota in _quotas)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${_memberName(quota['user_id'])} · ${_currencyLabel(quota['currency_id'])}'),
              subtitle: Text('${_displayDate(quota['period_start']?.toString() ?? '')} تا ${_displayDate(quota['period_end']?.toString() ?? '')}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(quota['percent'] == null ? 'بدون هدف' : '${quota['percent']}٪'),
                  if (canWrite)
                    IconButton(
                      tooltip: 'حذف سهمیه',
                      icon: const Icon(Icons.close),
                      onPressed: () => _deleteQuota(quota),
                    ),
                ],
              ),
            ),
          if (canWrite) ...[
            _userDropdown('کاربر سهمیه', _quotaUserId, (value) => setState(() => _quotaUserId = value)),
            _periodButton('شروع دوره', _periodStart),
            _periodButton('پایان دوره', _periodEnd),
            TextField(controller: _quotaAmount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ هدف')),
            if (_currencies.isEmpty)
              const Align(alignment: AlignmentDirectional.centerStart, child: Text('ارز فعالی برای این کسب‌وکار پیدا نشد.'))
            else
              DropdownButtonFormField<int>(
                value: _selectedCurrencyId,
                decoration: const InputDecoration(labelText: 'ارز'),
                items: [
                  for (final currency in _currencies)
                    if ((currency['id'] as num?) != null)
                      DropdownMenuItem(
                        value: (currency['id'] as num).toInt(),
                        child: Text(currency['code']?.toString() ?? currency['title']?.toString() ?? ''),
                      ),
                ],
                onChanged: (value) => setState(() => _selectedCurrencyId = value),
              ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _createQuota, child: const Text('ثبت سهمیه')),
          ],
        ],
      ),
    );
  }

  Widget _managerCard(bool canWrite) {
    return CrmSectionCard(
      title: 'ساختار مدیر',
      subtitle: 'هر عضو یک مدیر دارد. چرخه پذیرفته نمی‌شود.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_managerLinks.isEmpty) const Text('ارتباط مدیری ثبت نشده است.'),
          for (final link in _managerLinks)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${_memberName(link['member_user_id'])}'),
              subtitle: Text('مدیر: ${_memberName(link['manager_user_id'])}'),
              trailing: canWrite
                  ? IconButton(
                      tooltip: 'حذف ارتباط',
                      icon: const Icon(Icons.close),
                      onPressed: () => _deleteManagerLink(link),
                    )
                  : null,
            ),
          if (canWrite) ...[
            _userDropdown('مدیر', _managerId, (value) => setState(() => _managerId = value)),
            _userDropdown('عضو', _memberId, (value) => setState(() => _memberId = value)),
            const SizedBox(height: 8),
            FilledButton(onPressed: _setManager, child: const Text('ذخیره ارتباط')),
          ],
        ],
      ),
    );
  }

  Widget _queueCard(bool canWrite) {
    return CrmSectionCard(
      title: 'صف‌های سرنخ',
      subtitle: 'عضو صف می‌تواند سرنخ بدون مسئول را بردارد. اگر دیگری زودتر برداشته باشد، درخواست رد می‌شود.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_queues.isEmpty) const Text('صفی ساخته نشده است.'),
          for (final queue in _queues)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(queue['name']?.toString() ?? ''),
              subtitle: Text('اعضا: ${((queue['member_ids'] as List?) ?? const []).map(_memberName).join('، ')}'),
              trailing: canWrite
                  ? IconButton(
                      tooltip: 'حذف صف',
                      icon: const Icon(Icons.close),
                      onPressed: () => _deleteQueue(queue),
                    )
                  : null,
            ),
          if (canWrite) ...[
            TextField(controller: _queueName, decoration: const InputDecoration(labelText: 'نام صف')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final user in _members)
                  FilterChip(
                    label: Text(user.userName),
                    selected: _queueMembers.contains(user.userId),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _queueMembers.add(user.userId);
                      } else {
                        _queueMembers.remove(user.userId);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _createQueue, child: const Text('ساخت صف')),
          ],
        ],
      ),
    );
  }

  Widget _assignmentCard(bool canWrite) {
    return CrmSectionCard(
      title: 'گذاشتن سرنخ در صف',
      subtitle: 'با گذاشتن در صف، مسئول فعلی برداشته می‌شود تا اعضای صف بتوانند آن را بردارند.',
      child: canWrite
          ? Column(
              children: [
                TextField(
                  controller: _leadSearch,
                  decoration: const InputDecoration(labelText: 'جست‌وجوی سرنخ'),
                  onChanged: _searchLeads,
                ),
                if (_selectedLeadName != null) Align(alignment: AlignmentDirectional.centerStart, child: Text('سرنخ: $_selectedLeadName')),
                for (final lead in _leadHits)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(lead['name']?.toString() ?? 'سرنخ'),
                    subtitle: Text(lead['code']?.toString() ?? ''),
                    onTap: () => setState(() {
                      _selectedLeadId = (lead['id'] as num?)?.toInt();
                      _selectedLeadName = lead['name']?.toString();
                      _leadHits = [];
                      _leadSearch.clear();
                    }),
                  ),
                DropdownButtonFormField<int>(
                  value: _assignQueueId,
                  decoration: const InputDecoration(labelText: 'صف'),
                  items: [
                    for (final queue in _queues)
                      DropdownMenuItem(value: queue['id'] as int?, child: Text(queue['name']?.toString() ?? '')),
                  ],
                  onChanged: (value) => setState(() => _assignQueueId = value),
                ),
                const SizedBox(height: 8),
                if (_selectedLeadId != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(onPressed: () => _clearLeadQueue(_selectedLeadId!), child: const Text('برداشتن از صف')),
                  ),
                FilledButton(
                  onPressed: () async {
                    final leadId = _selectedLeadId;
                    if (leadId == null || _assignQueueId == null) {
                      SnackBarHelper.showWarning(context, message: 'سرنخ و صف را مشخص کنید');
                      return;
                    }
                    try {
                      await _crm.assignLeadQueue(businessId: widget.businessId, leadId: leadId, queueId: _assignQueueId);
                      if (!mounted) return;
                      SnackBarHelper.showSuccess(context, message: 'سرنخ به صف رفت');
                    } catch (e) {
                      if (!mounted) return;
                      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                    }
                  },
                  child: const Text('انتقال به صف'),
                ),
              ],
            )
          : const Text('برای انتقال سرنخ به مجوز ویرایش CRM نیاز است.'),
    );
  }

  Widget _aclCard(bool canWrite) {
    return CrmSectionCard(
      title: 'دسترسی یک رکورد',
      subtitle: 'این دسترسی فقط وقتی مجوز سطح رکورد روشن است اثر دارد. دیدن، رکورد را نشان می‌دهد و ویرایش اجازه تغییر می‌دهد.',
      child: canWrite
          ? Column(
              children: [
                if (_recordGrants.isEmpty)
                  const Align(alignment: AlignmentDirectional.centerStart, child: Text('دسترسی جداگانه‌ای ثبت نشده است.'))
                else
                  for (final grant in _recordGrants)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text('${grant['entity_type'] == 'deal' ? 'فرصت' : 'سرنخ'} ${grant['entity_label'] ?? ''}'),
                      subtitle: Text('${_memberName(grant['user_id'])} · ${grant['access'] == 'edit' ? 'ویرایش' : 'دیدن'}'),
                      trailing: IconButton(
                        tooltip: 'برداشتن دسترسی',
                        icon: const Icon(Icons.close),
                        onPressed: () => _revokeGrant(grant),
                      ),
                    ),
                DropdownButtonFormField<String>(
                  value: _aclEntityType,
                  decoration: const InputDecoration(labelText: 'نوع'),
                  items: const [
                    DropdownMenuItem(value: 'lead', child: Text('سرنخ')),
                    DropdownMenuItem(value: 'deal', child: Text('فرصت')),
                  ],
                  onChanged: (value) => setState(() {
                    _aclEntityType = value ?? 'lead';
                    _selectedRecordId = null;
                    _selectedRecordName = null;
                    _recordHits = [];
                    _recordSearch.clear();
                  }),
                ),
                TextField(
                  controller: _recordSearch,
                  decoration: InputDecoration(labelText: _aclEntityType == 'deal' ? 'جست‌وجوی فرصت' : 'جست‌وجوی سرنخ'),
                  onChanged: _searchRecords,
                ),
                if (_selectedRecordName != null) Align(alignment: AlignmentDirectional.centerStart, child: Text('رکورد: $_selectedRecordName')),
                for (final record in _recordHits)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text((record['name'] ?? record['title'])?.toString() ?? 'رکورد'),
                    onTap: () => setState(() {
                      _selectedRecordId = (record['id'] as num?)?.toInt();
                      _selectedRecordName = (record['name'] ?? record['title'])?.toString();
                      _recordHits = [];
                      _recordSearch.clear();
                    }),
                  ),
                _userDropdown('کاربر', _aclUserId, (value) => setState(() => _aclUserId = value)),
                DropdownButtonFormField<String>(
                  value: _aclAccess,
                  decoration: const InputDecoration(labelText: 'سطح'),
                  items: const [
                    DropdownMenuItem(value: 'view', child: Text('دیدن')),
                    DropdownMenuItem(value: 'edit', child: Text('ویرایش')),
                  ],
                  onChanged: (value) => setState(() => _aclAccess = value ?? 'view'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () async {
                    final entityId = _selectedRecordId;
                    if (entityId == null || _aclUserId == null) {
                      SnackBarHelper.showWarning(context, message: 'رکورد و کاربر را مشخص کنید');
                      return;
                    }
                    try {
                      await _crm.grantRecordAccess(
                        businessId: widget.businessId,
                        entityType: _aclEntityType,
                        entityId: entityId,
                        userId: _aclUserId!,
                        access: _aclAccess,
                      );
                      if (!mounted) return;
                      SnackBarHelper.showSuccess(context, message: 'دسترسی ذخیره شد');
                      await _load();
                    } catch (e) {
                      if (!mounted) return;
                      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                    }
                  },
                  child: const Text('ذخیره دسترسی'),
                ),
              ],
            )
          : const Text('برای دادن دسترسی به مجوز ویرایش CRM نیاز است.'),
    );
  }

  Future<void> _deleteQuota(Map<String, dynamic> quota) async {
    final id = (quota['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      await _crm.deleteQuota(businessId: widget.businessId, quotaId: id);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'سهمیه حذف شد');
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _deleteOrganization(Map<String, dynamic> org) async {
    final id = (org['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      await _crm.deleteOrganization(businessId: widget.businessId, organizationId: id);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'سازمان حذف شد');
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _deleteQueue(Map<String, dynamic> queue) async {
    final id = (queue['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      await _crm.deleteLeadQueue(businessId: widget.businessId, queueId: id);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'صف حذف شد');
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _clearLeadQueue(int leadId) async {
    try {
      await _crm.assignLeadQueue(businessId: widget.businessId, leadId: leadId, queueId: null);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'سرنخ از صف برداشته شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _deleteManagerLink(Map<String, dynamic> link) async {
    final id = (link['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      await _crm.deleteManagerLink(businessId: widget.businessId, linkId: id);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'ارتباط مدیر حذف شد');
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _revokeGrant(Map<String, dynamic> grant) async {
    final id = (grant['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      await _crm.revokeRecordAccess(businessId: widget.businessId, aclId: id);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'دسترسی برداشته شد');
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Widget _userDropdown(String label, int? value, ValueChanged<int?> onChanged) {
    return DropdownButtonFormField<int>(
      value: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final user in _members)
          DropdownMenuItem(value: user.userId, child: Text(user.userName)),
      ],
      onChanged: onChanged,
    );
  }

  int? _defaultCurrencyId(List<Map<String, dynamic>> currencies) {
    if (currencies.isEmpty) return null;
    for (final currency in currencies) {
      if (currency['is_default'] == true) return (currency['id'] as num?)?.toInt();
    }
    return (currencies.first['id'] as num?)?.toInt();
  }

  String _currencyLabel(dynamic id) {
    final numeric = id is num ? id.toInt() : int.tryParse('$id');
    for (final currency in _currencies) {
      if ((currency['id'] as num?)?.toInt() == numeric) {
        return currency['code']?.toString() ?? currency['title']?.toString() ?? 'ارز $numeric';
      }
    }
    return 'ارز $id';
  }

  String _memberName(dynamic id) {
    final numeric = id is num ? id.toInt() : int.tryParse('$id');
    for (final user in _members) {
      if (user.userId == numeric) return user.userName;
    }
    return 'کاربر $id';
  }

  DateTime? _parseApiDate(String raw) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw.trim());
    if (match == null) return null;
    return DateTime(int.parse(match.group(1)!), int.parse(match.group(2)!), int.parse(match.group(3)!));
  }

  String _displayDate(String raw) {
    final parsed = _parseApiDate(raw);
    if (parsed == null) return raw;
    final isJalali = ApiClient.getCalendarController()?.isJalali ?? false;
    final shown = HesabixDateUtils.formatForDisplay(parsed, isJalali);
    return shown.isEmpty ? raw : shown;
  }

  Widget _periodButton(String label, TextEditingController controller) {
    final shown = _displayDate(controller.text);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: () => _pickDate(controller),
        icon: const Icon(Icons.event_outlined),
        label: Text(shown.isEmpty ? label : '$label · $shown'),
      ),
    );
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    final picked = await showAdaptiveDatePicker(
      context: context,
      initialDate: _parseApiDate(controller.text) ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
      helpText: 'دوره سهمیه',
    );
    if (picked == null) return;
    setState(() => controller.text = HesabixDateUtils.formatForApiDate(picked));
  }

  Future<void> _searchLeads(String value) async {
    final term = value.trim();
    if (term.length < 2) {
      setState(() => _leadHits = []);
      return;
    }
    try {
      final data = await _crm.listLeads(businessId: widget.businessId, search: term, limit: 8);
      final items = data['items'];
      if (!mounted) return;
      setState(() {
        _leadHits = items is List ? items.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : [];
      });
    } catch (_) {
      if (mounted) setState(() => _leadHits = []);
    }
  }

  Future<void> _searchRecords(String value) async {
    final term = value.trim();
    if (term.length < 2) {
      setState(() => _recordHits = []);
      return;
    }
    try {
      final data = _aclEntityType == 'deal'
          ? await _crm.listDeals(businessId: widget.businessId, search: term, limit: 8)
          : await _crm.listLeads(businessId: widget.businessId, search: term, limit: 8);
      final items = data['items'];
      if (!mounted) return;
      setState(() {
        _recordHits = items is List ? items.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : [];
      });
    } catch (_) {
      if (mounted) setState(() => _recordHits = []);
    }
  }

  String _personLabel(Map<String, dynamic> person) {
    final name = person['alias_name'] ?? person['name'] ?? person['company_name'];
    return '${name ?? 'شخص'} (${person['id']})';
  }
}
