import 'dart:convert';
import 'package:flutter/material.dart';
import '../../models/workflow_editor_models.dart';
import '../../models/workflow_editor_state.dart';
import '../../l10n/app_localizations.dart';
import '../../services/workflow_service.dart';
import '../../services/workflow_translation_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../core/api_client.dart';
import '../../core/date_utils.dart' as date_utils;
import '../../models/person_model.dart';
import '../../services/person_service.dart';
import '../../services/product_service.dart';
import '../../services/warehouse_service.dart';
import '../../services/account_service.dart';
import '../../services/business_dashboard_service.dart';
import '../../models/business_user_model.dart';
import '../../services/business_user_service.dart';
import '../../models/warehouse_model.dart';
import '../invoice/person_combobox_widget.dart';
import '../invoice/product_combobox_widget.dart';
import '../jalali_date_picker.dart';

/// عملگرهای شرط ساده (هم‌خوان با workflow_engine)
const _kWorkflowConditionOperators = <String>[
  '==', '!=', '>', '<', '>=', '<=',
  'contains', 'not_contains', 'starts_with', 'ends_with',
  'in', 'not_in', 'is_null', 'is_not_null',
];

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
  List<Map<String, dynamic>> _baleUsers = [];
  bool _loadingBaleUsers = false;
  Map<String, dynamic>? _translations;
  List<Map<String, dynamic>> _currencies = [];
  bool _loadingCurrencies = false;
  List<Map<String, dynamic>> _smsTemplates = [];
  bool _loadingSmsTemplates = false;
  Map<String, dynamic>? _smsTemplateDetail;
  Map<String, dynamic>? _smsCostEstimate;
  bool _loadingSmsCost = false;

  /// همگام با انتخاب reference از نود قبلی (initialValue به‌تنهایی به‌روز نمی‌شود)
  final Map<String, TextEditingController> _workflowTextControllers = {};

  @override
  void dispose() {
    for (final c in _workflowTextControllers.values) {
      c.dispose();
    }
    _workflowTextControllers.clear();
    super.dispose();
  }

  TextEditingController _ensureWorkflowTextController(String key) {
    return _workflowTextControllers.putIfAbsent(
      key,
      () => TextEditingController(text: _config[key]?.toString() ?? ''),
    );
  }

  void _syncWorkflowTextControllersToConfig() {
    for (final e in _workflowTextControllers.entries) {
      _config[e.key] = e.value.text;
    }
  }

  /// فیلدهای متنی که معمولاً چند reference در یک جمله دارند: درج در موقعیت مکان‌نما به‌جای جایگزینی کل مقدار
  bool _fieldKeyPrefersInsertReference(String key, Map<String, dynamic>? schema) {
    if (schema != null && schema['ui_type'] == 'textarea') {
      return true;
    }
    final k = key.toLowerCase();
    const multiRefHints = <String>[
      'message', 'body', 'text', 'html', 'content', 'template',
      'caption', 'description', 'subject', 'title',
    ];
    for (final p in multiRefHints) {
      if (k == p || k.contains(p)) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _config = <String, dynamic>{};
    _config.addAll(widget.node.config);
    
    // دریافت config_schema از metadata
    if (widget.editorState != null && widget.node.key != null) {
      if (widget.node.type == WorkflowNodeType.trigger) {
        try {
          final metadata = widget.editorState!.triggers
              .firstWhere((t) => t.key == widget.node.key, orElse: () => throw StateError(''));
          _configSchema = metadata.configSchema;
        } catch (_) {}
      } else if (widget.node.type == WorkflowNodeType.action) {
        try {
          final metadata = widget.editorState!.actions
              .firstWhere((a) => a.key == widget.node.key, orElse: () => throw StateError(''));
          _configSchema = metadata.configSchema;
        } catch (_) {}
      }
    }
    if (widget.node.type == WorkflowNodeType.condition) {
      _configSchema = _getConditionConfigSchema(widget.node.key?.toString());
      if (_configSchema != null) {
        _configSchema!.forEach((key, schema) {
          if (schema is Map<String, dynamic> &&
              !_config.containsKey(key) &&
              schema['default'] != null) {
            _config[key] = schema['default'];
          }
        });
      }
      _migrateConditionConfigDefaults();
      _ensureConditionsListIfComplex();
    }
    if (widget.node.type == WorkflowNodeType.loop) {
      final loopKey = widget.node.key ?? (
        widget.node.config['loop_type'] == 'for_range' ? 'loop.for' :
        widget.node.config['loop_type'] == 'while' ? 'loop.while' : 'loop.for_each'
      );
      _configSchema = _getLoopConfigSchema(loopKey.toString());
      // flatten condition برای while loop
      final cond = _config['condition'];
      if (cond is Map) {
        _config['condition_left_value'] = cond['left_value']?.toString() ?? '';
        _config['condition_operator'] = cond['operator']?.toString() ?? '==';
        _config['condition_right_value'] = cond['right_value']?.toString() ?? '';
      }
      // اعمال defaultها برای loop
      if (_configSchema != null) {
        _configSchema!.forEach((key, schema) {
          if (schema is Map<String, dynamic> && !_config.containsKey(key) && schema['default'] != null) {
            _config[key] = schema['default'];
          }
        });
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
    
    // بارگذاری کاربران متصل به بله اگر لازم باشد
    _loadBaleUsersIfNeeded();
    
    // بارگذاری ارزها اگر لازم باشد
    _loadCurrenciesIfNeeded();

    // قالب‌های SMS برای نود ارسال پیامک
    _loadSmsTemplatesIfNeeded();
    
    // بارگذاری ترجمه‌ها
    _loadTranslations();
  }

  Future<void> _loadSmsTemplatesIfNeeded() async {
    if (widget.businessId == null) return;
    var need = widget.node.key == 'send_business_sms';
    if (!need && _configSchema != null) {
      for (final e in _configSchema!.entries) {
        final s = e.value;
        if (s is Map<String, dynamic> && s['ui_type'] == 'sms_template_selector') {
          need = true;
          break;
        }
      }
    }
    if (!need) return;

    setState(() => _loadingSmsTemplates = true);
    try {
      final list = await _workflowService.listApprovedSmsTemplates(
        businessId: widget.businessId!,
      );
      if (!mounted) return;
      setState(() {
        _smsTemplates = list;
        _loadingSmsTemplates = false;
      });
      await _prefetchSmsTemplateDetailForCurrentConfig();
    } catch (e) {
      debugPrint('خطا در بارگذاری قالب‌های SMS: $e');
      if (mounted) setState(() => _loadingSmsTemplates = false);
    }
  }

  Future<void> _prefetchSmsTemplateDetailForCurrentConfig() async {
    if (widget.businessId == null || widget.node.key != 'send_business_sms') return;
    final id = _parseIntOrNull(_config['template_id']);
    if (id == null) {
      if (mounted) {
        setState(() {
          _smsTemplateDetail = null;
          _smsCostEstimate = null;
        });
      }
      return;
    }
    setState(() => _loadingSmsCost = true);
    try {
      final results = await Future.wait([
        _workflowService.getNotificationTemplate(
          businessId: widget.businessId!,
          templateId: id,
        ),
        _workflowService.estimateSmsTemplateCost(
          businessId: widget.businessId!,
          templateId: id,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _smsTemplateDetail = results[0];
        _smsCostEstimate = results[1];
        _loadingSmsCost = false;
      });
    } catch (e) {
      debugPrint('جزئیات/برآورد قالب SMS: $e');
      if (mounted) {
        setState(() {
          _smsTemplateDetail = null;
          _smsCostEstimate = null;
          _loadingSmsCost = false;
        });
      }
    }
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

  Future<void> _loadBaleUsersIfNeeded() async {
    if (widget.businessId == null) return;
    
    bool needsBaleUsers = false;
    if (_configSchema != null) {
      for (final entry in _configSchema!.entries) {
        final schema = entry.value;
        if (schema is Map<String, dynamic>) {
          final uiType = schema['ui_type'] as String?;
          if (uiType == 'bale_user_selector') {
            needsBaleUsers = true;
            break;
          }
        }
      }
    }
    
    if (needsBaleUsers) {
      setState(() => _loadingBaleUsers = true);
      try {
        final users = await _workflowService.getBaleConnectedUsers(
          businessId: widget.businessId!,
        );
        setState(() {
          _baleUsers = users;
          _loadingBaleUsers = false;
        });
      } catch (e) {
        setState(() => _loadingBaleUsers = false);
        debugPrint('خطا در بارگذاری کاربران بله: $e');
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

  Map<String, dynamic>? _getConditionConfigSchema(String? conditionKey) {
    switch (conditionKey) {
      case 'condition.switch':
        return {
          'condition_type': {
            'type': 'string',
            'default': 'complex',
            'enum': ['complex', 'expression'],
            'description': 'چند شرط (AND/OR) یا یک عبارت بولی',
          },
          'logical_operator': {
            'type': 'string',
            'enum': ['AND', 'OR'],
            'default': 'OR',
            'description': 'ترکیب چند شرط ساده',
          },
          'expression': {
            'type': 'string',
            'description':
                'عبارت بولی (SimpleEval). مثال: resolve("\$n1.amount") > 100 یا context["trigger_data"]["invoice_id"]',
            'ui_type': 'textarea',
            'required': false,
          },
          'on_error': {
            'type': 'string',
            'enum': ['fail', 'false', 'true'],
            'default': 'fail',
            'description': 'رفتار در خطای ارزیابی',
          },
        };
      case 'condition.if':
      case 'condition.compare':
      default:
        return {
          'condition_type': {
            'type': 'string',
            'default': 'simple',
            'enum': ['simple', 'complex', 'expression'],
            'description': 'نوع شرط',
          },
          'left_value': {
            'type': 'string',
            'description': 'مقدار چپ یا \$node_id.field',
          },
          'operator': {
            'type': 'string',
            'enum': _kWorkflowConditionOperators,
            'default': '==',
            'description': 'عملگر',
          },
          'right_value': {
            'type': 'string',
            'description': 'مقدار راست',
          },
          'logical_operator': {
            'type': 'string',
            'enum': ['AND', 'OR'],
            'default': 'AND',
            'description': 'ترکیب چند شرط (فقط حالت complex)',
          },
          'expression': {
            'type': 'string',
            'description': 'فقط در حالت expression',
            'ui_type': 'textarea',
            'required': false,
          },
          'on_error': {
            'type': 'string',
            'enum': ['fail', 'false', 'true'],
            'default': 'fail',
            'description': 'رفتار در خطا',
          },
        };
    }
  }

  void _migrateConditionConfigDefaults() {
    if (widget.node.type != WorkflowNodeType.condition) return;
    if (widget.node.key != 'condition.switch') return;

    final ct = _config['condition_type']?.toString();
    final expr = _config['expression']?.toString().trim() ?? '';
    final conds = _config['conditions'];
    final hasComplex = conds is List && conds.isNotEmpty;

    if (ct == null || ct.isEmpty) {
      if (expr.isNotEmpty && !hasComplex) {
        _config['condition_type'] = 'expression';
      } else {
        _config['condition_type'] = 'complex';
      }
    }
  }

  bool _showComplexConditionsUI() {
    if (widget.node.type != WorkflowNodeType.condition) return false;
    final nk = widget.node.key;
    final ct = _config['condition_type']?.toString() ?? '';
    if (nk == 'condition.switch') {
      return ct != 'expression';
    }
    return ct == 'complex';
  }

  void _ensureConditionsListIfComplex() {
    if (!_showComplexConditionsUI()) return;
    _ensureConditionsList();
  }

  void _ensureConditionsList() {
    final c = _config['conditions'];
    if (c is! List || c.isEmpty) {
      _config['conditions'] = [
        <String, dynamic>{'left_value': '', 'operator': '==', 'right_value': ''},
      ];
      return;
    }
    final out = <Map<String, dynamic>>[];
    for (final e in c) {
      if (e is Map) {
        out.add({
          'left_value': '${e['left_value'] ?? ''}',
          'operator': '${e['operator'] ?? '=='}',
          'right_value': '${e['right_value'] ?? ''}',
        });
      }
    }
    if (out.isEmpty) {
      out.add({'left_value': '', 'operator': '==', 'right_value': ''});
    }
    _config['conditions'] = out;
  }

  bool _shouldShowConditionSchemaField(String fieldKey) {
    if (widget.node.type != WorkflowNodeType.condition) return true;
    final nk = widget.node.key;
    var ct = _config['condition_type']?.toString() ?? 'simple';
    if (nk == 'condition.switch') {
      ct = _config['condition_type']?.toString() ?? 'complex';
      if (fieldKey == 'expression') {
        return ct == 'expression';
      }
      if (fieldKey == 'logical_operator') {
        return ct != 'expression';
      }
      return true;
    }
    if (fieldKey == 'left_value' || fieldKey == 'operator' || fieldKey == 'right_value') {
      return ct == 'simple';
    }
    if (fieldKey == 'logical_operator') {
      return ct == 'complex';
    }
    if (fieldKey == 'expression') {
      return ct == 'expression';
    }
    return true;
  }

  void _onConditionTypeChanged(String newType) {
    if (widget.node.type != WorkflowNodeType.condition) return;
    final nk = widget.node.key;
    final needList = (nk == 'condition.switch' && newType != 'expression') ||
        (nk != 'condition.switch' && newType == 'complex');
    if (needList) {
      _ensureConditionsList();
    }
  }

  void _finalizeConditionConfigForSave() {
    if (widget.node.type != WorkflowNodeType.condition) return;
    final nk = widget.node.key;
    var ct = _config['condition_type']?.toString() ?? '';
    if (nk == 'condition.switch') {
      if (ct == 'expression') {
        _config.remove('conditions');
        _config.remove('logical_operator');
      } else {
        _config['condition_type'] = 'complex';
        _ensureConditionsList();
        _config.remove('expression');
      }
      return;
    }
    if (ct == 'expression') {
      _config.remove('left_value');
      _config.remove('operator');
      _config.remove('right_value');
      _config.remove('logical_operator');
      _config.remove('conditions');
    } else if (ct == 'complex') {
      _ensureConditionsList();
      _config.remove('left_value');
      _config.remove('operator');
      _config.remove('right_value');
      _config.remove('expression');
    } else {
      _config.remove('expression');
      _config.remove('logical_operator');
      _config.remove('conditions');
    }
  }

  bool _validateConditionExpressionIfNeeded() {
    if (widget.node.type != WorkflowNodeType.condition) return true;
    final ct = _config['condition_type']?.toString() ?? '';
    if (ct != 'expression') return true;
    _syncWorkflowTextControllersToConfig();
    final ex = _config['expression']?.toString().trim() ?? '';
    if (ex.isEmpty) {
      SnackBarHelper.show(
        context,
        message: 'عبارت شرط (expression) را وارد کنید',
      );
      return false;
    }
    return true;
  }

  Widget _buildComplexConditionsEditor() {
    _ensureConditionsList();
    final theme = Theme.of(context);
    final fromConfig = _config['conditions'];
    final rows = <Map<String, dynamic>>[];
    if (fromConfig is List) {
      for (final e in fromConfig) {
        if (e is Map) {
          rows.add(Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v))));
        }
      }
    }
    if (rows.isEmpty) {
      rows.add({'left_value': '', 'operator': '==', 'right_value': ''});
    }
    _config['conditions'] = rows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'شرط‌های ترکیبی (هر ردیف یک مقایسهٔ ساده؛ با AND/OR در بالا ترکیب می‌شود)',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...List.generate(rows.length, (i) {
          final row = rows[i];
          final op = row['operator']?.toString() ?? '==';
          final safeOp = _kWorkflowConditionOperators.contains(op) ? op : '==';
          if (safeOp != op) {
            row['operator'] = safeOp;
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('شرط ${i + 1}', style: theme.textTheme.labelLarge),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'حذف',
                          onPressed: rows.length <= 1
                              ? null
                              : () {
                                  setState(() {
                                    rows.removeAt(i);
                                    _config['conditions'] = rows;
                                  });
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: ValueKey('cond_l_${widget.node.id}_${identityHashCode(row)}'),
                      initialValue: row['left_value']?.toString() ?? '',
                      decoration: const InputDecoration(
                        labelText: 'مقدار چپ',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => row['left_value'] = v,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: safeOp,
                      decoration: const InputDecoration(
                        labelText: 'عملگر',
                        border: OutlineInputBorder(),
                      ),
                      items: _kWorkflowConditionOperators
                          .map((o) => DropdownMenuItem<String>(value: o, child: Text(o)))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          row['operator'] = v ?? '==';
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: ValueKey('cond_r_${widget.node.id}_${identityHashCode(row)}'),
                      initialValue: row['right_value']?.toString() ?? '',
                      decoration: const InputDecoration(
                        labelText: 'مقدار راست',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => row['right_value'] = v,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        TextButton.icon(
          onPressed: () {
            setState(() {
              rows.add({'left_value': '', 'operator': '==', 'right_value': ''});
              _config['conditions'] = rows;
            });
          },
          icon: const Icon(Icons.add),
          label: const Text('افزودن شرط'),
        ),
      ],
    );
  }

  Map<String, dynamic>? _getLoopConfigSchema(String loopKey) {
    if (loopKey == 'loop.for_each') {
      return {
        'loop_type': {'type': 'string', 'default': 'for_each', 'description': 'نوع حلقه'},
        'items_source': {
          'type': 'string',
          'description': 'منبع آیتم‌ها (آرایه یا reference مثل \$node_id)',
          'required': false,
        },
        'item_variable': {'type': 'string', 'default': 'item', 'description': 'نام متغیر آیتم'},
        'index_variable': {'type': 'string', 'default': 'index', 'description': 'نام متغیر اندیس'},
        'max_iterations': {'type': 'number', 'default': 1000, 'description': 'حداکثر تعداد تکرار'},
      };
    }
    if (loopKey == 'loop.for') {
      return {
        'loop_type': {'type': 'string', 'default': 'for_range'},
        'start': {'type': 'number', 'default': 0, 'description': 'شروع بازه'},
        'end': {'type': 'number', 'default': 10, 'description': 'پایان بازه'},
        'step': {'type': 'number', 'default': 1, 'description': 'گام'},
        'index_variable': {'type': 'string', 'default': 'index', 'description': 'نام متغیر اندیس'},
        'max_iterations': {'type': 'number', 'default': 1000, 'description': 'حداکثر تعداد تکرار'},
      };
    }
    if (loopKey == 'loop.while') {
      return {
        'loop_type': {'type': 'string', 'default': 'while'},
        'condition_left_value': {
          'type': 'string',
          'description': 'مقدار چپ شرط (یا reference مثل \$node_id.field)',
        },
        'condition_operator': {
          'type': 'string',
          'enum': ['==', '!=', '>', '<', '>=', '<=', 'contains'],
          'default': '==',
          'description': 'عملگر مقایسه',
        },
        'condition_right_value': {
          'type': 'string',
          'description': 'مقدار راست شرط',
        },
        'max_iterations': {'type': 'number', 'default': 1000, 'description': 'حداکثر تعداد تکرار'},
      };
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            _getNodeIcon(widget.node.type, widget.node.key),
            color: _getNodeColor(widget.node.type, theme, widget.node.key),
          ),
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
                if (_showComplexConditionsUI()) ...[
                  const SizedBox(height: 8),
                  _buildComplexConditionsEditor(),
                ],
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
            _syncWorkflowTextControllersToConfig();
            if (!_validateConditionExpressionIfNeeded()) {
              return;
            }
            if (_formKey.currentState?.validate() ?? false) {
              _formKey.currentState?.save();
              if (widget.node.type == WorkflowNodeType.condition) {
                _finalizeConditionConfigForSave();
              }
              // برای while loop: ساختن condition از فیلدهای flat
              if (widget.node.type == WorkflowNodeType.loop &&
                  (_config['loop_type'] == 'while' || widget.node.key == 'loop.while')) {
                _config['condition'] = {
                  'left_value': _config['condition_left_value'] ?? '',
                  'operator': _config['condition_operator'] ?? '==',
                  'right_value': _config['condition_right_value'] ?? '',
                };
                _config.remove('condition_left_value');
                _config.remove('condition_operator');
                _config.remove('condition_right_value');
              }
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
                    if (widget.node.type == WorkflowNodeType.condition && key == 'condition_type') {
                      _onConditionTypeChanged(newValue);
                    }
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
        } else if (uiType == 'bale_user_selector') {
          return _buildBaleUserSelector(key, schema, value, required, description);
        } else if (uiType == 'person_selector') {
          return _buildPersonSelector(key, schema, value, required, description);
        } else if (uiType == 'product_selector') {
          return _buildProductSelector(key, schema, value, required, description);
        } else if (uiType == 'currency_selector') {
          return _buildCurrencySelector(key, schema, value, required, description);
        } else if (uiType == 'date_picker') {
          return _buildDatePicker(key, schema, value, required, description);
        } else if (uiType == 'textarea') {
          return _buildTextarea(key, schema, value, required, description);
        }
        
        // Text field برای string با پشتیبانی از Reference
        final placeholder = _getPlaceholder(key, description);

        return Builder(
          builder: (context) {
            final theme = Theme.of(context);
            final c = _ensureWorkflowTextController(key);
            final hasRef = c.text.contains(r'$');
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: c,
                    decoration: InputDecoration(
                      labelText: _formatKey(key),
                      border: OutlineInputBorder(),
                      helperText: description,
                      hintText: placeholder,
                      prefixIcon: hasRef
                          ? Icon(Icons.link, size: 18, color: theme.colorScheme.primary)
                          : null,
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.allNodes != null && widget.allNodes!.isNotEmpty)
                            IconButton(
                              icon: Icon(Icons.select_all, size: 18),
                              tooltip: AppLocalizations.of(context).workflowConfigSelectFromNodes,
                              onPressed: () => _showReferenceSelector(key, fieldSchema: schema),
                            ),
                          if (required)
                            Icon(Icons.star, size: 12, color: Colors.red),
                        ],
                      ),
                    ),
                    validator: required
                        ? (_) => c.text.trim().isEmpty
                            ? AppLocalizations.of(context).workflowNodeFieldRequired
                            : null
                        : null,
                    onChanged: (v) {
                      _config[key] = v;
                      setState(() {});
                    },
                    onSaved: (_) {
                      final newValue = c.text;
                      if (newValue.isNotEmpty) {
                        _config[key] = newValue;
                      } else if (!required) {
                        _config.remove(key);
                      } else {
                        _config[key] = '';
                      }
                    },
                  ),
                  if (hasRef)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, right: 12),
                      child: Text(
                        AppLocalizations.of(context).workflowConfigValueUsesNode,
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
        if (uiType == 'sms_template_selector') {
          return _buildSmsTemplateSelector(key, schema, value, required, description);
        } else if (uiType == 'currency_selector') {
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
        } else if (uiType == 'user_selector') {
          return _buildUserSelector(key, schema, value, required, description);
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
        final arrUiType = schema['ui_type'] as String?;
        if (arrUiType == 'multi_select') {
          return _buildMultiSelect(key, schema, value, required, description);
        }
        if (arrUiType == 'invoice_items_builder') {
          return _buildInvoiceItemsBuilder(key, schema, value, required, description);
        }
        if (arrUiType == 'payments_builder') {
          return _buildPaymentsBuilder(key, schema, value, required, description);
        }
        // آرایهٔ رشته‌ها (cc, bcc, channels و مانند آن)
        final itemsSchema = schema['items'] as Map<String, dynamic>?;
        if (itemsSchema != null && itemsSchema['type'] == 'string') {
          return _buildStringArrayEditor(key, schema, value, required, description);
        }
        // Default array handling
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            '$_formatKey(key): ${AppLocalizations.of(context).workflowNodeArrayType}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        );
        
      case 'object':
        final objUiType = schema['ui_type'] as String?;
        if (objUiType == 'discount_config') {
          return _buildDiscountConfig(key, schema, value, required, description);
        }
        if (objUiType == 'json_editor') {
          return _buildJsonEditor(key, schema, value, required, description);
        }
        // برای objectهای دیگر، نمایش ساده
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
      if (widget.node.type == WorkflowNodeType.condition &&
          !_shouldShowConditionSchemaField(fieldKey)) {
        continue;
      }
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
      return AppLocalizations.of(context).workflowConfigGroupFilters;
    }
    
    // گروه زمان‌بندی
    if (keyLower.contains('timeout') || 
        keyLower.contains('cooldown') ||
        keyLower.contains('schedule') ||
        keyLower.contains('delay') ||
        keyLower.contains('retry_delay')) {
      return AppLocalizations.of(context).workflowConfigGroupScheduling;
    }
    
    // گروه Retry و خطا
    if (keyLower.contains('retry') || 
        keyLower.contains('error') ||
        keyLower.contains('on_error') ||
        keyLower.contains('break_on_error') ||
        keyLower.contains('continue_on_error') ||
        keyLower.contains('stop_workflow') ||
        keyLower.contains('send_failure')) {
      return AppLocalizations.of(context).workflowConfigGroupErrorManagement;
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
        keyLower == 'invoice_type' ||
        keyLower == 'template_id' ||
        keyLower == 'person_id' ||
        keyLower == 'recipient_mobile') {
      return AppLocalizations.of(context).workflowConfigGroupMainSettings;
    }
    
    // گروه تنظیمات پیشرفته
    if (keyLower.contains('include_') ||
        keyLower.contains('template') ||
        keyLower.contains('priority') ||
        keyLower.contains('channels') ||
        keyLower.contains('parse_mode')) {
      return AppLocalizations.of(context).workflowConfigGroupAdvanced;
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
    // ترجمه از API
    if (_translations != null && widget.node.key != null) {
      final actionKey = widget.node.key;
      final fieldKey = 'field_$key';
      if (_translations!.containsKey(actionKey)) {
        final actionTrans = _translations![actionKey] as Map<String, dynamic>?;
        if (actionTrans != null && actionTrans.containsKey(fieldKey)) {
          return actionTrans[fieldKey] as String;
        }
      }
      if (_translations!.containsKey(fieldKey)) {
        return _translations![fieldKey] as String;
      }
    }

    // ترجمه از AppLocalizations برای کلیدهای متداول
    final t = AppLocalizations.of(context);
    final localized = _getConfigFieldLabel(key, t);
    if (localized != null) return localized;

    // Fallback: تبدیل به عنوان خوانا (فقط اگر کلید ناشناخته بود)
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  String? _getConfigFieldLabel(String key, AppLocalizations t) {
    switch (key) {
      case 'enabled': return t.workflowConfigFieldEnabled;
      case 'to': return t.workflowConfigFieldTo;
      case 'subject': return t.workflowConfigFieldSubject;
      case 'body': return t.workflowConfigFieldBody;
      case 'message': return t.workflowConfigFieldMessage;
      case 'min_amount': return t.workflowConfigFieldMinAmount;
      case 'max_amount': return t.workflowConfigFieldMaxAmount;
      case 'status_filter': return t.workflowConfigFieldStatusFilter;
      case 'person_type': return t.workflowConfigFieldPersonType;
      case 'currency': return t.workflowConfigFieldCurrency;
      case 'person_id': return t.workflowConfigFieldPersonId;
      case 'product_id': return t.workflowConfigFieldProductId;
      case 'warehouse_id': return t.workflowConfigFieldWarehouseId;
      case 'account_id': return t.workflowConfigFieldAccountId;
      case 'retry_count': return t.workflowConfigFieldRetryCount;
      case 'retry_delay': return t.workflowConfigFieldRetryDelay;
      case 'on_error': return t.workflowConfigFieldOnError;
      case 'break_on_error': return t.workflowConfigFieldBreakOnError;
      case 'continue_on_error': return t.workflowConfigFieldContinueOnError;
      case 'trigger_type': return t.workflowConfigFieldTriggerType;
      case 'action_type': return t.workflowConfigFieldActionType;
      case 'loop_type': return t.workflowConfigFieldLoopType;
      case 'items_source': return t.workflowConfigFieldItemsSource;
      case 'item_variable': return t.workflowConfigFieldItemVariable;
      case 'index_variable': return t.workflowConfigFieldIndexVariable;
      case 'max_iterations': return t.workflowConfigFieldMaxIterations;
      case 'start': return t.workflowConfigFieldStart;
      case 'end': return t.workflowConfigFieldEnd;
      case 'step': return t.workflowConfigFieldStep;
      case 'condition_left_value': return t.workflowConfigFieldConditionLeft;
      case 'condition_operator': return t.workflowConfigFieldConditionOperator;
      case 'condition_right_value': return t.workflowConfigFieldConditionRight;
      case 'timeout': return t.workflowConfigFieldTimeout;
      case 'cooldown': return t.workflowConfigFieldCooldown;
      case 'schedule': return t.workflowConfigFieldSchedule;
      case 'delay': return t.workflowConfigFieldDelay;
      case 'retry_delay_sec': return t.workflowConfigFieldRetryDelay;
      case 'document_type': return t.workflowConfigFieldDocumentType;
      case 'fiscal_year_filter': return t.workflowConfigFieldFiscalYearFilter;
      case 'fiscal_year_id': return t.workflowConfigFieldFiscalYearId;
      case 'user_id_filter': return t.workflowConfigFieldUserIdFilter;
      case 'description_contains': return t.workflowConfigFieldDescriptionContains;
      case 'cooldown_seconds': return t.workflowConfigFieldCooldownSeconds;
      case 'timeout_seconds': return t.workflowConfigFieldTimeoutSeconds;
      case 'invoice_type': return t.workflowConfigFieldInvoiceType;
      case 'person_type_filter': return t.workflowConfigFieldPersonTypeFilter;
      case 'currency_id': return t.workflowConfigFieldCurrencyId;
      case 'include_tax_details': return t.workflowConfigFieldIncludeTaxDetails;
      case 'include_payment_status': return t.workflowConfigFieldIncludePaymentStatus;
      case 'account_id_filter': return t.workflowConfigFieldAccountIdFilter;
      case 'payment_method_filter': return t.workflowConfigFieldPaymentMethodFilter;
      case 'include_balance': return t.workflowConfigFieldIncludeBalance;
      case 'check_duplicate': return t.workflowConfigFieldCheckDuplicate;
      case 'type_filter': return t.workflowConfigFieldTypeFilter;
      case 'type': return t.workflowConfigType;
      case 'check_type': return t.workflowConfigFieldCheckType;
      case 'days_before': return t.workflowConfigFieldDaysBefore;
      case 'reference_code': return t.workflowConfigFieldReferenceCode;
      case 'extra_info': return t.workflowConfigFieldExtraInfo;
      case 'is_proforma': return t.workflowConfigFieldIsProforma;
      default: return null;
    }
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

  Color _getNodeColor(WorkflowNodeType type, ThemeData theme, String? nodeKey) {
    if (type == WorkflowNodeType.action && nodeKey == 'send_business_sms') {
      return Colors.teal.shade700;
    }
    if (type == WorkflowNodeType.action && nodeKey == 'send_email') {
      return Colors.indigo.shade600;
    }
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

  IconData _getNodeIcon(WorkflowNodeType type, [String? nodeKey]) {
    if (type == WorkflowNodeType.action) {
      switch (nodeKey) {
        case 'send_business_sms':
          return Icons.sms_outlined;
        case 'send_email':
          return Icons.email_outlined;
        case 'send_telegram':
          return Icons.send;
        case 'send_bale':
          return Icons.chat;
        case 'http_request':
          return Icons.http;
        default:
          return Icons.play_arrow;
      }
    }
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
  void _showReferenceSelector(String fieldKey, {Map<String, dynamic>? fieldSchema}) {
    if (widget.allNodes == null || widget.allNodes!.isEmpty) {
      SnackBarHelper.show(context, message: AppLocalizations.of(context).workflowConfigNoNodesToSelect);
      return;
    }

    final insertReference = _fieldKeyPrefersInsertReference(fieldKey, fieldSchema);
    _ensureWorkflowTextController(fieldKey);

    showDialog(
      context: context,
      builder: (dialogContext) => _ReferenceSelectorDialog(
        allNodes: widget.allNodes!,
        currentNode: widget.node,
        onSelected: (reference) {
          setState(() {
            final c = _workflowTextControllers[fieldKey]!;
            if (insertReference) {
              final text = c.text;
              final sel = c.selection;
              int start;
              int end;
              if (sel.isValid && sel.start >= 0 && sel.end >= 0) {
                start = sel.start.clamp(0, text.length);
                end = sel.end.clamp(0, text.length);
              } else {
                start = end = text.length;
              }
              final before = text.substring(0, start);
              final after = text.substring(end);
              var insert = reference;
              if (before.isNotEmpty &&
                  !before.endsWith(' ') &&
                  !insert.startsWith(' ')) {
                insert = ' $insert';
              }
              if (after.isNotEmpty &&
                  !after.startsWith(' ') &&
                  !insert.endsWith(' ')) {
                insert = '$insert ';
              }
              final newText = before + insert + after;
              c.value = TextEditingValue(
                text: newText,
                selection: TextSelection.collapsed(offset: (before + insert).length),
              );
              _config[fieldKey] = newText;
            } else {
              _config[fieldKey] = reference;
              c.value = TextEditingValue(
                text: reference,
                selection: TextSelection.collapsed(offset: reference.length),
              );
            }
          });
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
                      AppLocalizations.of(context).workflowConfigNoTelegramUsers,
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
                    helperText: description ?? AppLocalizations.of(context).workflowConfigSelectTelegramUser,
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
                    final name = user['name']?.toString() ?? AppLocalizations.of(context).workflowConfigUserDefault;
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
                                    AppLocalizations.of(context).workflowConfigOwner,
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
                      _disposeWorkflowTextController(key);
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
                      label: Text(AppLocalizations.of(context).workflowConfigUsePreviousNode),
                      onPressed: () => _showReferenceSelector(key, fieldSchema: schema),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// ساخت Bale User Selector
  Widget _buildBaleUserSelector(
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
          if (_loadingBaleUsers)
            const LinearProgressIndicator()
          else if (_baleUsers.isEmpty)
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
                      AppLocalizations.of(context).workflowConfigNoBaleUsers,
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
                    helperText: description ?? AppLocalizations.of(context).workflowConfigSelectBaleUser,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble, size: 18, color: theme.colorScheme.primary),
                        if (required)
                          Icon(Icons.star, size: 12, color: Colors.red),
                      ],
                    ),
                    prefixIcon: selectedUserId != null
                        ? Icon(Icons.person, color: theme.colorScheme.primary)
                        : null,
                  ),
                  items: _baleUsers.map((user) {
                    final userId = user['user_id']?.toString() ?? '';
                    final name = user['name']?.toString() ?? AppLocalizations.of(context).workflowConfigUserDefault;
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
                                    AppLocalizations.of(context).workflowConfigOwner,
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
                      _disposeWorkflowTextController(key);
                      if (newValue != null) {
                        _config[key] = newValue;
                      } else if (!required) {
                        _config.remove(key);
                      }
                    });
                  },
                ),
                if (widget.allNodes != null && widget.allNodes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.link, size: 16),
                      label: Text(AppLocalizations.of(context).workflowConfigUsePreviousNode),
                      onPressed: () => _showReferenceSelector(key, fieldSchema: schema),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _openDatePickerForKey(String key, DateTime? parsedDate) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 2);
    final lastDate = DateTime(now.year + 2);
    final initialDate = parsedDate ?? now;

    final picked = await showAdaptiveDatePicker(
      context: context,
      calendarController: ApiClient.getCalendarController(),
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: _formatKey(key),
    );

    if (picked != null && mounted) {
      setState(() {
        _config[key] = date_utils.HesabixDateUtils.formatForApiDate(picked);
        _disposeWorkflowTextController(key);
      });
    }
  }

  void _disposeWorkflowTextController(String key) {
    final c = _workflowTextControllers.remove(key);
    c?.dispose();
  }

  /// ساخت Date Picker
  Widget _buildDatePicker(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    // مقادیر reference (مثل $node.date) را با TextField نمایش می‌دهیم
    if (currentValue?.toString().startsWith('\$') ?? false) {
      return _buildReferenceTextField(key, schema, currentValue, required, description);
    }

    DateTime? parsedDate;
    final strVal = currentValue?.toString();
    if (strVal != null && strVal.isNotEmpty && strVal != 'today') {
      parsedDate = date_utils.HesabixDateUtils.parseFromAPI(strVal);
    } else if (strVal != 'today') {
      parsedDate = null;
    } else {
      parsedDate = DateTime.now();
    }

    final displayText = parsedDate != null
        ? date_utils.HesabixDateUtils.formatForDisplay(
            parsedDate,
            ApiClient.getCalendarController()?.isJalali ?? true,
          )
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            key: ValueKey(displayText),
            readOnly: true,
            initialValue: displayText.isEmpty ? (strVal == 'today' ? AppLocalizations.of(context).workflowConfigToday : '') : displayText,
            decoration: InputDecoration(
              labelText: _formatKey(key),
              border: const OutlineInputBorder(),
              helperText: description ?? AppLocalizations.of(context).workflowConfigDateHelper,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.calendar_today),
                    tooltip: AppLocalizations.of(context).workflowConfigSelectDate,
                    onPressed: () => _openDatePickerForKey(key, parsedDate),
                  ),
                  if (required)
                    const Icon(Icons.star, size: 12, color: Colors.red),
                ],
              ),
            ),
            validator: required && parsedDate == null && strVal != 'today'
                ? (v) => AppLocalizations.of(context).workflowNodeFieldRequired
                : null,
            onTap: () => _openDatePickerForKey(key, parsedDate),
          ),
          if (widget.allNodes != null && widget.allNodes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.link, size: 16),
                label: Text(AppLocalizations.of(context).workflowConfigUsePreviousNode),
                onPressed: () => _showReferenceSelector(key, fieldSchema: schema),
              ),
            ),
        ],
      ),
    );
  }

  /// ساخت Textarea
  Widget _buildTextarea(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    final maxLength = schema['maxLength'] as int?;
    final placeholder = _getPlaceholder(key, description);
    final theme = Theme.of(context);
    final c = _ensureWorkflowTextController(key);
    final hasRef = c.text.contains(r'$');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: c,
            maxLines: 4,
            minLines: 3,
            maxLength: maxLength,
            decoration: InputDecoration(
              labelText: _formatKey(key),
              border: const OutlineInputBorder(),
              helperText: description,
              hintText: placeholder,
              alignLabelWithHint: true,
              prefixIcon: hasRef
                  ? Icon(Icons.link, size: 18, color: theme.colorScheme.primary)
                  : null,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.allNodes != null && widget.allNodes!.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.select_all, size: 18),
                      tooltip: AppLocalizations.of(context).workflowConfigSelectFromNodes,
                      onPressed: () => _showReferenceSelector(key, fieldSchema: schema),
                    ),
                  if (required)
                    const Icon(Icons.star, size: 12, color: Colors.red),
                ],
              ),
            ),
            validator: required
                ? (_) => c.text.trim().isEmpty
                    ? AppLocalizations.of(context).workflowNodeFieldRequired
                    : null
                : null,
            onChanged: (v) {
              _config[key] = v;
              setState(() {});
            },
            onSaved: (_) {
              final newValue = c.text;
              if (newValue.isNotEmpty) {
                _config[key] = newValue;
              } else if (!required) {
                _config.remove(key);
              } else {
                _config[key] = '';
              }
            },
          ),
          if (hasRef)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 12),
              child: Text(
                AppLocalizations.of(context).workflowConfigValueUsesNode,
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

  bool _workflowLangIsFa() {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    return code == 'fa' || code.startsWith('fa');
  }

  String _formatSmsEstimateNumber(dynamic n) {
    if (n == null) return '—';
    final d = n is num ? n.toDouble() : double.tryParse('$n');
    if (d == null) return '—';
    return d.toStringAsFixed(d == d.roundToDouble() ? 0 : 2);
  }

  Widget _smsEstimateRow(
    ThemeData theme,
    String label,
    String value, {
    bool emphasize = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: emphasize ? FontWeight.w600 : null,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: emphasize ? FontWeight.bold : null,
                color: emphasize ? theme.colorScheme.primary : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// انتخاب قالب SMS (لیست از API)
  Widget _buildSmsTemplateSelector(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    final theme = Theme.of(context);
    final isFa = _workflowLangIsFa();

    if (currentValue?.toString().trim().startsWith(r'$') ?? false) {
      return _buildReferenceTextField(key, schema, currentValue, required, description);
    }

    if (widget.businessId == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          isFa
              ? 'برای بارگذاری قالب‌ها، زمینهٔ کسب‌وکار لازم است.'
              : 'Business context is required to load SMS templates.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
        ),
      );
    }

    final selectedId = _parseIntOrNull(currentValue);
    final validIds = <int>{};
    for (final t in _smsTemplates) {
      final id = _parseIntOrNull(t['id']);
      if (id != null) {
        validIds.add(id);
      }
    }

    final int? dropdownValue =
        selectedId != null && validIds.contains(selectedId) ? selectedId : null;

    final detailMatches =
        _smsTemplateDetail != null && _parseIntOrNull(_smsTemplateDetail!['id']) == dropdownValue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loadingSmsTemplates)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(),
            ),
          if (!_loadingSmsTemplates && _smsTemplates.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                isFa
                    ? 'قالب SMS فعال و تاییدشده‌ای یافت نشد. می‌توانید با «ارجاع از نود قبلی» شناسه قالب را وارد کنید.'
                    : 'No approved active SMS templates. Use «previous node» to set template_id.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          DropdownButtonFormField<int>(
            value: dropdownValue,
            decoration: InputDecoration(
              labelText: _formatKey(key),
              border: const OutlineInputBorder(),
              helperText: description,
              suffixIcon: required ? const Icon(Icons.star, size: 12, color: Colors.red) : null,
            ),
            hint: Text(isFa ? 'انتخاب قالب پیامک' : 'Select SMS template'),
            items: [
              for (final tpl in _smsTemplates)
                if (_parseIntOrNull(tpl['id']) != null)
                  DropdownMenuItem<int>(
                    value: _parseIntOrNull(tpl['id']),
                    child: Text(
                      '${tpl['name'] ?? tpl['id']} (${tpl['event_type'] ?? ''})',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
            ],
            onChanged: _loadingSmsTemplates
                ? null
                : (v) async {
                    setState(() {
                      if (v != null) {
                        _config[key] = v;
                      } else if (!required) {
                        _config.remove(key);
                      }
                      _smsTemplateDetail = null;
                      _smsCostEstimate = null;
                    });
                    if (v == null || widget.businessId == null) {
                      return;
                    }
                    setState(() => _loadingSmsCost = true);
                    try {
                      final results = await Future.wait([
                        _workflowService.getNotificationTemplate(
                          businessId: widget.businessId!,
                          templateId: v,
                        ),
                        _workflowService.estimateSmsTemplateCost(
                          businessId: widget.businessId!,
                          templateId: v,
                        ),
                      ]);
                      if (!mounted) return;
                      setState(() {
                        _smsTemplateDetail = results[0];
                        _smsCostEstimate = results[1];
                        _loadingSmsCost = false;
                      });
                    } catch (_) {
                      if (mounted) {
                        setState(() {
                          _smsTemplateDetail = null;
                          _smsCostEstimate = null;
                          _loadingSmsCost = false;
                        });
                      }
                    }
                  },
          ),
          if (widget.allNodes != null && widget.allNodes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.link, size: 16),
                label: Text(AppLocalizations.of(context).workflowConfigUsePreviousNode),
                onPressed: () => _showReferenceSelector(key, fieldSchema: schema),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              isFa
                  ? 'هزینه بر اساس طول متن (بخش پیامک) و قیمت‌گذاری ادمین است؛ کمبود موجودی ورک‌فلو را متوقف می‌کند.'
                  : 'Cost depends on SMS segments and admin pricing; insufficient wallet stops the workflow.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (_loadingSmsCost)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(),
            )
          else if (_smsCostEstimate != null &&
              dropdownValue != null &&
              _parseIntOrNull(_smsCostEstimate!['template_id']) == dropdownValue)
            Card(
              margin: const EdgeInsets.only(top: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.calculate_outlined, size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isFa ? 'برآورد هزینه (متن خام قالب)' : 'Cost estimate (raw template)',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isFa
                          ? 'پس از جایگزینی متغیرها طول متن و هزینه ممکن است عوض شود.'
                          : 'After variables are filled, length and cost may change.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _smsEstimateRow(
                      theme,
                      isFa ? 'تعداد کاراکتر متن خام' : 'Raw body characters',
                      '${_smsCostEstimate!['body_char_count'] ?? '—'}',
                    ),
                    _smsEstimateRow(
                      theme,
                      isFa ? 'تعداد بخش پیامک (تقریبی)' : 'SMS segments (approx.)',
                      '${_smsCostEstimate!['sms_segments'] ?? '—'}',
                    ),
                    _smsEstimateRow(
                      theme,
                      isFa ? 'قیمت هر بخش' : 'Price per segment',
                      _formatSmsEstimateNumber(_smsCostEstimate!['price_per_sms']),
                    ),
                    const Divider(height: 16),
                    _smsEstimateRow(
                      theme,
                      isFa ? 'جمع تقریبی (ارز کیف پول)' : 'Estimated total (wallet currency)',
                      _formatSmsEstimateNumber(_smsCostEstimate!['estimated_total']),
                      emphasize: true,
                    ),
                  ],
                ),
              ),
            ),
          if (detailMatches) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                isFa
                    ? 'متغیرهای قالب (در «متغیرهای قالب» JSON وارد کنید)'
                    : 'Template variables (fill template_context JSON)',
                style: theme.textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 8),
            _buildSmsTemplateVariableChips(theme, isFa),
          ],
        ],
      ),
    );
  }

  Widget _buildSmsTemplateVariableChips(ThemeData theme, bool isFa) {
    final raw = _smsTemplateDetail?['available_variables'];
    final keys = <String>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map && e['key'] != null) {
          keys.add(e['key'].toString());
        } else {
          keys.add(e.toString());
        }
      }
    } else if (raw is Map) {
      keys.addAll(raw.keys.map((k) => k.toString()));
    }
    if (keys.isEmpty) {
      return Text(
        isFa ? 'لیست متغیر برای این قالب ثبت نشده است.' : 'No variable list on this template.',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: keys
          .map(
            (k) => Chip(
              visualDensity: VisualDensity.compact,
              label: Text(k, style: theme.textTheme.bodySmall),
            ),
          )
          .toList(),
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

    // استفاده از PersonComboboxWidget وقتی businessId موجود است
    if (widget.businessId != null) {
      final personTypes = schema['ui_config']?['person_types'] as List<dynamic>?;
      final types = personTypes != null
          ? personTypes.map((e) => e.toString()).toList()
          : null;

      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WorkflowPersonSelectorField(
              key: ValueKey('person_${key}_${currentValue}'),
              businessId: widget.businessId!,
              configKey: key,
              initialPersonId: _parseIntOrNull(currentValue),
              required: required,
              label: _formatKey(key),
              description: description,
              personTypes: types,
              onChanged: (id) {
                setState(() {
                  _disposeWorkflowTextController(key);
                  if (id != null) {
                    _config[key] = id;
                  } else if (!required) {
                    _config.remove(key);
                  }
                });
              },
            ),
            if (widget.allNodes != null && widget.allNodes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.link, size: 16),
                  label: Text(AppLocalizations.of(context).workflowConfigUsePreviousNode),
                  onPressed: () => _showReferenceSelector(key, fieldSchema: schema),
                ),
              ),
          ],
        ),
      );
    }

    // Fallback: TextField ساده
    final c = _ensureWorkflowTextController(key);
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
          TextFormField(
            controller: c,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).workflowConfigPersonIdLabel,
              border: OutlineInputBorder(),
              helperText: AppLocalizations.of(context).workflowConfigPersonIdHelper,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.allNodes != null && widget.allNodes!.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.link, size: 18),
                      tooltip: AppLocalizations.of(context).workflowConfigUsePreviousNode,
                      onPressed: () => _showReferenceSelector(key, fieldSchema: schema),
                    ),
                  if (required)
                    Icon(Icons.star, size: 12, color: Colors.red),
                ],
              ),
            ),
            validator: required
                ? (_) => c.text.trim().isEmpty
                    ? AppLocalizations.of(context).workflowNodeFieldRequired
                    : null
                : null,
            onChanged: (v) {
              _config[key] = int.tryParse(v) ?? v;
              setState(() {});
            },
            onSaved: (_) {
              final newValue = c.text;
              if (newValue.isNotEmpty) {
                _config[key] = int.tryParse(newValue) ?? newValue;
              } else if (!required) {
                _config.remove(key);
              }
            },
          ),
        ],
      ),
    );
  }

  int? _parseIntOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  /// ساخت Product Selector
  Widget _buildProductSelector(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    if (currentValue?.toString().startsWith('\$') ?? false) {
      return _buildReferenceTextField(key, schema, currentValue, required, description);
    }

    if (widget.businessId != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WorkflowProductSelectorField(
              key: ValueKey('product_${key}_${currentValue}'),
              businessId: widget.businessId!,
              configKey: key,
              initialProductId: _parseIntOrNull(currentValue),
              required: required,
              label: _formatKey(key),
              description: description ?? AppLocalizations.of(context).workflowConfigProductIdLabel,
              onChanged: (id) {
                setState(() {
                  _disposeWorkflowTextController(key);
                  if (id != null) {
                    _config[key] = id;
                  } else if (!required) {
                    _config.remove(key);
                  }
                });
              },
            ),
            if (widget.allNodes != null && widget.allNodes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.link, size: 16),
                  label: Text(AppLocalizations.of(context).workflowConfigUsePreviousNode),
                  onPressed: () => _showReferenceSelector(key, fieldSchema: schema),
                ),
              ),
          ],
        ),
      );
    }

    return _buildPersonSelector(key, schema, currentValue, required, description ?? AppLocalizations.of(context).workflowConfigProductIdHelper);
  }

  /// ساخت تنظیمات تخفیف (object با type و value)
  Widget _buildDiscountConfig(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    final obj = currentValue is Map<String, dynamic>
        ? Map<String, dynamic>.from(currentValue)
        : <String, dynamic>{};
    final type = obj['type'] as String? ?? 'percent';
    final valueStr = obj['value']?.toString() ?? '';
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};
    final typeSchema = properties['type'] as Map<String, dynamic>?;
    final valueSchema = properties['value'] as Map<String, dynamic>?;
    final enumValues = typeSchema?['enum'] as List<dynamic>? ?? ['percent', 'fixed'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatKey(key),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  value: enumValues.contains(type) ? type : enumValues.firstOrNull?.toString(),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).workflowConfigType,
                    border: const OutlineInputBorder(),
                  ),
                  items: enumValues.map((e) {
                    final v = e.toString();
                    final label = v == 'percent'
                        ? AppLocalizations.of(context).workflowConfigPercent
                        : (v == 'fixed' ? AppLocalizations.of(context).workflowConfigFixedAmount : v);
                    return DropdownMenuItem<String>(value: v, child: Text(label));
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        final map = Map<String, dynamic>.from(_config[key] ?? {});
                        map['type'] = v;
                        _config[key] = map;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: valueStr,
                  decoration: InputDecoration(
                    labelText: type == 'percent'
                        ? AppLocalizations.of(context).workflowConfigDiscountPercent
                        : AppLocalizations.of(context).workflowConfigDiscountAmount,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) {
                    final parsed = num.tryParse(v);
                    setState(() {
                      if (_config[key] == null) {
                        _config[key] = <String, dynamic>{'type': type};
                      }
                      final map = Map<String, dynamic>.from(_config[key] as Map);
                      map['value'] = parsed;
                      _config[key] = map;
                    });
                  },
                  onSaved: (v) {
                    final parsed = num.tryParse(v ?? '');
                    if (_config[key] == null) {
                      _config[key] = <String, dynamic>{'type': type};
                    }
                    final map = Map<String, dynamic>.from(_config[key] as Map);
                    map['value'] = parsed;
                    _config[key] = map;
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// تبدیل خطوط API به فرمت UI برای ویرایش
  List<Map<String, dynamic>> _linesToItems(List<dynamic> lines) {
    return lines.map((line) {
      if (line is! Map) return <String, dynamic>{};
      final m = Map<String, dynamic>.from(line);
      final info = m['extra_info'] is Map ? Map<String, dynamic>.from(m['extra_info'] as Map) : <String, dynamic>{};
      final qty = (m['quantity'] as num?)?.toDouble() ?? 1;
      final unitPrice = (info['unit_price'] as num?)?.toDouble();
      final lineDiscount = (info['line_discount'] as num?)?.toDouble() ?? 0;
      final taxAmount = (info['tax_amount'] as num?)?.toDouble() ?? 0;
      final gross = qty * (unitPrice ?? 0);
      final discountPercent = gross > 0 ? (lineDiscount / gross * 100) : 0;
      final subtotal = gross - lineDiscount;
      final taxPercent = subtotal > 0 ? (taxAmount / subtotal * 100) : 9;
      return {
        'product_id': m['product_id'],
        'quantity': qty,
        'unit_price': unitPrice,
        'discount_percent': discountPercent,
        'tax_percent': taxPercent,
        'description': m['description']?.toString() ?? '',
      };
    }).toList();
  }

  /// سازندهٔ آیتم‌های فاکتور (جدول محصول، تعداد، قیمت، تخفیف، مالیات)
  Widget _buildInvoiceItemsBuilder(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    final uiConfig = schema['ui_config'] as Map<String, dynamic>? ?? {};
    final itemSchema = uiConfig['item_schema'] as Map<String, dynamic>? ?? {};
    final minItems = uiConfig['min_items'] as int? ?? 1;
    final maxItems = uiConfig['max_items'] as int? ?? 100;

    List<Map<String, dynamic>> items;
    if (currentValue is List<dynamic> && currentValue.isNotEmpty) {
      final first = currentValue.first;
      if (first is Map && (first as Map).containsKey('extra_info')) {
        items = _linesToItems(currentValue);
      } else {
        items = List<Map<String, dynamic>>.from(
            currentValue.map((e) => e is Map ? Map<String, dynamic>.from(e as Map) : <String, dynamic>{}));
      }
    } else {
      items = <Map<String, dynamic>>[];
    }

    if (items.isEmpty && minItems > 0) {
      items = [
        {
          'product_id': null,
          'quantity': 1,
          'unit_price': null,
          'discount_percent': 0,
          'tax_percent': 9,
          'description': '',
        },
      ];
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatKey(key),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (required)
                Icon(Icons.star, size: 14, color: Colors.red),
            ],
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ...items.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            return _InvoiceItemRow(
              key: ValueKey('item_$idx'),
              index: idx + 1,
              item: item,
              itemSchema: itemSchema,
              businessId: widget.businessId,
              allNodes: widget.allNodes,
              onChanged: (updated) {
                setState(() {
                  final newItems = List<Map<String, dynamic>>.from(items);
                  if (idx < newItems.length) {
                    newItems[idx] = updated;
                    _config[key] = _itemsToLines(newItems);
                  }
                });
              },
              onRemove: items.length > minItems
                  ? () {
                      setState(() {
                        final newItems = List<Map<String, dynamic>>.from(items);
                        newItems.removeAt(idx);
                        _config[key] = _itemsToLines(newItems);
                      });
                    }
                  : null,
              onReference: () => _showReferenceSelector(key, fieldSchema: schema),
            );
          }),
          if (items.length < maxItems)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: Text(AppLocalizations.of(context).workflowConfigAddLineItem),
                onPressed: () {
                  setState(() {
                    final newItems = List<Map<String, dynamic>>.from(items);
                    newItems.add({
                      'product_id': null,
                      'quantity': 1,
                      'unit_price': null,
                      'discount_percent': 0,
                      'tax_percent': 9,
                      'description': '',
                    });
                    _config[key] = _itemsToLines(newItems);
                  });
                },
              ),
            ),
          if (widget.allNodes != null && widget.allNodes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.link, size: 16),
                label: Text(AppLocalizations.of(context).workflowConfigUsePreviousNode),
                onPressed: () => _showReferenceSelector(key, fieldSchema: schema),
              ),
            ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _itemsToLines(List<Map<String, dynamic>> items) {
    return items.map((item) {
      final productId = item['product_id'];
      final qty = (item['quantity'] as num?)?.toDouble() ?? 1;
      final unitPrice = (item['unit_price'] as num?)?.toDouble();
      final discountPercent = (item['discount_percent'] as num?)?.toDouble() ?? 0;
      final taxPercent = (item['tax_percent'] as num?)?.toDouble() ?? 9;
      final desc = item['description']?.toString();
      final gross = qty * (unitPrice ?? 0);
      final lineDiscount = gross * (discountPercent / 100);
      final subtotal = gross - lineDiscount;
      final taxAmount = subtotal * (taxPercent / 100);
      return {
        'product_id': productId,
        'quantity': qty,
        'description': desc,
        'extra_info': {
          'unit_price': unitPrice ?? 0,
          'line_discount': lineDiscount,
          'tax_amount': taxAmount,
        },
      };
    }).toList();
  }

  /// سازندهٔ پرداخت‌ها (مبلغ، روش پرداخت، حساب)
  Widget _buildPaymentsBuilder(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    final uiConfig = schema['ui_config'] as Map<String, dynamic>? ?? {};
    final maxPayments = uiConfig['max_payments'] as int? ?? 5;

    var payments = (currentValue is List<dynamic>)
        ? List<Map<String, dynamic>>.from(
            currentValue.map((e) => e is Map ? Map<String, dynamic>.from(e as Map) : <String, dynamic>{}))
        : <Map<String, dynamic>>[];

    final l10n = AppLocalizations.of(context);
    final methodLabels = {
      'cash': l10n.workflowConfigCash,
      'bank': l10n.workflowConfigBank,
      'check': l10n.workflowConfigCheck,
      'card': l10n.workflowConfigCard,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatKey(key),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (payments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                AppLocalizations.of(context).workflowConfigNoPaymentsYet,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
          ...payments.asMap().entries.map((entry) {
            final idx = entry.key;
            final p = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              key: ValueKey('pay_$idx'),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(AppLocalizations.of(context).workflowConfigPaymentN(idx + 1), style: Theme.of(context).textTheme.titleSmall),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, size: 20),
                          onPressed: () {
                            setState(() {
                              final newList = List<Map<String, dynamic>>.from(payments);
                              newList.removeAt(idx);
                              _config[key] = newList;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: TextFormField(
                              initialValue: p['amount']?.toString(),
                              decoration: InputDecoration(
                                labelText: AppLocalizations.of(context).workflowConfigAmount,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (v) {
                                final amt = num.tryParse(v ?? '');
                                setState(() {
                                  final newList = List<Map<String, dynamic>>.from(payments);
                                  if (idx < newList.length) {
                                    newList[idx] = Map<String, dynamic>.from(newList[idx]);
                                    newList[idx]['amount'] = amt;
                                    _config[key] = newList;
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: (p['payment_method'] ?? 'cash').toString(),
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(context).workflowConfigPaymentMethod,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: methodLabels.entries
                                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                                .toList(),
                            isExpanded: true,
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                final newList = List<Map<String, dynamic>>.from(payments);
                                if (idx < newList.length) {
                                  newList[idx] = Map<String, dynamic>.from(newList[idx]);
                                  newList[idx]['payment_method'] = v;
                                  _config[key] = newList;
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (widget.businessId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 0),
                        child: FutureBuilder<Map<String, dynamic>>(
                          future: AccountService().searchAccounts(
                            businessId: widget.businessId!,
                            limit: 200,
                          ),
                          builder: (context, snapshot) {
                            final accounts = (snapshot.data?['items'] as List<dynamic>?) ?? [];
                            final accountItems = accounts.map((a) => Map<String, dynamic>.from(a as Map)).toList();
                            final selId = (p['account_id'] as num?)?.toInt();
                            final hasSel = selId != null && accountItems.any((a) => (a['id'] as num?)?.toInt() == selId);
                            return DropdownButtonFormField<int?>(
                              value: hasSel ? selId : null,
                              decoration: InputDecoration(
                                labelText: AppLocalizations.of(context).workflowConfigAccountSelect,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: [
                                DropdownMenuItem<int?>(value: null, child: Text(AppLocalizations.of(context).workflowConfigNotSelected)),
                                ...accountItems.map((a) {
                                  final id = (a['id'] as num?)?.toInt();
                                  final code = a['code']?.toString() ?? '';
                                  final name = a['name']?.toString() ?? '';
                                  return DropdownMenuItem<int?>(
                                    value: id,
                                    child: Text('$code - $name'),
                                  );
                                }),
                              ],
                              onChanged: (v) {
                                setState(() {
                                  final newList = List<Map<String, dynamic>>.from(payments);
                                  if (idx < newList.length) {
                                    newList[idx] = Map<String, dynamic>.from(newList[idx]);
                                    newList[idx]['account_id'] = v;
                                    newList[idx]['transaction_type'] = 'account';
                                    _config[key] = newList;
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextFormField(
                        initialValue: p['description']?.toString(),
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context).workflowConfigDescription,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLines: 1,
                        onChanged: (v) {
                          setState(() {
                            final newList = List<Map<String, dynamic>>.from(payments);
                            if (idx < newList.length) {
                              newList[idx] = Map<String, dynamic>.from(newList[idx]);
                              newList[idx]['description'] = v;
                              _config[key] = newList;
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (payments.length < maxPayments)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: Text(AppLocalizations.of(context).workflowConfigAddPayment),
                onPressed: () {
                  setState(() {
                    final newList = List<Map<String, dynamic>>.from(payments);
                    newList.add({
                      'amount': null,
                      'payment_method': 'cash',
                      'account_id': null,
                      'description': '',
                    });
                    _config[key] = newList;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  /// ویرایشگر آرایهٔ رشته‌ها (cc, bcc, channels و غیره)
  Widget _buildStringArrayEditor(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    final list = (currentValue is List<dynamic>)
        ? List<String>.from(currentValue.map((e) => e?.toString() ?? ''))
        : <String>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatKey(key),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ...list.asMap().entries.map((entry) {
            final idx = entry.key;
            final val = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: val,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).workflowConfigItemN(idx + 1),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        setState(() {
                          final newList = List<String>.from(list);
                          if (idx < newList.length) {
                            newList[idx] = v;
                            _config[key] = newList;
                          }
                        });
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () {
                      setState(() {
                        final newList = List<String>.from(list);
                        newList.removeAt(idx);
                        _config[key] = newList;
                      });
                    },
                  ),
                ],
              ),
            );
          }),
          OutlinedButton.icon(
            icon: const Icon(Icons.add, size: 18),
                label: Text(AppLocalizations.of(context).workflowConfigAddItem),
            onPressed: () {
              setState(() {
                final newList = List<String>.from(list);
                newList.add('');
                _config[key] = newList;
              });
            },
          ),
        ],
      ),
    );
  }

  /// ویرایشگر JSON برای object
  Widget _buildJsonEditor(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    String jsonStr;
    if (currentValue is Map<String, dynamic>) {
      try {
        jsonStr = const JsonEncoder.withIndent('  ').convert(currentValue);
      } catch (_) {
        jsonStr = '{}';
      }
    } else if (currentValue is String) {
      jsonStr = currentValue;
    } else {
      jsonStr = '{}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatKey(key),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          TextFormField(
            initialValue: jsonStr,
            maxLines: 6,
            minLines: 3,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).workflowConfigJsonLabel,
              border: const OutlineInputBorder(),
              hintText: AppLocalizations.of(context).workflowConfigJsonHint,
              alignLabelWithHint: true,
              errorText: null,
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                if (required) {
                  return AppLocalizations.of(context).workflowNodeFieldRequired;
                }
                return null;
              }
              try {
                jsonDecode(v);
              } catch (e) {
                return AppLocalizations.of(context).workflowConfigInvalidJson;
              }
              return null;
            },
            onChanged: (v) {
              if (v == null || v.trim().isEmpty) {
                setState(() {
                  if (!required) {
                    _config.remove(key);
                  }
                });
                return;
              }
              try {
                final decoded = jsonDecode(v) as Map<String, dynamic>;
                setState(() => _config[key] = decoded);
              } catch (_) {}
            },
            onSaved: (v) {
              if (v == null || v.trim().isEmpty) {
                if (!required) _config.remove(key);
                return;
              }
              try {
                final decoded = jsonDecode(v) as Map<String, dynamic>;
                _config[key] = decoded;
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }

  /// ساخت Warehouse Selector
  Widget _buildWarehouseSelector(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    if (currentValue?.toString().startsWith('\$') ?? false) {
      return _buildReferenceTextField(key, schema, currentValue, required, description);
    }

    if (widget.businessId == null) {
      return _buildNumberFieldWithReference(key, schema, currentValue, required, description, 'integer');
    }

    final intVal = _parseIntOrNull(currentValue);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<List<Warehouse>>(
            future: WarehouseService().listWarehouses(businessId: widget.businessId!),
            builder: (context, snapshot) {
              final warehouses = snapshot.data ?? [];
              return DropdownButtonFormField<int?>(
                value: intVal != null && warehouses.any((w) => w.id == intVal) ? intVal : null,
                decoration: InputDecoration(
                  labelText: _formatKey(key),
                  border: const OutlineInputBorder(),
                  helperText: description ?? AppLocalizations.of(context).workflowConfigSelectWarehouse,
                  suffixIcon: required ? const Icon(Icons.star, size: 12, color: Colors.red) : null,
                ),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(AppLocalizations.of(context).workflowConfigNotSelected)),
                  ...warehouses.map((w) => DropdownMenuItem<int?>(
                    value: w.id,
                    child: Text('${w.name} (${w.code})'),
                  )),
                ],
                onChanged: (v) {
                  setState(() {
                    _disposeWorkflowTextController(key);
                    if (v != null) {
                      _config[key] = v;
                    } else if (!required) {
                      _config.remove(key);
                    }
                  });
                },
              );
            },
          ),
          if (widget.allNodes != null && widget.allNodes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.link, size: 16),
                label: Text(AppLocalizations.of(context).workflowConfigUsePreviousNode),
                onPressed: () => _showReferenceSelector(key, fieldSchema: schema),
              ),
            ),
        ],
      ),
    );
  }

  /// ساخت Account Selector
  Widget _buildAccountSelector(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    if (currentValue?.toString().startsWith('\$') ?? false) {
      return _buildReferenceTextField(key, schema, currentValue, required, description);
    }

    if (widget.businessId == null) {
      return _buildNumberFieldWithReference(key, schema, currentValue, required, description, 'integer');
    }

    final intVal = _parseIntOrNull(currentValue);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<Map<String, dynamic>>(
            future: AccountService().searchAccounts(
              businessId: widget.businessId!,
              limit: 200,
            ),
            builder: (context, snapshot) {
              final items = (snapshot.data?['items'] as List<dynamic>?) ?? [];
              final accounts = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
              final hasSelected = intVal != null && accounts.any((a) => (a['id'] as num?)?.toInt() == intVal);
              return DropdownButtonFormField<int?>(
                value: hasSelected ? intVal : null,
                decoration: InputDecoration(
                  labelText: _formatKey(key),
                  border: const OutlineInputBorder(),
                  helperText: description ?? AppLocalizations.of(context).workflowConfigSelectAccount,
                  suffixIcon: required ? const Icon(Icons.star, size: 12, color: Colors.red) : null,
                ),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(AppLocalizations.of(context).workflowConfigNotSelected)),
                  ...accounts.map((a) {
                    final id = (a['id'] as num?)?.toInt();
                    final code = a['code']?.toString() ?? '';
                    final name = a['name']?.toString() ?? '';
                    return DropdownMenuItem<int?>(
                      value: id,
                      child: Text('$code - $name'),
                    );
                  }),
                ],
                onChanged: (v) {
                  setState(() {
                    _disposeWorkflowTextController(key);
                    if (v != null) {
                      _config[key] = v;
                    } else if (!required) {
                      _config.remove(key);
                    }
                  });
                },
              );
            },
          ),
          if (widget.allNodes != null && widget.allNodes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.link, size: 16),
                label: Text(AppLocalizations.of(context).workflowConfigUsePreviousNode),
                onPressed: () => _showReferenceSelector(key, fieldSchema: schema),
              ),
            ),
        ],
      ),
    );
  }

  /// ساخت Fiscal Year Selector
  Widget _buildFiscalYearSelector(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    if (currentValue?.toString().startsWith('\$') ?? false) {
      return _buildReferenceTextField(key, schema, currentValue, required, description);
    }

    if (widget.businessId == null) {
      return _buildNumberFieldWithReference(key, schema, currentValue, required, description, 'integer');
    }

    final intVal = _parseIntOrNull(currentValue);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: BusinessDashboardService(ApiClient()).listFiscalYears(widget.businessId!),
            builder: (context, snapshot) {
              final years = snapshot.data ?? [];
              final hasSelected = intVal != null && years.any((y) => (y['id'] as num?)?.toInt() == intVal);
              return DropdownButtonFormField<int?>(
                value: hasSelected ? intVal : null,
                decoration: InputDecoration(
                  labelText: _formatKey(key),
                  border: const OutlineInputBorder(),
                  helperText: description ?? AppLocalizations.of(context).workflowConfigSelectFiscalYear,
                  suffixIcon: required ? const Icon(Icons.star, size: 12, color: Colors.red) : null,
                ),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(AppLocalizations.of(context).workflowConfigNotSelected)),
                  ...years.map((y) {
                    final id = (y['id'] as num?)?.toInt();
                    final title = y['title']?.toString() ?? y['name']?.toString() ?? AppLocalizations.of(context).workflowConfigFiscalYearDefault;
                    return DropdownMenuItem<int?>(
                      value: id,
                      child: Text(title),
                    );
                  }),
                ],
                onChanged: (v) {
                  setState(() {
                    _disposeWorkflowTextController(key);
                    if (v != null) {
                      _config[key] = v;
                    } else if (!required) {
                      _config.remove(key);
                    }
                  });
                },
              );
            },
          ),
          if (widget.allNodes != null && widget.allNodes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.link, size: 16),
                label: Text(AppLocalizations.of(context).workflowConfigUsePreviousNode),
                onPressed: () => _showReferenceSelector(key, fieldSchema: schema),
              ),
            ),
        ],
      ),
    );
  }

  /// ساخت User Selector (کاربران عضو کسب‌وکار)
  Widget _buildUserSelector(
    String key,
    Map<String, dynamic> schema,
    dynamic currentValue,
    bool required,
    String? description,
  ) {
    if (currentValue?.toString().startsWith('\$') ?? false) {
      return _buildReferenceTextField(key, schema, currentValue, required, description);
    }

    if (widget.businessId == null) {
      return _buildNumberFieldWithReference(key, schema, currentValue, required, description, 'integer');
    }

    final intVal = _parseIntOrNull(currentValue);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<BusinessUsersResponse>(
            future: BusinessUserService(ApiClient()).getBusinessUsers(widget.businessId!),
            builder: (context, snapshot) {
              final users = snapshot.data?.users ?? [];
              final hasSelected = intVal != null && users.any((u) => u.userId == intVal);
              return DropdownButtonFormField<int?>(
                value: hasSelected ? intVal : null,
                decoration: InputDecoration(
                  labelText: _formatKey(key),
                  border: const OutlineInputBorder(),
                  helperText: description,
                  suffixIcon: required ? const Icon(Icons.star, size: 12, color: Colors.red) : null,
                ),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(AppLocalizations.of(context).workflowConfigNotSelected)),
                  ...users.map((u) => DropdownMenuItem<int?>(
                    value: u.userId,
                    child: Text('${u.userName}${u.userEmail.isNotEmpty ? ' (${u.userEmail})' : ''}'),
                  )),
                ],
                onChanged: (v) {
                  setState(() {
                    _disposeWorkflowTextController(key);
                    if (v != null) {
                      _config[key] = v;
                    } else if (!required) {
                      _config.remove(key);
                    }
                  });
                },
              );
            },
          ),
          if (widget.allNodes != null && widget.allNodes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.link, size: 16),
                label: Text(AppLocalizations.of(context).workflowConfigUsePreviousNode),
                onPressed: () => _showReferenceSelector(key, fieldSchema: schema),
              ),
            ),
        ],
      ),
    );
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
    final c = _ensureWorkflowTextController(key);
    final isReference = c.text.trim().startsWith(r'$');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: c,
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
                      tooltip: AppLocalizations.of(context).workflowConfigSelectFromNodes,
                      onPressed: () => _showReferenceSelector(key, fieldSchema: schema),
                    ),
                  if (required)
                    Icon(Icons.star, size: 12, color: Colors.red),
                ],
              ),
            ),
            keyboardType: isReference ? TextInputType.text : TextInputType.number,
            validator: required
                ? (_) => c.text.trim().isEmpty
                    ? AppLocalizations.of(context).workflowNodeFieldRequired
                    : null
                : null,
            onChanged: (v) {
              if (v.startsWith(r'$')) {
                _config[key] = v;
              } else if (v.isNotEmpty) {
                _config[key] = fieldType == 'integer'
                    ? int.tryParse(v) ?? v
                    : double.tryParse(v) ?? v;
              } else {
                _config[key] = v;
              }
              setState(() {});
            },
            onSaved: (_) {
              final newValue = c.text;
              if (newValue.isNotEmpty) {
                if (newValue.startsWith(r'$')) {
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
                AppLocalizations.of(context).workflowConfigValueUsesNode,
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
                label: Text(AppLocalizations.of(context).workflowConfigUsePreviousNode),
                onPressed: () => _showReferenceSelector(key, fieldSchema: schema),
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
          AppLocalizations.of(context).workflowConfigEnumRequiredForMultiSelect,
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
                AppLocalizations.of(context).workflowConfigSelectAtLeastOne,
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
    final c = _ensureWorkflowTextController(key);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: c,
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
                      tooltip: AppLocalizations.of(context).workflowConfigSelectFromNodes,
                      onPressed: () => _showReferenceSelector(key, fieldSchema: schema),
                    ),
                  if (required)
                    Icon(Icons.star, size: 12, color: Colors.red),
                ],
              ),
            ),
            validator: required
                ? (_) => c.text.trim().isEmpty
                    ? AppLocalizations.of(context).workflowNodeFieldRequired
                    : null
                : null,
            onChanged: (v) {
              _config[key] = v;
              setState(() {});
            },
            onSaved: (_) {
              final newValue = c.text;
              if (newValue.isNotEmpty) {
                _config[key] = newValue;
              } else if (!required) {
                _config.remove(key);
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 12),
            child: Text(
              AppLocalizations.of(context).workflowConfigValueUsesNode,
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
          ? 'مثال: فاکتور \$node_id.invoice_code برای \$node_id.customer_name'
          : 'Example: Invoice \$node_id.invoice_code for \$node_id.customer_name';
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
/// ردیف آیتم فاکتور در ورک‌فلو
class _InvoiceItemRow extends StatelessWidget {
  final int index;
  final Map<String, dynamic> item;
  final Map<String, dynamic> itemSchema;
  final int? businessId;
  final List<WorkflowNodeModel>? allNodes;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback? onRemove;
  final VoidCallback onReference;

  const _InvoiceItemRow({
    super.key,
    required this.index,
    required this.item,
    required this.itemSchema,
    required this.businessId,
    required this.allNodes,
    required this.onChanged,
    this.onRemove,
    required this.onReference,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final productId = item['product_id'];
    final qty = (item['quantity'] as num?)?.toDouble() ?? 1;
    final unitPrice = item['unit_price'] != null ? (item['unit_price'] as num?)?.toDouble() : null;
    final discountPercent = (item['discount_percent'] as num?)?.toDouble() ?? 0;
    final taxPercent = (item['tax_percent'] as num?)?.toDouble() ?? 9;
    final desc = item['description']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  l10n.workflowConfigItemN(index),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    onPressed: onRemove,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (businessId != null)
              _WorkflowProductSelectorField(
                key: ValueKey('prod_$index'),
                businessId: businessId!,
                configKey: '_item_product',
                initialProductId: productId is int ? productId : int.tryParse(productId?.toString() ?? ''),
                required: true,
                label: l10n.workflowConfigProduct,
                description: null,
                onChanged: (id) {
                  final updated = Map<String, dynamic>.from(item);
                  updated['product_id'] = id;
                  onChanged(updated);
                },
              ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: qty.toString(),
                    decoration: InputDecoration(
                      labelText: l10n.workflowConfigQuantity,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      final q = num.tryParse(v ?? '')?.toDouble();
                      if (q != null && q > 0) {
                        final updated = Map<String, dynamic>.from(item);
                        updated['quantity'] = q;
                        onChanged(updated);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: unitPrice?.toString() ?? '',
                    decoration: InputDecoration(
                      labelText: l10n.workflowConfigUnitPrice,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      final p = num.tryParse(v ?? '')?.toDouble();
                      final updated = Map<String, dynamic>.from(item);
                      updated['unit_price'] = p;
                      onChanged(updated);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: discountPercent.toString(),
                    decoration: InputDecoration(
                      labelText: l10n.workflowConfigDiscountPercent,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      final d = num.tryParse(v ?? '')?.toDouble() ?? 0;
                      final updated = Map<String, dynamic>.from(item);
                      updated['discount_percent'] = d.clamp(0, 100);
                      onChanged(updated);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: taxPercent.toString(),
                    decoration: InputDecoration(
                      labelText: l10n.workflowConfigTaxPercent,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      final t = num.tryParse(v ?? '')?.toDouble() ?? 9;
                      final updated = Map<String, dynamic>.from(item);
                      updated['tax_percent'] = t.clamp(0, 100);
                      onChanged(updated);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: desc,
              decoration: InputDecoration(
                labelText: l10n.workflowConfigDescription,
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 1,
              onChanged: (v) {
                final updated = Map<String, dynamic>.from(item);
                updated['description'] = v;
                onChanged(updated);
              },
            ),
            if (businessId == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextFormField(
                  initialValue: productId?.toString() ?? '',
                  decoration: InputDecoration(
                    labelText: l10n.workflowConfigProductIdHelper,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final id = int.tryParse(v ?? '');
                    final updated = Map<String, dynamic>.from(item);
                    updated['product_id'] = id;
                    onChanged(updated);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ویجت انتخاب طرف حساب با جستجو برای ورک‌فلو
class _WorkflowPersonSelectorField extends StatefulWidget {
  final int businessId;
  final String configKey;
  final int? initialPersonId;
  final bool required;
  final String label;
  final String? description;
  final List<String>? personTypes;
  final ValueChanged<int?> onChanged;

  const _WorkflowPersonSelectorField({
    super.key,
    required this.businessId,
    required this.configKey,
    required this.initialPersonId,
    required this.required,
    required this.label,
    this.description,
    this.personTypes,
    required this.onChanged,
  });

  @override
  State<_WorkflowPersonSelectorField> createState() => _WorkflowPersonSelectorFieldState();
}

class _WorkflowPersonSelectorFieldState extends State<_WorkflowPersonSelectorField> {
  Future<Person?>? _personFuture;
  Person? _selectedPerson;

  @override
  void initState() {
    super.initState();
    if (widget.initialPersonId != null) {
      _personFuture = PersonService().getPerson(widget.initialPersonId!);
    }
  }

  @override
  void didUpdateWidget(covariant _WorkflowPersonSelectorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPersonId != oldWidget.initialPersonId) {
      if (widget.initialPersonId != null) {
        _personFuture = PersonService().getPerson(widget.initialPersonId!);
      } else {
        _personFuture = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_personFuture == null) {
      return PersonComboboxWidget(
        businessId: widget.businessId,
        selectedPerson: _selectedPerson,
        label: widget.label,
        hintText: AppLocalizations.of(context).workflowConfigSearchSelectPerson,
        isRequired: widget.required,
        personTypes: widget.personTypes,
        onChanged: (p) {
          _selectedPerson = p;
          widget.onChanged(p?.id);
        },
      );
    }

    return FutureBuilder<Person?>(
      future: _personFuture,
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        final person = _selectedPerson ?? loaded;
        return PersonComboboxWidget(
          businessId: widget.businessId,
          selectedPerson: person,
          label: widget.label,
          hintText: AppLocalizations.of(context).workflowConfigSearchSelectPerson,
          isRequired: widget.required,
          personTypes: widget.personTypes,
          onChanged: (p) {
            setState(() => _selectedPerson = p);
            widget.onChanged(p?.id);
          },
        );
      },
    );
  }
}

/// ویجت انتخاب کالا/خدمت با جستجو برای ورک‌فلو
class _WorkflowProductSelectorField extends StatefulWidget {
  final int businessId;
  final String configKey;
  final int? initialProductId;
  final bool required;
  final String label;
  final String? description;
  final ValueChanged<int?> onChanged;

  const _WorkflowProductSelectorField({
    super.key,
    required this.businessId,
    required this.configKey,
    required this.initialProductId,
    required this.required,
    required this.label,
    this.description,
    required this.onChanged,
  });

  @override
  State<_WorkflowProductSelectorField> createState() => _WorkflowProductSelectorFieldState();
}

class _WorkflowProductSelectorFieldState extends State<_WorkflowProductSelectorField> {
  Future<Map<String, dynamic>?>? _productFuture;
  Map<String, dynamic>? _selectedProduct;

  @override
  void initState() {
    super.initState();
    if (widget.initialProductId != null) {
      _productFuture = ProductService().getProduct(
        businessId: widget.businessId,
        productId: widget.initialProductId!,
      );
    }
  }

  @override
  void didUpdateWidget(covariant _WorkflowProductSelectorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialProductId != oldWidget.initialProductId) {
      if (widget.initialProductId != null) {
        _productFuture = ProductService().getProduct(
          businessId: widget.businessId,
          productId: widget.initialProductId!,
        );
      } else {
        _productFuture = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_productFuture == null) {
      return ProductComboboxWidget(
        businessId: widget.businessId,
        selectedProduct: _selectedProduct,
        label: widget.label,
        hintText: AppLocalizations.of(context).workflowConfigSearchSelectProduct,
        onChanged: (p) {
          _selectedProduct = p;
          final id = p != null ? (p['id'] as int?) : null;
          widget.onChanged(id);
        },
      );
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: _productFuture,
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        final product = _selectedProduct ?? loaded;
        return ProductComboboxWidget(
          businessId: widget.businessId,
          selectedProduct: product,
          label: widget.label,
          hintText: AppLocalizations.of(context).workflowConfigSearchSelectProduct,
          onChanged: (p) {
            setState(() => _selectedProduct = p);
            final id = p != null ? (p['id'] as int?) : null;
            widget.onChanged(id);
          },
        );
      },
    );
  }
}

/// فیلد پیشنهادی در دیالوگ «انتخاب از نود» — برچسب‌ها از [AppLocalizations]
Map<String, String> _workflowSuggestedField(
  String key,
  String name,
  String desc,
  String type,
) {
  return {
    'key': key,
    'name': name,
    'description': desc,
    'type': type,
  };
}

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
        title: Text(AppLocalizations.of(context).workflowConfigReferenceTitle),
        content: SizedBox(
          width: 400,
          height: 400,
          child: availableNodes.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(AppLocalizations.of(context).workflowConfigNoNodesAvailable),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        AppLocalizations.of(context).workflowConfigStep1Node,
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
                                _getNodeIcon(node.type, node.key),
                                color: _getNodeColor(node.type, theme, node.key),
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
            child: Text(AppLocalizations.of(context).workflowConfigCancel),
          ),
        ],
      );
    } else {
      // مرحله 2: انتخاب فیلد یا استفاده از کل نود
      return AlertDialog(
        title: Text(AppLocalizations.of(context).workflowConfigSelectDataFrom(_selectedNode!.label ?? '')),
        content: SizedBox(
          width: 400,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  AppLocalizations.of(context).workflowConfigStep2Data,
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
                  title: Text(AppLocalizations.of(context).workflowConfigUseFullNodeOutput),
                  subtitle: Text(AppLocalizations.of(context).workflowConfigFullNodeOutputDesc),
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
                AppLocalizations.of(context).workflowConfigOrSelectField,
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
            child: Text(AppLocalizations.of(context).workflowConfigBack),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).workflowConfigCancel),
          ),
        ],
      );
    }
  }

  Widget _buildFieldsList(ThemeData theme) {
    final t = AppLocalizations.of(context);
    final fields = _getSuggestedFields(_selectedNode!, t);

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
                t.workflowNoSuggestedFields,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t.workflowTypeFieldManually(_selectedNode!.id),
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

  List<Map<String, String>> _getSuggestedFields(WorkflowNodeModel node, AppLocalizations t) {
    final key = node.key ?? '';

    // قبل از هر چیزی: receipt_payment شامل زیررشتهٔ «payment» است — نباید با payment عمومی قاطی شود
    if (key.contains('receipt_payment')) {
      return [
        _workflowSuggestedField('receipt_payment_id', t.workflowFieldReceiptPaymentId,
            t.workflowFieldDescReceiptPaymentId, 'number'),
        _workflowSuggestedField('type', t.workflowFieldType, t.workflowFieldDescType, 'string'),
        _workflowSuggestedField('amount', t.workflowFieldAmount, t.workflowFieldDescAmount, 'number'),
      ];
    }

    if (key.contains('invoice')) {
      return [
        _workflowSuggestedField('invoice_id', t.workflowFieldInvoiceId, t.workflowFieldDescInvoiceId, 'number'),
        _workflowSuggestedField('document_id', t.workflowFieldDocumentId, t.workflowFieldDescDocumentId, 'number'),
        _workflowSuggestedField('invoice_type', t.workflowFieldInvoiceType, t.workflowFieldDescInvoiceType, 'string'),
        _workflowSuggestedField('invoice_code', t.workflowFieldInvoiceCode, t.workflowFieldDescInvoiceCode, 'string'),
        _workflowSuggestedField(
            'invoice_number', t.workflowFieldInvoiceNumber, t.workflowFieldDescInvoiceNumber, 'string'),
        _workflowSuggestedField('invoice_date', t.workflowFieldInvoiceDate, t.workflowFieldDescInvoiceDate, 'date'),
        _workflowSuggestedField('total_amount', t.workflowFieldTotalAmount, t.workflowFieldDescTotalAmount, 'number'),
        _workflowSuggestedField(
            'discount_amount', t.workflowFieldDiscountAmount, t.workflowFieldDescDiscountAmount, 'number'),
        _workflowSuggestedField('tax_amount', t.workflowFieldTaxAmount, t.workflowFieldDescTaxAmount, 'number'),
        _workflowSuggestedField('final_amount', t.workflowFieldFinalAmount, t.workflowFieldDescFinalAmount, 'number'),
        _workflowSuggestedField(
            'customer_name', t.workflowFieldCustomerName, t.workflowFieldDescCustomerName, 'string'),
        _workflowSuggestedField('customer_id', t.workflowFieldCustomerId, t.workflowFieldDescCustomerId, 'number'),
        _workflowSuggestedField(
            'description', t.workflowFieldDescription, t.workflowFieldInvoiceDescription, 'string'),
        _workflowSuggestedField('status', t.workflowFieldStatus, t.workflowFieldInvoiceStatus, 'string'),
      ];
    }

    if (key.contains('document')) {
      return [
        _workflowSuggestedField('document_id', t.workflowFieldDocumentId, t.workflowFieldDescDocumentId, 'number'),
        _workflowSuggestedField(
            'document_type', t.workflowFieldDocumentType, t.workflowFieldDescDocumentType, 'string'),
        _workflowSuggestedField(
            'description', t.workflowFieldDocDescription, t.workflowFieldDescDocDescription, 'string'),
      ];
    }

    if (key.startsWith('crm.lead.')) {
      if (key.contains('assigned')) {
        return [
          _workflowSuggestedField('lead_id', t.workflowFieldLeadId, t.workflowFieldDescLeadId, 'number'),
          _workflowSuggestedField('old_assigned_to_user_id', 'شناسه مسئول قبلی', 'قبل از تغییر تخصیص', 'number'),
          _workflowSuggestedField('new_assigned_to_user_id', 'شناسه مسئول جدید', 'پس از تغییر تخصیص', 'number'),
          _workflowSuggestedField('lead_code', 'کد سرنخ', 'کد یکتای سرنخ', 'string'),
          _workflowSuggestedField('stage_name', 'نام مرحله', 'نام مرحله فعلی سرنخ', 'string'),
          _workflowSuggestedField('assigned_to_user_name', 'نام مسئول', 'نام کاربر مسئول', 'string'),
        ];
      }
      if (key.contains('stage_changed')) {
        return [
          _workflowSuggestedField('lead_id', t.workflowFieldLeadId, t.workflowFieldDescLeadId, 'number'),
          _workflowSuggestedField(
              'old_stage_id', t.workflowFieldOldStageId, t.workflowFieldDescOldStageId, 'number'),
          _workflowSuggestedField(
              'new_stage_id', t.workflowFieldNewStageId, t.workflowFieldDescNewStageId, 'number'),
          _workflowSuggestedField('old_stage_name', 'نام مرحله قبلی', 'متن مرحله قبل از تغییر', 'string'),
          _workflowSuggestedField('new_stage_name', 'نام مرحله جدید', 'متن مرحله بعد از تغییر', 'string'),
        ];
      }
      if (key.contains('converted')) {
        return [
          _workflowSuggestedField('lead_id', t.workflowFieldLeadId, t.workflowFieldDescLeadId, 'number'),
          _workflowSuggestedField('person_id', t.workflowFieldPersonId, t.workflowFieldDescPersonId, 'number'),
          _workflowSuggestedField('person_name', t.workflowFieldPersonName, t.workflowFieldDescPersonName, 'string'),
        ];
      }
      return [
        _workflowSuggestedField('lead_id', t.workflowFieldLeadId, t.workflowFieldDescLeadId, 'number'),
        _workflowSuggestedField('process_definition_id', t.workflowFieldProcessDefinitionId,
            t.workflowFieldDescProcessDefinitionId, 'number'),
        _workflowSuggestedField('stage_id', t.workflowFieldStageId, t.workflowFieldDescStageId, 'number'),
        _workflowSuggestedField('name', t.workflowFieldName, t.workflowFieldDescName, 'string'),
        _workflowSuggestedField('source_code', 'کد منبع', 'منبع سرنخ در CRM', 'string'),
        _workflowSuggestedField('mobile', t.workflowFieldMobile, t.workflowFieldDescMobile, 'string'),
        _workflowSuggestedField('email', t.workflowFieldEmail, t.workflowFieldDescEmail, 'string'),
      ];
    }

    if (key.startsWith('crm.activity')) {
      return [
        _workflowSuggestedField('activity_id', 'شناسه فعالیت', 'شناسه رکورد فعالیت', 'number'),
        _workflowSuggestedField('activity_code', 'کد فعالیت', 'کد یکتای فعالیت', 'string'),
        _workflowSuggestedField('activity_type', 'نوع فعالیت', 'call | email | meeting | note', 'string'),
        _workflowSuggestedField('person_id', t.workflowFieldPersonId, t.workflowFieldDescPersonId, 'number'),
        _workflowSuggestedField('lead_id', t.workflowFieldLeadId, t.workflowFieldDescLeadId, 'number'),
        _workflowSuggestedField('deal_id', t.workflowFieldDealId, t.workflowFieldDescDealId, 'number'),
        _workflowSuggestedField('subject', 'موضوع', 'موضوع فعالیت', 'string'),
      ];
    }

    if (key.startsWith('crm.deal.')) {
      if (key.contains('assigned')) {
        return [
          _workflowSuggestedField('deal_id', t.workflowFieldDealId, t.workflowFieldDescDealId, 'number'),
          _workflowSuggestedField('old_assigned_to_user_id', 'شناسه مسئول قبلی', 'قبل از تغییر تخصیص', 'number'),
          _workflowSuggestedField('new_assigned_to_user_id', 'شناسه مسئول جدید', 'پس از تغییر تخصیص', 'number'),
          _workflowSuggestedField('title', t.workflowFieldTitle, t.workflowFieldDescTitle, 'string'),
          _workflowSuggestedField('person_name', t.workflowFieldPersonName, t.workflowFieldDescPersonName, 'string'),
        ];
      }
      if (key.contains('closed')) {
        return [
          _workflowSuggestedField('deal_id', t.workflowFieldDealId, t.workflowFieldDescDealId, 'number'),
          _workflowSuggestedField('amount', t.workflowFieldAmount, t.workflowFieldDescAmount, 'number'),
          _workflowSuggestedField('is_win', t.workflowFieldIsWin, t.workflowFieldDescIsWin, 'boolean'),
          _workflowSuggestedField('is_lost', 'شکست معامله', 'true اگر مرحله بازنده باشد', 'boolean'),
          _workflowSuggestedField('document_id', t.workflowFieldDocumentId, t.workflowFieldDescDocumentId, 'number'),
        ];
      }
      if (key.contains('stage_changed')) {
        return [
          _workflowSuggestedField('deal_id', t.workflowFieldDealId, t.workflowFieldDescDealId, 'number'),
          _workflowSuggestedField(
              'old_stage_id', t.workflowFieldOldStageId, t.workflowFieldDescOldStageId, 'number'),
          _workflowSuggestedField(
              'new_stage_id', t.workflowFieldNewStageId, t.workflowFieldDescNewStageId, 'number'),
          _workflowSuggestedField('old_stage_name', 'نام مرحله قبلی', 'متن مرحله قبل از تغییر', 'string'),
          _workflowSuggestedField('new_stage_name', 'نام مرحله جدید', 'متن مرحله بعد از تغییر', 'string'),
        ];
      }
      return [
        _workflowSuggestedField('deal_id', t.workflowFieldDealId, t.workflowFieldDescDealId, 'number'),
        _workflowSuggestedField('process_definition_id', t.workflowFieldProcessDefinitionId,
            t.workflowFieldDescProcessDefinitionId, 'number'),
        _workflowSuggestedField('stage_id', t.workflowFieldStageId, t.workflowFieldDescStageId, 'number'),
        _workflowSuggestedField('person_id', t.workflowFieldPersonId, t.workflowFieldDescPersonId, 'number'),
        _workflowSuggestedField('title', t.workflowFieldTitle, t.workflowFieldDescTitle, 'string'),
        _workflowSuggestedField('amount', t.workflowFieldAmount, t.workflowFieldDescAmount, 'number'),
      ];
    }

    if (key == 'person.created') {
      return [
        _workflowSuggestedField('person_id', t.workflowFieldPersonId, t.workflowFieldDescPersonId, 'number'),
        _workflowSuggestedField(
            'person_types', t.workflowFieldPersonTypesList, t.workflowFieldDescPersonTypesList, 'string'),
      ];
    }

    if (key.contains('inventory.low')) {
      return [
        _workflowSuggestedField('product_id', t.workflowFieldProductId, t.workflowFieldDescProductId, 'number'),
        _workflowSuggestedField('warehouse_id', t.workflowFieldWarehouseId, t.workflowFieldDescWarehouseId, 'number'),
        _workflowSuggestedField(
            'current_quantity', t.workflowFieldCurrentQuantity, t.workflowFieldDescCurrentQuantity, 'number'),
        _workflowSuggestedField('min_quantity', t.workflowFieldMinQuantity, t.workflowFieldDescMinQuantity, 'number'),
      ];
    }

    if (key.contains('check.due')) {
      return [
        _workflowSuggestedField('check_id', t.workflowFieldCheckId, t.workflowFieldDescCheckId, 'number'),
        _workflowSuggestedField('check_number', t.workflowFieldCheckNumber, t.workflowFieldDescCheckNumber, 'string'),
        _workflowSuggestedField('due_date', t.workflowFieldDueDate, t.workflowFieldDescDueDate, 'date'),
        _workflowSuggestedField('amount', t.workflowFieldAmount, t.workflowFieldDescAmount, 'number'),
      ];
    }

    if (key == 'webhook') {
      return [
        _workflowSuggestedField('payload', t.workflowFieldWebhookPayload, t.workflowFieldDescWebhookPayload, 'string'),
        _workflowSuggestedField('body', t.workflowFieldWebhookBody, t.workflowFieldDescWebhookBody, 'string'),
      ];
    }

    if (key == 'scheduled') {
      return [
        _workflowSuggestedField(
            'scheduled_at', t.workflowFieldScheduledAt, t.workflowFieldDescScheduledAt, 'date'),
      ];
    }

    if (key == 'business_backup') {
      return [
        _workflowSuggestedField('success', t.workflowFieldSuccess, t.workflowFieldDescSuccess, 'boolean'),
        _workflowSuggestedField(
            'file_id', t.workflowFieldFileStorageId, t.workflowFieldDescFileStorageId, 'string'),
        _workflowSuggestedField(
            'attachment_file_id', t.workflowFieldAttachmentFileId, t.workflowFieldDescAttachmentFileId, 'string'),
        _workflowSuggestedField(
            'filename', t.workflowFieldStoredFilename, t.workflowFieldDescStoredFilename, 'string'),
      ];
    }

    if (key == 'send_telegram') {
      return [
        _workflowSuggestedField('success', t.workflowFieldSuccess, t.workflowFieldDescSuccess, 'boolean'),
        _workflowSuggestedField(
            'user_id', t.workflowFieldWorkflowUserId, t.workflowFieldDescWorkflowUserId, 'number'),
        _workflowSuggestedField(
            'telegram_chat_id', t.workflowFieldTelegramChatId, t.workflowFieldDescTelegramChatId, 'string'),
        _workflowSuggestedField('message', t.workflowFieldSentMessage, t.workflowFieldDescSentMessage, 'string'),
      ];
    }
    if (key == 'send_bale') {
      return [
        _workflowSuggestedField('success', t.workflowFieldSuccess, t.workflowFieldDescSuccess, 'boolean'),
        _workflowSuggestedField(
            'user_id', t.workflowFieldWorkflowUserId, t.workflowFieldDescWorkflowUserId, 'number'),
        _workflowSuggestedField('bale_chat_id', t.workflowFieldBaleChatId, t.workflowFieldDescBaleChatId, 'string'),
        _workflowSuggestedField('message', t.workflowFieldSentMessage, t.workflowFieldDescSentMessage, 'string'),
        _workflowSuggestedField(
            'send_file_attachment', t.workflowFieldSendFileAttachment, t.workflowFieldDescSendFileAttachment, 'boolean'),
        _workflowSuggestedField(
            'attachment_file_id', t.workflowFieldAttachmentFileId, t.workflowFieldDescAttachmentFileId, 'string'),
        _workflowSuggestedField(
            'filename', t.workflowFieldStoredFilename, t.workflowFieldDescStoredFilename, 'string'),
      ];
    }
    if (key == 'send_email') {
      return [
        _workflowSuggestedField('success', t.workflowFieldSuccess, t.workflowFieldDescSuccess, 'boolean'),
        _workflowSuggestedField('to', t.workflowFieldEmailTo, t.workflowFieldDescEmailTo, 'string'),
        _workflowSuggestedField(
            'subject', t.workflowFieldEmailSubject, t.workflowFieldDescEmailSubject, 'string'),
      ];
    }
    if (key == 'send_business_sms') {
      return [
        _workflowSuggestedField('success', t.workflowFieldSuccess, t.workflowFieldDescSuccess, 'boolean'),
        _workflowSuggestedField('template_id', t.workflowFieldId, t.workflowFieldDescId, 'number'),
        _workflowSuggestedField('log_id', t.workflowFieldDocumentId, t.workflowFieldDescDocumentId, 'number'),
        _workflowSuggestedField('event_type', t.workflowFieldType, t.workflowFieldDescType, 'string'),
        _workflowSuggestedField('cost', t.workflowFieldAmount, t.workflowFieldDescAmount, 'number'),
        _workflowSuggestedField('message', t.workflowFieldSentMessage, t.workflowFieldDescSentMessage, 'string'),
        _workflowSuggestedField('person_id', t.workflowFieldPersonId, t.workflowFieldDescPersonId, 'number'),
        _workflowSuggestedField(
            'error', t.workflowFieldGenStatus, t.workflowFieldDescGenStatus, 'string'),
      ];
    }
    if (key == 'http_request') {
      return [
        _workflowSuggestedField('success', t.workflowFieldSuccess, t.workflowFieldDescSuccess, 'boolean'),
        _workflowSuggestedField(
            'status_code', t.workflowFieldHttpStatusCode, t.workflowFieldDescHttpStatusCode, 'number'),
        _workflowSuggestedField('response', t.workflowFieldHttpResponse, t.workflowFieldDescHttpResponse, 'string'),
      ];
    }
    if (key == 'set_variable') {
      return [
        _workflowSuggestedField('success', t.workflowFieldSuccess, t.workflowFieldDescSuccess, 'boolean'),
        _workflowSuggestedField(
            'variable_name', t.workflowFieldVariableName, t.workflowFieldDescVariableName, 'string'),
        _workflowSuggestedField('value', t.workflowFieldVariableValue, t.workflowFieldDescVariableValue, 'string'),
      ];
    }
    if (key == 'log') {
      return [
        _workflowSuggestedField('success', t.workflowFieldSuccess, t.workflowFieldDescSuccess, 'boolean'),
        _workflowSuggestedField('level', t.workflowFieldLogLevel, t.workflowFieldDescLogLevel, 'string'),
        _workflowSuggestedField('message', t.workflowFieldSentMessage, t.workflowFieldDescSentMessage, 'string'),
      ];
    }
    if (key == 'create_notification') {
      return [
        _workflowSuggestedField('success', t.workflowFieldSuccess, t.workflowFieldDescSuccess, 'boolean'),
      ];
    }

    if (key == 'crm.chat.conversation.started') {
      return [
        _workflowSuggestedField(
            'conversation_id', t.workflowFieldCrmChatConversationId, t.workflowFieldDescCrmChatConversationId, 'number'),
        _workflowSuggestedField(
            'widget_id', t.workflowFieldCrmChatWidgetId, t.workflowFieldDescCrmChatWidgetId, 'number'),
        _workflowSuggestedField('visitor_first_name', t.workflowFieldCrmChatVisitorFirstName,
            t.workflowFieldDescCrmChatVisitorFirstName, 'string'),
        _workflowSuggestedField(
            'visitor_last_name', t.workflowFieldCrmChatVisitorLastName, t.workflowFieldDescCrmChatVisitorLastName, 'string'),
        _workflowSuggestedField('visitor_email', t.workflowFieldEmail, t.workflowFieldDescEmail, 'string'),
        _workflowSuggestedField('visitor_phone', t.workflowFieldPhone, t.workflowFieldDescPhone, 'string'),
        _workflowSuggestedField(
            'page_url', t.workflowFieldCrmChatPageUrl, t.workflowFieldDescCrmChatPageUrl, 'string'),
        _workflowSuggestedField('conversation_status', t.workflowFieldCrmChatConversationStatus,
            t.workflowFieldDescCrmChatConversationStatus, 'string'),
        _workflowSuggestedField('assigned_to_user_id', t.workflowFieldCrmChatAssignedToUserId,
            t.workflowFieldDescCrmChatAssignedToUserId, 'number'),
        _workflowSuggestedField('lead_id', t.workflowFieldLeadId, t.workflowFieldDescLeadId, 'number'),
        _workflowSuggestedField('person_id', t.workflowFieldPersonId, t.workflowFieldDescPersonId, 'number'),
      ];
    }
    if (key == 'crm.chat.message.received') {
      return [
        _workflowSuggestedField(
            'conversation_id', t.workflowFieldCrmChatConversationId, t.workflowFieldDescCrmChatConversationId, 'number'),
        _workflowSuggestedField(
            'widget_id', t.workflowFieldCrmChatWidgetId, t.workflowFieldDescCrmChatWidgetId, 'number'),
        _workflowSuggestedField(
            'message_id', t.workflowFieldCrmChatMessageId, t.workflowFieldDescCrmChatMessageId, 'number'),
        _workflowSuggestedField('body', t.workflowFieldCrmChatBody, t.workflowFieldDescCrmChatBody, 'string'),
        _workflowSuggestedField(
            'sender_role', t.workflowFieldCrmChatSenderRole, t.workflowFieldDescCrmChatSenderRole, 'string'),
        _workflowSuggestedField(
            'file_storage_id', t.workflowFieldFileStorageId, t.workflowFieldDescFileStorageId, 'string'),
        _workflowSuggestedField('visitor_first_name', t.workflowFieldCrmChatVisitorFirstName,
            t.workflowFieldDescCrmChatVisitorFirstName, 'string'),
        _workflowSuggestedField(
            'visitor_last_name', t.workflowFieldCrmChatVisitorLastName, t.workflowFieldDescCrmChatVisitorLastName, 'string'),
        _workflowSuggestedField('visitor_email', t.workflowFieldEmail, t.workflowFieldDescEmail, 'string'),
        _workflowSuggestedField('visitor_phone', t.workflowFieldPhone, t.workflowFieldDescPhone, 'string'),
        _workflowSuggestedField('conversation_status', t.workflowFieldCrmChatConversationStatus,
            t.workflowFieldDescCrmChatConversationStatus, 'string'),
        _workflowSuggestedField('assigned_to_user_id', t.workflowFieldCrmChatAssignedToUserId,
            t.workflowFieldDescCrmChatAssignedToUserId, 'number'),
        _workflowSuggestedField('lead_id', t.workflowFieldLeadId, t.workflowFieldDescLeadId, 'number'),
        _workflowSuggestedField('person_id', t.workflowFieldPersonId, t.workflowFieldDescPersonId, 'number'),
        _workflowSuggestedField(
            'page_url', t.workflowFieldCrmChatPageUrl, t.workflowFieldDescCrmChatPageUrl, 'string'),
      ];
    }
    if (key == 'crm.chat.message.sent') {
      return [
        _workflowSuggestedField(
            'conversation_id', t.workflowFieldCrmChatConversationId, t.workflowFieldDescCrmChatConversationId, 'number'),
        _workflowSuggestedField(
            'widget_id', t.workflowFieldCrmChatWidgetId, t.workflowFieldDescCrmChatWidgetId, 'number'),
        _workflowSuggestedField(
            'message_id', t.workflowFieldCrmChatMessageId, t.workflowFieldDescCrmChatMessageId, 'number'),
        _workflowSuggestedField('body', t.workflowFieldCrmChatBody, t.workflowFieldDescCrmChatBody, 'string'),
        _workflowSuggestedField(
            'sender_role', t.workflowFieldCrmChatSenderRole, t.workflowFieldDescCrmChatSenderRole, 'string'),
        _workflowSuggestedField(
            'agent_user_id', t.workflowFieldCrmChatAgentUserId, t.workflowFieldDescCrmChatAgentUserId, 'number'),
        _workflowSuggestedField(
            'automation_source', t.workflowFieldAutomationSource, t.workflowFieldDescAutomationSource, 'string'),
        _workflowSuggestedField(
            'operator_relay', t.workflowFieldOperatorRelay, t.workflowFieldDescOperatorRelay, 'boolean'),
      ];
    }
    if (key == 'crm.chat.conversation.assigned') {
      return [
        _workflowSuggestedField(
            'conversation_id', t.workflowFieldCrmChatConversationId, t.workflowFieldDescCrmChatConversationId, 'number'),
        _workflowSuggestedField(
            'widget_id', t.workflowFieldCrmChatWidgetId, t.workflowFieldDescCrmChatWidgetId, 'number'),
        _workflowSuggestedField('old_assigned_to_user_id', t.workflowFieldCrmChatOldAssignedUserId,
            t.workflowFieldDescCrmChatOldAssignedUserId, 'number'),
        _workflowSuggestedField('new_assigned_to_user_id', t.workflowFieldCrmChatNewAssignedUserId,
            t.workflowFieldDescCrmChatNewAssignedUserId, 'number'),
      ];
    }
    if (key == 'crm.chat.conversation.resolved') {
      return [
        _workflowSuggestedField(
            'conversation_id', t.workflowFieldCrmChatConversationId, t.workflowFieldDescCrmChatConversationId, 'number'),
        _workflowSuggestedField(
            'widget_id', t.workflowFieldCrmChatWidgetId, t.workflowFieldDescCrmChatWidgetId, 'number'),
      ];
    }
    if (key == 'crm.chat.conversation.reopened') {
      return [
        _workflowSuggestedField(
            'conversation_id', t.workflowFieldCrmChatConversationId, t.workflowFieldDescCrmChatConversationId, 'number'),
        _workflowSuggestedField(
            'widget_id', t.workflowFieldCrmChatWidgetId, t.workflowFieldDescCrmChatWidgetId, 'number'),
        _workflowSuggestedField(
            'old_status', t.workflowFieldCrmChatOldStatus, t.workflowFieldDescCrmChatOldStatus, 'string'),
        _workflowSuggestedField(
            'new_status', t.workflowFieldCrmChatNewStatus, t.workflowFieldDescCrmChatNewStatus, 'string'),
      ];
    }

    if (key.contains('payment')) {
      return [
        _workflowSuggestedField('payment_id', t.workflowFieldPaymentId, t.workflowFieldDescPaymentId, 'number'),
        _workflowSuggestedField('amount', t.workflowFieldAmount, t.workflowFieldPaymentAmount, 'number'),
        _workflowSuggestedField('payment_date', t.workflowFieldPaymentDate, t.workflowFieldDescPaymentDate, 'date'),
        _workflowSuggestedField(
            'payment_method', t.workflowFieldPaymentMethod, t.workflowFieldDescPaymentMethod, 'string'),
        _workflowSuggestedField('status', t.workflowFieldStatus, t.workflowFieldPaymentStatus, 'string'),
        _workflowSuggestedField(
            'reference_code', t.workflowFieldReferenceCode, t.workflowFieldDescReferenceCode, 'string'),
      ];
    }

    if (key.contains('product')) {
      return [
        _workflowSuggestedField('product_id', t.workflowFieldProductId, t.workflowFieldDescProductId, 'number'),
        _workflowSuggestedField('name', t.workflowFieldProductName, t.workflowFieldDescProductName, 'string'),
        _workflowSuggestedField('code', t.workflowFieldProductCode, t.workflowFieldDescProductCode, 'string'),
        _workflowSuggestedField('price', t.workflowFieldPrice, t.workflowFieldDescPrice, 'number'),
        _workflowSuggestedField('quantity', t.workflowFieldQuantity, t.workflowFieldDescQuantity, 'number'),
      ];
    }

    return [
      _workflowSuggestedField('id', t.workflowFieldId, t.workflowFieldDescId, 'number'),
      _workflowSuggestedField('name', t.workflowFieldName, t.workflowFieldDescName, 'string'),
      _workflowSuggestedField('title', t.workflowFieldTitle, t.workflowFieldDescTitle, 'string'),
      _workflowSuggestedField(
          'description', t.workflowFieldGenDescription, t.workflowFieldDescGenDescription, 'string'),
      _workflowSuggestedField('status', t.workflowFieldGenStatus, t.workflowFieldDescGenStatus, 'string'),
      _workflowSuggestedField('created_at', t.workflowFieldCreatedAt, t.workflowFieldDescCreatedAt, 'date'),
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

  Color _getNodeColor(WorkflowNodeType type, ThemeData theme, String? nodeKey) {
    if (type == WorkflowNodeType.action && nodeKey == 'send_business_sms') {
      return Colors.teal.shade700;
    }
    if (type == WorkflowNodeType.action && nodeKey == 'send_email') {
      return Colors.indigo.shade600;
    }
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

  IconData _getNodeIcon(WorkflowNodeType type, [String? nodeKey]) {
    if (type == WorkflowNodeType.action) {
      switch (nodeKey) {
        case 'send_business_sms':
          return Icons.sms_outlined;
        case 'send_email':
          return Icons.email_outlined;
        case 'send_telegram':
          return Icons.send;
        case 'send_bale':
          return Icons.chat;
        case 'http_request':
          return Icons.http;
        default:
          return Icons.play_arrow;
      }
    }
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


