import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class StorageConfigCard extends StatelessWidget {
  final Map<String, dynamic> config;
  final VoidCallback? onEdit;
  final VoidCallback? onSetDefault;
  final VoidCallback? onTestConnection;
  final VoidCallback? onDelete;

  const StorageConfigCard({
    super.key,
    required this.config,
    this.onEdit,
    this.onSetDefault,
    this.onTestConnection,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDefault = config['is_default'] == true;
    final isActive = config['is_active'] == true;
    final storageType = config['storage_type'] ?? 'unknown';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isDefault 
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: isDefault 
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.05),
                    theme.colorScheme.primary.withValues(alpha: 0.02),
                  ],
                )
              : null,
        ),
      child: Padding(
          padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              // Header
            Row(
              children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getStorageColor(storageType).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getStorageIcon(storageType),
                      color: _getStorageColor(storageType),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                    child: Text(
                                config['name'] ?? 'Unknown',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                            if (isDefault) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                                      Icons.star,
                  size: 16,
                                      color: theme.colorScheme.onPrimary,
                ),
                const SizedBox(width: 4),
                Text(
                                      'پیش‌فرض',
                  style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
              ],
            ),
            const SizedBox(height: 4),
              Row(
                children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getStorageColor(storageType),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _getStorageTypeName(storageType),
                    style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                    ),
                  ),
                  const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isActive ? Colors.green : Colors.red,
                                borderRadius: BorderRadius.circular(8),
                              ),
                    child: Text(
                                isActive ? 'فعال' : 'غیرفعال',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              // Configuration details
              _buildConfigDetails(context, config),
              
              const SizedBox(height: 20),
              
              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onTestConnection != null)
                    _buildActionButton(
                      context: context,
                      icon: Icons.wifi_protected_setup,
                      label: l10n.testConnection,
                      onPressed: onTestConnection!,
                      color: theme.colorScheme.primary,
                    ),
                  if (onEdit != null) ...[
                    const SizedBox(width: 8),
                    _buildActionButton(
                      context: context,
                      icon: Icons.edit,
                      label: l10n.edit,
                      onPressed: onEdit!,
                      color: theme.colorScheme.secondary,
                    ),
                  ],
                  if (onSetDefault != null) ...[
                    const SizedBox(width: 8),
                    _buildActionButton(
                      context: context,
                      icon: Icons.star,
                      label: l10n.setAsDefault,
                      onPressed: onSetDefault!,
                      color: Colors.orange,
                    ),
                  ],
                  if (onDelete != null) ...[
                    const SizedBox(width: 8),
                    _buildActionButton(
                      context: context,
                      icon: Icons.delete,
                      label: l10n.delete,
                      onPressed: onDelete!,
                      color: theme.colorScheme.error,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildConfigDetails(BuildContext context, Map<String, dynamic> config) {
    final theme = Theme.of(context);
    final configData = config['config_data'] ?? {};
    final storageType = config['storage_type'];

    if (storageType == 'local') {
      return _buildLocalConfigDetails(context, configData);
    } else if (storageType == 'ftp') {
      return _buildFtpConfigDetails(context, configData);
    } else {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'نوع ذخیره‌سازی نامشخص',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      );
    }
  }

  Widget _buildLocalConfigDetails(BuildContext context, Map<String, dynamic> configData) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final basePath = configData['base_path'] ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              Row(
                children: [
                  Icon(
                Icons.folder_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
                  Text(
                'پیکربندی ذخیره‌سازی محلی',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.basePath,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    basePath,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFtpConfigDetails(BuildContext context, Map<String, dynamic> configData) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final host = configData['host'] ?? '';
    final port = configData['port'] ?? 21;
    final username = configData['username'] ?? '';
    final directory = configData['directory'] ?? '/';
    final useTls = configData['use_tls'] == true;
    final passive = configData['passive'] != false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'پیکربندی FTP',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildConfigRow(
            context,
            Icons.dns,
            'میزبان',
            host,
          ),
          const SizedBox(height: 8),
          _buildConfigRow(
            context,
            Icons.settings_ethernet,
            'پورت',
            port.toString(),
          ),
          const SizedBox(height: 8),
          _buildConfigRow(
            context,
            Icons.person,
            l10n.username,
            username,
          ),
          const SizedBox(height: 8),
          _buildConfigRow(
            context,
            Icons.folder,
            'دایرکتوری',
            directory,
          ),
          const SizedBox(height: 8),
          _buildConfigRow(
            context,
            Icons.security,
            'امنیت',
            useTls ? 'TLS فعال' : 'TLS غیرفعال',
          ),
          const SizedBox(height: 8),
          _buildConfigRow(
            context,
            Icons.router_outlined,
            l10n.adminStorageFtpPassive,
            passive ? l10n.yes : l10n.no,
          ),
        ],
      ),
    );
  }

  Widget _buildConfigRow(BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  IconData _getStorageIcon(String storageType) {
    switch (storageType) {
      case 'local':
        return Icons.storage;
      case 'ftp':
        return Icons.cloud_upload;
      default:
        return Icons.help_outline;
    }
  }

  Color _getStorageColor(String storageType) {
    switch (storageType) {
      case 'local':
        return Colors.blue;
      case 'ftp':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getStorageTypeName(String storageType) {
    switch (storageType) {
      case 'local':
        return 'Local Storage';
      case 'ftp':
        return 'FTP Server';
      default:
        return 'Unknown';
    }
  }
}