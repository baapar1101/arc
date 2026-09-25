import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../core/api_client.dart';
import '../../models/business_dashboard_models.dart';
import '../../models/business_user_model.dart';
import '../../services/business_api_service.dart';
import '../../services/business_user_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

typedef BusinessHubRefreshCallback = VoidCallback;

class BusinessHubActions {
  static final BusinessUserService _userService = BusinessUserService(ApiClient());

  static Future<void> leave(
    BuildContext context, {
    required BusinessWithPermission business,
    required AuthStore authStore,
    BusinessHubRefreshCallback? onRefresh,
  }) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.businessesHubLeaveConfirmTitle),
        content: Text(t.businessesHubLeaveConfirmMessage(business.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(t.businessesHubLeave),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final response = await _userService.leaveBusiness(LeaveBusinessRequest(businessId: business.id));
      if (!context.mounted) return;
      if (response.success) {
        SnackBarHelper.showSuccess(context, message: response.message);
        if (authStore.currentBusiness?.id == business.id) {
          await authStore.clearCurrentBusiness();
        }
        onRefresh?.call();
      } else {
        SnackBarHelper.showError(context, message: response.message);
      }
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(
        context,
        message: t.businessesHubLeaveFailed(ErrorExtractor.forContext(e, context)),
      );
    }
  }

  static Future<void> restore(
    BuildContext context, {
    required BusinessWithPermission business,
    BusinessHubRefreshCallback? onRefresh,
  }) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.businessesHubRestoreConfirmTitle),
        content: Text(t.businessesHubRestoreConfirmMessage(business.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: SemanticColorResolver.positive(context)),
            child: Text(t.businessesHubRestore),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await BusinessApiService.restoreBusiness(business.id);
      if (!context.mounted) return;
      SnackBarHelper.showSuccess(context, message: t.businessesHubRestoreSuccess);
      onRefresh?.call();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(
        context,
        message: t.businessesHubRestoreFailed(ErrorExtractor.forContext(e, context)),
      );
    }
  }
}
