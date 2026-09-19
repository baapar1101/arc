import 'package:flutter/widgets.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';

import 'ar_ap_aging_report_shared.dart';

class ApAgingReportPage extends StatelessWidget {
  const ApAgingReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  final int businessId;
  final CalendarController calendarController;

  @override
  Widget build(BuildContext context) => ArApAgingReportPage(
    businessId: businessId,
    calendarController: calendarController,
    mode: AgingReportMode.ap,
  );
}
