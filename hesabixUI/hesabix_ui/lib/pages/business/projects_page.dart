import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/models/project_model.dart';
import 'package:hesabix_ui/services/project_service.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';
import 'package:hesabix_ui/widgets/project/project_form_dialog.dart';
import 'package:hesabix_ui/widgets/business_subpage_back_leading.dart';

/// صفحه لیست پروژه‌ها
class ProjectsPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final AuthStore authStore;
  final ApiClient apiClient;

  const ProjectsPage({
    Key? key,
    required this.businessId,
    required this.calendarController,
    required this.authStore,
    required this.apiClient,
  }) : super(key: key);

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  final GlobalKey _tableKey = GlobalKey();
  late final ProjectService _projectService;
  
  String? _selectedStatus;
  bool _showOnlyActive = true;

  @override
  void initState() {
    super.initState();
    _projectService = ProjectService(widget.apiClient);
  }

  void _refreshData() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = _tableKey.currentState;
      if (state != null) {
        try {
          // ignore: avoid_dynamic_calls
          (state as dynamic).refresh();
        } catch (_) {}
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final contentPadding = ResponsiveHelper.getPadding(context);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('مدیریت پروژه‌ها'),
        leading: businessSubpageBackLeading(context, widget.businessId),
        actions: [
          if (!isMobile)
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: ElevatedButton.icon(
                onPressed: _onAddProject,
                icon: const Icon(Icons.add),
                label: const Text('پروژه جدید'),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFilters(t, isMobile),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  contentPadding,
                  8,
                  contentPadding,
                  isMobile ? 88 : 8,
                ),
                child: DataTableWidget<ProjectModel>(
                  key: _tableKey,
                  config: _buildTableConfig(t),
                  fromJson: (json) => ProjectModel.fromJson(json),
                  calendarController: widget.calendarController,
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: isMobile
          ? FloatingActionButton.extended(
              onPressed: _onAddProject,
              icon: const Icon(Icons.add),
              label: Text(t.add),
            )
          : null,
    );
  }

  Widget _buildFilters(AppLocalizations t, bool isMobile) {
    final padding = ResponsiveHelper.getPadding(context);
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // وضعیت
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String?>(
              segments: [
                ButtonSegment<String?>(
                  value: null,
                  label: const Text('همه'),
                  icon: const Icon(Icons.all_inclusive),
                ),
                ButtonSegment<String?>(
                  value: 'active',
                  label: const Text('فعال'),
                  icon: const Icon(Icons.check_circle_outline),
                ),
                ButtonSegment<String?>(
                  value: 'completed',
                  label: const Text('تکمیل شده'),
                  icon: const Icon(Icons.done_all),
                ),
                ButtonSegment<String?>(
                  value: 'on_hold',
                  label: const Text('معلق'),
                  icon: const Icon(Icons.pause_circle_outline),
                ),
                ButtonSegment<String?>(
                  value: 'cancelled',
                  label: const Text('لغو شده'),
                  icon: const Icon(Icons.cancel_outlined),
                ),
              ],
              selected: _selectedStatus != null ? {_selectedStatus} : <String?>{},
              onSelectionChanged: (set) {
                setState(() {
                  _selectedStatus = set.isEmpty ? null : set.first;
                });
                _refreshData();
              },
            ),
          ),
          const SizedBox(height: 8),
          // فعال/غیرفعال
          Row(
            children: [
              Checkbox(
                value: _showOnlyActive,
                onChanged: (value) {
                  setState(() {
                    _showOnlyActive = value ?? true;
                  });
                  _refreshData();
                },
              ),
              const Text('فقط پروژه‌های فعال'),
            ],
          ),
        ],
      ),
    );
  }

  DataTableConfig<ProjectModel> _buildTableConfig(AppLocalizations t) {
    final params = <String, dynamic>{};
    
    if (_selectedStatus != null) {
      params['status'] = _selectedStatus;
    }
    
    if (_showOnlyActive) {
      params['is_active'] = true;
    }

    return DataTableConfig<ProjectModel>(
      endpoint: '/api/v1/businesses/${widget.businessId}/projects',
      additionalParams: params.isNotEmpty ? params : null,
      columns: [
        TextColumn(
          'code',
          'کد',
          width: ColumnWidth.small,
          formatter: (item) => (item as ProjectModel).code,
        ),
        CustomColumn(
          'name',
          'نام پروژه',
          width: ColumnWidth.medium,
          builder: (item, index) {
            final project = item as ProjectModel;
            return Text(
              project.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            );
          },
        ),
        CustomColumn(
          'status_name',
          'وضعیت',
          width: ColumnWidth.small,
          builder: (item, index) {
            final project = item as ProjectModel;
            final status = project.status;
            final statusName = project.statusName;
            Color color;
            switch (status) {
              case 'active':
                color = Colors.green;
                break;
              case 'completed':
                color = Colors.blue;
                break;
              case 'on_hold':
                color = Colors.orange;
                break;
              case 'cancelled':
                color = Colors.red;
                break;
              default:
                color = Colors.grey;
            }
            
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(
                statusName,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          },
        ),
        DateColumn(
          'start_date',
          'تاریخ شروع',
          width: ColumnWidth.small,
          formatter: (item) {
            final project = item as ProjectModel;
            return project.startDate?.toString() ?? '';
          },
        ),
        DateColumn(
          'end_date',
          'تاریخ پایان',
          width: ColumnWidth.small,
          formatter: (item) {
            final project = item as ProjectModel;
            return project.endDate?.toString() ?? '';
          },
        ),
        CustomColumn(
          'person_name',
          'مشتری/تامین‌کننده',
          width: ColumnWidth.medium,
          builder: (item, index) {
            final project = item as ProjectModel;
            return Text(project.personName ?? '-');
          },
        ),
        CustomColumn(
          'manager_name',
          'مدیر پروژه',
          width: ColumnWidth.medium,
          builder: (item, index) {
            final project = item as ProjectModel;
            return Text(project.managerName ?? '-');
          },
        ),
        CustomColumn(
          'budget',
          'بودجه',
          width: ColumnWidth.medium,
          builder: (item, index) {
            final project = item as ProjectModel;
            if (project.budget == null) return const Text('-');
            return Text('${project.budget!.toStringAsFixed(0)} ${project.currencySymbol ?? ''}');
          },
        ),
        DateColumn(
          'created_at',
          'تاریخ ایجاد',
          width: ColumnWidth.medium,
          formatter: (item) {
            final project = item as ProjectModel;
            return project.createdAt.toString();
          },
        ),
        ActionColumn(
          'actions',
          'عملیات',
          width: ColumnWidth.small,
          actions: [
            DataTableAction(
              icon: Icons.visibility,
              label: 'مشاهده',
              onTap: _onViewProject,
            ),
            DataTableAction(
              icon: Icons.edit,
              label: 'ویرایش',
              onTap: _onEditProject,
            ),
            DataTableAction(
              icon: Icons.delete,
              label: 'حذف',
              onTap: _onDeleteProject,
              isDestructive: true,
            ),
          ],
        ),
      ],
      enableRowSelection: true,
      showExportButtons: true,
      httpMethod: 'GET',
      expandBodyHeightToFitRows: true,
    );
  }

  void _onAddProject() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ProjectFormDialog(
        businessId: widget.businessId,
        calendarController: widget.calendarController,
        onSuccess: () {
          _refreshData();
        },
      ),
    );
    
    if (result == true) {
      _refreshData();
    }
  }

  void _onViewProject(dynamic item) async {
    if (item is! ProjectModel) return;
    final projectId = item.id;
    
    try {
      final result = await _projectService.getProject(projectId);
      
      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('جزئیات پروژه: ${result['project']['name']}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildInfoRow('کد', result['project']['code']),
                _buildInfoRow('وضعیت', result['project']['status_name']),
                _buildInfoRow('تعداد اسناد', result['statistics']['total_documents'].toString()),
                _buildInfoRow('مجموع بدهکار', result['statistics']['total_debit'].toString()),
                _buildInfoRow('مجموع بستانکار', result['statistics']['total_credit'].toString()),
                _buildInfoRow('مانده', result['statistics']['balance'].toString()),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('بستن'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا در دریافت اطلاعات پروژه');
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _onEditProject(dynamic item) async {
    if (item is! ProjectModel) return;
    final projectId = item.id;
    
    try {
      // دریافت اطلاعات کامل پروژه
      final response = await _projectService.getProject(projectId);
      final projectData = response['project'] as Map<String, dynamic>;
      final project = ProjectModel.fromJson(projectData);
      
      if (!mounted) return;
      
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => ProjectFormDialog(
          businessId: widget.businessId,
          calendarController: widget.calendarController,
          project: project,
          onSuccess: () {
            _refreshData();
          },
        ),
      );
      
      if (result == true) {
        _refreshData();
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا در دریافت اطلاعات پروژه: ${e.toString()}');
    }
  }

  void _onDeleteProject(dynamic item) async {
    if (item is! ProjectModel) return;
    final projectId = item.id;
    final projectName = item.name;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف پروژه'),
        content: Text('آیا از حذف پروژه "$projectName" اطمینان دارید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _projectService.deleteProject(projectId);
      
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'پروژه با موفقیت حذف شد');
      _refreshData();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا در حذف پروژه: ${e.toString()}');
    }
  }

  void _onBulkDelete(List<dynamic> selectedItems) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف گروهی'),
        content: Text('آیا از حذف ${selectedItems.length} پروژه اطمینان دارید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('حذف همه'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    int successCount = 0;
    int errorCount = 0;

    for (final item in selectedItems) {
      try {
        final projectId = item['id'] as int;
        await _projectService.deleteProject(projectId);
        successCount++;
      } catch (e) {
        errorCount++;
      }
    }

    if (!mounted) return;
    
    if (errorCount == 0) {
      SnackBarHelper.showSuccess(context, message: '$successCount پروژه با موفقیت حذف شد');
    } else {
      SnackBarHelper.showWarning(
        context,
        message: '$successCount موفقیت، $errorCount خطا',
      );
    }
    
    _refreshData();
  }
}

