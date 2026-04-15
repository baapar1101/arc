import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../../core/api_client.dart';
import '../../../services/errors/api_error.dart';
import '../../../utils/number_normalizer.dart';
import '../../../utils/snackbar_helper.dart';

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
  bool _testingFtp = false;
  bool _useTls = false;
  bool _ftpPassive = true;
  bool _hasStoredFtpPassword = false;

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
      _ftpPasswordController.clear();
      _ftpDirectoryController.text = configData['directory'] ?? '/';
      _useTls = configData['use_tls'] == true;
      _ftpPassive = configData['passive'] != false;
      _hasStoredFtpPassword = configData['has_password'] == true;
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

  String _formatApiError(Object e, AppLocalizations t) {
    if (e is DioException && e.error is ApiErrorDetails) {
      return (e.error! as ApiErrorDetails).message ?? e.message ?? t.error;
    }
    if (e is DioException && e.response?.data is Map) {
      final d = e.response!.data as Map<String, dynamic>;
      final err = d['error'] ?? d['detail'];
      if (err is Map && err['message'] is String) {
        return err['message'] as String;
      }
      if (d['message'] is String) {
        return d['message'] as String;
      }
    }
    return e.toString();
  }

  Future<void> _testFtpConnection(AppLocalizations t) async {
    if (_selectedStorageType != 'ftp') return;

    final host = _ftpHostController.text.trim();
    final username = _ftpUsernameController.text.trim();
    final port = int.tryParse(_ftpPortController.text.trim());
    if (host.isEmpty || username.isEmpty) {
      SnackBarHelper.showError(context, message: t.fixFormErrors);
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      SnackBarHelper.showError(context, message: t.invalidPort);
      return;
    }
    final pw = _ftpPasswordController.text.trim();
    if (widget.config == null && pw.isEmpty) {
      SnackBarHelper.showError(context, message: t.fixFormErrors);
      return;
    }
    if (widget.config != null && pw.isEmpty && !_hasStoredFtpPassword) {
      SnackBarHelper.showError(context, message: t.fixFormErrors);
      return;
    }

    setState(() => _testingFtp = true);
    try {
      final api = ApiClient();
      final dir = _ftpDirectoryController.text.trim().isEmpty ? '/' : _ftpDirectoryController.text.trim();
      final cd = <String, dynamic>{
        'host': host,
        'port': port,
        'username': username,
        'directory': dir,
        'use_tls': _useTls,
        'passive': _ftpPassive,
      };
      if (pw.isNotEmpty) {
        cd['password'] = pw;
      }
      final res = await api.post<Map<String, dynamic>>(
        '/api/v1/admin/files/storage-configs/ftp/test-draft',
        data: <String, dynamic>{
          'config_data': cd,
          if (widget.config != null) 'existing_config_id': widget.config!['id'],
        },
      );
      if (!mounted) return;
      final root = res.data;
      if (root == null || root['success'] != true) {
        SnackBarHelper.showError(context, message: t.adminStorageTestFailed);
        return;
      }
      final inner = root['data'];
      Map<String, dynamic>? payload;
      if (inner is Map) {
        payload = Map<String, dynamic>.from(inner);
      }
      final testResult = payload?['test_result'];
      final success = testResult is Map && testResult['success'] == true;
      if (success) {
        SnackBarHelper.showSuccess(context, message: t.adminStorageTestSuccess);
      } else {
        final err = testResult is Map ? (testResult['error'] as String?) : null;
        SnackBarHelper.showError(
          context,
          message: err != null && err.isNotEmpty ? '${t.adminStorageTestFailed}: $err' : t.adminStorageTestFailed,
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: _formatApiError(e, t));
      }
    } finally {
      if (mounted) {
        setState(() => _testingFtp = false);
      }
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final t = AppLocalizations.of(context);
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
          'directory': _ftpDirectoryController.text.trim().isEmpty ? '/' : _ftpDirectoryController.text.trim(),
          'use_tls': _useTls,
          'passive': _ftpPassive,
        };
        final pw = _ftpPasswordController.text.trim();
        if (pw.isNotEmpty) {
          configData['password'] = pw;
        }
      }

      final requestData = {
        'name': _nameController.text.trim(),
        'storage_type': _selectedStorageType,
        'config_data': configData,
        'is_default': _isDefault,
        'is_active': _isActive,
      };

      if (widget.config != null) {
        await api.put(
          '/api/v1/admin/files/storage-configs/${widget.config!['id']}',
          data: requestData,
        );
      } else {
        await api.post(
          '/api/v1/admin/files/storage-configs/',
          data: requestData,
        );
      }

      if (!mounted) return;

      if (widget.onSaved == null) {
        SnackBarHelper.showSuccess(
          context,
          message: widget.config != null ? t.storageConfigUpdated : t.storageConfigCreated,
        );
      }
      widget.onSaved?.call();
      context.pop();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: _formatApiError(e, t));
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
    final busy = _isLoading || _testingFtp;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                          isEditing ? l10n.adminStorageEditTitle : l10n.adminStorageCreateTitle,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: busy ? null : () => context.pop(),
                        icon: const Icon(Icons.close),
                        color: theme.colorScheme.onPrimary,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(context, l10n.adminStorageFormSectionBasic),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: l10n.configurationName,
                              hintText: l10n.adminStorageNameHint,
                              prefixIcon: const Icon(Icons.label_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return l10n.fixFormErrors;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
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
                                  onChanged: busy
                                      ? null
                                      : (value) => setState(() => _selectedStorageType = value!),
                                ),
                                title: Text(l10n.localStorage),
                                trailing: const Icon(Icons.storage, size: 20),
                                onTap: busy ? null : () => setState(() => _selectedStorageType = 'local'),
                                contentPadding: EdgeInsets.zero,
                              ),
                              ListTile(
                                leading: Radio<String>(
                                  value: 'ftp',
                                  // ignore: deprecated_member_use
                                  groupValue: _selectedStorageType,
                                  // ignore: deprecated_member_use
                                  onChanged: busy
                                      ? null
                                      : (value) => setState(() => _selectedStorageType = value!),
                                ),
                                title: Text(l10n.adminStorageFtpServerTitle),
                                trailing: const Icon(Icons.cloud_upload, size: 20),
                                onTap: busy ? null : () => setState(() => _selectedStorageType = 'ftp'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                          if (_selectedStorageType == 'ftp') ...[
                            const SizedBox(height: 8),
                            Text(
                              l10n.adminStorageFtpPurposeSubtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          _buildSectionHeader(context, l10n.adminStorageFormSectionDetails),
                          const SizedBox(height: 16),
                          if (_selectedStorageType == 'local') ...[
                            _buildLocalConfigFields(context, l10n),
                          ] else if (_selectedStorageType == 'ftp') ...[
                            _buildFtpConfigFields(context, l10n, theme),
                          ],
                          const SizedBox(height: 24),
                          _buildSectionHeader(context, l10n.adminStorageFormSectionOptions),
                          const SizedBox(height: 16),
                          SwitchListTile(
                            title: Text(l10n.adminStorageDefaultTitle),
                            subtitle: Text(l10n.adminStorageDefaultSubtitle),
                            value: _isDefault,
                            onChanged: busy
                                ? null
                                : (value) {
                                    setState(() {
                                      _isDefault = value;
                                    });
                                  },
                            secondary: const Icon(Icons.star),
                          ),
                          SwitchListTile(
                            title: Text(l10n.adminStorageActiveTitle),
                            subtitle: Text(l10n.adminStorageActiveSubtitle),
                            value: _isActive,
                            onChanged: busy
                                ? null
                                : (value) {
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
                    children: [
                      if (_selectedStorageType == 'ftp')
                        OutlinedButton.icon(
                          onPressed: busy ? null : () => _testFtpConnection(l10n),
                          icon: _testingFtp
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.link),
                          label: Text(
                            _testingFtp ? l10n.adminStorageTestingConnection : l10n.adminStorageTestConnection,
                          ),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: busy ? null : () => context.pop(),
                        child: Text(l10n.cancel),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: busy ? null : _saveConfig,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(isEditing ? Icons.save : Icons.add),
                        label: Text(
                          _isLoading
                              ? l10n.adminStorageSaveInProgress
                              : (isEditing ? l10n.adminStorageUpdateButton : l10n.adminStorageCreateButton),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (busy)
              Positioned.fill(
                child: AbsorbPointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
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

  Widget _buildLocalConfigFields(BuildContext context, AppLocalizations l10n) {
    return TextFormField(
      controller: _basePathController,
      decoration: InputDecoration(
        labelText: l10n.adminStorageLocalBasePath,
        hintText: '/var/hesabix_files',
        prefixIcon: const Icon(Icons.folder_outlined),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return l10n.fixFormErrors;
        }
        return null;
      },
    );
  }

  Widget _buildFtpConfigFields(BuildContext context, AppLocalizations l10n, ThemeData theme) {
    final portHint = _useTls ? l10n.adminStorageFtpPortHintTls : l10n.adminStorageFtpPortHintPlain;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_useTls) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.adminStorageFtpInsecureWarning,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 480;
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ftpHostField(l10n),
                  const SizedBox(height: 16),
                  _ftpPortField(l10n, portHint),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _ftpHostField(l10n)),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: _ftpPortField(l10n, portHint)),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _ftpUsernameController,
          decoration: InputDecoration(
            labelText: l10n.username,
            prefixIcon: const Icon(Icons.person),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return l10n.fixFormErrors;
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _ftpPasswordController,
          decoration: InputDecoration(
            labelText: l10n.password,
            hintText: widget.config != null && _hasStoredFtpPassword ? l10n.adminStorageFtpPasswordOptionalHint : null,
            prefixIcon: const Icon(Icons.lock),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          obscureText: true,
          validator: (value) {
            final v = value?.trim() ?? '';
            if (widget.config == null && v.isEmpty) {
              return l10n.fixFormErrors;
            }
            if (widget.config != null && v.isEmpty && !_hasStoredFtpPassword) {
              return l10n.fixFormErrors;
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _ftpDirectoryController,
          decoration: InputDecoration(
            labelText: l10n.adminStorageFtpDirectoryLabel,
            hintText: l10n.adminStorageFtpDirectoryHint,
            prefixIcon: const Icon(Icons.folder),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: Text(l10n.adminStorageFtpPassive),
          value: _ftpPassive,
          onChanged: _isLoading || _testingFtp ? null : (v) => setState(() => _ftpPassive = v),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: Text(l10n.adminStorageFtpUseTlsTitle),
          subtitle: Text(l10n.adminStorageFtpUseTlsSubtitle),
          value: _useTls,
          onChanged: _isLoading || _testingFtp
              ? null
              : (value) {
                  setState(() {
                    _useTls = value;
                  });
                },
          secondary: const Icon(Icons.security),
        ),
      ],
    );
  }

  Widget _ftpHostField(AppLocalizations l10n) {
    return TextFormField(
      controller: _ftpHostController,
      decoration: InputDecoration(
        labelText: l10n.adminStorageFtpHostLabel,
        hintText: l10n.adminStorageFtpHostHint,
        prefixIcon: const Icon(Icons.dns),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return l10n.fixFormErrors;
        }
        return null;
      },
    );
  }

  Widget _ftpPortField(AppLocalizations l10n, String portHint) {
    return TextFormField(
      controller: _ftpPortController,
      decoration: InputDecoration(
        labelText: l10n.smtpPort,
        hintText: _useTls ? '990' : '21',
        helperText: portHint,
        prefixIcon: const Icon(Icons.settings_ethernet),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        EnglishDigitsFormatter(),
        FilteringTextInputFormatter.digitsOnly,
      ],
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return l10n.fixFormErrors;
        }
        final port = int.tryParse(value);
        if (port == null || port < 1 || port > 65535) {
          return l10n.invalidPort;
        }
        return null;
      },
    );
  }

}
