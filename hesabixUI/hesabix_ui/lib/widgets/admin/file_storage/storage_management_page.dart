import 'package:flutter/material.dart';
import 'storage_config_list_widget.dart';
import 'storage_config_form_dialog.dart';
import '../../../utils/snackbar_helper.dart';

class StorageManagementPage extends StatefulWidget {
  const StorageManagementPage({super.key});

  @override
  State<StorageManagementPage> createState() => _StorageManagementPageState();
}

class _StorageManagementPageState extends State<StorageManagementPage> {
  final GlobalKey<StorageConfigListWidgetState> _listKey = GlobalKey<StorageConfigListWidgetState>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'پیکربندی‌های ذخیره‌سازی',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onPrimary,
          ),
        ),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.1),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: StorageConfigListWidget(
          key: _listKey,
          onRefresh: () => _listKey.currentState?.loadStorageConfigs(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('ایجاد پیکربندی ذخیره‌سازی'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => StorageConfigFormDialog(
        onSaved: () {
          // Refresh the list
          _listKey.currentState?.loadStorageConfigs();
          // Show success message
          SnackBarHelper.showSuccess(context, message: 'تنظیمات ذخیره‌سازی ایجاد شد');
        },
      ),
    );
  }
}
