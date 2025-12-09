import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';

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
  
  bool _isLoading = false;
  bool _isSaving = false;
  bool _showPreview = false;
  
  // Event types
  List<Map<String, dynamic>> _eventTypes = [];
  Map<String, dynamic>? _selectedEventType;
  
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
    _loadEventTypes();
    if (widget.templateId != null) {
      _loadTemplate();
    }
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
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/business-notifications/event-types',
      );
      
      final data = response.data?['data'] as Map<String, dynamic>?;
      final items = data?['items'] as List? ?? [];
      
      setState(() {
        _eventTypes = items.map((e) => e as Map<String, dynamic>).toList();
      });
      
      // اگر خالی بود، از داده‌های پیش‌فرض استفاده کن
      if (_eventTypes.isEmpty) {
        _loadDefaultEventTypes();
      }
    } catch (e) {
      // در صورت خطا، از داده‌های پیش‌فرض استفاده کن
      _loadDefaultEventTypes();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ رویدادها از حافظه محلی بارگذاری شدند. جداول سیستم ممکن است ایجاد نشده باشند.'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
  
  void _loadDefaultEventTypes() {
    // Event types پیش‌فرض (fallback)
    setState(() {
      _eventTypes = [
        {
          'id': 0,
          'code': 'invoice.created',
          'name': 'ثبت فاکتور فروش',
          'description': 'هنگامی که فاکتور فروش جدیدی ثبت می‌شود',
          'category': 'sales',
          'available_variables': [
            {'key': 'invoice_number', 'type': 'string', 'description': 'شماره فاکتور'},
            {'key': 'customer_name', 'type': 'string', 'description': 'نام مشتری'},
            {'key': 'amount', 'type': 'number', 'description': 'مبلغ کل'},
            {'key': 'invoice_date', 'type': 'date', 'description': 'تاریخ فاکتور'},
            {'key': 'business_name', 'type': 'string', 'description': 'نام کسب‌وکار'},
            {'key': 'business_phone', 'type': 'string', 'description': 'تلفن کسب‌وکار'},
          ],
          'default_sms_template': 'سلام {{ customer_name }}، فاکتور {{ invoice_number }} به مبلغ {{ amount | format_currency }} ثبت شد. {{ business_name }}',
          'default_email_subject': 'فاکتور جدید - {{ invoice_number }}',
        },
        {
          'id': 0,
          'code': 'repair_shop.received',
          'name': 'دریافت کالا در تعمیرگاه',
          'description': 'هنگامی که کالای مشتری برای تعمیر دریافت می‌شود',
          'category': 'repair_shop',
          'available_variables': [
            {'key': 'repair_code', 'type': 'string', 'description': 'کد رسید تعمیر'},
            {'key': 'customer_name', 'type': 'string', 'description': 'نام مشتری'},
            {'key': 'product_name', 'type': 'string', 'description': 'نام کالا'},
            {'key': 'estimated_delivery', 'type': 'date', 'description': 'تاریخ تحویل تقریبی'},
            {'key': 'business_name', 'type': 'string', 'description': 'نام تعمیرگاه'},
            {'key': 'business_phone', 'type': 'string', 'description': 'تلفن تعمیرگاه'},
          ],
          'default_sms_template': 'سلام {{ customer_name }}، {{ product_name }} با کد {{ repair_code }} دریافت شد. تحویل تقریبی: {{ estimated_delivery | format_date }}. {{ business_name }}',
          'default_email_subject': 'دریافت کالا - {{ repair_code }}',
        },
        {
          'id': 0,
          'code': 'repair_shop.ready',
          'name': 'آماده تحویل از تعمیرگاه',
          'description': 'هنگامی که کالای تعمیر شده آماده تحویل است',
          'category': 'repair_shop',
          'available_variables': [
            {'key': 'repair_code', 'type': 'string', 'description': 'کد رسید'},
            {'key': 'customer_name', 'type': 'string', 'description': 'نام مشتری'},
            {'key': 'product_name', 'type': 'string', 'description': 'نام کالا'},
            {'key': 'final_cost', 'type': 'number', 'description': 'هزینه نهایی'},
            {'key': 'business_name', 'type': 'string', 'description': 'نام تعمیرگاه'},
            {'key': 'business_phone', 'type': 'string', 'description': 'تلفن تعمیرگاه'},
          ],
          'default_sms_template': 'سلام {{ customer_name }}، {{ product_name }} (کد {{ repair_code }}) آماده تحویل است. هزینه: {{ final_cost | format_currency }}. {{ business_name }}',
          'default_email_subject': 'کالای شما آماده تحویل است',
        },
        {
          'id': 0,
          'code': 'payment.received',
          'name': 'دریافت پرداخت',
          'description': 'هنگامی که پرداختی از مشتری دریافت می‌شود',
          'category': 'financial',
          'available_variables': [
            {'key': 'receipt_number', 'type': 'string', 'description': 'شماره رسید'},
            {'key': 'customer_name', 'type': 'string', 'description': 'نام مشتری'},
            {'key': 'amount', 'type': 'number', 'description': 'مبلغ دریافتی'},
            {'key': 'payment_date', 'type': 'date', 'description': 'تاریخ پرداخت'},
            {'key': 'business_name', 'type': 'string', 'description': 'نام کسب‌وکار'},
          ],
          'default_sms_template': 'سلام {{ customer_name }}، پرداخت شما به مبلغ {{ amount | format_currency }} دریافت شد. رسید: {{ receipt_number }}. {{ business_name }}',
          'default_email_subject': 'رسید پرداخت - {{ receipt_number }}',
        },
      ];
    });
  }

  Future<void> _loadTemplate() async {
    setState(() => _isLoading = true);

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
          
          // پیدا کردن event type
          final eventTypeCode = data['event_type'] as String?;
          if (eventTypeCode != null) {
            _selectedEventType = _eventTypes.firstWhere(
              (et) => et['code'] == eventTypeCode,
              orElse: () => {},
            );
          }
        });
      }
      
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در بارگذاری قالب: $e')),
        );
      }
    }
  }

  Future<void> _saveTemplate() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedEventType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً نوع رویداد را انتخاب کنید')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // تولید کد خودکار اگر خالی باشد
      String code = _codeController.text;
      if (code.isEmpty && widget.templateId == null) {
        final eventCode = _selectedEventType!['code'] as String;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        code = '${eventCode}_${_selectedChannel}_$timestamp';
      }
      
      final data = {
        'code': code,
        'name': _nameController.text,
        'description': _descriptionController.text.isNotEmpty ? _descriptionController.text : null,
        'event_type': _selectedEventType!['code'],
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ قالب ایجاد شد. برای فعال‌سازی باید آن را برای تایید ارسال کنید.')),
          );
          context.pop(true);
        }
      } else {
        // ویرایش
        await _apiClient.put(
          '/api/v1/business-notifications/businesses/${widget.businessId}/templates/${widget.templateId}',
          data: data,
        );
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ قالب به‌روزرسانی شد')),
          );
          context.pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _generatePreview() async {
    if (_selectedEventType == null || _bodyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً رویداد و محتوای قالب را وارد کنید')),
      );
      return;
    }

    // ساخت context نمونه از متغیرها
    final variables = _selectedEventType!['available_variables'] as List? ?? [];
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در پیش‌نمایش: $e')),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
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
                        value: _selectedEventType,
                        decoration: const InputDecoration(
                          labelText: 'نوع رویداد *',
                          prefixIcon: Icon(Icons.event),
                          helperText: 'رویدادی که باعث ارسال نوتیفیکیشن می‌شود',
                        ),
                        items: _eventTypes.map((et) {
                          return DropdownMenuItem(
                            value: et,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(et['name'] as String),
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
                          if (_selectedEventType != null)
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
    if (_selectedEventType == null) return;
    
    final variables = _selectedEventType!['available_variables'] as List? ?? [];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('متغیرهای قابل استفاده'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('در محتوای قالب می‌توانید از متغیرهای زیر استفاده کنید:'),
                const SizedBox(height: 16),
                ...variables.map((v) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '{{ ${v['key']} }}',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              v['type'] as String,
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          v['description'] as String,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text('فیلترها:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('• {{ amount | format_currency }} → 1,500,000 تومان'),
                const Text('• {{ date | format_date }} → 1403/12/15'),
                const Text('• {{ count | format_number }} → 1,500'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
        ],
      ),
    );
  }
}

