import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/mobile_launcher_nav.dart';
import '../core/mobile_launcher_prefs.dart';
import '../utils/responsive_helper.dart';

/// بازگشت با پشته؛ اگر با [GoRouter.go] بدون پشته آمده باشد:
/// - در حالت لانچر موبایل → خانهٔ لانچر
/// - وگرنه → هاب تنظیمات
Widget businessSubpageBackLeading(BuildContext context, int businessId) {
  return IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => popBusinessOrLauncher(
      context,
      businessId,
      fallbackPath: '/business/$businessId/settings',
    ),
  );
}

/// pop در صورت وجود پشته؛ در حالت لانچر موبایل به خانهٔ لانچر؛ وگرنه [fallbackPath].
void popBusinessOrLauncher(
  BuildContext context,
  int businessId, {
  String? fallbackPath,
}) {
  if (!context.mounted) return;
  if (context.canPop()) {
    context.pop();
    return;
  }
  final home = MobileLauncherBackInfo.maybeHomeOf(context) ??
      (ResponsiveHelper.isMobile(context)
          ? MobileLauncherPrefs.syncLauncherHomePathForBusiness(businessId)
          : null);
  if (home != null) {
    context.go(home);
    return;
  }
  if (fallbackPath != null && fallbackPath.isNotEmpty) {
    context.go(fallbackPath);
  }
}
