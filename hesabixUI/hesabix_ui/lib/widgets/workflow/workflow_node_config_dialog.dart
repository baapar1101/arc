import 'package:flutter/material.dart';
import '../../models/workflow_editor_models.dart';
import '../../models/workflow_editor_state.dart';
import '../../l10n/app_localizations.dart';
import '../../services/workflow_service.dart';
import '../../services/workflow_translation_service.dart';
import '../../utils/snackbar_helper.dart';


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
  final WorkflowTranslationService _translationService = WorkflowTranslationService();
  List<Map<String, dynamic>> _telegramUsers = [];
  bool _loadingTelegramUsers = false;
  Map<String, dynamic>? _translations;
  List<Map<String, dynamic>> _currencies = [];
  bool _loadingCurrencies = false;

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
    
    // بارگذاری ارزها اگر لازم باشد
    _loadCurrenciesIfNeeded();
    
    // بارگذاری ترجمه‌ها
    _loadTranslations();
  }
  
  Future<void> _loadTranslations() async {
    try {
      final locale = Localizations.localeOf(context);
      final lang = locale.languageCode;
      final translations = await _translationService.getTranslations(lang: lang);
      if (mounted) {
        setState(() {
          _translations = translations;
        });
      }
    } catch (e) {
      debugPrint('خطا در بارگذاری ترجمه‌های ورک‌فلو: $e');
    }
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

  Future<void> _loadCurrenciesIfNeeded() async {
    if (widget.businessId == null) return;
    
    // بررسی اینکه آیا فیلدی با ui_type="currency_selector" وجود دارد
    bool needsCurrencies = false;
    if (_configSchema != null) {
      for (final entry in _configSchema!.entries) {
        final schema = entry.value;
        if (schema is Map<String, dynamic>) {
          final uiType = schema['ui_type'] as String?;
          if (uiType == 'currency_selector') {
            needsCurrencies = true;
            break;
          }
        }
      }
    }
    
    if (needsCurrencies) {
      setState(() => _loadingCurrencies = true);
      try {
        // استفاده از CurrencyService برای لود ارزهای کسب‌وکار
        final response = await _workflowService.getBusinessCurrencies(
          businessId: widget.businessId!,
        );
        setState(() {
          _currencies = response;
          _loadingCurrencies = false;
        });
      } catch (e) {
        debugPrint('خطا در بارگذاری ارزها: $e');
        // در صورت خطا، از لیست پیش‌فرض استفاده می‌کنیم
        setState(() {
          _currencies = [
            {'id': 1, 'code': 'IRR', 'name': 'ریال', 'symbol': '﷼', 'title': 'ریال ایران'},
            {'id': 2, 'code': 'USD', 'name': 'دلار آمریکا', 'symbol': '\$', 'title': 'دلار آمریکا'},
            {'id': 3, 'code': 'EUR', 'name': 'یورو', 'symbol': '€', 'title': 'یورو'},
            {'id': 4, 'code': 'AED', 'name': 'درهم امارات', 'symbol': 'د.إ', 'title': 'درهم'},
          ];
          _loadingCurrencies = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
            if (_formKey.currentState?.validate() ?? false) {
              _formKey.currentState?.save();
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
    var description = schema['description'] as String?;
    final required = schema['required'] == true;
    final defaultValue = schema['default'];
    final enumValues = schema['enum'] as List<dynamic>?;
    
    // دریافت ترجمه برای description (اگر موجود باشد)
    if (_translations != null && widget.node.key != null) {
      final actionKey = widget.node.key;
      final descKey = 'field_${key}_desc';
      
      // جستجو در ترجمه‌های خاص action
      if (_translations!.containsKey(actionKey)) {
        final actionTrans = _translations![actionKey] as Map<String, dynamic>?;
        if (actionTrans != null && actionTrans.containsKey(descKey)) {
          description = actionTrans[descKey] as String;
        }
      }
    }
    
    // استفاده از مقدار فعلی یا default
    final value = currentValue ?? defaultValue;
    
    // اگر required است و مقدار نداریم، از default استفاده کن
    if (value == null && required && defaultValue != null) {
      _config[key] = defaultValue;
    }
    
    switch (fieldType) {
      case 'string':
        if (enumValues != null) {
          // دریافت labels از ui_config (اگر وجود دارد)
          final uiConfig = schema['ui_config'] as Map<String, dynamic>?;
          final enumLabels = uiConfig?['labels'] as Map<String, dynamic>?;
          
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
                final enumValue = e.toString();
                // استفاده از label ترجمه شده (اگر موجود باشد)
                final label = enumLabels?[enumValue] as String? ?? _getEnumLabel(enumValue, key);
                
                return DropdownMenuItem<String>(
                  value: enumValue,
                  child: Text(label),
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
        } else if (uiType == 'person_selector') {
          return _buildPersonSelector(key, schema, value, required, description);
        } else if (uiType == 'product_selector') {
          return _buildProductSelector(key, schema, value, required, description);
        } else if (uiType == 'currency_selector') {
          return _buildCurrencySelector(key, schema, value, required, description);
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
                    validator: required
                        ? (v) => (v == null || v.isEmpty)
                            ? AppLocalizations.of(context).workflowNodeFieldRequired
                            : null
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
        // بررسی ui_type برای فیلدهای خاص number/integer
        final uiType = schema['ui_type'] as String?;
        if (uiType == 'currency_selector') {
          return _buildCurrencySelector(key, schema, value, required, description);
        } else if (uiType == 'person_selector') {
          return _buildPersonSelector(key, schema, value, required, description);
        } else if (uiType == 'product_selector') {
          return _buildProductSelector(key, schema, value, required, description);
        } else if (uiType == 'warehouse_selector') {
          return _buildWarehouseSelector(key, schema, value, required, description);
        } else if (uiType == 'account_selector') {
          return _buildAccountSelector(key, schema, value, required, description);
        } else if (uiType == 'fiscal_year_selector') {
          return _buildFiscalYearSelector(key, schema, value, required, description);
        }
        
        // Default: TextField عددی
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
            validator: required
                ? (v) => (v == null || v.isEmpty)
                    ? AppLocalizations.of(context).workflowNodeFieldRequired
                    : null
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
        // بررسی اینکه آیا multi-select است
        final uiType = schema['ui_type'] as String?;
        if (uiType == 'multi_select') {
          return _buildMultiSelect(key, schema, value, required, description);
        }
        
        // Default array handling
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
    // بررسی ترجمه موجود
    if (_translations != null && widget.node.key != null) {
      final actionKey = widget.node.key;
      final fieldKey = 'field_$key';
      
      // جستجو در ترجمه‌های خاص action
      if (_translations!.containsKey(actionKey)) {
        final actionTrans = _translations![actionKey] as Map<String, dynamic>?;
        if (actionTrans != null && actionTrans.containsKey(fieldKey)) {
          return actionTrans[fieldKey] as String;
        }
      }
      
      // جستجو در ترجمه‌های مشترک
      if (_translations!.containsKey(fieldKey)) {
        return _translations![fieldKey] as String;
      }
    }
    
    // Fallback: تبدیل camelCase به عنوان خوانا
    return key
        .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(0)}')
        .trim()
        .replaceRange(0, 1, key[0].toUpperCase());
  }
  
  /// دریافت label برای enum
  String _getEnumLabel(String enumValue, String fieldKey) {
    // بررسی ترجمه موجود
    if (_translations != null && widget.node.key != null) {
      final actionKey = widget.node.key;
      final labelKey = enumValue.replaceAll('-', '_').replaceAll('.', '_');
      
      // جستجو در ترجمه‌های خاص action
      if (_translations!.containsKey(actionKey)) {
        final actionTrans = _translations![actionKey] as Map<String, dynamic>?;
        if (actionTrans != null && actionTrans.containsKey(labelKey)) {
          return actionTrans[labelKey] as String;
        }
      }
    }
    
    // Fallback: فرمت کردن enum value
    return enumValue
        .split('_')
        .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1))
        .join(' ');
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
      SnackBarHelper.show(context, message: 'هیچ نودی برای انتخاب وجود ندارد');
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

  /// ساخت Person Selector
  Widget _buildPersonSelector(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    final theme = Theme.of(context);
    
    // برای حالت reference
    if (currentValue?.toString().startsWith('\$') ?? false) {
      return _buildReferenceTextField(key, schema, currentValue, required, description);
    }
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatKey(key),
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 8),
          // Note: PersonComboboxWidget نیاز به businessId داره که باید از context بگیریم
          TextFormField(
            initialValue: currentValue?.toString(),
            decoration: InputDecoration(
              labelText: 'شناسه طرف حساب',
              border: OutlineInputBorder(),
              helperText: 'می‌توانید شناسه را وارد کنید یا از نود قبلی استفاده کنید: \$node_id.person_id',
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.allNodes != null && widget.allNodes!.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.link, size: 18),
                      tooltip: 'استفاده از نود قبلی',
                      onPressed: () => _showReferenceSelector(key),
                    ),
                  if (required)
                    Icon(Icons.star, size: 12, color: Colors.red),
                ],
              ),
            ),
            validator: required
                ? (v) => (v == null || v.isEmpty)
                    ? 'این فیلد الزامی است'
                    : null
                : null,
            onSaved: (newValue) {
              if (newValue != null && newValue.isNotEmpty) {
                _config[key] = int.tryParse(newValue) ?? newValue;
              } else if (!required) {
                _config.remove(key);
              }
            },
          ),
          const SizedBox(height: 8),
          Text(
            '💡 نکته: در حال حاضر باید شناسه طرف حساب را وارد کنید',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.orange,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  /// ساخت Product Selector
  Widget _buildProductSelector(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    // مشابه Person Selector - فعلاً TextField ساده
    return _buildPersonSelector(key, schema, currentValue, required, description ?? 'شناسه محصول');
  }

  /// ساخت Warehouse Selector (stub - برای آینده)
  Widget _buildWarehouseSelector(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    // فعلاً مانند TextField عددی عمل می‌کند
    return _buildNumberFieldWithReference(key, schema, currentValue, required, description, 'integer');
  }

  /// ساخت Account Selector (stub - برای آینده)
  Widget _buildAccountSelector(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    // فعلاً مانند TextField عددی عمل می‌کند
    return _buildNumberFieldWithReference(key, schema, currentValue, required, description, 'integer');
  }

  /// ساخت Fiscal Year Selector (stub - برای آینده)
  Widget _buildFiscalYearSelector(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    // فعلاً مانند TextField عددی عمل می‌کند
    return _buildNumberFieldWithReference(key, schema, currentValue, required, description, 'integer');
  }

  /// Helper: TextField عددی با پشتیبانی Reference
  Widget _buildNumberFieldWithReference(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
    String fieldType,
  ) {
    final theme = Theme.of(context);
    final isReference = currentValue?.toString().startsWith('\$') ?? false;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: currentValue?.toString(),
            decoration: InputDecoration(
              labelText: _formatKey(key),
              border: OutlineInputBorder(),
              helperText: description,
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
            keyboardType: isReference ? TextInputType.text : TextInputType.number,
            validator: required
                ? (v) => (v == null || v.isEmpty)
                    ? AppLocalizations.of(context).workflowNodeFieldRequired
                    : null
                : null,
            onSaved: (newValue) {
              if (newValue != null && newValue.isNotEmpty) {
                // اگر reference است، به صورت string ذخیره می‌شود
                if (newValue.startsWith('\$')) {
                  _config[key] = newValue;
                } else {
                  _config[key] = fieldType == 'integer' 
                      ? int.tryParse(newValue) ?? currentValue
                      : double.tryParse(newValue) ?? currentValue;
                }
              } else if (!required) {
                _config.remove(key);
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
  }

  /// ساخت Currency Selector
  Widget _buildCurrencySelector(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    final theme = Theme.of(context);
    
    // چک کردن اینکه آیا مقدار reference است
    if (currentValue?.toString().startsWith('\$') ?? false) {
      return _buildReferenceTextField(key, schema, currentValue, required, description);
    }
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loadingCurrencies)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text('در حال بارگذاری ارزها...'),
                ],
              ),
            )
          else if (_currencies.isEmpty)
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
                      'ارزی یافت نشد. لطفاً شناسه ارز را وارد کنید.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            DropdownButtonFormField<int>(
              value: currentValue is int ? currentValue : null,
              decoration: InputDecoration(
                labelText: _formatKey(key),
                border: OutlineInputBorder(),
                helperText: description,
                prefixIcon: Icon(Icons.monetization_on, size: 20),
                suffixIcon: required ? Icon(Icons.star, size: 12, color: Colors.red) : null,
              ),
              items: _currencies.map((currency) {
                final id = currency['id'] as int;
                final symbol = currency['symbol'] as String? ?? '';
                final name = currency['title'] as String? ?? currency['name'] as String? ?? '';
                final code = currency['code'] as String? ?? '';
                final isDefault = currency['is_default'] == true;
                
                return DropdownMenuItem<int>(
                  value: id,
                  child: Row(
                    children: [
                      Text(
                        symbol,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('$name ($code)'),
                      ),
                      if (isDefault)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'پیش‌فرض',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
              validator: required
                  ? (v) => v == null ? 'این فیلد الزامی است' : null
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
          if (widget.allNodes != null && widget.allNodes!.isNotEmpty && !_loadingCurrencies)
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
    );
  }

  /// ساخت Multi-Select Dropdown
  Widget _buildMultiSelect(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    final theme = Theme.of(context);
    final items = schema['items'] as Map<String, dynamic>?;
    final enumValues = items?['enum'] as List<dynamic>?;
    
    if (enumValues == null || enumValues.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          'خطا: enum values برای multi-select تعریف نشده است',
          style: TextStyle(color: Colors.red),
        ),
      );
    }
    
    final uiConfig = schema['ui_config'] as Map<String, dynamic>?;
    final labels = uiConfig?['labels'] as Map<String, dynamic>?;
    
    // مقدار فعلی باید لیست باشد
    List<String> selectedValues = [];
    if (currentValue is List) {
      selectedValues = currentValue.map((e) => e.toString()).toList();
    }
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatKey(key),
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: enumValues.map((enumValue) {
              final value = enumValue.toString();
              final label = labels?[value] as String? ?? value;
              final isSelected = selectedValues.contains(value);
              
              return FilterChip(
                label: Text(label),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      selectedValues.add(value);
                    } else {
                      selectedValues.remove(value);
                    }
                    _config[key] = List<String>.from(selectedValues);
                  });
                },
              );
            }).toList(),
          ),
          if (required && selectedValues.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'حداقل یک مورد را انتخاب کنید',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.red,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// ساخت Reference TextField (برای زمانی که مقدار reference است)
  Widget _buildReferenceTextField(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: currentValue?.toString(),
            decoration: InputDecoration(
              labelText: _formatKey(key),
              border: OutlineInputBorder(),
              helperText: description,
              prefixIcon: Icon(Icons.link, size: 18, color: theme.colorScheme.primary),
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
            validator: required
                ? (v) => (v == null || v.isEmpty)
                    ? 'این فیلد الزامی است'
                    : null
                : null,
            onSaved: (newValue) {
              if (newValue != null && newValue.isNotEmpty) {
                _config[key] = newValue;
              } else if (!required) {
                _config.remove(key);
              }
            },
          ),
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
  }

  /// دریافت placeholder برای فیلد
  String? _getPlaceholder(String key, String? description) {
    final keyLower = key.toLowerCase();
    
    // ابتدا بررسی ترجمه‌های موجود
    if (_translations != null && widget.node.key != null) {
      final actionKey = widget.node.key;
      final placeholderKey = 'field_${key}_placeholder';
      
      // جستجو در ترجمه‌های خاص action
      if (_translations!.containsKey(actionKey)) {
        final actionTrans = _translations![actionKey] as Map<String, dynamic>?;
        if (actionTrans != null && actionTrans.containsKey(placeholderKey)) {
          return actionTrans[placeholderKey] as String;
        }
      }
    }
    
    // Fallback به مقادیر پیش‌فرض
    final locale = Localizations.localeOf(context);
    final isFarsi = locale.languageCode == 'fa';
    
    if (keyLower.contains('email') || keyLower == 'to') {
      return isFarsi 
          ? 'مثال: user@example.com یا \$node_id.email'
          : 'Example: user@example.com or \$node_id.email';
    }
    if (keyLower.contains('amount') || keyLower.contains('price')) {
      return isFarsi
          ? 'مثال: 100000 یا \$node_id.total_amount'
          : 'Example: 100000 or \$node_id.total_amount';
    }
    if (keyLower.contains('subject') || keyLower.contains('title')) {
      return isFarsi
          ? 'مثال: فاکتور شماره \$node_id.invoice_number'
          : 'Example: Invoice #\$node_id.invoice_number';
    }
    if (keyLower.contains('message') || keyLower.contains('body')) {
      return isFarsi
          ? 'مثال: متن پیام یا \$node_id.description'
          : 'Example: Message text or \$node_id.description';
    }
    if (keyLower.contains('url')) {
      return isFarsi
          ? 'مثال: https://example.com/api'
          : 'Example: https://example.com/api';
    }
    if (description != null && description.contains('reference')) {
      return isFarsi
          ? 'مثال: \$node_id.field_name'
          : 'Example: \$node_id.field_name';
    }
    
    return null;
  }
}

/// Dialog برای انتخاب Reference از نودهای قبلی
class _ReferenceSelectorDialog extends StatefulWidget {
  final List<WorkflowNodeModel> allNodes;
  final WorkflowNodeModel currentNode;
  final Function(String) onSelected;

  const _ReferenceSelectorDialog({
    required this.allNodes,
    required this.currentNode,
    required this.onSelected,
  });

  @override
  State<_ReferenceSelectorDialog> createState() => _ReferenceSelectorDialogState();
}

class _ReferenceSelectorDialogState extends State<_ReferenceSelectorDialog> {
  WorkflowNodeModel? _selectedNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // فیلتر کردن نودهای قبل از نود فعلی
    final availableNodes = widget.allNodes.where((node) => node.id != widget.currentNode.id).toList();
    
    if (_selectedNode == null) {
      // مرحله 1: انتخاب نود
      return AlertDialog(
        title: const Text('انتخاب از نودهای قبلی'),
        content: SizedBox(
          width: 400,
          height: 400,
          child: availableNodes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('هیچ نودی برای انتخاب وجود ندارد'),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'مرحله 1: انتخاب نود',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: availableNodes.length,
                        itemBuilder: (context, index) {
                          final node = availableNodes[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(
                                _getNodeIcon(node.type),
                                color: _getNodeColor(node.type, theme),
                              ),
                              title: Text(node.label),
                              subtitle: Text(_getNodeTypeLabel(node.type)),
                              trailing: const Icon(Icons.arrow_forward),
                              onTap: () {
                                setState(() {
                                  _selectedNode = node;
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('انصراف'),
          ),
        ],
      );
    } else {
      // مرحله 2: انتخاب فیلد یا استفاده از کل نود
      return AlertDialog(
        title: Text('انتخاب داده از "${_selectedNode!.label}"'),
        content: SizedBox(
          width: 400,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'مرحله 2: انتخاب داده',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // گزینه استفاده از کل نود
              Card(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                child: ListTile(
                  leading: Icon(Icons.dataset, color: theme.colorScheme.primary),
                  title: const Text('استفاده از کل خروجی نود'),
                  subtitle: const Text('تمام داده‌های خروجی نود'),
                  trailing: const Icon(Icons.check_circle_outline),
                  onTap: () {
                    final reference = '\$${_selectedNode!.id}';
                    widget.onSelected(reference);
                    Navigator.of(context).pop();
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'یا یک فیلد خاص را انتخاب کنید:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _buildFieldsList(theme),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedNode = null;
              });
            },
            child: const Text('بازگشت'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('انصراف'),
          ),
        ],
      );
    }
  }

  Widget _buildFieldsList(ThemeData theme) {
    // لیست فیلدهای پیشنهادی بر اساس نوع نود
    final fields = _getSuggestedFields(_selectedNode!);
    
    if (fields.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'فیلدهای پیشنهادی برای این نود موجود نیست',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'می‌توانید به صورت دستی فیلد مورد نظر را تایپ کنید:\n\$${_selectedNode!.id}.field_name',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return ListView.builder(
      itemCount: fields.length,
      itemBuilder: (context, index) {
        final field = fields[index];
        return ListTile(
          leading: Icon(
            _getFieldIcon(field['type'] as String?),
            size: 20,
            color: theme.colorScheme.secondary,
          ),
          title: Text(field['name'] as String),
          subtitle: Text(field['description'] as String? ?? ''),
          trailing: const Icon(Icons.arrow_forward, size: 18),
          onTap: () {
            final fieldKey = field['key'] as String;
            final reference = '\$${_selectedNode!.id}.$fieldKey';
            widget.onSelected(reference);
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  List<Map<String, String>> _getSuggestedFields(WorkflowNodeModel node) {
    // فیلدهای پیشنهادی بر اساس نوع و key نود
    final key = node.key;
    
    if (key == null) return [];
    
    // فیلدهای مشترک برای تریگرهای فاکتور
    if (key.contains('invoice')) {
      return [
        {'key': 'invoice_id', 'name': 'شناسه فاکتور', 'description': 'شناسه عددی فاکتور', 'type': 'number'},
        {'key': 'invoice_code', 'name': 'کد فاکتور', 'description': 'کد یکتا فاکتور', 'type': 'string'},
        {'key': 'invoice_number', 'name': 'شماره فاکتور', 'description': 'شماره فاکتور', 'type': 'string'},
        {'key': 'invoice_date', 'name': 'تاریخ فاکتور', 'description': 'تاریخ صدور فاکتور', 'type': 'date'},
        {'key': 'total_amount', 'name': 'مبلغ کل', 'description': 'مبلغ کل فاکتور', 'type': 'number'},
        {'key': 'discount_amount', 'name': 'مبلغ تخفیف', 'description': 'مجموع تخفیفات', 'type': 'number'},
        {'key': 'tax_amount', 'name': 'مبلغ مالیات', 'description': 'مجموع مالیات', 'type': 'number'},
        {'key': 'final_amount', 'name': 'مبلغ نهایی', 'description': 'مبلغ قابل پرداخت', 'type': 'number'},
        {'key': 'customer_name', 'name': 'نام مشتری', 'description': 'نام طرف حساب', 'type': 'string'},
        {'key': 'customer_id', 'name': 'شناسه مشتری', 'description': 'شناسه طرف حساب', 'type': 'number'},
        {'key': 'description', 'name': 'توضیحات', 'description': 'توضیحات فاکتور', 'type': 'string'},
        {'key': 'status', 'name': 'وضعیت', 'description': 'وضعیت فاکتور', 'type': 'string'},
      ];
    }
    
    // فیلدهای مشترک برای تریگرهای پرداخت
    if (key.contains('payment')) {
      return [
        {'key': 'payment_id', 'name': 'شناسه پرداخت', 'description': 'شناسه عددی پرداخت', 'type': 'number'},
        {'key': 'amount', 'name': 'مبلغ', 'description': 'مبلغ پرداخت', 'type': 'number'},
        {'key': 'payment_date', 'name': 'تاریخ پرداخت', 'description': 'تاریخ پرداخت', 'type': 'date'},
        {'key': 'payment_method', 'name': 'روش پرداخت', 'description': 'نوع روش پرداخت', 'type': 'string'},
        {'key': 'status', 'name': 'وضعیت', 'description': 'وضعیت پرداخت', 'type': 'string'},
        {'key': 'reference_code', 'name': 'کد پیگیری', 'description': 'کد پیگیری تراکنش', 'type': 'string'},
      ];
    }
    
    // فیلدهای مشترک برای تریگرهای مشتری
    if (key.contains('person') || key.contains('customer')) {
      return [
        {'key': 'person_id', 'name': 'شناسه', 'description': 'شناسه طرف حساب', 'type': 'number'},
        {'key': 'name', 'name': 'نام', 'description': 'نام طرف حساب', 'type': 'string'},
        {'key': 'email', 'name': 'ایمیل', 'description': 'آدرس ایمیل', 'type': 'string'},
        {'key': 'phone', 'name': 'تلفن', 'description': 'شماره تلفن', 'type': 'string'},
        {'key': 'mobile', 'name': 'موبایل', 'description': 'شماره موبایل', 'type': 'string'},
        {'key': 'person_type', 'name': 'نوع', 'description': 'نوع طرف حساب', 'type': 'string'},
      ];
    }
    
    // فیلدهای مشترک برای تریگرهای محصول
    if (key.contains('product')) {
      return [
        {'key': 'product_id', 'name': 'شناسه محصول', 'description': 'شناسه عددی محصول', 'type': 'number'},
        {'key': 'name', 'name': 'نام محصول', 'description': 'نام محصول', 'type': 'string'},
        {'key': 'code', 'name': 'کد محصول', 'description': 'کد محصول', 'type': 'string'},
        {'key': 'price', 'name': 'قیمت', 'description': 'قیمت فروش', 'type': 'number'},
        {'key': 'quantity', 'name': 'تعداد', 'description': 'تعداد موجودی', 'type': 'number'},
      ];
    }
    
    // فیلدهای عمومی
    return [
      {'key': 'id', 'name': 'شناسه', 'description': 'شناسه رکورد', 'type': 'number'},
      {'key': 'name', 'name': 'نام', 'description': 'نام', 'type': 'string'},
      {'key': 'title', 'name': 'عنوان', 'description': 'عنوان', 'type': 'string'},
      {'key': 'description', 'name': 'توضیحات', 'description': 'توضیحات', 'type': 'string'},
      {'key': 'status', 'name': 'وضعیت', 'description': 'وضعیت', 'type': 'string'},
      {'key': 'created_at', 'name': 'تاریخ ایجاد', 'description': 'تاریخ و زمان ایجاد', 'type': 'date'},
    ];
  }

  IconData _getFieldIcon(String? type) {
    switch (type) {
      case 'number':
        return Icons.numbers;
      case 'string':
        return Icons.text_fields;
      case 'date':
        return Icons.calendar_today;
      case 'boolean':
        return Icons.toggle_on;
      default:
        return Icons.data_object;
    }
  }

  String _getNodeTypeLabel(WorkflowNodeType type) {
    switch (type) {
      case WorkflowNodeType.trigger:
        return 'تریگر';
      case WorkflowNodeType.action:
        return 'اکشن';
      case WorkflowNodeType.condition:
        return 'شرط';
      case WorkflowNodeType.loop:
        return 'حلقه';
    }
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


