import 'package:flutter/material.dart';
import '../../models/workflow_editor_models.dart';
import '../../models/workflow_editor_state.dart';
import '../../l10n/app_localizations.dart';
import '../../services/workflow_service.dart';

/// Dialog برای تنظیمات یک node
class WorkflowNodeConfigDialog extends StatefulWidget {
  final WorkflowNodeModel node;
  final WorkflowEditorState? editorState; // برای دسترسی به metadata
  final Map<String, dynamic>? schema; // JSON Schema برای validation (deprecated - use metadata)
  final List<WorkflowNodeModel>? allNodes; // برای Reference Selector
  final int? businessId; // برای دریافت کاربران متصل به تلگرام

  const WorkflowNodeConfigDialog({
    super.key,
    required this.node,
    this.editorState,
    this.schema,
    this.allNodes,
    this.businessId,
  });

  @override
  State<WorkflowNodeConfigDialog> createState() => _WorkflowNodeConfigDialogState();
}

class _WorkflowNodeConfigDialogState extends State<WorkflowNodeConfigDialog> {
  late Map<String, dynamic> _config;
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic>? _configSchema;
  final WorkflowService _workflowService = WorkflowService();
  List<Map<String, dynamic>> _telegramUsers = [];
  bool _loadingTelegramUsers = false;

  @override
  void initState() {
    super.initState();
    _config = <String, dynamic>{};
    _config.addAll(widget.node.config);
    
    // دریافت config_schema از metadata
    if (widget.editorState != null && widget.node.key != null) {
      if (widget.node.type == WorkflowNodeType.trigger) {
        final metadata = widget.editorState!.triggers
            .firstWhere((t) => t.key == widget.node.key, orElse: () => throw StateError(''));
        _configSchema = metadata.configSchema;
      } else if (widget.node.type == WorkflowNodeType.action) {
        final metadata = widget.editorState!.actions
            .firstWhere((a) => a.key == widget.node.key, orElse: () => throw StateError(''));
        _configSchema = metadata.configSchema;
      }
    }
    
    // مقداردهی اولیه برای فیلدهای موجود در schema
    if (_configSchema != null) {
      _configSchema!.forEach((key, schema) {
        if (schema is Map<String, dynamic>) {
          if (!_config.containsKey(key) && schema['default'] != null) {
            _config[key] = schema['default'];
          }
        }
      });
    }
    
    // بارگذاری کاربران متصل به تلگرام اگر لازم باشد
    _loadTelegramUsersIfNeeded();
  }
  
