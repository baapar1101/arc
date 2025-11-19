import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/admin/file_storage/storage_config_form_dialog.dart';
import 'package:hesabix_ui/widgets/admin/file_storage/storage_config_card.dart';
import '../../../core/api_client.dart';
import '../../../l10n/app_localizations.dart';

class StorageConfigListWidget extends StatefulWidget {
  final VoidCallback? onRefresh;
  
  const StorageConfigListWidget({
    super.key,
    this.onRefresh,
  });

  @override
  State<StorageConfigListWidget> createState() => StorageConfigListWidgetState();
}

class StorageConfigListWidgetState extends State<StorageConfigListWidget> {
  List<Map<String, dynamic>> _storageConfigs = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    loadStorageConfigs();
  }

  Future<void> loadStorageConfigs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ApiClient();
      final response = await api.get('/api/v1/admin/files/storage-configs/');
      
      if (response.data != null && response.data['success'] == true) {
        setState(() {
          _storageConfigs = (response.data['data']['configs'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      } else {
        throw Exception(response.data?['message'] ?? 'خطا در دریافت تنظیمات ذخیره‌سازی');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _testConnection(String configId) async {
    try {
      final api = ApiClient();
      final response = await api.post('/api/v1/admin/files/storage-configs/$configId/test');
      
      if (!mounted) return;
      if (response.data != null && response.data['success'] == true) {
        final testResult = response.data['data']['test_result'];
        if (testResult['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('اتصال موفقیت‌آمیز بود'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('اتصال ناموفق: ${testResult['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        throw Exception(response.data?['message'] ?? 'خطا در تست اتصال');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('اتصال ناموفق: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteConfig(String configId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تأیید حذف'),
        content: Text('آیا از حذف این پیکربندی اطمینان دارید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('لغو'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final api = ApiClient();
        final response = await api.delete('/api/v1/admin/files/storage-configs/$configId');
        
        if (!mounted) return;
        if (response.data != null && response.data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فایل حذف شد'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Refresh the list
          loadStorageConfigs();
        } else {
          final errorMessage = response.data?['error']?['message'] ?? 
                              response.data?['message'] ?? 
                              'خطا در حذف تنظیمات';
          throw Exception(errorMessage);
        }
      } catch (e) {
        if (!context.mounted) return;
        final ctx = context;
        String errorMessage = AppLocalizations.of(ctx).error;
        
        // بررسی نوع خطا
        if (e.toString().contains('STORAGE_CONFIG_HAS_FILES')) {
          errorMessage = AppLocalizations.of(ctx).cannotDeleteDefault;
        } else if (e.toString().contains('STORAGE_CONFIG_NOT_FOUND')) {
          errorMessage = AppLocalizations.of(ctx).noEmailConfigurations;
        } else if (e.toString().contains('FORBIDDEN')) {
          errorMessage = AppLocalizations.of(ctx).accessDenied;
        } else {
          errorMessage = e.toString().replaceFirst('Exception: ', '');
        }
        
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _setAsDefault(String configId) async {
    try {
      final api = ApiClient();
      final response = await api.put('/api/v1/admin/files/storage-configs/$configId/set-default');
      
      if (!context.mounted) return;
      final ctx = context;
      if (response.data != null && response.data['success'] == true) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(ctx).defaultSetSuccessfully),
              backgroundColor: Colors.green,
            ),
          );
        
        // Refresh the list
        loadStorageConfigs();
      } else {
        throw Exception(response.data?['message'] ?? AppLocalizations.of(ctx).defaultSetFailed);
      }
    } catch (e) {
      if (!context.mounted) return;
      final ctx2 = context;
      ScaffoldMessenger.of(ctx2).showSnackBar(
        SnackBar(
          content: Text('${AppLocalizations.of(ctx2).defaultSetFailed}: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _editStorageConfig(Map<String, dynamic> config) {
    showDialog(
      context: context,
      builder: (context) => StorageConfigFormDialog(
        config: config,
        onSaved: () {
          loadStorageConfigs();
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تنظیمات ذخیره‌سازی به‌روزرسانی شد'),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'در حال بارگذاری...',
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'خطا',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: loadStorageConfigs,
              icon: const Icon(Icons.refresh),
              label: Text('تلاش مجدد'),
            ),
          ],
        ),
      );
    }

    if (_storageConfigs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.storage_outlined,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'هیچ پیکربندی ذخیره‌سازی وجود ندارد',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'اولین پیکربندی ذخیره‌سازی را ایجاد کنید',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Text(
              'از دکمه + در پایین صفحه استفاده کنید',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: loadStorageConfigs,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.storage,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'پیکربندی‌های ذخیره‌سازی',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_storageConfigs.length} پیکربندی',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Storage Configs List
            Expanded(
              child: ListView.builder(
                itemCount: _storageConfigs.length,
                itemBuilder: (context, index) {
                  final config = _storageConfigs[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: StorageConfigCard(
                      config: config,
                      onEdit: () => _editStorageConfig(config),
                      onSetDefault: config['is_default'] == false
                          ? () => _setAsDefault(config['id'])
                          : null,
                      onTestConnection: () => _testConnection(config['id']),
                      onDelete: () => _deleteConfig(config['id']),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}