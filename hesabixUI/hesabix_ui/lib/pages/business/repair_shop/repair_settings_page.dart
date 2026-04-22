import 'package:flutter/material.dart';
import '../../../services/repair_shop_service.dart';
import '../../../models/repair_settings_model.dart';
import '../../../core/api_client.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/business_subpage_back_leading.dart';


/// صفحه تنظیمات تعمیرگاه
class RepairSettingsPage extends StatefulWidget {
  final int businessId;

  const RepairSettingsPage({
    super.key,
    required this.businessId,
  });

  @override
  State<RepairSettingsPage> createState() => _RepairSettingsPageState();
}

class _RepairSettingsPageState extends State<RepairSettingsPage> {
  late final RepairShopService _service;
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  // Controllers
  final TextEditingController _prefixController = TextEditingController();
  String _codeFormat = 'sequential';
  bool _autoSmsOnReceive = false;
  bool _autoSmsOnStatusChange = false;
  bool _autoEmailOnReceive = false;
  bool _autoEmailOnStatusChange = false;

  @override
  void initState() {
    super.initState();
    _service = RepairShopService(ApiClient());
    _loadSettings();
  }

  @override
  void dispose() {
    _prefixController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final settings = await _service.getSettings(
        businessId: widget.businessId,
      );

      setState(() {
        _prefixController.text = settings.receiptCodePrefix;
        _codeFormat = settings.receiptCodeFormat;
        _autoSmsOnReceive = settings.autoSendSmsOnReceive;
        _autoSmsOnStatusChange = settings.autoSendSmsOnStatusChange;
        _autoEmailOnReceive = settings.autoSendEmailOnReceive;
        _autoEmailOnStatusChange = settings.autoSendEmailOnStatusChange;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'خطا در بارگذاری تنظیمات: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final data = {
        'receipt_code_prefix': _prefixController.text,
        'receipt_code_format': _codeFormat,
        'auto_send_sms_on_receive': _autoSmsOnReceive,
        'auto_send_sms_on_status_change': _autoSmsOnStatusChange,
        'auto_send_email_on_receive': _autoEmailOnReceive,
        'auto_send_email_on_status_change': _autoEmailOnStatusChange,
      };

      await _service.updateSettings(
        businessId: widget.businessId,
        settings: data,
      );

      if (mounted) {
        SnackBarHelper.show(context, message: 'تنظیمات با موفقیت ذخیره شد');
        _loadSettings();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا در ذخیره تنظیمات: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تنظیمات تعمیرگاه'),
        leading: businessSubpageBackLeading(context, widget.businessId),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _saveSettings,
              tooltip: 'ذخیره',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, size: 64, color: colorScheme.error),
                      const SizedBox(height: 16),
                      Text(_errorMessage!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadSettings,
                        child: const Text('تلاش مجدد'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // بخش شماره‌گذاری
                        _buildSectionTitle('شماره‌گذاری سفارشات', Icons.numbers),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                // فرمت کد
                                DropdownButtonFormField<String>(
                                  initialValue: _codeFormat,
                                  decoration: const InputDecoration(
                                    labelText: 'فرمت شماره‌گذاری',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.format_list_numbered),
                                    helperText:
                                        'ترتیبی: REC-2025-0001 | تصادفی: REC-A7B3C9',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'sequential',
                                      child: Text('ترتیبی'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'random',
                                      child: Text('تصادفی'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    setState(() => _codeFormat = value!);
                                  },
                                ),

                                const SizedBox(height: 16),

                                // پیشوند کد
                                TextFormField(
                                  controller: _prefixController,
                                  decoration: const InputDecoration(
                                    labelText: 'پیشوند کد',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.label),
                                    helperText: 'مثال: REC، REP، REPAIR',
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'پیشوند الزامی است';
                                    }
                                    if (value.length > 10) {
                                      return 'حداکثر 10 کاراکتر';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // بخش اعلان‌ها
                        _buildSectionTitle('اعلان‌های خودکار', Icons.notifications),
                        Card(
                          child: Column(
                            children: [
                              SwitchListTile(
                                title: const Text('پیامک دریافت سفارش'),
                                subtitle: const Text(
                                    'ارسال خودکار پیامک هنگام دریافت سفارش جدید'),
                                value: _autoSmsOnReceive,
                                onChanged: (value) {
                                  setState(() => _autoSmsOnReceive = value);
                                },
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                title: const Text('پیامک تغییر وضعیت'),
                                subtitle: const Text(
                                    'ارسال خودکار پیامک هنگام تغییر وضعیت'),
                                value: _autoSmsOnStatusChange,
                                onChanged: (value) {
                                  setState(() => _autoSmsOnStatusChange = value);
                                },
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                title: const Text('ایمیل دریافت سفارش'),
                                subtitle: const Text(
                                    'ارسال خودکار ایمیل هنگام دریافت سفارش جدید'),
                                value: _autoEmailOnReceive,
                                onChanged: (value) {
                                  setState(() => _autoEmailOnReceive = value);
                                },
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                title: const Text('ایمیل تغییر وضعیت'),
                                subtitle: const Text(
                                    'ارسال خودکار ایمیل هنگام تغییر وضعیت'),
                                value: _autoEmailOnStatusChange,
                                onChanged: (value) {
                                  setState(
                                      () => _autoEmailOnStatusChange = value);
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // بخش اطلاعات
                        _buildSectionTitle('راهنما', Icons.info_outline),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildInfoRow(
                                  '📋 فرمت ترتیبی',
                                  'کدها به صورت REC-2025-0001، REC-2025-0002 و... تولید می‌شوند',
                                ),
                                const SizedBox(height: 12),
                                _buildInfoRow(
                                  '🎲 فرمت تصادفی',
                                  'کدها به صورت REC-A7B3C9، REC-XY4K2L و... تولید می‌شوند',
                                ),
                                const SizedBox(height: 12),
                                _buildInfoRow(
                                  '📱 اعلان‌های خودکار',
                                  'برای استفاده از این قابلیت، ابتدا باید تنظیمات پیامک و ایمیل را در بخش تنظیمات کلی فعال کنید',
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // دکمه ذخیره
                        ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveSettings,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.check),
                          label: Text(_isSaving ? 'در حال ذخیره...' : 'ذخیره تنظیمات'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 24),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

