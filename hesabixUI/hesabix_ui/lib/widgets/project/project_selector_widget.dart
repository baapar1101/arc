import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/models/project_model.dart';
import 'package:hesabix_ui/services/project_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/project/project_form_dialog.dart';

/// ویجت انتخاب پروژه (کمبوباکس)
class ProjectSelectorWidget extends StatefulWidget {
  final int businessId;
  final ApiClient apiClient;
  final int? selectedProjectId;
  final Function(int?) onChanged;
  final bool allowNull;
  final String? labelText;
  final bool enabled;
  final AuthStore? authStore; // برای بررسی دسترسی‌ها
  final CalendarController? calendarController; // برای دیالوگ ایجاد پروژه
  final bool isDense;

  const ProjectSelectorWidget({
    Key? key,
    required this.businessId,
    required this.apiClient,
    this.selectedProjectId,
    required this.onChanged,
    this.allowNull = true,
    this.labelText,
    this.enabled = true,
    this.authStore,
    this.calendarController,
    this.isDense = false,
  }) : super(key: key);

  @override
  State<ProjectSelectorWidget> createState() => _ProjectSelectorWidgetState();
}

class _ProjectSelectorWidgetState extends State<ProjectSelectorWidget> {
  List<ProjectModel> _projects = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final projectService = ProjectService(widget.apiClient);
      final projects = await projectService.listActiveProjects(widget.businessId);

      if (mounted) {
        setState(() {
          _projects = projects;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ErrorExtractor.forContext(e, context);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int?>(
      value: _loading ? null : widget.selectedProjectId,
      isDense: widget.isDense,
      decoration: InputDecoration(
        labelText: widget.labelText ?? 'پروژه',
        border: const OutlineInputBorder(),
        errorText: _error != null ? 'خطا در بارگذاری پروژه‌ها' : null,
        suffixIcon: _buildSuffixIcon(),
        isDense: widget.isDense,
        contentPadding: widget.isDense
            ? const EdgeInsetsDirectional.only(start: 12, top: 10, bottom: 10, end: 12)
            : null,
      ),
      isExpanded: true,
      items: [
        if (widget.allowNull)
          const DropdownMenuItem<int?>(
            value: null,
            child: Text('بدون پروژه'),
          ),
        ..._projects.map((project) {
          return DropdownMenuItem<int?>(
            value: project.id,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${project.code} - ${project.name}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (project.status != 'active')
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getStatusColor(project.status).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      project.statusName,
                      style: TextStyle(
                        fontSize: 10,
                        color: _getStatusColor(project.status),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ],
      onChanged: (widget.enabled && !_loading) ? widget.onChanged : null,
      validator: (value) {
        // می‌توان اعتبارسنجی اضافه کرد
        return null;
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'completed':
        return Colors.blue;
      case 'on_hold':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// همان کنترلر تقویم اپ یا بارگذاری از تنظیمات محلی (مثل سایر فرم‌ها).
  Future<CalendarController> _resolveCalendarController() async {
    final fromWidget = widget.calendarController;
    if (fromWidget != null) return fromWidget;
    final fromApi = ApiClient.getCalendarController();
    if (fromApi != null) return fromApi;
    return CalendarController.load();
  }

  Future<void> _showQuickCreateDialog() async {
    final calendarController = await _resolveCalendarController();

    // ذخیره تعداد پروژه‌های فعلی برای تشخیص پروژه جدید
    final projectsCountBefore = _projects.length;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ProjectFormDialog(
        businessId: widget.businessId,
        calendarController: calendarController,
        onSuccess: () async {
          // بارگذاری مجدد لیست پروژه‌ها
          await _loadProjects();
          
          // اگر پروژه جدیدی اضافه شده، آن را انتخاب می‌کنیم
          if (mounted && _projects.length > projectsCountBefore) {
            // آخرین پروژه در لیست (که احتمالاً همان پروژه جدید است)
            final newProject = _projects.last;
            widget.onChanged(newProject.id);
          }
        },
      ),
    );

    // اگر دیالوگ با موفقیت بسته شد، لیست را refresh می‌کنیم
    if (result == true && mounted) {
      await _loadProjects();
    }
  }

  /// بررسی دسترسی کاربر به ایجاد پروژه
  /// کاربر باید دسترسی به settings با action join یا write داشته باشد
  bool _canCreateProject() {
    // اگر AuthStore موجود نباشد، برای سازگاری با کدهای قدیمی، اجازه می‌دهیم
    if (widget.authStore == null) {
      return true;
    }

    // مالک کسب و کار همیشه دسترسی دارد
    if (widget.authStore!.currentBusiness?.isOwner == true) {
      return true;
    }

    // بررسی دسترسی به settings با action join یا write
    final hasJoin = widget.authStore!.hasBusinessPermission('settings', 'join');
    final hasWrite = widget.authStore!.hasBusinessPermission('settings', 'write');
    
    return hasJoin || hasWrite;
  }

  Widget _buildSuffixIcon() {
    final canCreate = _canCreateProject();
    
    // اگر در حال بارگذاری است، آیکون loading نمایش داده می‌شود
    if (_loading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    // اگر خطا وجود دارد، دکمه refresh و در صورت داشتن دسترسی، دکمه + نمایش داده می‌شود
    if (_error != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canCreate)
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.blue),
              onPressed: widget.enabled ? _showQuickCreateDialog : null,
              tooltip: 'ایجاد پروژه جدید',
              iconSize: 24,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProjects,
            tooltip: 'تلاش مجدد',
          ),
        ],
      );
    }

    // در حالت عادی، دکمه + و در صورت خالی بودن لیست، آیکون warning
    if (_projects.isEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canCreate)
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.blue),
              onPressed: widget.enabled ? _showQuickCreateDialog : null,
              tooltip: 'ایجاد پروژه جدید',
              iconSize: 24,
            ),
          const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
        ],
      );
    }

    // در حالت عادی، فقط دکمه + (اگر دسترسی داشته باشد)
    if (canCreate) {
      return IconButton(
        icon: const Icon(Icons.add_circle, color: Colors.blue),
        onPressed: widget.enabled ? _showQuickCreateDialog : null,
        tooltip: 'ایجاد پروژه جدید',
        iconSize: 24,
      );
    }

    // اگر دسترسی نداشته باشد، هیچ آیکونی نمایش داده نمی‌شود
    return const SizedBox.shrink();
  }
}

