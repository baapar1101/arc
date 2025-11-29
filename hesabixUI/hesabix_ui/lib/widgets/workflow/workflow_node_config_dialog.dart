import 'package:flutter/material.dart';
import '../../models/workflow_editor_models.dart';
import '../../models/workflow_editor_state.dart';
import '../../l10n/app_localizations.dart';

/// Dialog برای تنظیمات یک node
class WorkflowNodeConfigDialog extends StatefulWidget {
  final WorkflowNodeModel node;
  final WorkflowEditorState? editorState; // برای دسترسی به metadata
  final Map<String, dynamic>? schema; // JSON Schema برای validation (deprecated - use metadata)

  const WorkflowNodeConfigDialog({
    super.key,
    required this.node,
    this.editorState,
    this.schema,
  });

  @override
  State<WorkflowNodeConfigDialog> createState() => _WorkflowNodeConfigDialogState();
}

class _WorkflowNodeConfigDialogState extends State<WorkflowNodeConfigDialog> {
  late Map<String, dynamic> _config;
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic>? _configSchema;

  @override
  void initState() {
    super.initState();
    _config = Map<String, dynamic>.from(widget.node.config);
    
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
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // نمایش فیلدهای config بر اساس schema
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
                  ..._configSchema!.entries.map((entry) {
                    final fieldKey = entry.key;
                    final fieldSchema = entry.value as Map<String, dynamic>?;
                    final currentValue = _config[fieldKey];
                    return _buildConfigFieldFromSchema(fieldKey, fieldSchema, currentValue);
                  }).toList(),
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
        // Text field برای string
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
}


