import 'package:flutter/material.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

class RepairShopStatus {
  RepairShopStatus._();

  static const Map<String, String> labels = {
    'received': 'دریافت شده',
    'assigned': 'اختصاص داده شده',
    'in_progress': 'در حال تعمیر',
    'waiting_parts': 'منتظر قطعات',
    'testing': 'در حال تست',
    'completed_fixed': 'تعمیر موفق',
    'completed_unfixable': 'غیرقابل تعمیر',
    'ready_for_pickup': 'آماده تحویل',
    'delivered': 'تحویل داده شده',
    'cancelled': 'لغو شده',
  };

  static String label(String status) => labels[status] ?? status;

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
