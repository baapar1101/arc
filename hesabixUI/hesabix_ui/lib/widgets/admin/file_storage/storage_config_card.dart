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

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  _getStorageIcon(config['storage_type']),
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config['name'] ?? 'Unknown',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getStorageTypeName(config['storage_type']),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                // Status badges
                Row(
                  children: [
                    if (isDefault)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          l10n.isDefault,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimary,
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
                        borderRadius: BorderRadius.circular(12),
                      ),
                        child: Text(
                          isActive ? l10n.isActive : 'غیرفعال',
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
            
            const SizedBox(height: 16),
            
            // Configuration details
            _buildConfigDetails(context, config),
            
            const SizedBox(height: 16),
            
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onTestConnection != null)
                  TextButton.icon(
                    onPressed: onTestConnection,
                    icon: const Icon(Icons.wifi_protected_setup, size: 16),
                    label: Text(l10n.testConnection),
                  ),
                if (onEdit != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 16),
                    label: Text(l10n.edit),
                  ),
                ],
                if (onSetDefault != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onSetDefault,
                    icon: const Icon(Icons.star, size: 16),
                    label: Text(l10n.setAsDefault),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                    ),
                  ),
                ],
                if (onDelete != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete, size: 16),
                    label: Text(l10n.delete),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigDetails(BuildContext context, Map<String, dynamic> config) {
    final l10n = AppLocalizations.of(context);
    final configData = config['config_data'] ?? {};
    final storageType = config['storage_type'];

    if (storageType == 'local') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow(
            context,
            l10n.basePath,
            configData['base_path'] ?? 'N/A',
            Icons.folder,
          ),
        ],
      );
    } else if (storageType == 'ftp') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow(
            context,
            l10n.ftpHost,
            configData['host'] ?? 'N/A',
            Icons.dns,
          ),
          const SizedBox(height: 8),
          _buildDetailRow(
            context,
            l10n.ftpPort,
            configData['port']?.toString() ?? 'N/A',
            Icons.settings_ethernet,
          ),
          const SizedBox(height: 8),
          _buildDetailRow(
            context,
            l10n.ftpUsername,
            configData['username'] ?? 'N/A',
            Icons.person,
          ),
          const SizedBox(height: 8),
          _buildDetailRow(
            context,
            l10n.ftpDirectory,
            configData['directory'] ?? 'N/A',
            Icons.folder,
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: theme.colorScheme.onSurface.withOpacity(0.6),
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.8),
            ),
            overflow: TextOverflow.ellipsis,
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
        return Icons.storage;
    }
  }

  String _getStorageTypeName(String storageType) {
    switch (storageType) {
      case 'local':
        return 'Local Storage';
      case 'ftp':
        return 'FTP Storage';
      default:
        return 'Unknown Storage';
    }
  }
}