import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/business_panel_ui_store.dart';

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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await BusinessPanelUiStore.instance.updateAppearancePreferences(
        navigationMode: _draft,
        sidebarTabBehavior: _draftSidebarTabBehavior,
      );
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
