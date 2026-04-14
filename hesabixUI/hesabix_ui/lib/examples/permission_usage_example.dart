import 'package:flutter/material.dart';
import '../core/auth_store.dart';
import '../widgets/permission/permission_widgets.dart';

/// مثال کامل از نحوه استفاده از سیستم دسترسی‌ها
class PermissionUsageExample extends StatelessWidget {
  final AuthStore authStore;

  const PermissionUsageExample({
    super.key,
    required this.authStore,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مثال استفاده از سیستم دسترسی‌ها'),
        actions: [
          // دکمه اضافه کردن فقط در صورت داشتن دسترسی
          PermissionButton(
            section: 'people',
            action: 'add',
            authStore: authStore,
            child: IconButton(
              onPressed: () => _addPerson(),
              icon: const Icon(Icons.add),
              tooltip: 'اضافه کردن شخص',
            ),
          ),
          
          // دکمه ویرایش فقط در صورت داشتن دسترسی
          PermissionButton(
            section: 'people',
            action: 'edit',
            authStore: authStore,
            child: IconButton(
              onPressed: () => _editPerson(),
              icon: const Icon(Icons.edit),
              tooltip: 'ویرایش شخص',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // لیست اشخاص با بررسی دسترسی‌ها
          Expanded(
            child: ListView.builder(
              itemCount: 10, // مثال
              itemBuilder: (context, index) {
                return PermissionListTile(
                  section: 'people',
                  action: 'view',
                  authStore: authStore,
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.person),
                    ),
                    title: Text('شخص ${index + 1}'),
                    subtitle: const Text('توضیحات شخص'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // دکمه ویرایش
                        PermissionButton(
                          section: 'people',
                          action: 'edit',
                          authStore: authStore,
                          child: IconButton(
                            onPressed: () => _editPerson(),
                            icon: const Icon(Icons.edit),
                            tooltip: 'ویرایش',
                          ),
                        ),
                        
                        // دکمه حذف
                        PermissionButton(
                          section: 'people',
                          action: 'delete',
                          authStore: authStore,
                          child: IconButton(
                            onPressed: () => _deletePerson(),
                            icon: const Icon(Icons.delete),
                            tooltip: 'حذف',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          // دکمه‌های عملیات
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // دکمه گزارش
                PermissionButton(
                  section: 'reports',
                  action: 'view',
                  authStore: authStore,
                  child: ElevatedButton.icon(
                    onPressed: () => _viewReports(),
                    icon: const Icon(Icons.assessment),
                    label: const Text('مشاهده گزارش‌ها'),
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // دکمه صادرات
                PermissionButton(
                  section: 'reports',
                  action: 'export',
                  authStore: authStore,
                  child: ElevatedButton.icon(
                    onPressed: () => _exportReports(),
                    icon: const Icon(Icons.download),
                    label: const Text('صادرات گزارش'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addPerson() {
    // منطق اضافه کردن شخص
  }

  void _editPerson() {
    // منطق ویرایش شخص
  }

  void _deletePerson() {
    // منطق حذف شخص
  }

  void _viewReports() {
    // منطق مشاهده گزارش‌ها
  }

  void _exportReports() {
    // منطق صادرات گزارش
  }
}

/// مثال استفاده از PermissionWidget
class ExamplePermissionWidget extends StatelessWidget {
  final AuthStore authStore;

  const ExamplePermissionWidget({
    super.key,
    required this.authStore,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // نمایش ویجت فقط در صورت داشتن دسترسی
        PermissionWidget(
          section: 'settings',
          action: 'view',
          authStore: authStore,
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('تنظیمات'),
              subtitle: const Text('مدیریت تنظیمات سیستم'),
              onTap: () => _openSettings(),
            ),
          ),
        ),
        
        // نمایش پیام عدم دسترسی در صورت عدم دسترسی
        PermissionWidget(
          section: 'admin',
          action: 'view',
          authStore: authStore,
          fallbackWidget: const AccessDeniedWidget(
            message: 'شما دسترسی لازم برای مشاهده پنل مدیریت را ندارید',
            icon: Icons.admin_panel_settings,
          ),
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: const Text('پنل مدیریت'),
              subtitle: const Text('دسترسی به پنل مدیریت'),
              onTap: () => _openAdminPanel(),
            ),
          ),
        ),
      ],
    );
  }

  void _openSettings() {
  }

  void _openAdminPanel() {
  }
}
