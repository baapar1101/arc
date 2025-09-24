import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../../core/api_client.dart';

class StorageConfigFormDialog extends StatefulWidget {
  final Map<String, dynamic>? config;
  final VoidCallback? onSaved;

  const StorageConfigFormDialog({
    super.key,
    this.config,
    this.onSaved,
  });

  @override
  State<StorageConfigFormDialog> createState() => _StorageConfigFormDialogState();
}

class _StorageConfigFormDialogState extends State<StorageConfigFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _basePathController = TextEditingController();
  final _ftpHostController = TextEditingController();
  final _ftpPortController = TextEditingController();
  final _ftpUsernameController = TextEditingController();
  final _ftpPasswordController = TextEditingController();
  final _ftpDirectoryController = TextEditingController();

  String _selectedStorageType = 'local';
  bool _isDefault = false;
  bool _isActive = true;
  bool _isLoading = false;
  bool _useTls = false;

  @override
  void initState() {
    super.initState();
    if (widget.config != null) {
      _loadConfigData();
    }
  }

  void _loadConfigData() {
    final config = widget.config!;
    _nameController.text = config['name'] ?? '';
    _selectedStorageType = config['storage_type'] ?? 'local';
    _isDefault = config['is_default'] == true;
    _isActive = config['is_active'] == true;

    final configData = config['config_data'] ?? {};
    if (_selectedStorageType == 'local') {
      _basePathController.text = configData['base_path'] ?? '';
    } else if (_selectedStorageType == 'ftp') {
      _ftpHostController.text = configData['host'] ?? '';
      _ftpPortController.text = (configData['port'] ?? 21).toString();
      _ftpUsernameController.text = configData['username'] ?? '';
      _ftpPasswordController.text = configData['password'] ?? '';
      _ftpDirectoryController.text = configData['directory'] ?? '/';
      _useTls = configData['use_tls'] == true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _basePathController.dispose();
    _ftpHostController.dispose();
    _ftpPortController.dispose();
    _ftpUsernameController.dispose();
    _ftpPasswordController.dispose();
    _ftpDirectoryController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final api = ApiClient();
      Map<String, dynamic> configData = {};

      if (_selectedStorageType == 'local') {
        configData = {
          'base_path': _basePathController.text.trim(),
        };
      } else if (_selectedStorageType == 'ftp') {
        configData = {
          'host': _ftpHostController.text.trim(),
          'port': int.tryParse(_ftpPortController.text) ?? 21,
          'username': _ftpUsernameController.text.trim(),
          'password': _ftpPasswordController.text,
          'directory': _ftpDirectoryController.text.trim(),
          'use_tls': _useTls,
        };
      }

      final requestData = {
        'name': _nameController.text.trim(),
        'storage_type': _selectedStorageType,
        'config_data': configData,
        'is_default': _isDefault,
        'is_active': _isActive,
      };

      if (widget.config != null) {
        // Update existing config
        await api.put(
          '/api/v1/admin/files/storage-configs/${widget.config!['id']}',
          data: requestData,
        );
      } else {
        // Create new config
        await api.post(
          '/api/v1/admin/files/storage-configs/',
          data: requestData,
        );
      }

      if (mounted) {
        context.pop();
        
        // Only show SnackBar if there's no onSaved callback (parent will handle notification)
        if (widget.onSaved == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.config != null 
                    ? AppLocalizations.of(context).emailConfigUpdatedSuccessfully
                    : AppLocalizations.of(context).emailConfigSavedSuccessfully,
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
        
        widget.onSaved?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context).error}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isEditing = widget.config != null;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
                child: Row(
                  children: [
                    Icon(
                      isEditing ? Icons.edit : Icons.add,
                    color: theme.colorScheme.onPrimary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEditing 
                          ? 'ویرایش پیکربندی ذخیره‌سازی'
                          : 'ایجاد پیکربندی ذخیره‌سازی',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.close),
                    color: theme.colorScheme.onPrimary,
                    ),
                  ],
                ),
              ),
            
            // Form
              Flexible(
                child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Basic Information
                      _buildSectionHeader(context, 'اطلاعات پایه'),
                      const SizedBox(height: 16),
                      
                      // Name
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'نام',
                          hintText: 'نام پیکربندی ذخیره‌سازی را وارد کنید',
                          prefixIcon: const Icon(Icons.label_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'لطفاً نام را وارد کنید';
                          }
                          return null;
                        },
                      ),
                      
                      const SizedBox(height: 16),

                      // Storage Type
                      Text(
                        l10n.storageType,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Column(
                        children: [
                          ListTile(
                            leading: Radio<String>(
                              value: 'local',
                              // ignore: deprecated_member_use
                              groupValue: _selectedStorageType,
                              // ignore: deprecated_member_use
                              onChanged: (value) => setState(() => _selectedStorageType = value!),
                            ),
                            title: Text(l10n.localStorage),
                            trailing: Icon(Icons.storage, size: 20),
                            onTap: () => setState(() => _selectedStorageType = 'local'),
                            contentPadding: EdgeInsets.zero,
                          ),
                          ListTile(
                            leading: Radio<String>(
                              value: 'ftp',
                              // ignore: deprecated_member_use
                              groupValue: _selectedStorageType,
                              // ignore: deprecated_member_use
                              onChanged: (value) => setState(() => _selectedStorageType = value!),
                            ),
                            title: Text('سرور FTP'),
                            trailing: Icon(Icons.cloud_upload, size: 20),
                            onTap: () => setState(() => _selectedStorageType = 'ftp'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Configuration Details
                      _buildSectionHeader(context, 'جزئیات پیکربندی'),
                      const SizedBox(height: 16),

                      if (_selectedStorageType == 'local') ...[
                        _buildLocalConfigFields(context),
                      ] else if (_selectedStorageType == 'ftp') ...[
                        _buildFtpConfigFields(context),
                      ],
                      
                      const SizedBox(height: 24),
                      
                      // Options
                      _buildSectionHeader(context, 'گزینه‌ها'),
                      const SizedBox(height: 16),

                      SwitchListTile(
                        title: Text('تنظیم به عنوان پیش‌فرض'),
                        subtitle: Text('این پیکربندی به عنوان پیش‌فرض تنظیم شود'),
                            value: _isDefault,
                            onChanged: (value) {
                              setState(() {
                            _isDefault = value;
                              });
                            },
                        secondary: const Icon(Icons.star),
                      ),
                      
                      SwitchListTile(
                        title: Text('فعال'),
                        subtitle: Text('این پیکربندی فعال باشد'),
                            value: _isActive,
                            onChanged: (value) {
                              setState(() {
                            _isActive = value;
                              });
                            },
                        secondary: const Icon(Icons.power),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Actions
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading ? null : () => context.pop(),
                      child: Text(l10n.cancel),
                    ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                      onPressed: _isLoading ? null : _saveConfig,
                    icon: _isLoading 
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                        : Icon(isEditing ? Icons.save : Icons.add),
                    label: Text(
                      _isLoading 
                          ? 'در حال ذخیره...'
                          : (isEditing ? 'به‌روزرسانی' : 'ایجاد'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildLocalConfigFields(BuildContext context) {
    
    return Column(
      children: [
        TextFormField(
          controller: _basePathController,
          decoration: InputDecoration(
            labelText: 'مسیر پایه',
            hintText: 'مسیر پایه را وارد کنید',
            prefixIcon: const Icon(Icons.folder_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'لطفاً مسیر پایه را وارد کنید';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildFtpConfigFields(BuildContext context) {
    
    return Column(
      children: [
        TextFormField(
          controller: _ftpHostController,
          decoration: InputDecoration(
            labelText: 'میزبان',
            hintText: 'آدرس میزبان را وارد کنید',
            prefixIcon: const Icon(Icons.dns),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'لطفاً میزبان را وارد کنید';
            }
            return null;
          },
        ),
        
        const SizedBox(height: 16),
        
        TextFormField(
          controller: _ftpPortController,
          decoration: InputDecoration(
            labelText: 'پورت',
            hintText: '21',
            prefixIcon: const Icon(Icons.settings_ethernet),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          keyboardType: TextInputType.number,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'لطفاً پورت را وارد کنید';
            }
            final port = int.tryParse(value);
            if (port == null || port < 1 || port > 65535) {
              return 'لطفاً پورت معتبر وارد کنید';
            }
            return null;
          },
        ),
        
        const SizedBox(height: 16),
        
        TextFormField(
          controller: _ftpUsernameController,
          decoration: InputDecoration(
            labelText: 'نام کاربری',
            hintText: 'نام کاربری را وارد کنید',
            prefixIcon: const Icon(Icons.person),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'لطفاً نام کاربری را وارد کنید';
            }
            return null;
          },
        ),
        
        const SizedBox(height: 16),
        
        TextFormField(
          controller: _ftpPasswordController,
          decoration: InputDecoration(
            labelText: 'رمز عبور',
            hintText: 'رمز عبور را وارد کنید',
            prefixIcon: const Icon(Icons.lock),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          obscureText: true,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'لطفاً رمز عبور را وارد کنید';
            }
            return null;
          },
        ),
        
        const SizedBox(height: 16),
        
        TextFormField(
          controller: _ftpDirectoryController,
          decoration: InputDecoration(
            labelText: 'دایرکتوری',
            hintText: '/',
            prefixIcon: const Icon(Icons.folder),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        SwitchListTile(
          title: Text('استفاده از TLS'),
          subtitle: Text('اتصال امن با TLS فعال شود'),
          value: _useTls,
          onChanged: (value) {
            setState(() {
              _useTls = value;
            });
          },
          secondary: const Icon(Icons.security),
        ),
      ],
    );
  }
}