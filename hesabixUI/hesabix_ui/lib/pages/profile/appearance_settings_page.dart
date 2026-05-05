import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/business_panel_ui_store.dart';
import '../../core/api_client.dart';
import '../../models/business_dashboard_models.dart';
import '../../services/business_dashboard_service.dart';
import '../../services/business_menu_preferences_service.dart';

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
  List<String> _rootOrder = const [];
  Set<String> _hiddenKeys = <String>{};
  bool _menuPrefsLoading = false;

  static const List<_MenuEditorItem> _menuCatalog = <_MenuEditorItem>[
    _MenuEditorItem(key: 'dashboard', labelFa: 'داشبورد'),
    _MenuEditorItem(key: 'persons', labelFa: 'اشخاص'),
    _MenuEditorItem(key: 'group:products', labelFa: 'کالاها و خدمات'),
    _MenuEditorItem(key: 'group:bank-accounts', labelFa: 'بانکداری'),
    _MenuEditorItem(key: 'group:chart-of-accounts', labelFa: 'حسابداری'),
    _MenuEditorItem(key: 'group:warehouses', labelFa: 'مدیریت انبار'),
    _MenuEditorItem(key: 'group:ai', labelFa: 'هوش مصنوعی'),
    _MenuEditorItem(key: 'group:crm', labelFa: 'CRM'),
    _MenuEditorItem(key: 'warranty', labelFa: 'گارانتی'),
    _MenuEditorItem(key: 'repair-shop', labelFa: 'تعمیرگاه'),
    _MenuEditorItem(key: 'customer-club', labelFa: 'باشگاه مشتریان'),
    _MenuEditorItem(key: 'distribution', labelFa: 'پخش مویرگی'),
    _MenuEditorItem(key: 'zohal/inquiries', labelFa: 'استعلامات'),
    _MenuEditorItem(key: 'settings', labelFa: 'تنظیمات'),
    _MenuEditorItem(key: 'report-templates', labelFa: 'قالب‌ها'),
    _MenuEditorItem(key: 'plugin-marketplace', labelFa: 'بازار افزونه‌ها'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMenuPrefsForSelectedBusiness() async {
    final bid = _selectedBusinessId;
    if (bid == null) return;
    _menuPrefsLoading = true;
    try {
      final prefs = await _menuPreferencesService.getPreferences(bid);
      final defaultOrder = _menuCatalog.map((e) => e.key).toList();
      final ordered = <String>[];
      for (final key in prefs.rootOrder) {
        if (defaultOrder.contains(key) && !ordered.contains(key)) ordered.add(key);
      }
      for (final key in defaultOrder) {
        if (!ordered.contains(key)) ordered.add(key);
      }
      _rootOrder = ordered;
      _hiddenKeys = prefs.hiddenKeys.toSet();
    } catch (_) {
      _rootOrder = _menuCatalog.map((e) => e.key).toList();
      _hiddenKeys = <String>{};
    } finally {
      _menuPrefsLoading = false;
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
            rootOrder: _rootOrder,
            hiddenKeys: _hiddenKeys.toList(),
            childrenOrder: const {},
          ),
        );
      }
      if (!mounted) return;
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
                    else
                      SizedBox(
                        height: 360,
                        child: ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          itemCount: _rootOrder.length,
                          onReorder: (oldIndex, newIndex) {
                            setState(() {
                              if (newIndex > oldIndex) newIndex--;
                              final item = _rootOrder.removeAt(oldIndex);
                              _rootOrder.insert(newIndex, item);
                            });
                          },
                          itemBuilder: (context, index) {
                            final key = _rootOrder[index];
                            final item = _menuCatalog.firstWhere(
                              (e) => e.key == key,
                              orElse: () => _MenuEditorItem(key: key, labelFa: key),
                            );
                            final hidden = _hiddenKeys.contains(key);
                            return ListTile(
                              key: ValueKey('menu_pref_$key'),
                              leading: ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_indicator),
                              ),
                              title: Text(item.labelFa),
                              subtitle: Text(
                                hidden ? 'مخفی' : 'نمایش',
                                style: TextStyle(
                                  color: hidden ? theme.colorScheme.error : theme.colorScheme.primary,
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
                          },
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'برای تغییر ترتیب، آیتم‌ها را بکشید. تغییرات برای کاربر و کسب‌وکار انتخاب‌شده ذخیره می‌شود.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
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
      ),
    );
  }
}

class _MenuEditorItem {
  final String key;
  final String labelFa;

  const _MenuEditorItem({
    required this.key,
    required this.labelFa,
  });
}
