import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../services/api_key_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/jalali_date_picker.dart';

class ApiKeysPage extends StatefulWidget {
  final CalendarController calendarController;
  
  const ApiKeysPage({
    super.key,
    required this.calendarController,
  });

  @override
  State<ApiKeysPage> createState() => _ApiKeysPageState();
}

class _ApiKeysPageState extends State<ApiKeysPage> {
  final ApiKeyService _apiKeyService = ApiKeyService(ApiClient());
  List<Map<String, dynamic>> _apiKeys = [];
  bool _loading = false;
  String _filterType = 'active'; // 'active', 'revoked', 'all'

  @override
  void initState() {
    super.initState();
    _loadApiKeys();
  }

  Future<void> _loadApiKeys() async {
    setState(() => _loading = true);
    try {
      final response = await _apiKeyService.listApiKeys();
      if (response['success'] == true && response['data'] is List) {
        setState(() {
          _apiKeys = (response['data'] as List).cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(
          context,
          message:
              '${t.apiKeyErrorLoadingKeys}: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createApiKey() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _CreateApiKeyDialog(calendarController: widget.calendarController),
    );
    
    if (result != null && mounted) {
      try {
        final response = await _apiKeyService.createApiKey(
          name: result['name'],
          scopes: result['scopes'],
          expiresAt: result['expiresAt'],
          ipWhitelist: result['ipWhitelist'],
        );
        
        if (response['success'] == true && response['data'] != null) {
          final apiKey = response['data']['api_key'] as String;
          _loadApiKeys();
          
          if (mounted) {
            await _showApiKeyDialog(apiKey);
          }
        }
      } catch (e) {
        if (mounted) {
          final t = AppLocalizations.of(context);
          SnackBarHelper.showError(
          context,
          message:
              '${t.apiKeyErrorCreatingKey}: ${ErrorExtractor.forContext(e, context)}',
        );
        }
      }
    }
  }

  Future<void> _showApiKeyDialog(String apiKey) async {
    final t = AppLocalizations.of(context);
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(t.apiKeyCreatedSuccessfully)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.onErrorContainer, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.apiKeySaveWarning,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
              ),
              child: SelectableText(
                apiKey,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.apiKeyClose),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: apiKey));
              SnackBarHelper.showSuccess(context, message: t.apiKeyCopied);
            },
            icon: const Icon(Icons.copy, size: 18),
            label: Text(t.apiKeyCopy),
          ),
        ],
      ),
    );
  }

  Future<void> _editApiKey(Map<String, dynamic> apiKey) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditApiKeyDialog(
        apiKey: apiKey,
        calendarController: widget.calendarController,
      ),
    );
    
    if (result != null && mounted) {
      try {
        await _apiKeyService.updateApiKey(
          keyId: apiKey['id'] as int,
          name: result['name'],
          scopes: result['scopes'],
          expiresAt: result['expiresAt'],
          ipWhitelist: result['ipWhitelist'],
        );
        
        _loadApiKeys();
        if (mounted) {
          final t = AppLocalizations.of(context);
          SnackBarHelper.showSuccess(context, message: t.apiKeyUpdatedSuccessfully);
        }
      } catch (e) {
        if (mounted) {
          final t = AppLocalizations.of(context);
          SnackBarHelper.showError(
          context,
          message:
              '${t.apiKeyErrorUpdating}: ${ErrorExtractor.forContext(e, context)}',
        );
        }
      }
    }
  }

  Future<void> _deleteApiKey(Map<String, dynamic> apiKey) async {
    final t = AppLocalizations.of(context);
    final keyName = apiKey['name'] ?? t.apiKeyWithoutName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(t.apiKeyDeleteTitle)),
          ],
        ),
        content: Text('آیا مطمئن هستید که می‌خواهید کلید "$keyName" را حذف کنید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(t.delete),
          ),
        ],
      ),
    );
    
    if (confirmed == true && mounted) {
      try {
        await _apiKeyService.deleteApiKey(apiKey['id'] as int);
        _loadApiKeys();
        if (mounted) {
          final t = AppLocalizations.of(context);
          SnackBarHelper.showSuccess(context, message: t.apiKeyDeletedSuccessfully);
        }
      } catch (e) {
        if (mounted) {
          final t = AppLocalizations.of(context);
          SnackBarHelper.showError(
          context,
          message:
              '${t.apiKeyErrorDeleting}: ${ErrorExtractor.forContext(e, context)}',
        );
        }
      }
    }
  }

  List<Map<String, dynamic>> get _filteredApiKeys {
    switch (_filterType) {
      case 'active':
        return _apiKeys.where((key) => key['is_active'] == true).toList();
      case 'revoked':
        return _apiKeys.where((key) => key['is_active'] == false).toList();
      case 'all':
      default:
        return _apiKeys;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final filteredKeys = _filteredApiKeys;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(t.apiKeysPageTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment<String>(
                  value: 'active',
                  label: Text(t.apiKeyFilterActive),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                ),
                ButtonSegment<String>(
                  value: 'revoked',
                  label: Text(t.apiKeyFilterRevoked),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                ),
                ButtonSegment<String>(
                  value: 'all',
                  label: Text(t.apiKeyFilterAll),
                  icon: const Icon(Icons.list_outlined, size: 18),
                ),
              ],
              selected: {_filterType},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() {
                  _filterType = newSelection.first;
                });
              },
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadApiKeys,
              child: filteredKeys.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _filterType == 'active'
                                ? Icons.check_circle_outline
                                : _filterType == 'revoked'
                                    ? Icons.cancel_outlined
                                    : Icons.key_off,
                            size: 64,
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _filterType == 'active'
                                ? t.apiKeyNoActiveKeys
                                : _filterType == 'revoked'
                                    ? t.apiKeyNoRevokedKeys
                                    : t.apiKeyNoKeysCreated,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              _filterType == 'active'
                                  ? t.apiKeyCreateHint
                                  : _filterType == 'revoked'
                                      ? t.apiKeyNoRevokedHint
                                      : t.apiKeyUsageHint,
                              style: theme.textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredKeys.length,
                      itemBuilder: (context, index) {
                        final apiKey = filteredKeys[index];
                        return _ApiKeyCard(
                          apiKey: apiKey,
                          calendarController: widget.calendarController,
                          onEdit: () => _editApiKey(apiKey),
                          onDelete: () => _deleteApiKey(apiKey),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createApiKey,
        icon: const Icon(Icons.add),
        label: Text(t.apiKeyCreateNewButton),
      ),
    );
  }
}

