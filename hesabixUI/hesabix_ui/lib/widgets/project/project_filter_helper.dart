import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/widgets/project/project_selector_widget.dart';

/// Helper widget برای افزودن فیلتر پروژه به صفحات
class ProjectFilterWidget extends StatelessWidget {
  final int businessId;
  final ApiClient apiClient;
  final int? selectedProjectId;
  final Function(int?) onChanged;
  final bool enabled;

  const ProjectFilterWidget({
    Key? key,
    required this.businessId,
    required this.apiClient,
    this.selectedProjectId,
    required this.onChanged,
    this.enabled = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ProjectSelectorWidget(
      businessId: businessId,
      apiClient: apiClient,
      selectedProjectId: selectedProjectId,
      onChanged: onChanged,
      allowNull: true,
      labelText: 'پروژه',
      enabled: enabled,
    );
  }
}

/// Helper برای اضافه کردن فیلتر پروژه به additionalFilters
List<dynamic> addProjectFilter(List<dynamic> filters, int? projectId) {
  final result = List<dynamic>.from(filters);
  
  if (projectId != null) {
    result.add({
      'property': 'project_id',
      'operator': '=',
      'value': projectId,
    });
  }
  
  return result;
}

