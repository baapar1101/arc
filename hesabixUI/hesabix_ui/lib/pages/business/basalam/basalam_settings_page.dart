import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/business_nav.dart';
import '../../../core/auth_store.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/permission_guard.dart';
import 'basalam_plugin_settings_body.dart';

/// تنظیمات افزونهٔ باسلام زیر مسیر `.../settings/basalam`.
class BasalamSettingsPage extends StatelessWidget {
  final int businessId;
  final AuthStore authStore;

  const BasalamSettingsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final canView =
        authStore.hasBusinessPermission('basalam', 'view') ||
            authStore.currentBusiness?.isOwner == true;

    if (!canView) {
      return Scaffold(
        appBar: AppBar(title: Text(t.basalamSettingsPageTitle)),
        body: PermissionGuard.buildAccessDeniedPage(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.basalamSettingsPageTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: t.basalamOpenIntegrationHub,
            onPressed: () => context.push(
                  context.businessPanelUrl(businessId, 'basalam'),
                ),
            icon: const Icon(Icons.storefront_outlined),
          ),
        ],
      ),
      body: BasalamPluginSettingsBody(
        businessId: businessId,
        authStore: authStore,
      ),
    );
  }
}