class _ApiKeyCard extends StatelessWidget {
  final Map<String, dynamic> apiKey;
  final CalendarController calendarController;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ApiKeyCard({
    required this.apiKey,
    required this.calendarController,
    required this.onEdit,
    required this.onDelete,
  });

  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null) return null;
    try {
      return DateTime.parse(dateStr);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final isActive = apiKey['is_active'] == true;
    final name = apiKey['name'] as String? ?? t.apiKeyWithoutName;
    final created = _parseDate(apiKey['created_at'] as String?);
    final lastUsed = _parseDate(apiKey['last_used_at'] as String?);
    final expiresAt = _parseDate(apiKey['expires_at'] as String?);
    final revokedAt = _parseDate(apiKey['revoked_at'] as String?);
    final isJalali = calendarController.isJalali;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isActive
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.errorContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isActive ? Icons.check_circle : Icons.cancel,
                    color: isActive
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onErrorContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isActive) ...[
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                    tooltip: t.apiKeyEdit,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                    tooltip: t.apiKeyDelete,
                    color: theme.colorScheme.error,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (created != null) ...[
              _buildInfoRow(
                context,
                icon: Icons.calendar_today_outlined,
                label: t.apiKeyCreatedAt,
                value: HesabixDateUtils.formatDateTime(created, isJalali),
              ),
            ],
            if (lastUsed != null) ...[
              const SizedBox(height: 6),
              _buildInfoRow(
                context,
                icon: Icons.access_time_outlined,
                label: t.apiKeyLastUsed,
                value: HesabixDateUtils.formatDateTime(lastUsed, isJalali),
              ),
            ],
            if (expiresAt != null) ...[
              const SizedBox(height: 6),
              _buildInfoRow(
                context,
                icon: Icons.event_outlined,
                label: t.apiKeyExpiresAt,
                value: HesabixDateUtils.formatDateTime(expiresAt, isJalali),
                valueColor: expiresAt.isBefore(DateTime.now()) ? theme.colorScheme.error : null,
              ),
            ],
            if (revokedAt != null) ...[
              const SizedBox(height: 6),
              _buildInfoRow(
                context,
                icon: Icons.block_outlined,
                label: t.apiKeyRevokedAt,
                value: HesabixDateUtils.formatDateTime(revokedAt, isJalali),
                valueColor: theme.colorScheme.error,
              ),
            ],
            if (apiKey['ip'] != null && (apiKey['ip'] as String).isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildInfoRow(
                context,
                icon: Icons.location_on_outlined,
                label: t.apiKeyAllowedIPs,
                value: apiKey['ip'] as String,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: valueColor ?? theme.colorScheme.onSurface,
              fontWeight: valueColor != null ? FontWeight.w500 : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _CreateApiKeyDialog extends StatefulWidget {
  final CalendarController calendarController;

  const _CreateApiKeyDialog({required this.calendarController});

  @override
  State<_CreateApiKeyDialog> createState() => _CreateApiKeyDialogState();
}

class _CreateApiKeyDialogState extends State<_CreateApiKeyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _scopesController = TextEditingController();
  final _ipWhitelistController = TextEditingController();
  DateTime? _expiresAt;

  @override
  void dispose() {
    _nameController.dispose();
    _scopesController.dispose();
    _ipWhitelistController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final now = DateTime.now();
    final maxDate = DateTime(now.year + 10, 12, 31);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.add_circle_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t.apiKeyCreateNewTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Form
            Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: t.apiKeyNameLabel,
                          hintText: t.apiKeyNameHint,
                          prefixIcon: const Icon(Icons.label_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _scopesController,
                        decoration: InputDecoration(
                          labelText: t.apiKeyScopeLabel,
                          hintText: t.apiKeyScopeHint,
                          prefixIcon: const Icon(Icons.security_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                        ),
                        maxLines: 3,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _ipWhitelistController,
                        decoration: InputDecoration(
                          labelText: t.apiKeyIPsLabel,
                          hintText: t.apiKeyIPsHint,
                          prefixIcon: const Icon(Icons.network_check_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      _DateTimeInputField(
                        value: _expiresAt,
                        onChanged: (dateTime) {
                          setState(() {
                            _expiresAt = dateTime;
                          });
                        },
                        calendarController: widget.calendarController,
                        labelText: t.apiKeyExpiryLabel,
                        hintText: t.apiKeyExpiryHint,
                        firstDate: now,
                        lastDate: maxDate,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(t.cancel),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        Navigator.of(context).pop({
                          'name': _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
                          'scopes': _scopesController.text.trim().isEmpty ? null : _scopesController.text.trim(),
                          'expiresAt': _expiresAt?.toIso8601String(),
                          'ipWhitelist': _ipWhitelistController.text.trim().isEmpty ? null : _ipWhitelistController.text.trim(),
                        });
                      }
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(t.apiKeyCreateNewButton),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditApiKeyDialog extends StatefulWidget {
  final Map<String, dynamic> apiKey;
  final CalendarController calendarController;

  const _EditApiKeyDialog({
    required this.apiKey,
    required this.calendarController,
  });

  @override
  State<_EditApiKeyDialog> createState() => _EditApiKeyDialogState();
}

class _EditApiKeyDialogState extends State<_EditApiKeyDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _scopesController;
  late final TextEditingController _ipWhitelistController;
  DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.apiKey['name'] as String? ?? '');
    _scopesController = TextEditingController(text: widget.apiKey['scopes'] as String? ?? '');
    _ipWhitelistController = TextEditingController(text: widget.apiKey['ip'] as String? ?? '');
    
    final expiresAtStr = widget.apiKey['expires_at'] as String?;
    if (expiresAtStr != null) {
      try {
        _expiresAt = DateTime.parse(expiresAtStr);
      } catch (e) {
        // ignore
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scopesController.dispose();
    _ipWhitelistController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final now = DateTime.now();
    final maxDate = DateTime(now.year + 10, 12, 31);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t.apiKeyEditTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Form
            Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: GlobalKey<FormState>(),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'نام کلید',
                          prefixIcon: const Icon(Icons.label_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _scopesController,
                        decoration: InputDecoration(
                          labelText: 'محدوده دسترسی (JSON)',
                          prefixIcon: const Icon(Icons.security_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                        ),
                        maxLines: 3,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _ipWhitelistController,
                        decoration: InputDecoration(
                          labelText: 'لیست IP های مجاز',
                          hintText: 'جدا شده با کاما',
                          prefixIcon: const Icon(Icons.network_check_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      _DateTimeInputField(
                        value: _expiresAt,
                        onChanged: (dateTime) {
                          setState(() {
                            _expiresAt = dateTime;
                          });
                        },
                        calendarController: widget.calendarController,
                        labelText: t.apiKeyExpiryLabel,
                        hintText: t.apiKeyNoExpiry,
                        firstDate: now,
                        lastDate: maxDate,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('لغو'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop({
                        'name': _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
                        'scopes': _scopesController.text.trim().isEmpty ? null : _scopesController.text.trim(),
                        'expiresAt': _expiresAt?.toIso8601String(),
                        'ipWhitelist': _ipWhitelistController.text.trim().isEmpty ? null : _ipWhitelistController.text.trim(),
                      });
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('ذخیره'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ویجت ترکیبی برای انتخاب تاریخ و زمان
class _DateTimeInputField extends StatefulWidget {
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final CalendarController calendarController;
  final String? labelText;
  final String? hintText;
  final DateTime? firstDate;
  final DateTime? lastDate;

  const _DateTimeInputField({
    required this.value,
    required this.onChanged,
    required this.calendarController,
    this.labelText,
    this.hintText,
    this.firstDate,
    this.lastDate,
  });

  @override
  State<_DateTimeInputField> createState() => _DateTimeInputFieldState();
}

class _DateTimeInputFieldState extends State<_DateTimeInputField> {
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    if (widget.value != null) {
      _selectedDate = DateTime(
        widget.value!.year,
        widget.value!.month,
        widget.value!.day,
      );
      _selectedTime = TimeOfDay.fromDateTime(widget.value!);
    }
  }

  @override
  void didUpdateWidget(_DateTimeInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (widget.value != null) {
        _selectedDate = DateTime(
          widget.value!.year,
          widget.value!.month,
          widget.value!.day,
        );
        _selectedTime = TimeOfDay.fromDateTime(widget.value!);
      } else {
        _selectedDate = null;
        _selectedTime = null;
      }
    }
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final firstDate = widget.firstDate ?? now;
    final lastDate = widget.lastDate ?? DateTime(now.year + 10, 12, 31);
    final initialDate = _selectedDate ?? now;

    final selectedDate = await showAdaptiveDatePicker(
      context: context,
      calendarController: widget.calendarController,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: widget.labelText ?? AppLocalizations.of(context).datePickerSelectDate,
    );

    if (selectedDate != null) {
      setState(() {
        _selectedDate = selectedDate;
        _updateValue();
      });
    }
  }

  Future<void> _selectTime() async {
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      helpText: AppLocalizations.of(context).timePickerSelectTime,
    );

    if (selectedTime != null) {
      setState(() {
        _selectedTime = selectedTime;
        _updateValue();
      });
    }
  }

  void _updateValue() {
    if (_selectedDate != null && _selectedTime != null) {
      final dateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
      widget.onChanged(dateTime);
    } else if (_selectedDate != null) {
      final dateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        23,
        59,
      );
      _selectedTime = const TimeOfDay(hour: 23, minute: 59);
      widget.onChanged(dateTime);
    } else {
      widget.onChanged(null);
    }
  }

  void _clearDateTime() {
    setState(() {
      _selectedDate = null;
      _selectedTime = null;
      widget.onChanged(null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isJalali = widget.calendarController.isJalali;
    final dateDisplay = _selectedDate != null
        ? HesabixDateUtils.formatForDisplay(_selectedDate, isJalali)
        : '';
    final timeDisplay = _selectedTime != null
        ? '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}'
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.labelText ?? AppLocalizations.of(context).dateTimeLabel,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _selectDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context).dateLabel,
                    prefixIcon: const Icon(Icons.calendar_today_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                  ),
                  child: Text(dateDisplay.isEmpty ? AppLocalizations.of(context).dateLabel : dateDisplay),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: _selectTime,
                child: InputDecorator(
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context).timeLabel,
                    prefixIcon: const Icon(Icons.access_time_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                  ),
                  child: Text(timeDisplay.isEmpty ? AppLocalizations.of(context).timeLabel : timeDisplay),
                ),
              ),
            ),
            if (_selectedDate != null || _selectedTime != null)
              IconButton(
                icon: const Icon(Icons.clear),
                tooltip: AppLocalizations.of(context).clearButton,
                onPressed: _clearDateTime,
              ),
          ],
        ),
        if (_selectedDate != null && _selectedTime != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: theme.colorScheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    HesabixDateUtils.formatDateTime(
                      DateTime(
                        _selectedDate!.year,
                        _selectedDate!.month,
                        _selectedDate!.day,
                        _selectedTime!.hour,
                        _selectedTime!.minute,
                      ),
                      isJalali,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
