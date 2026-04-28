import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/error_extractor.dart';


/// صفحه فرم ایجاد/ویرایش قالب نوتیفیکیشن
class NotificationTemplateFormPage extends StatefulWidget {
  final int businessId;
  final int? templateId; // null = ایجاد جدید

  const NotificationTemplateFormPage({
    super.key,
    required this.businessId,
    this.templateId,
  });

  @override
  State<NotificationTemplateFormPage> createState() => _NotificationTemplateFormPageState();
}

class _NotificationTemplateFormPageState extends State<NotificationTemplateFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _apiClient = ApiClient();
  
  bool _isSaving = false;
  bool _showPreview = false;
  bool _bootstrapComplete = false;
  
  // Event types (فقط از سرور؛ بدون دادهٔ ساختگی)
  List<Map<String, dynamic>> _eventTypes = [];
  Map<String, dynamic>? _selectedEventType;
  String? _eventTypesError;
  
  // Form controllers
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  final _dailyLimitController = TextEditingController(text: '100');
  
  String _selectedChannel = 'sms';
  String _selectedRecipientType = 'customer';
  bool _isAutomated = false;
  
  // Preview
  String _previewBody = '';
  String _previewSubject = '';

  @override
  void initState() {
    super.initState();
    _bodyController.addListener(() {
      if (mounted) setState(() {});
    });
    Future<void>.microtask(_bootstrap);
  }

  /// ابتدا کاتالوگ رویدادها، سپس در حالت ویرایش بارگذاری قالب (جلوگیری از race و نقشهٔ `{}` نامعتبر)
  Future<void> _bootstrap() async {
    await _loadEventTypes();
    if (!mounted) return;
    if (widget.templateId != null) {
      await _loadTemplate();
    }
    if (mounted) {
      setState(() => _bootstrapComplete = true);
    }
  }

  List<Map<String, dynamic>> get _sortedEventTypes {
    final list = List<Map<String, dynamic>>.from(_eventTypes);
    list.sort((a, b) {
      final ca = '${a['category'] ?? ''}';
      final cb = '${b['category'] ?? ''}';
      final c = ca.compareTo(cb);
      if (c != 0) return c;
      return '${a['name']}'.compareTo('${b['name']}');
    });
    return list;
  }

  /// فقط اگر همان شیء در لیست سرور باشد معتبر است (برای Dropdown و ذخیره)
  Map<String, dynamic>? get _resolvedSelectedEvent {
    final raw = _selectedEventType;
    if (raw == null) return null;
    final code = raw['code'];
    if (code is! String || code.isEmpty) return null;
    for (final et in _eventTypes) {
      if (et['code'] == code) return et;
    }
    return null;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    _dailyLimitController.dispose();
    super.dispose();
  }

  Future<void> _loadEventTypes() async {
    setState(() {
      _eventTypesError = null;
    });
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/business-notifications/event-types',
      );

      final data = response.data?['data'] as Map<String, dynamic>?;
      final items = data?['items'] as List? ?? [];

      if (!mounted) return;
      setState(() {
        _eventTypes = items.map((e) => e as Map<String, dynamic>).toList();
        if (_eventTypes.isEmpty) {
          _eventTypesError =
              'هیچ نوع رویدادی در سرور ثبت نشده است. پس از به‌روزرسانی سیستم (مهاجرت دیتابیس) دوباره تلاش کنید یا با پشتیبانی تماس بگیرید.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _eventTypes = [];
        _eventTypesError =
            'بارگذاری رویدادها ناموفق بود. اتصال اینترنت یا دسترسی API را بررسی کنید. جزئیات: $e';
      });
    }
  }

  Future<void> _loadTemplate() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/business-notifications/businesses/${widget.businessId}/templates/${widget.templateId}',
      );
      
      final data = response.data?['data'] as Map<String, dynamic>?;
      if (data != null) {
        _codeController.text = data['code'] as String? ?? '';
        _nameController.text = data['name'] as String? ?? '';
        _descriptionController.text = data['description'] as String? ?? '';
        _subjectController.text = data['subject'] as String? ?? '';
        _bodyController.text = data['body'] as String? ?? '';
        _dailyLimitController.text = (data['daily_limit'] as int? ?? 100).toString();
        
        setState(() {
          _selectedChannel = data['channel'] as String? ?? 'sms';
          _selectedRecipientType = data['recipient_type'] as String? ?? 'customer';
          _isAutomated = data['is_automated'] as bool? ?? false;

          final eventTypeCode = data['event_type'] as String?;
          Map<String, dynamic>? match;
          if (eventTypeCode != null) {
            for (final et in _eventTypes) {
              if (et['code'] == eventTypeCode) {
                match = et;
                break;
              }
            }
          }
          _selectedEventType = match;
        });
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message:
              'خطا در بارگذاری قالب: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    }
  }

  Future<void> _saveTemplate() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_resolvedSelectedEvent == null) {
      SnackBarHelper.show(context, message: 'لطفاً نوع رویداد را از فهرست سرور انتخاب کنید');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // تولید کد خودکار اگر خالی باشد
      String code = _codeController.text;
      if (code.isEmpty && widget.templateId == null) {
        final eventCode = _resolvedSelectedEvent!['code'] as String;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        code = '${eventCode}_${_selectedChannel}_$timestamp';
      }
      
      final data = {
        'code': code,
        'name': _nameController.text,
        'description': _descriptionController.text.isNotEmpty ? _descriptionController.text : null,
        'event_type': _resolvedSelectedEvent!['code'],
        'channel': _selectedChannel,
        'recipient_type': _selectedRecipientType,
        'subject': _subjectController.text.isNotEmpty ? _subjectController.text : null,
        'body': _bodyController.text,
        'daily_limit': int.parse(_dailyLimitController.text),
        'is_automated': _isAutomated,
      };

      if (widget.templateId == null) {
        // ایجاد جدید
        await _apiClient.post(
          '/api/v1/business-notifications/businesses/${widget.businessId}/templates',
          data: data,
        );
        
        if (mounted) {
          SnackBarHelper.show(context, message: '✅ قالب ایجاد شد. برای فعال‌سازی باید آن را برای تایید ارسال کنید.');
          context.pop(true);
        }
      } else {
        // ویرایش
        await _apiClient.put(
          '/api/v1/business-notifications/businesses/${widget.businessId}/templates/${widget.templateId}',
          data: data,
        );
        
        if (mounted) {
          SnackBarHelper.show(context, message: '✅ قالب به‌روزرسانی شد');
          context.pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _generatePreview() async {
    if (_resolvedSelectedEvent == null || _bodyController.text.isEmpty) {
      SnackBarHelper.show(context, message: 'لطفاً رویداد و محتوای قالب را وارد کنید');
      return;
    }

    // ساخت context نمونه از متغیرها
    final variables = _resolvedSelectedEvent!['available_variables'] as List? ?? [];
    final sampleContext = <String, dynamic>{};
    
    for (var v in variables) {
      final key = v['key'] as String;
      final type = v['type'] as String;
      
      switch (type) {
        case 'string':
          sampleContext[key] = 'نمونه';
          break;
        case 'number':
          sampleContext[key] = 1000000;
          break;
        case 'date':
          sampleContext[key] = DateTime.now().toIso8601String();
          break;
        default:
          sampleContext[key] = 'مقدار';
      }
    }

    try {
      if (widget.templateId != null) {
        // استفاده از API preview
        final response = await _apiClient.post(
          '/api/v1/business-notifications/businesses/${widget.businessId}/templates/${widget.templateId}/preview',
          data: {'sample_context': sampleContext},
        );
        
        final data = response.data?['data'] as Map<String, dynamic>?;
        final rendered = data?['rendered'] as Map<String, dynamic>?;
        
        setState(() {
          _previewBody = rendered?['body'] as String? ?? _bodyController.text;
          _previewSubject = rendered?['subject'] as String? ?? _subjectController.text;
          _showPreview = true;
        });
      } else {
        // پیش‌نمایش ساده (client-side)
        setState(() {
          _previewBody = _renderTemplate(_bodyController.text, sampleContext);
          _previewSubject = _renderTemplate(_subjectController.text, sampleContext);
          _showPreview = true;
        });
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message:
              'خطا در پیش‌نمایش: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    }
  }

  String _renderTemplate(String template, Map<String, dynamic> context) {
    String result = template;
    
    // جایگزینی متغیرهای ساده
    context.forEach((key, value) {
      // پشتیبانی از فرمت‌های مختلف
      result = result.replaceAll('{{ $key }}', _formatValue(value));
      result = result.replaceAll('{{$key}}', _formatValue(value));
      result = result.replaceAll('{{ $key|format_currency }}', _formatCurrency(value));
      result = result.replaceAll('{{$key|format_currency}}', _formatCurrency(value));
      result = result.replaceAll('{{ $key | format_currency }}', _formatCurrency(value));
      result = result.replaceAll('{{$key | format_currency}}', _formatCurrency(value));
      result = result.replaceAll('{{ $key|format_date }}', _formatDate(value));
      result = result.replaceAll('{{$key|format_date}}', _formatDate(value));
      result = result.replaceAll('{{ $key | format_date }}', _formatDate(value));
      result = result.replaceAll('{{$key | format_date}}', _formatDate(value));
      result = result.replaceAll('{{ $key|format_number }}', _formatNumber(value));
      result = result.replaceAll('{{$key|format_number}}', _formatNumber(value));
      result = result.replaceAll('{{ $key | format_number }}', _formatNumber(value));
      result = result.replaceAll('{{$key | format_number}}', _formatNumber(value));
    });
    
    return result;
  }

  String _formatValue(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  String _formatCurrency(dynamic value) {
    try {
      final num = double.tryParse(value.toString()) ?? 0;
      final formatted = num.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (match) => '${match[1]}،',
      );
      return '$formatted تومان';
    } catch (e) {
      return value.toString();
    }
  }

  String _formatDate(dynamic value) {
    try {
      if (value is String) {
        final date = DateTime.parse(value);
        return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
      } else if (value is DateTime) {
        return '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
      }
      return value.toString();
    } catch (e) {
      return value.toString();
    }
  }

  String _formatNumber(dynamic value) {
    try {
      final num = double.tryParse(value.toString()) ?? 0;
      return num.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (match) => '${match[1]}،',
      );
    } catch (e) {
      return value.toString();
    }
  }

  String _categoryLabel(String? code) {
    switch (code) {
      case 'sales':
        return 'فروش';
      case 'purchases':
        return 'خرید';
      case 'financial':
        return 'مالی';
      case 'repair_shop':
        return 'تعمیرگاه';
      case 'warranty':
        return 'گارانتی';
      case 'people':
        return 'اشخاص';
      case 'crm':
        return 'CRM';
      case 'documents':
        return 'اسناد';
      case 'warehouse':
        return 'انبار';
      case 'distribution':
        return 'پخش مویرگی';
      default:
        if (code != null && code.isNotEmpty) return code;
        return 'سایر';
    }
  }

  Future<void> _retryCatalogAndTemplate() async {
    if (!mounted) return;
    setState(() => _bootstrapComplete = false);
    await _bootstrap();
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      SnackBarHelper.show(context, message: 'در کلیپ‌بورد کپی شد');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!_bootstrapComplete) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.templateId == null ? 'قالب جدید' : 'ویرایش قالب'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.templateId == null ? 'قالب جدید' : 'ویرایش قالب'),
        actions: [
          if (!_isSaving)
            IconButton(
              icon: const Icon(Icons.visibility),
              tooltip: 'پیش‌نمایش',
              onPressed: _generatePreview,
            ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'ذخیره',
              onPressed: _saveTemplate,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: colorScheme.primaryContainer.withOpacity(0.28),
                borderRadius: BorderRadius.circular(12),
                child: ExpansionTile(
                  leading: Icon(Icons.menu_book_outlined, color: colorScheme.onPrimaryContainer),
                  title: Text(
                    'راهنما و نکات مهم',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('پیش از ذخیره بخوانید تا خطای رویداد نامعتبر تکرار نشود'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(
                        '• نوع رویداد باید فقط از فهرست زیر انتخاب شود؛ اگر سرور هنوز رویدادی ثبت نکرده باشد، ابتدا باید دیتابیس با مهاجرت یا اسکریپت seed به‌روز شود.\n'
                        '• برای اتوماسیون فاکتور: «invoice.sales.created» فقط فروش، «invoice.purchase.created» فقط خرید، «invoice.created» برای همه فاکتورها در تریگر عمومی.\n'
                        '• قالب‌ها با Jinja2 رندر می‌شوند؛ مثال متغیر: {{ customer_name }} و فیلترها: {{ amount | format_currency }}، {{ invoice_date | format_date }}.\n'
                        '• پس از ذخیره، قالب پیش‌نویس است و برای ارسال انبوه باید از مسیر تأیید مدیر عبور کند.',
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_eventTypesError != null) ...[
                Card(
                  color: colorScheme.errorContainer.withOpacity(0.38),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: colorScheme.error),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _eventTypesError!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _retryCatalogAndTemplate,
                          child: const Text('تلاش مجدد'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // اطلاعات اولیه
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'اطلاعات پایه',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      
                      // کد قالب
                      TextFormField(
                        controller: _codeController,
                        decoration: const InputDecoration(
                          labelText: 'کد قالب (اختیاری - خودکار تولید می‌شود)',
                          hintText: 'مثلاً: invoice_created_sms',
                          helperText: 'اگر خالی بگذارید، خودکار تولید می‌شود',
                          prefixIcon: Icon(Icons.code),
                        ),
                        enabled: widget.templateId == null, // فقط در ایجاد
                      ),
                      const SizedBox(height: 16),
                      
                      // نام قالب
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'نام قالب *',
                          hintText: 'مثلاً: پیامک ثبت فاکتور',
                          prefixIcon: Icon(Icons.title),
                        ),
                        validator: (v) => v == null || v.isEmpty ? 'نام الزامی است' : null,
                      ),
                      const SizedBox(height: 16),
                      
                      // توضیحات
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'توضیحات (اختیاری)',
                          hintText: 'توضیح مختصر درباره این قالب',
                          prefixIcon: Icon(Icons.description),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // تنظیمات رویداد و کانال
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'رویداد و کانال',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      
                      // انتخاب event type
                      DropdownButtonFormField<Map<String, dynamic>>(
                        value: _resolvedSelectedEvent,
                        decoration: const InputDecoration(
                          labelText: 'نوع رویداد *',
                          prefixIcon: Icon(Icons.event),
                          helperText: 'رویدادی که باعث ارسال نوتیفیکیشن می‌شود',
                        ),
                        items: _sortedEventTypes.map((et) {
                          return DropdownMenuItem(
                            value: et,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                              Text(
                                  '${_categoryLabel(et['category'] as String?)} • ${et['name'] as String}'),
                                Text(
                                  et['code'] as String,
                                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedEventType = value;
                            
                            // پیشنهاد قالب پیش‌فرض
                            if (value != null && _bodyController.text.isEmpty) {
                              if (_selectedChannel == 'sms' && value['default_sms_template'] != null) {
                                _bodyController.text = value['default_sms_template'] as String;
                              } else if (_selectedChannel == 'email' && value['default_email_template'] != null) {
                                _bodyController.text = value['default_email_template'] as String;
                                _subjectController.text = value['default_email_subject'] as String? ?? '';
                              }
                            }
                          });
                        },
                        validator: (v) => v == null ? 'انتخاب رویداد الزامی است' : null,
                      ),
                      const SizedBox(height: 16),
                      
                      // انتخاب کانال
                      DropdownButtonFormField<String>(
                        value: _selectedChannel,
                        decoration: const InputDecoration(
                          labelText: 'کانال ارسال *',
                          prefixIcon: Icon(Icons.send),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'sms', child: Text('📱 پیامک (SMS)')),
                          DropdownMenuItem(value: 'email', child: Text('📧 ایمیل')),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedChannel = value!);
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // نوع گیرنده
                      DropdownButtonFormField<String>(
                        value: _selectedRecipientType,
                        decoration: const InputDecoration(
                          labelText: 'نوع گیرنده',
                          prefixIcon: Icon(Icons.people),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'customer', child: Text('مشتری')),
                          DropdownMenuItem(value: 'supplier', child: Text('تامین‌کننده')),
                          DropdownMenuItem(value: 'employee', child: Text('کارمند')),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedRecipientType = value!);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // محتوای قالب
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'محتوای قالب',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          if (_resolvedSelectedEvent != null)
                            TextButton.icon(
                              onPressed: _showVariablesHelp,
                              icon: const Icon(Icons.help_outline, size: 18),
                              label: const Text('متغیرهای قابل استفاده'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // موضوع (فقط برای email)
                      if (_selectedChannel == 'email') ...[
                        TextFormField(
                          controller: _subjectController,
                          decoration: const InputDecoration(
                            labelText: 'موضوع (Subject) *',
                            hintText: 'مثلاً: فاکتور جدید - {{ invoice_number }}',
                            prefixIcon: Icon(Icons.subject),
                          ),
                          validator: (v) => v == null || v.isEmpty ? 'موضوع الزامی است' : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      // محتوا
                      TextFormField(
                        controller: _bodyController,
                        decoration: InputDecoration(
                          labelText: 'محتوای پیام *',
                          hintText: _selectedChannel == 'sms'
                              ? 'سلام {{ customer_name }}، فاکتور {{ invoice_number }} ثبت شد.'
                              : 'محتوای ایمیل با استفاده از متغیرها...',
                          alignLabelWithHint: true,
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(bottom: 80),
                            child: Icon(Icons.message),
                          ),
                        ),
                        maxLines: _selectedChannel == 'sms' ? 4 : 10,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'محتوا الزامی است';
                          if (_selectedChannel == 'sms' && v.length > 500) {
                            return 'پیامک نباید بیش از 500 کاراکتر باشد';
                          }
                          return null;
                        },
                        onChanged: (v) {
                          // هشدار در صورت استفاده نادرست از متغیر
                          if (v.contains('{') && !v.contains('{{')) {
                            // نمایش hint
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedChannel == 'sms'
                                ? 'تعداد کاراکتر: ${_bodyController.text.length} / 500'
                                : 'تعداد کاراکتر: ${_bodyController.text.length}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _bodyController.text.length > 500 && _selectedChannel == 'sms'
                                  ? Colors.red
                                  : Colors.grey,
                            ),
                          ),
                          if (_selectedChannel == 'email')
                            Text(
                              'حداکثر توصیه شده: 2000 کاراکتر',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _bodyController.text.length > 2000
                                    ? Colors.orange
                                    : Colors.grey,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // تنظیمات پیشرفته
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تنظیمات پیشرفته',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      
                      // محدودیت روزانه
                      TextFormField(
                        controller: _dailyLimitController,
                        decoration: const InputDecoration(
                          labelText: 'حداکثر ارسال روزانه',
                          hintText: '100',
                          helperText: 'برای جلوگیری از spam',
                          prefixIcon: Icon(Icons.speed),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'الزامی است';
                          final num = int.tryParse(v);
                          if (num == null || num < 1 || num > 10000) {
                            return 'عدد بین 1 تا 10000';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // ارسال خودکار
                      SwitchListTile(
                        title: const Text('ارسال خودکار'),
                        subtitle: const Text('ارسال خودکار هنگام وقوع رویداد'),
                        value: _isAutomated,
                        onChanged: (value) {
                          setState(() => _isAutomated = value);
                        },
                        secondary: const Icon(Icons.autorenew),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // دکمه‌ها
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : () => context.pop(),
                      icon: const Icon(Icons.cancel),
                      label: const Text('انصراف'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveTemplate,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(_isSaving ? 'در حال ذخیره...' : 'ذخیره قالب'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      
      // پیش‌نمایش به صورت bottom sheet
      bottomSheet: _showPreview ? _buildPreviewSheet(theme, colorScheme) : null,
    );
  }

  Widget _buildPreviewSheet(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.4,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility),
              const SizedBox(width: 8),
              Text('پیش‌نمایش', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _showPreview = false),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectedChannel == 'email' && _previewSubject.isNotEmpty) ...[
                    Text('موضوع:', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_previewSubject),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text('محتوا:', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
                    ),
                    child: Text(_previewBody),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showVariablesHelp() {
    final et = _resolvedSelectedEvent;
    if (et == null) return;

    final variables = et['available_variables'] as List? ?? [];

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('متغیرها و فیلترها'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'رویداد: ${et['name']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'کد فنی: ${et['code']}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
                const SizedBox(height: 12),
                Text(
                  et['description']?.toString() ?? '',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                const Text('در متن قالب بکار ببرید (ضربه روی دکمه کپی):'),
                const SizedBox(height: 8),
                ...variables.map((v) {
                  final key = v['key'] as String;
                  final tpl = '{{ $key }}';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  tpl,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'کپی',
                              icon: const Icon(Icons.copy, size: 20),
                              onPressed: () => _copyToClipboard(tpl),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              v['type'] as String,
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                v['description'] as String,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text('فیلترهای پرکاربرد:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('مبلغ + واحد'),
                      onPressed: () => _copyToClipboard(r'{{ amount | format_currency }}'),
                    ),
                    ActionChip(
                      label: const Text('تاریخ'),
                      onPressed: () => _copyToClipboard(r'{{ invoice_date | format_date }}'),
                    ),
                    ActionChip(
                      label: const Text('عدد با جداکننده'),
                      onPressed: () => _copyToClipboard(r'{{ amount | format_number }}'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'فاصله دور | در الگو مهم است (مثل Jinja2).',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('بستن'),
          ),
        ],
      ),
    );
  }
}

