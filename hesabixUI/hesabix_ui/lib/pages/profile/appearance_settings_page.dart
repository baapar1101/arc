import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/business_panel_ui_store.dart';
import '../../core/api_client.dart';
import '../../models/business_dashboard_models.dart';
import '../../services/business_dashboard_service.dart';
import '../../services/business_menu_preferences_service.dart';

/// کلیدهای جداکننده در [business_shell] — همیشه در rootOrder حفظ می‌شوند.
const String _sepPracticalTools = 'sep_practical_tools';
const String _sepAccounting = 'sep_accounting';
const String _sepServicesPlugins = 'sep_services_plugins';
const String _sepOthers = 'sep_others';

class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key});

  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  bool _loading = true;
  String? _error;
  BusinessPanelNavigationMode _draft = BusinessPanelNavigationMode.single;
  BusinessPanelSidebarTabBehavior _draftSidebarTabBehavior =
      BusinessPanelSidebarTabBehavior.reuseAcrossTabsOnTap;
  bool _saving = false;
  final BusinessDashboardService _businessService = BusinessDashboardService(ApiClient());
  final BusinessMenuPreferencesService _menuPreferencesService =
      BusinessMenuPreferencesService(ApiClient());
  List<BusinessWithPermission> _businesses = const [];
  int? _selectedBusinessId;
  bool _menuPrefsLoading = false;
  String _baselineSignature = '';

  /// ترتیب ریشه بدون داشبورد و بدون جداکننده‌ها (فقط برای بخش‌های چهارگانه).
  List<String> _orderPractical = [];
  List<String> _orderAccounting = [];
  List<String> _orderPrograms = [];
  List<String> _orderOther = [];

  Set<String> _hiddenKeys = <String>{};
  Map<String, List<String>> _childrenOrder = {};

  static const List<String> _defaultOrderPractical = [
    'persons',
    'group:products',
    'group:accounts',
  ];

  static const List<String> _defaultOrderAccounting = [
    'quick-sales',
    'invoice',
    'receipts-payments',
    'expense-income',
    'transfers',
    'checks',
    'documents',
    'group:chart-of-accounts',
    'reports',
  ];

  static const List<String> _defaultOrderPrograms = [
    'group:warehouses',
    'storage-files',
    'tax-workspace',
    'group:ai',
    'workflows',
    'group:crm',
    'warranty',
    'repair-shop',
    'customer-club',
    'distribution',
    'zohal/inquiries',
  ];

  static const List<String> _defaultOrderOther = [
    'settings',
    'report-templates',
    'plugin-marketplace',
  ];

  static const Map<String, List<String>> _defaultChildrenOrder = {
    'group:products': ['products', 'categories', 'product-attributes'],
    'group:accounts': ['accounts', 'petty-cash', 'cash-box', 'wallet'],
    'group:chart-of-accounts': [
      'chart-of-accounts',
      'opening-balance',
      'year-end-closing',
      'currency-revaluation',
    ],
    'group:warehouses': ['warehouses', 'warehouse-docs', 'stock-count'],
    'group:ai': ['ai/subscription', 'ai/usage'],
    'group:crm': [
      'crm/dashboard',
      'crm/notes-calendar',
      'crm/web-chat',
      'crm/process-definitions',
      'crm/leads',
      'crm/deals',
      'crm/activities',
      'crm/reports',
    ],
  };

  /// برچسب نمایشی آیتم ریشه (فقط فارسی؛ با منوی فعلی هم‌خوان است).
  static const Map<String, String> _rootLabelsFa = {
    'dashboard': 'داشبورد',
    'persons': 'اشخاص',
    'group:products': 'کالاها و خدمات',
    'group:accounts': 'بانکداری',
    'quick-sales': 'فروش سریع',
    'invoice': 'فاکتور',
    'receipts-payments': 'دریافت و پرداخت',
    'expense-income': 'هزینه و درآمد',
    'transfers': 'انتقال وجه',
    'checks': 'چک‌ها',
    'documents': 'اسناد',
    'group:chart-of-accounts': 'حسابداری پیشرفته',
    'reports': 'گزارش‌ها',
    'group:warehouses': 'مدیریت انبار',
    'storage-files': 'فضای ذخیره‌سازی',
    'tax-workspace': 'مودیان',
    'group:ai': 'هوش مصنوعی',
    'workflows': 'اتوماسیون‌ها',
    'group:crm': 'CRM',
    'warranty': 'گارانتی',
    'repair-shop': 'تعمیرگاه',
    'customer-club': 'باشگاه مشتریان',
    'distribution': 'پخش مویرگی',
    'zohal/inquiries': 'استعلامات',
    'settings': 'تنظیمات',
    'report-templates': 'قالب‌ها',
    'plugin-marketplace': 'بازار افزونه‌ها',
  };

  static const Map<String, String> _childLabelsFa = {
    'products': 'کالاها',
    'categories': 'دسته‌بندی‌ها',
    'product-attributes': 'خصوصیات کالا',
    'accounts': 'حساب‌های بانکی',
    'petty-cash': 'تنخواه',
    'cash-box': 'صندوق',
    'wallet': 'کیف‌پول',
    'chart-of-accounts': 'جدول حساب‌ها',
    'opening-balance': 'مانده اول دوره',
    'year-end-closing': 'بستن سال مالی',
    'currency-revaluation': 'محاسبات ارزی',
    'warehouses': 'انبارها',
    'warehouse-docs': 'حواله‌های انبار',
    'stock-count': 'انبار گردانی',
    'ai/subscription': 'اشتراک AI',
    'ai/usage': 'آمار استفاده',
    'crm/dashboard': 'داشبورد CRM',
    'crm/notes-calendar': 'یادداشت‌ها و تقویم',
    'crm/web-chat': 'چت وب',
    'crm/process-definitions': 'فرایندها و مراحل قیف',
    'crm/leads': 'سرنخ‌ها',
    'crm/deals': 'فرصت‌های فروش',
    'crm/activities': 'فعالیت‌ها',
    'crm/reports': 'گزارشات CRM',
  };

  /// نگاشت کلیدهای قدیمی (در صورت ذخیره قبلی) به کلیدهای فعلی.
  static final Map<String, String> _legacyRootKeyMigrate = {
    'group:bank-accounts': 'group:accounts',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _migrateKey(String key) => _legacyRootKeyMigrate[key] ?? key;

  static const Map<String, String> _legacyChildKeyMigrate = {
    'product_attributes': 'product-attributes',
  };

  String _migrateChildKey(String key) =>
      _legacyChildKeyMigrate[key] ?? _migrateKey(key);

  String _migrateAnyMenuKey(String key) => _migrateChildKey(key);

  String _buildStateSignature() {
    final hidden = _hiddenKeys.toList()..sort();
    final childrenKeys = _childrenOrder.keys.toList()..sort();
    final normalizedChildren = <String, List<String>>{};
    for (final k in childrenKeys) {
      normalizedChildren[k] = List<String>.from(_childrenOrder[k] ?? const <String>[]);
    }
    return jsonEncode(<String, dynamic>{
      'mode': _draft.name,
      'sidebarTabBehavior': _draftSidebarTabBehavior.name,
      'businessId': _selectedBusinessId,
      'orderPractical': _orderPractical,
      'orderAccounting': _orderAccounting,
      'orderPrograms': _orderPrograms,
      'orderOther': _orderOther,
      'hiddenKeys': hidden,
      'childrenOrder': normalizedChildren,
    });
  }

  bool get _hasUnsavedChanges => _baselineSignature != _buildStateSignature();

  void _captureBaseline() {
    _baselineSignature = _buildStateSignature();
  }

  void _discardChanges() {
    _load();
  }

  void _resetAllMenuToDefaults() {
    setState(() {
      _orderPractical = [..._defaultOrderPractical];
      _orderAccounting = [..._defaultOrderAccounting];
      _orderPrograms = [..._defaultOrderPrograms];
      _orderOther = [..._defaultOrderOther];
      _hiddenKeys = <String>{};
      _childrenOrder = _mergedChildrenOrder(null);
    });
  }

  void _resetSectionToDefault(String section) {
    setState(() {
      switch (section) {
        case 'practical':
          _orderPractical = [..._defaultOrderPractical];
          break;
        case 'accounting':
          _orderAccounting = [..._defaultOrderAccounting];
          break;
        case 'programs':
          _orderPrograms = [..._defaultOrderPrograms];
          break;
        case 'other':
          _orderOther = [..._defaultOrderOther];
          break;
      }
    });
  }

  List<String> _mergeOrder(List<String> saved, List<String> defaults) {
    final seen = <String>{};
    final out = <String>[];
    for (final k in saved.map(_migrateKey)) {
      if (!defaults.contains(k)) continue;
      if (seen.add(k)) out.add(k);
    }
    for (final k in defaults) {
      if (seen.add(k)) out.add(k);
    }
    return out;
  }

  Map<String, List<String>> _mergedChildrenOrder(Map<String, List<String>>? fromServer) {
    final merged = <String, List<String>>{};
    for (final entry in _defaultChildrenOrder.entries) {
      final parent = entry.key;
      final defaults = entry.value;
      final rawSaved = fromServer?[parent];
      merged[parent] = _mergeChildOrder(rawSaved, defaults);
    }
    return merged;
  }

  List<String> _mergeChildOrder(List<String>? saved, List<String> defaults) {
    final migrated = saved?.map(_migrateChildKey).toList() ?? const <String>[];
    return _mergeOrder(migrated, defaults);
  }

  List<String> _canonicalFlatRoot() {
    return [
      'dashboard',
      _sepPracticalTools,
      ..._orderPractical,
      _sepAccounting,
      ..._orderAccounting,
      _sepServicesPlugins,
      ..._orderPrograms,
      _sepOthers,
      ..._orderOther,
    ];
  }

  void _applyBucketsFromFlat(List<String> flat) {
    List<String> norm = flat.map(_migrateKey).toList();

    int indexOfSep(String sep) {
      final i = norm.indexWhere((e) => e == sep);
      return i;
    }

    final ip = indexOfSep(_sepPracticalTools);
    final ia = indexOfSep(_sepAccounting);
    final ig = indexOfSep(_sepServicesPlugins);
    final io = indexOfSep(_sepOthers);

    if (ip < 0 || ia < ip || ig < ia || io < ig) {
      _bucketingFallbackFromMixedOrder(
        norm.where((k) => k != 'dashboard' && !k.startsWith('sep_')).toList(),
      );
      return;
    }

    List<String> sliceExclusive(int lo, int hi) {
      if (hi <= lo + 1) return [];
      final sub = norm.sublist(lo + 1, hi);
      return sub.where((k) => k != 'dashboard' && !k.startsWith('sep_')).toList();
    }

    List<String> tailExclusive(int sepIndex) {
      if (sepIndex < 0 || sepIndex + 1 >= norm.length) return [];
      final sub = norm.sublist(sepIndex + 1);
      return sub.where((k) => k != 'dashboard' && !k.startsWith('sep_')).toList();
    }

    final p = sliceExclusive(ip, ia);
    final a = sliceExclusive(ia, ig);
    final g = sliceExclusive(ig, io);
    final o = tailExclusive(io);

    _orderPractical = _mergeOrder(p, _defaultOrderPractical);
    _orderAccounting = _mergeOrder(a, _defaultOrderAccounting);
    _orderPrograms = _mergeOrder(g, _defaultOrderPrograms);
    _orderOther = _mergeOrder(o, _defaultOrderOther);
  }

  /// وقتی rootOrder بدون sep ذخیره شده یا جداکننده‌ها نامعتبر باشند؛ بر اساس «عضویت کلید در بلوک پیش‌فرض» خرد می‌شود.
  void _bucketingFallbackFromMixedOrder(List<String> keysWithoutSepOrDashboard) {
    final p = <String>[];
    final a = <String>[];
    final g = <String>[];
    final o = <String>[];

    for (final key in keysWithoutSepOrDashboard) {
      final k = _migrateKey(key);
      if (k.startsWith('sep_')) continue;
      if (_defaultOrderPractical.contains(k)) {
        p.add(k);
      } else if (_defaultOrderAccounting.contains(k)) {
        a.add(k);
      } else if (_defaultOrderPrograms.contains(k)) {
        g.add(k);
      } else if (_defaultOrderOther.contains(k)) {
        o.add(k);
      }
    }

    _orderPractical = _mergeOrder(p, _defaultOrderPractical);
    _orderAccounting = _mergeOrder(a, _defaultOrderAccounting);
    _orderPrograms = _mergeOrder(g, _defaultOrderPrograms);
    _orderOther = _mergeOrder(o, _defaultOrderOther);
  }

  void _deserializeFromPrefs(BusinessMenuPreferencesDto prefs) {
    final flat = prefs.rootOrder.map(_migrateAnyMenuKey).toList();
    if (flat.any((k) =>
        k == _sepPracticalTools ||
        k == _sepAccounting ||
        k == _sepServicesPlugins ||
        k == _sepOthers)) {
      _applyBucketsFromFlat(flat);
    } else {
      // قدیمی: لیست بدون جداکننده
      _bucketingFallbackFromMixedOrder(
        flat.where((k) => k != 'dashboard' && !k.startsWith('sep_')).toList(),
      );
    }

    final hiddenRaw = prefs.hiddenKeys.map(_migrateAnyMenuKey).where((k) => !k.startsWith('sep_')).toSet();
    _hiddenKeys = hiddenRaw;

    _childrenOrder = _mergedChildrenOrder(prefs.childrenOrder);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.appearanceSettingsPageTitle, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ),
            if (_hasUnsavedChanges)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.edit_note_outlined,
                        size: 18,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تغییرات ذخیره نشده دارید.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _saving ? null : _discardChanges,
                        child: const Text('لغو تغییرات'),
                      ),
                    ],
                  ),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.appearanceBusinessPanelSection, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    RadioListTile<BusinessPanelNavigationMode>(
                      title: Text(t.appearanceNavigationSingleLabel),
                      subtitle: Text(t.appearanceNavigationSingleSubtitle),
                      value: BusinessPanelNavigationMode.single,
                      groupValue: _draft,
                      onChanged: _saving
                          ? null
                          : (v) {
                              if (v != null) setState(() => _draft = v);
                            },
                    ),
                    RadioListTile<BusinessPanelNavigationMode>(
                      title: Text(t.appearanceNavigationTabsLabel),
                      subtitle: Text(t.appearanceNavigationTabsSubtitle),
                      value: BusinessPanelNavigationMode.tabs,
                      groupValue: _draft,
                      onChanged: _saving
                          ? null
                          : (v) {
                              if (v != null) setState(() => _draft = v);
                            },
                    ),
                    if (_draft == BusinessPanelNavigationMode.tabs) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.appearanceSidebarTabBehaviorSection,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            RadioListTile<BusinessPanelSidebarTabBehavior>(
                              title: Text(t.appearanceSidebarTabBehaviorReuseTitle),
                              subtitle: Text(t.appearanceSidebarTabBehaviorReuseSubtitle),
                              value: BusinessPanelSidebarTabBehavior.reuseAcrossTabsOnTap,
                              groupValue: _draftSidebarTabBehavior,
                              onChanged: _saving
                                  ? null
                                  : (v) {
                                      if (v != null) setState(() => _draftSidebarTabBehavior = v);
                                    },
                            ),
                            RadioListTile<BusinessPanelSidebarTabBehavior>(
                              title: Text(t.appearanceSidebarTabBehaviorLongPressTitle),
                              subtitle: Text(t.appearanceSidebarTabBehaviorLongPressSubtitle),
                              value: BusinessPanelSidebarTabBehavior.newTabViaLongPress,
                              groupValue: _draftSidebarTabBehavior,
                              onChanged: _saving
                                  ? null
                                  : (v) {
                                      if (v != null) setState(() => _draftSidebarTabBehavior = v);
                                    },
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(t.appearanceDesktopOnlyNote, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('چیدمان منوی پنل کسب‌وکار', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: _selectedBusinessId,
                      decoration: const InputDecoration(
                        labelText: 'کسب‌وکار',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _businesses
                          .map(
                            (b) => DropdownMenuItem<int>(
                              value: b.id,
                              child: Text(b.name),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (v) async {
                              if (v == null) return;
                              setState(() => _selectedBusinessId = v);
                              await _loadMenuPrefsForSelectedBusiness();
                              if (mounted) setState(() {});
                            },
                    ),
                    const SizedBox(height: 12),
                    if (_menuPrefsLoading)
                      const LinearProgressIndicator()
                    else ...[
                      _dashboardRow(theme),
                      const SizedBox(height: 16),
                      _menuSection(theme, title: 'ابزارهای کاربردی', order: _orderPractical,
                          setOrder: (v) => setState(() => _orderPractical = v), onResetSection: () => _resetSectionToDefault('practical')),
                      const Divider(height: 24),
                      _menuSection(theme, title: 'حسابداری', order: _orderAccounting,
                          setOrder: (v) => setState(() => _orderAccounting = v), onResetSection: () => _resetSectionToDefault('accounting')),
                      const Divider(height: 24),
                      _menuSection(theme, title: 'برنامه‌های جانبی', order: _orderPrograms,
                          setOrder: (v) => setState(() => _orderPrograms = v), onResetSection: () => _resetSectionToDefault('programs')),
                      const Divider(height: 24),
                      _menuSection(theme, title: 'سایر', order: _orderOther,
                          setOrder: (v) => setState(() => _orderOther = v), onResetSection: () => _resetSectionToDefault('other')),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'در هر بخش می‌توانید ترتیب را با کشیدن عوض کنید. '
                      'آیتم‌های بازشونده را برای مرتب‌سازی زیرمنوها باز کنید. '
                      'جداکننده‌های بصری در منو به‌صورت خودکار حفظ می‌شوند.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('پیش‌نمایش و وضعیت', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Text(
                      'مجموع آیتم‌های مخفی: ${_hiddenKeys.length}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ترتیب نهایی ریشه: ${_canonicalFlatRoot().join('  |  ')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('بازگشت به چیدمان پیش‌فرض'),
                              content: const Text('همه بخش‌های منو به حالت پیش‌فرض برگردند؟'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: const Text('انصراف'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: const Text('تایید'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) _resetAllMenuToDefaults();
                        },
                  icon: const Icon(Icons.restore_outlined),
                  label: const Text('بازگشت به پیش‌فرض'),
                ),
                FilledButton.icon(
                  onPressed: _saving || !_hasUnsavedChanges ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(t.appearanceSaveButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboardRow(ThemeData theme) {
    const key = 'dashboard';
    final hidden = _hiddenKeys.contains(key);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.dashboard_outlined, color: theme.colorScheme.primary),
      title: Text(_rootLabelsFa[key] ?? key, style: theme.textTheme.titleSmall),
      subtitle: Text(
        hidden ? 'مخفی' : 'بعد از ذخیره، در اول منو نمایش داده می‌شود',
        style: theme.textTheme.bodySmall?.copyWith(
          color: hidden ? theme.colorScheme.error : theme.colorScheme.outline,
        ),
      ),
      trailing: Switch(
        value: !hidden,
        onChanged: _saving
            ? null
            : (v) {
                setState(() {
                  if (v) {
                    _hiddenKeys.remove(key);
                  } else {
                    _hiddenKeys.add(key);
                  }
                });
              },
      ),
    );
  }

  Widget _menuSection(
    ThemeData theme, {
    required String title,
    required List<String> order,
    required void Function(List<String>) setOrder,
    required VoidCallback onResetSection,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            TextButton.icon(
              onPressed: _saving ? null : onResetSection,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('ریست بخش'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ReorderableListView.builder(
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: order.length,
            onReorder: (oldIndex, newIndex) {
              var ni = newIndex;
              if (ni > oldIndex) ni--;
              final copy = List<String>.from(order);
              final item = copy.removeAt(oldIndex);
              copy.insert(ni, item);
              setOrder(copy);
            },
            itemBuilder: (context, index) => _menuKeyTile(theme, order, index, title),
        ),
      ],
    );
  }

  Widget _menuKeyTile(ThemeData theme, List<String> orderList, int index, String sectionTitle) {
    final key = orderList[index];
    final label = _rootLabelsFa[key] ?? key;
    final hidden = _hiddenKeys.contains(key);
    final childKeys = _defaultChildrenOrder[key];

    Widget titleRow = Row(
      children: [
        ReorderableDragStartListener(
          index: index,
          child: Icon(Icons.drag_indicator, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
              color: hidden ? theme.colorScheme.onSurface.withValues(alpha: 0.45) : null,
            ),
          ),
        ),
      ],
    );

    if (childKeys == null) {
      return ListTile(
        key: ValueKey('${sectionTitle}_$key'),
        dense: true,
        minVerticalPadding: 8,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        title: titleRow,
        subtitle: Text(
          hidden ? 'مخفی' : 'نمایش',
          style: TextStyle(color: hidden ? theme.colorScheme.error : theme.colorScheme.primary, fontSize: 11),
        ),
        trailing: Switch(
          value: !hidden,
          onChanged: _saving
              ? null
              : (v) {
                  setState(() {
                    if (v) {
                      _hiddenKeys.remove(key);
                    } else {
                      _hiddenKeys.add(key);
                    }
                  });
                },
        ),
      );
    }

    final cOrder = _childrenOrder[key] ?? childKeys;

    return ExpansionTile(
      key: ValueKey('exp_${sectionTitle}_$key'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsetsDirectional.only(bottom: 8),
      initiallyExpanded: false,
      leading: ReorderableDragStartListener(
        index: index,
        child: Icon(Icons.drag_indicator, color: theme.colorScheme.onSurfaceVariant),
      ),
      title: Row(
        children: [
          Expanded(child: Text(label)),
          Switch(
            value: !hidden,
            onChanged: _saving
                ? null
                : (v) {
                    setState(() {
                      if (v) {
                        _hiddenKeys.remove(key);
                      } else {
                        _hiddenKeys.add(key);
                      }
                    });
                  },
          ),
        ],
      ),
      subtitle: Text(
        hidden ? 'کل گروه مخفی است' : 'زیرمنوها را اینجا مرتب کنید',
        style: theme.textTheme.bodySmall?.copyWith(
          color: hidden ? theme.colorScheme.error : theme.colorScheme.outline,
        ),
      ),
      children: hidden
          ? const <Widget>[]
          : [
              ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cOrder.length,
                  onReorder: (o, n) {
                    var nn = n;
                    if (nn > o) nn--;
                    setState(() {
                      final src = List<String>.from(_childrenOrder[key] ?? childKeys);
                      final mv = src.removeAt(o);
                      src.insert(nn, mv);
                      _childrenOrder[key] = src;
                    });
                  },
                  itemBuilder: (_, ci) {
                    final ck = cOrder[ci];
                    final cHidden = _hiddenKeys.contains(ck);
                    return ListTile(
                      key: ValueKey('child_${key}_$ck'),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: ReorderableDragStartListener(index: ci, child: Icon(Icons.drag_handle, size: 18, color: theme.colorScheme.outline)),
                      title: Text(_childLabelsFa[ck] ?? ck),
                      subtitle: Text(
                        cHidden ? 'مخفی' : 'نمایش',
                        style: TextStyle(fontSize: 11, color: cHidden ? theme.colorScheme.error : theme.colorScheme.primary),
                      ),
                      trailing: Switch(
                        value: !cHidden,
                        onChanged: _saving
                            ? null
                            : (v) {
                                setState(() {
                                  if (v) {
                                    _hiddenKeys.remove(ck);
                                  } else {
                                    _hiddenKeys.add(ck);
                                  }
                                });
                              },
                      ),
                    );
                  },
                ),
            ],
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await BusinessPanelUiStore.instance.hydrateIfNeeded();
      final auth = ApiClient.getAuthStore();
      _businesses = await _businessService.getUserBusinesses();
      _selectedBusinessId = auth?.currentBusiness?.id ?? (_businesses.isNotEmpty ? _businesses.first.id : null);
      await _loadMenuPrefsForSelectedBusiness();
      if (!mounted) return;
      final store = BusinessPanelUiStore.instance;
      setState(() {
        _draft = store.mode;
        _draftSidebarTabBehavior = store.sidebarTabBehavior;
        _loading = false;
        _captureBaseline();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _captureBaseline();
      });
    }
  }

  Future<void> _loadMenuPrefsForSelectedBusiness() async {
    final bid = _selectedBusinessId;
    if (bid == null) return;
    setState(() => _menuPrefsLoading = true);
    try {
      final prefs = await _menuPreferencesService.getPreferences(bid);
      if (!mounted) return;
      setState(() => _deserializeFromPrefs(prefs));
      _captureBaseline();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _orderPractical = [..._defaultOrderPractical];
        _orderAccounting = [..._defaultOrderAccounting];
        _orderPrograms = [..._defaultOrderPrograms];
        _orderOther = [..._defaultOrderOther];
        _hiddenKeys = <String>{};
        _childrenOrder = _mergedChildrenOrder(null);
      });
      _captureBaseline();
    } finally {
      if (mounted) setState(() => _menuPrefsLoading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await BusinessPanelUiStore.instance.updateAppearancePreferences(
        navigationMode: _draft,
        sidebarTabBehavior: _draftSidebarTabBehavior,
      );
      final bid = _selectedBusinessId;
      if (bid != null) {
        await _menuPreferencesService.putPreferences(
          bid,
          BusinessMenuPreferencesDto(
            rootOrder: _canonicalFlatRoot(),
            hiddenKeys: _hiddenKeys.toList(),
            childrenOrder: {..._childrenOrder},
          ),
        );
      }
      if (!mounted) return;
      _captureBaseline();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).appearanceSaved)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).appearanceSaveError)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
