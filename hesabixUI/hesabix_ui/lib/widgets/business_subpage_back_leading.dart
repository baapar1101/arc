import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// بازگشت با پشته؛ اگر با [GoRouter.go] بدون پشته آمده باشد، به هاب تنظیمات.
Widget businessSubpageBackLeading(BuildContext context, int businessId) {
  return IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/business/$businessId/settings');
      }
    },
  );
}
