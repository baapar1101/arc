import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../l10n/app_localizations.dart';
import '../../main.dart' show navigatorKey;
import '../../utils/snackbar_helper.dart';
import 'ai_chat_dialog.dart';
import 'ai_quick_launcher.dart';

/// نقطهٔ ورود واحد برای شروع سریع دستیار هوشمند.
///
/// جریان: لانچر شناور → دریافت موضوع → چت جدید با ارسال خودکار.
abstract final class AiQuickStart {
  static bool _opening = false;

  /// آیا لانچر یا جریان باز کردن در حال اجراست.
  static bool get isBusy => _opening || AiQuickLauncher.isShowing;

  /// باز کردن لانچر و سپس چت با auto-submit.
  static Future<void> open(BuildContext context) async {
    if (_opening || AiQuickLauncher.isShowing) return;

    final dialogContext = navigatorKey.currentContext ?? context;
    if (!dialogContext.mounted) return;

    final l10n = AppLocalizations.of(dialogContext);
    final authStore = ApiClient.getAuthStore();

    if (authStore == null ||
        authStore.apiKey == null ||
        authStore.apiKey!.isEmpty) {
      SnackBarHelper.show(
        dialogContext,
        message: l10n.aiQuickLauncherNeedLogin,
        isError: true,
      );
      return;
    }

    final businessId = resolveBusinessId(dialogContext, authStore);
    if (businessId == null) {
      SnackBarHelper.show(
        dialogContext,
        message: l10n.aiQuickLauncherNeedBusiness,
        isError: true,
      );
      return;
    }

    _opening = true;
    try {
      HapticFeedback.mediumImpact();
      final topic = await AiQuickLauncher.show(dialogContext);
      if (topic == null || topic.trim().isEmpty) return;
      if (!dialogContext.mounted) return;

      // اجازه بده route لانچر کامل بسته شود تا انتقال به چت نرم باشد
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!dialogContext.mounted) return;

      final calendar = ApiClient.getCalendarController();
      await AIChatDialog.show(
        dialogContext,
        authStore: authStore,
        businessId: businessId,
        calendarController: calendar,
        initialPrompt: topic.trim(),
        autoSendInitialPrompt: true,
      );
    } finally {
      _opening = false;
    }
  }

  /// استخراج شناسه کسب‌وکار از AuthStore یا مسیر فعلی روتر.
  static int? resolveBusinessId(BuildContext context, [AuthStore? store]) {
    final auth = store ?? ApiClient.getAuthStore();
    final fromAuth = auth?.currentBusiness?.id;
    if (fromAuth != null && fromAuth > 0) return fromAuth;

    try {
      final path = GoRouter.of(context)
          .routerDelegate
          .currentConfiguration
          .uri
          .path;
      final match = RegExp(r'/business/(\d+)').firstMatch(path);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
    } catch (_) {
      // روتر در دسترس نیست
    }

    final root = navigatorKey.currentContext;
    if (root != null && !identical(root, context)) {
      try {
        final path = GoRouter.of(root)
            .routerDelegate
            .currentConfiguration
            .uri
            .path;
        final match = RegExp(r'/business/(\d+)').firstMatch(path);
        if (match != null) {
          return int.tryParse(match.group(1)!);
        }
      } catch (_) {}
    }

    return null;
  }

  /// آیا فوکوس روی فیلد متنی است (نباید میانبر سراسری فعال شود).
  static bool isTextInputFocused() {
    final primary = FocusManager.instance.primaryFocus;
    final ctx = primary?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }
}
