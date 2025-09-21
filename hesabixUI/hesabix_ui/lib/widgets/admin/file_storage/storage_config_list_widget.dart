import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/widgets/admin/file_storage/storage_config_form_dialog.dart';
import 'package:hesabix_ui/widgets/admin/file_storage/storage_config_card.dart';
import '../../../core/api_client.dart';

class StorageConfigListWidget extends StatefulWidget {
  const StorageConfigListWidget({super.key});

  @override
  State<StorageConfigListWidget> createState() => _StorageConfigListWidgetState();
}

class _StorageConfigListWidgetState extends State<StorageConfigListWidget> {
  List<Map<String, dynamic>> _storageConfigs = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStorageConfigs();
  }

  Future<void> _loadStorageConfigs() async {
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


  Future<void> _addStorageConfig() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const StorageConfigFormDialog(),
    );

    if (result != null) {
      _loadStorageConfigs();
    }
  }

  Future<void> _editStorageConfig(Map<String, dynamic> config) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StorageConfigFormDialog(config: config),
    );

    if (result != null) {
      _loadStorageConfigs();
    }
  }

  Future<void> _setAsDefault(String configId) async {
    final l10n = AppLocalizations.of(context);
    try {
      // TODO: Call API to set as default
      await Future.delayed(const Duration(seconds: 1)); // Simulate API call
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.setAsDefault),
          backgroundColor: Colors.green,
        ),
      );
      
      _loadStorageConfigs();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _testConnection(String configId) async {
    final l10n = AppLocalizations.of(context);
    try {
      final api = ApiClient();
      final response = await api.post('/api/v1/admin/files/storage-configs/$configId/test');
      
      if (response.data != null && response.data['success'] == true) {
        final testResult = response.data['data']['test_result'];
        if (testResult['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.connectionSuccessful),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l10n.connectionFailed}: ${testResult['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        throw Exception(response.data?['message'] ?? 'خطا در تست اتصال');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.connectionFailed}: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  Future<void> _deleteConfig(String configId) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteConfirm),
        content: Text(l10n.deleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // TODO: Call API to delete config
        await Future.delayed(const Duration(seconds: 1)); // Simulate API call
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.fileDeleted),
            backgroundColor: Colors.green,
          ),
        );
        
        _loadStorageConfigs();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
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
              _error!,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadStorageConfigs,
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.storageConfigurations,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _addStorageConfig,
                icon: const Icon(Icons.add),
                label: Text(l10n.addStorageConfig),
              ),
            ],
          ),
        ),
        Expanded(
          child: _storageConfigs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.storage_outlined,
                        size: 64,
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.noFilesFound,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _storageConfigs.length,
                  itemBuilder: (context, index) {
                    final config = _storageConfigs[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: StorageConfigCard(
                        config: config,
                        onEdit: () => _editStorageConfig(config),
                        onSetDefault: config['is_default'] == false
                            ? () => _setAsDefault(config['id'])
                            : null,
                        onTestConnection: () => _testConnection(config['id']),
                        onDelete: config['is_default'] == false
                            ? () => _deleteConfig(config['id'])
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
