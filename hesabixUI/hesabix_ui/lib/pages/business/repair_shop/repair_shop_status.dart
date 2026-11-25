import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

class RepairShopStatus {
  RepairShopStatus._();

  static const List<String> codes = [
    'received',
    'assigned',
    'in_progress',
    'waiting_parts',
    'testing',
    'completed_fixed',
    'completed_unfixable',
    'ready_for_pickup',
    'delivered',
    'cancelled',
  ];

  static String label(String status, AppLocalizations t) {
    switch (status) {
      case 'received':
        return t.repairShopStatusReceived;
      case 'assigned':
        return t.repairShopStatusAssigned;
      case 'in_progress':
        return t.repairShopStatusInProgress;
      case 'waiting_parts':
        return t.repairShopStatusWaitingParts;
      case 'testing':
        return t.repairShopStatusTesting;
      case 'completed_fixed':
        return t.repairShopStatusCompletedFixed;
      case 'completed_unfixable':
        return t.repairShopStatusCompletedUnfixable;
      case 'ready_for_pickup':
        return t.repairShopStatusReadyForPickup;
      case 'delivered':
        return t.repairShopStatusDelivered;
      case 'cancelled':
        return t.repairShopStatusCancelled;
      default:
        return status;
    }
  }

  static Color color(BuildContext context, String? status) {
    final map = <String, Color>{
      'received': SemanticColorResolver.info(context),
      'assigned': Colors.purple,
      'in_progress': SemanticColorResolver.warning(context),
      'waiting_parts': Colors.amber,
      'testing': Colors.cyan,
      'completed_fixed': SemanticColorResolver.positive(context),
      'completed_unfixable': SemanticColorResolver.negative(context),
      'ready_for_pickup': Colors.teal,
      'delivered': Colors.grey,
      'cancelled': Colors.black54,
    };
    return map[status] ?? Colors.grey;
  }

  static bool isEditable(String status) =>
      status != 'delivered' && status != 'cancelled';

  static bool canAddParts(String status) =>
      isEditable(status) &&
      !{'completed_fixed', 'completed_unfixable', 'ready_for_pickup'}
          .contains(status);

  static bool canSetLabor(String status) => isEditable(status);

  static bool canComplete(String status) => const {
        'assigned',
        'in_progress',
        'waiting_parts',
        'testing',
      }.contains(status);

  static bool canInvoice(String status) => const {
        'completed_fixed',
        'ready_for_pickup',
        'delivered',
      }.contains(status);

  static bool canDeliver(String status) => const {
        'completed_fixed',
        'completed_unfixable',
        'ready_for_pickup',
      }.contains(status);

  static bool canAssign(String status) => isEditable(status);
}
