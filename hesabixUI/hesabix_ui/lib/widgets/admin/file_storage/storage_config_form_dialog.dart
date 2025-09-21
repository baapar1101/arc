import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../../core/api_client.dart';

class StorageConfigFormDialog extends StatefulWidget {
  final Map<String, dynamic>? config;

  const StorageConfigFormDialog({
    super.key,
    this.config,
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
      _ftpPortController.text = configData['port']?.toString() ?? '21';
      _ftpUsernameController.text = configData['username'] ?? '';
      _ftpPasswordController.text = configData['password'] ?? '';
      _ftpDirectoryController.text = configData['directory'] ?? '';
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

  Map<String, dynamic> _buildConfigData() {
    if (_selectedStorageType == 'local') {
      return {
        'base_path': _basePathController.text,
      };
    } else if (_selectedStorageType == 'ftp') {
      return {
        'host': _ftpHostController.text,
        'port': int.tryParse(_ftpPortController.text) ?? 21,
        'username': _ftpUsernameController.text,
        'password': _ftpPasswordController.text,
        'directory': _ftpDirectoryController.text,
      };
    }
    return {};
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final api = ApiClient();
      final response = await api.post(
        '/api/v1/admin/files/storage-configs/',
        data: {
          'name': _nameController.text,
          'storage_type': _selectedStorageType,
          'is_default': _isDefault,
          'is_active': _isActive,
          'config_data': _buildConfigData(),
        },
      );

      if (response.data != null && response.data['success'] == true) {
        if (mounted) {
          Navigator.of(context).pop(response.data['data']);
        }
      } else {
        throw Exception(response.data?['message'] ?? 'خطا در ذخیره تنظیمات');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
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
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        constraints: const BoxConstraints(maxWidth: 600),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      isEditing ? Icons.edit : Icons.add,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isEditing ? l10n.editStorageConfig : l10n.addStorageConfig,
                      style: theme.textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: l10n.storageName,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.requiredField;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Storage Type
                      DropdownButtonFormField<String>(
                        value: _selectedStorageType,
                        decoration: InputDecoration(
                          labelText: l10n.storageType,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'local',
                            child: Text(l10n.localStorage),
                          ),
                          DropdownMenuItem(
                            value: 'ftp',
                            child: Text(l10n.ftpStorage),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedStorageType = value!;
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // Configuration based on storage type
                      if (_selectedStorageType == 'local') ...[
                        TextFormField(
                          controller: _basePathController,
                          decoration: InputDecoration(
                            labelText: l10n.basePath,
                            border: const OutlineInputBorder(),
                            hintText: '/var/hesabix/files',
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return l10n.requiredField;
                            }
                            return null;
                          },
                        ),
                      ] else if (_selectedStorageType == 'ftp') ...[
                        TextFormField(
                          controller: _ftpHostController,
                          decoration: InputDecoration(
                            labelText: l10n.ftpHost,
                            border: const OutlineInputBorder(),
                            hintText: 'ftp.example.com',
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return l10n.requiredField;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _ftpPortController,
                          decoration: InputDecoration(
                            labelText: l10n.ftpPort,
                            border: const OutlineInputBorder(),
                            hintText: '21',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return l10n.requiredField;
                            }
                            if (int.tryParse(value) == null) {
                              return 'Invalid port number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _ftpUsernameController,
                          decoration: InputDecoration(
                            labelText: l10n.ftpUsername,
                            border: const OutlineInputBorder(),
                            hintText: 'username',
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return l10n.requiredField;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _ftpPasswordController,
                          decoration: InputDecoration(
                            labelText: l10n.ftpPassword,
                            border: const OutlineInputBorder(),
                            hintText: 'password',
                          ),
                          obscureText: true,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return l10n.requiredField;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _ftpDirectoryController,
                          decoration: InputDecoration(
                            labelText: l10n.ftpDirectory,
                            border: const OutlineInputBorder(),
                            hintText: '/hesabix/files',
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return l10n.requiredField;
                            }
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Options
                      Row(
                        children: [
                          Checkbox(
                            value: _isDefault,
                            onChanged: (value) {
                              setState(() {
                                _isDefault = value ?? false;
                              });
                            },
                          ),
                          Text(l10n.isDefault),
                          const SizedBox(width: 24),
                          Checkbox(
                            value: _isActive,
                            onChanged: (value) {
                              setState(() {
                                _isActive = value ?? false;
                              });
                            },
                          ),
                          Text(l10n.isActive),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                      child: Text(l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _saveConfig,
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.save),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
