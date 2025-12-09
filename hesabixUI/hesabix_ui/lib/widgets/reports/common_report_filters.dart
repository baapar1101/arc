import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/project/project_selector_widget.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';

/// فیلترهای مشترک برای گزارشات مالی
/// 
/// این widget یک رابط یکپارچه برای فیلترهای رایج در گزارشات ارائه می‌دهد:
/// - فیلتر تاریخ (از/تا)
/// - فیلتر سال مالی
/// - فیلتر پروژه
class CommonReportFilters extends StatelessWidget {
  final int businessId;
  final ApiClient apiClient;
  final CalendarController calendarController;
  
  // فیلترهای تاریخ
  final DateTime? fromDate;
  final DateTime? toDate;
  final VoidCallback? onClearDates;
  final Function(DateTime?) onFromDateChanged;
  final Function(DateTime?) onToDateChanged;
  
  // فیلتر سال مالی
  final int? selectedFiscalYearId;
  final List<Map<String, dynamic>>? fiscalYears;
  final Function(int?)? onFiscalYearChanged;
  
  // فیلتر پروژه
  final int? selectedProjectId;
  final Function(int?) onProjectChanged;
  
  // نمایش/عدم نمایش فیلترها
  final bool showDateFilters;
  final bool showFiscalYearFilter;
  final bool showProjectFilter;
  
  // برچسب‌های سفارشی
  final String? fromDateLabel;
  final String? toDateLabel;
  final String? fiscalYearLabel;
  final String? projectLabel;

  const CommonReportFilters({
    Key? key,
    required this.businessId,
    required this.apiClient,
    required this.calendarController,
    this.fromDate,
    this.toDate,
    this.onClearDates,
    required this.onFromDateChanged,
    required this.onToDateChanged,
    this.selectedFiscalYearId,
    this.fiscalYears,
    this.onFiscalYearChanged,
    required this.selectedProjectId,
    required this.onProjectChanged,
    this.showDateFilters = true,
    this.showFiscalYearFilter = true,
    this.showProjectFilter = true,
    this.fromDateLabel,
    this.toDateLabel,
    this.fiscalYearLabel,
    this.projectLabel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.start,
        children: [
          // فیلترهای تاریخ
          if (showDateFilters) ...[
            SizedBox(
              width: isMobile ? double.infinity : 200,
              child: DateInputField(
                value: fromDate,
                calendarController: calendarController,
                onChanged: onFromDateChanged,
                labelText: fromDateLabel ?? 'از تاریخ',
                hintText: 'انتخاب تاریخ',
              ),
            ),
            SizedBox(
              width: isMobile ? double.infinity : 200,
              child: DateInputField(
                value: toDate,
                calendarController: calendarController,
                onChanged: onToDateChanged,
                labelText: toDateLabel ?? 'تا تاریخ',
                hintText: 'انتخاب تاریخ',
              ),
            ),
            if (onClearDates != null && (fromDate != null || toDate != null))
              SizedBox(
                width: 48,
                child: IconButton(
                  onPressed: onClearDates,
                  icon: const Icon(Icons.clear),
                  tooltip: 'پاک کردن فیلتر تاریخ',
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ),
          ],
          
          // فیلتر سال مالی
          if (showFiscalYearFilter && fiscalYears != null && fiscalYears!.isNotEmpty)
            SizedBox(
              width: isMobile ? double.infinity : 220,
              child: DropdownButtonFormField<int>(
                value: selectedFiscalYearId,
                decoration: InputDecoration(
                  labelText: fiscalYearLabel ?? 'سال مالی',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                ),
                items: fiscalYears!.map((fy) {
                  final id = fy['id'] as int;
                  final title = fy['title'] as String? ?? 'FY $id';
                  final isCurrent = fy['is_current'] as bool? ?? false;
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrent)
                          Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'جاری',
                              style: TextStyle(fontSize: 10, color: Colors.green),
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: onFiscalYearChanged,
              ),
            ),
          
          // 🆕 فیلتر پروژه
          if (showProjectFilter)
            SizedBox(
              width: isMobile ? double.infinity : 280,
              child: ProjectSelectorWidget(
                businessId: businessId,
                apiClient: apiClient,
                selectedProjectId: selectedProjectId,
                onChanged: onProjectChanged,
                allowNull: true,
                labelText: projectLabel ?? 'پروژه (همه)',
              ),
            ),
        ],
      ),
    );
  }
}

/// Badge نمایش پروژه انتخاب شده
class ProjectFilterBadge extends StatelessWidget {
  final String projectName;
  final VoidCallback onClear;

  const ProjectFilterBadge({
    Key? key,
    required this.projectName,
    required this.onClear,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_special, size: 16, color: Colors.blue.shade700),
          const SizedBox(width: 6),
          Text(
            'پروژه: $projectName',
            style: TextStyle(
              color: Colors.blue.shade900,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(12),
            child: Icon(Icons.close, size: 16, color: Colors.blue.shade700),
          ),
        ],
      ),
    );
  }
}