  Future<void> _loadTelegramUsersIfNeeded() async {
    if (widget.businessId == null) return;
    
    // بررسی اینکه آیا فیلدی با ui_type="telegram_user_selector" وجود دارد
    bool needsTelegramUsers = false;
    if (_configSchema != null) {
      for (final entry in _configSchema!.entries) {
        final schema = entry.value;
        if (schema is Map<String, dynamic>) {
          final uiType = schema['ui_type'] as String?;
          if (uiType == 'telegram_user_selector') {
            needsTelegramUsers = true;
            break;
          }
        }
      }
    }
    
    if (needsTelegramUsers) {
      setState(() => _loadingTelegramUsers = true);
      try {
        final users = await _workflowService.getTelegramConnectedUsers(
          businessId: widget.businessId!,
        );
        setState(() {
          _telegramUsers = users;
          _loadingTelegramUsers = false;
        });
      } catch (e) {
        setState(() => _loadingTelegramUsers = false);
        debugPrint('خطا در بارگذاری کاربران تلگرام: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = Localizations.of(context, MaterialLocalizations);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(_getNodeIcon(widget.node.type), color: _getNodeColor(widget.node.type, theme)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${AppLocalizations.of(context).workflowNodeSettings}: ${widget.node.label}',
              style: theme.textTheme.titleLarge,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // نمایش فیلدهای config بر اساس schema با گروه‌بندی
                if (_configSchema == null || _configSchema!.isEmpty)
                  if (_config.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        AppLocalizations.of(context).workflowNodeNoSettings,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    ..._config.entries.map((entry) {
                      return _buildConfigField(entry.key, entry.value, null);
                    }).toList()
                else
                  ..._buildGroupedFields(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context).workflowCancel),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? true) {
              Navigator.of(context).pop(_config);
            }
          },
          child: Text(AppLocalizations.of(context).workflowSave),
        ),
      ],
    );
  }

  Widget _buildConfigField(String key, dynamic value, Map<String, dynamic>? schema) {
    final theme = Theme.of(context);

    if (value is String) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          initialValue: value,
          decoration: InputDecoration(
            labelText: _formatKey(key),
            border: OutlineInputBorder(),
            helperText: schema?['description'] as String?,
          ),
          onSaved: (newValue) {
            if (newValue != null && newValue.isNotEmpty) {
              _config[key] = newValue;
            } else if (schema?['required'] != true) {
              _config.remove(key);
            }
          },
        ),
      );
    } else if (value is num) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          initialValue: value.toString(),
          decoration: InputDecoration(
            labelText: _formatKey(key),
            border: OutlineInputBorder(),
            helperText: schema?['description'] as String?,
          ),
          keyboardType: TextInputType.number,
          onSaved: (newValue) {
            if (newValue != null && newValue.isNotEmpty) {
              _config[key] = num.tryParse(newValue) ?? value;
            } else if (schema?['required'] != true) {
              _config.remove(key);
            }
          },
        ),
      );
    } else if (value is bool) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: CheckboxListTile(
          title: Text(_formatKey(key)),
          subtitle: schema?['description'] != null ? Text(schema!['description'] as String) : null,
          value: value,
          onChanged: (newValue) {
            setState(() {
              _config[key] = newValue ?? value;
            });
          },
        ),
      );
    } else {
      // برای انواع پیچیده‌تر، نمایش JSON
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          '$_formatKey(key): ${value.toString()}',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
  }
  
  Widget _buildConfigFieldFromSchema(String key, Map<String, dynamic>? schema, dynamic currentValue) {
    if (schema == null) {
      return _buildConfigField(key, currentValue, null);
    }
    
    final fieldType = schema['type'] as String?;
    final description = schema['description'] as String?;
    final required = schema['required'] == true;
    final defaultValue = schema['default'];
    final enumValues = schema['enum'] as List<dynamic>?;
    
    // استفاده از مقدار فعلی یا default
    final value = currentValue ?? defaultValue;
    
    // اگر required است و مقدار نداریم، از default استفاده کن
    if (value == null && required && defaultValue != null) {
      _config[key] = defaultValue;
    }
    
    switch (fieldType) {
      case 'string':
        if (enumValues != null) {
          // Dropdown برای enum
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: DropdownButtonFormField<String>(
              value: value is String ? value : (enumValues.isNotEmpty ? enumValues.first.toString() : null),
              decoration: InputDecoration(
                labelText: _formatKey(key),
                border: OutlineInputBorder(),
                helperText: description,
              ),
              items: enumValues!.map((e) {
                return DropdownMenuItem<String>(
                  value: e.toString(),
                  child: Text(e.toString()),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  if (newValue != null) {
                    _config[key] = newValue;
                  } else if (!required) {
                    _config.remove(key);
                  }
                });
              },
            ),
          );
        }
        // بررسی ui_type برای فیلدهای خاص
        final uiType = schema['ui_type'] as String?;
        if (uiType == 'telegram_user_selector') {
          return _buildTelegramUserSelector(key, schema, value, required, description);
        }
        
        // Text field برای string با پشتیبانی از Reference
        final isReference = value?.toString().startsWith('\$') ?? false;
        final placeholder = _getPlaceholder(key, description);
        
        return Builder(
          builder: (context) {
            final theme = Theme.of(context);
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    initialValue: value?.toString(),
                    decoration: InputDecoration(
                      labelText: _formatKey(key),
                      border: OutlineInputBorder(),
                      helperText: description,
                      hintText: placeholder,
                      prefixIcon: isReference 
                          ? Icon(Icons.link, size: 18, color: theme.colorScheme.primary)
                          : null,
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.allNodes != null && widget.allNodes!.isNotEmpty)
                            IconButton(
                              icon: Icon(Icons.select_all, size: 18),
                              tooltip: 'انتخاب از نودهای قبلی',
                              onPressed: () => _showReferenceSelector(key),
                            ),
                          if (required)
                            Icon(Icons.star, size: 12, color: Colors.red),
                        ],
                      ),
                    ),
                    validator: required && (value == null || value.toString().isEmpty)
                        ? (v) => AppLocalizations.of(context).workflowNodeFieldRequired
                        : null,
                    onSaved: (newValue) {
                      if (newValue != null && newValue.isNotEmpty) {
                        _config[key] = newValue;
                      } else if (!required) {
                        _config.remove(key);
                      } else {
                        _config[key] = '';
                      }
                    },
                  ),
                  if (isReference)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, right: 12),
                      child: Text(
                        'این مقدار از یک نود قبلی استفاده می‌کند',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
        
      case 'number':
      case 'integer':
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextFormField(
            initialValue: value?.toString(),
            decoration: InputDecoration(
              labelText: _formatKey(key),
              border: OutlineInputBorder(),
              helperText: description,
              suffixIcon: required ? const Icon(Icons.star, size: 12, color: Colors.red) : null,
            ),
            keyboardType: TextInputType.number,
            validator: required && value == null
                ? (v) => AppLocalizations.of(context).workflowNodeFieldRequired
                : null,
            onSaved: (newValue) {
              if (newValue != null && newValue.isNotEmpty) {
                _config[key] = fieldType == 'integer' 
                    ? int.tryParse(newValue) ?? value
                    : double.tryParse(newValue) ?? value;
              } else if (!required) {
                _config.remove(key);
              }
            },
          ),
        );
        
      case 'boolean':
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: CheckboxListTile(
            title: Text(_formatKey(key)),
            subtitle: description != null ? Text(description) : null,
            value: value is bool ? value : (defaultValue as bool? ?? false),
            onChanged: (newValue) {
              setState(() {
                _config[key] = newValue ?? false;
              });
            },
          ),
        );
        
      case 'array':
        // برای array، نمایش ساده
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            '$_formatKey(key): ${AppLocalizations.of(context).workflowNodeArrayType}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        );
        
      case 'object':
        // برای object، نمایش ساده
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            '$_formatKey(key): ${AppLocalizations.of(context).workflowNodeObjectType}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        );
        
      default:
        return _buildConfigField(key, value, schema);
    }
  }

  /// ساخت فیلدهای گروه‌بندی شده
  List<Widget> _buildGroupedFields() {
    if (_configSchema == null || _configSchema!.isEmpty) {
      return [];
    }

    // گروه‌بندی فیلدها
    final groups = <String, List<MapEntry<String, dynamic>>>{};
    final ungrouped = <MapEntry<String, dynamic>>[];

    for (final entry in _configSchema!.entries) {
      final fieldKey = entry.key;
      final fieldSchema = entry.value as Map<String, dynamic>?;
      final group = _getFieldGroup(fieldKey, fieldSchema);
      
      if (group != null) {
        groups.putIfAbsent(group, () => []);
        groups[group]!.add(entry);
      } else {
        ungrouped.add(entry);
      }
    }

    final widgets = <Widget>[];

    // نمایش گروه‌ها
    for (final groupEntry in groups.entries) {
      widgets.add(_buildGroupSection(groupEntry.key, groupEntry.value));
    }

    // نمایش فیلدهای بدون گروه
    if (ungrouped.isNotEmpty) {
      widgets.addAll(ungrouped.map((entry) {
        final fieldKey = entry.key;
        final fieldSchema = entry.value as Map<String, dynamic>?;
        final currentValue = _config[fieldKey];
        return _buildConfigFieldFromSchema(fieldKey, fieldSchema, currentValue);
      }));
    }

    return widgets;
  }

  /// تعیین گروه یک فیلد بر اساس نام و schema
  String? _getFieldGroup(String key, Map<String, dynamic>? schema) {
    final keyLower = key.toLowerCase();
    
    // گروه فیلترها
    if (keyLower.contains('filter') || 
        keyLower.contains('min_') || 
        keyLower.contains('max_') ||
        keyLower.contains('status') ||
        keyLower.contains('type') ||
        keyLower.contains('currency') ||
        keyLower.contains('person_type')) {
      return 'فیلترها';
    }
    
    // گروه زمان‌بندی
    if (keyLower.contains('timeout') || 
        keyLower.contains('cooldown') ||
        keyLower.contains('schedule') ||
        keyLower.contains('delay') ||
        keyLower.contains('retry_delay')) {
      return 'زمان‌بندی';
    }
    
    // گروه Retry و خطا
    if (keyLower.contains('retry') || 
        keyLower.contains('error') ||
        keyLower.contains('on_error') ||
        keyLower.contains('break_on_error') ||
        keyLower.contains('continue_on_error')) {
      return 'مدیریت خطا';
    }
    
    // گروه تنظیمات اصلی
    if (keyLower == 'enabled' ||
        keyLower == 'to' ||
        keyLower == 'subject' ||
        keyLower == 'body' ||
        keyLower == 'message' ||
        keyLower == 'title' ||
        keyLower == 'url' ||
        keyLower == 'method' ||
        keyLower == 'document_type' ||
        keyLower == 'invoice_type') {
      return 'تنظیمات اصلی';
    }
    
    // گروه تنظیمات پیشرفته
    if (keyLower.contains('include_') ||
        keyLower.contains('template') ||
        keyLower.contains('priority') ||
        keyLower.contains('channels') ||
        keyLower.contains('parse_mode')) {
      return 'تنظیمات پیشرفته';
    }
    
    return null; // بدون گروه
  }

  /// ساخت بخش گروه
  Widget _buildGroupSection(String groupName, List<MapEntry<String, dynamic>> fields) {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Text(
              groupName,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: fields.map((entry) {
                final fieldKey = entry.key;
                final fieldSchema = entry.value as Map<String, dynamic>?;
                final currentValue = _config[fieldKey];
                return _buildConfigFieldFromSchema(fieldKey, fieldSchema, currentValue);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _formatKey(String key) {
    // تبدیل camelCase به عنوان خوانا
    return key
        .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(0)}')
        .trim()
        .replaceRange(0, 1, key[0].toUpperCase());
  }

  Color _getNodeColor(WorkflowNodeType type, ThemeData theme) {
    switch (type) {
      case WorkflowNodeType.trigger:
        return Colors.green;
      case WorkflowNodeType.action:
        return theme.colorScheme.primary;
      case WorkflowNodeType.condition:
        return Colors.orange;
      case WorkflowNodeType.loop:
        return Colors.purple;
    }
  }

  IconData _getNodeIcon(WorkflowNodeType type) {
    switch (type) {
      case WorkflowNodeType.trigger:
        return Icons.bolt;
      case WorkflowNodeType.action:
        return Icons.play_arrow;
      case WorkflowNodeType.condition:
        return Icons.code;
      case WorkflowNodeType.loop:
        return Icons.loop;
    }
  }

  /// نمایش Reference Selector
  void _showReferenceSelector(String fieldKey) {
    if (widget.allNodes == null || widget.allNodes!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هیچ نودی برای انتخاب وجود ندارد')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _ReferenceSelectorDialog(
        allNodes: widget.allNodes!,
        currentNode: widget.node,
        onSelected: (reference) {
          setState(() {
            _config[fieldKey] = reference;
          });
          Navigator.of(context).pop();
        },
      ),
    );
  }

  /// ساخت Telegram User Selector
  Widget _buildTelegramUserSelector(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    final theme = Theme.of(context);
    final selectedUserId = currentValue?.toString();
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loadingTelegramUsers)
            const LinearProgressIndicator()
          else if (_telegramUsers.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'هیچ کاربری به ربات تلگرام متصل نیست. لطفاً ابتدا کاربران را به ربات متصل کنید.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedUserId,
                  decoration: InputDecoration(
                    labelText: _formatKey(key),
                    border: OutlineInputBorder(),
                    helperText: description ?? 'انتخاب کاربر عضو کسب و کار که به ربات تلگرام متصل است',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.telegram, size: 18, color: theme.colorScheme.primary),
                        if (required)
                          Icon(Icons.star, size: 12, color: Colors.red),
                      ],
                    ),
                    prefixIcon: selectedUserId != null
                        ? Icon(Icons.person, color: theme.colorScheme.primary)
                        : null,
                  ),
                  items: _telegramUsers.map((user) {
                    final userId = user['user_id']?.toString() ?? '';
                    final name = user['name']?.toString() ?? 'کاربر';
                    final email = user['email']?.toString() ?? '';
                    final role = user['role']?.toString() ?? 'member';
                    
                    return DropdownMenuItem<String>(
                      value: userId,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                name,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (role == 'owner')
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'مالک',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onPrimaryContainer,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (email.isNotEmpty)
                            Text(
                              email,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                  validator: required && selectedUserId == null
                      ? (v) => AppLocalizations.of(context).workflowNodeFieldRequired
                      : null,
                  onChanged: (newValue) {
                    setState(() {
                      if (newValue != null) {
                        _config[key] = newValue;
                      } else if (!required) {
                        _config.remove(key);
                      }
                    });
                  },
                ),
                // دکمه Reference Selector
                if (widget.allNodes != null && widget.allNodes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.link, size: 16),
                      label: const Text('استفاده از نود قبلی'),
                      onPressed: () => _showReferenceSelector(key),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// دریافت placeholder برای فیلد
  String? _getPlaceholder(String key, String? description) {
    final keyLower = key.toLowerCase();
    
    if (keyLower.contains('email') || keyLower == 'to') {
      return 'مثال: user@example.com یا \$node_id.email';
    }
    if (keyLower.contains('amount') || keyLower.contains('price')) {
      return 'مثال: 100000 یا \$node_id.total_amount';
    }
    if (keyLower.contains('subject') || keyLower.contains('title')) {
      return 'مثال: فاکتور شماره \$node_id.invoice_number';
    }
    if (keyLower.contains('message') || keyLower.contains('body')) {
      return 'مثال: متن پیام یا \$node_id.description';
    }
    if (keyLower.contains('url')) {
      return 'مثال: https://example.com/api';
    }
    if (description != null && description.contains('reference')) {
      return 'مثال: \$node_id.field_name';
    }
    
    return null;
  }
}

/// Dialog برای انتخاب Reference از نودهای قبلی
class _ReferenceSelectorDialog extends StatelessWidget {
  final List<WorkflowNodeModel> allNodes;
  final WorkflowNodeModel currentNode;
  final Function(String) onSelected;

  const _ReferenceSelectorDialog({
    required this.allNodes,
    required this.currentNode,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // فیلتر کردن نودهای قبل از نود فعلی
    final availableNodes = allNodes.where((node) => node.id != currentNode.id).toList();
    
    return AlertDialog(
      title: const Text('انتخاب از نودهای قبلی'),
      content: SizedBox(
        width: 400,
        child: availableNodes.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text('هیچ نودی برای انتخاب وجود ندارد'),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: availableNodes.length,
                itemBuilder: (context, index) {
                  final node = availableNodes[index];
                  return ListTile(
                    leading: Icon(
                      _getNodeIcon(node.type),
                      color: _getNodeColor(node.type, theme),
                    ),
                    title: Text(node.label),
                    subtitle: Text('ID: ${node.id}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () {
                        // ساخت reference
                        final reference = '\$${node.id}';
                        onSelected(reference);
                      },
                    ),
                    onTap: () {
                      final reference = '\$${node.id}';
                      onSelected(reference);
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
      ],
    );
  }

  Color _getNodeColor(WorkflowNodeType type, ThemeData theme) {
    switch (type) {
      case WorkflowNodeType.trigger:
        return Colors.green;
      case WorkflowNodeType.action:
        return theme.colorScheme.primary;
      case WorkflowNodeType.condition:
        return Colors.orange;
      case WorkflowNodeType.loop:
        return Colors.purple;
    }
  }

  IconData _getNodeIcon(WorkflowNodeType type) {
    switch (type) {
      case WorkflowNodeType.trigger:
        return Icons.bolt;
      case WorkflowNodeType.action:
        return Icons.play_arrow;
      case WorkflowNodeType.condition:
        return Icons.code;
      case WorkflowNodeType.loop:
        return Icons.loop;
    }
  }
}


