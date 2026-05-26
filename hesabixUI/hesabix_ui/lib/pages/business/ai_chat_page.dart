import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_dialog.dart';

/// صفحهٔ دائمی دستیار هوشمند در پنل کسب‌وکار.
class AIChatPage extends StatelessWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController? calendarController;

  const AIChatPage({
    super.key,
    required this.businessId,
    required this.authStore,
    this.calendarController,
  });

  @override
  Widget build(BuildContext context) {
    return AIChatDialog(
      businessId: businessId,
      authStore: authStore,
      calendarController: calendarController,
      embeddedInShell: true,
    );
  }
}
