import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/tokens/extensions.dart';

String adminTx(BuildContext context, String fa, String en) {
  return Localizations.localeOf(context).languageCode == 'en' ? en : fa;
}

/// پوستهٔ فشردهٔ صفحه‌های داخلی پنل مدیر، هم‌تراز با هاب تنظیمات.
class AdminCompactScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final Widget? floatingActionButton;
  final String backFallback;

  const AdminCompactScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
    this.bottom,
    this.floatingActionButton,
    this.backFallback = '/user/profile/system-settings',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hub = context.settingsHub;
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        toolbarHeight: subtitle == null ? 48 : 64,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: hub.pageTitleStyle(theme.textTheme, color: colorScheme.onSurface),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: hub.pageSubtitleStyle(
                  theme.textTheme,
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => adminBackToHub(context, fallback: backFallback),
        ),
        actions: actions,
        bottom: bottom,
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}

void adminBackToHub(
  BuildContext context, {
  String fallback = '/user/profile/system-settings',
}) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  context.go(fallback);
}

/// داخل زبانهٔ هاب، عنوان و دکمهٔ برگشت حذف می‌شود ولی اکشن‌ها می‌مانند.
PreferredSizeWidget aiHubAppBar({
  required bool embedded,
  required Widget title,
  List<Widget> actions = const [],
}) {
  if (!embedded) {
    return AppBar(title: title, actions: actions);
  }
  if (actions.isEmpty) {
    return const PreferredSize(preferredSize: Size.zero, child: SizedBox.shrink());
  }
  return AppBar(
    primary: false,
    automaticallyImplyLeading: false,
    toolbarHeight: 40,
    title: const SizedBox.shrink(),
    actions: actions,
  );
}

class AdminLoadBody extends StatelessWidget {
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final Widget child;

  const AdminLoadBody({
    super.key,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final hub = context.settingsHub;
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: hub.pagePadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: Text(adminTx(context, 'تلاش مجدد', 'Retry'))),
            ],
          ),
        ),
      );
    }
    return child;
  }
}
