import 'package:flutter/material.dart';
import '../../../services/repair_shop_service.dart';
import '../../../models/repair_settings_model.dart';
import '../../../core/api_client.dart';
import '../../../core/calendar_controller.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/business_subpage_back_leading.dart';
import '../../../widgets/invoice/product_combobox_widget.dart';
import '../../../widgets/invoice/warehouse_combobox_widget.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';


/// صفحه تنظیمات تعمیرگاه
class RepairSettingsPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const RepairSettingsPage({
    super.key,
    required this.businessId,
    required this.calendarController,
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
  Map<String, dynamic>? _serviceProduct;
  int? _defaultWarehouseId;

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
      final RepairShopSettings settings = await _service.getSettings(
        businessId: widget.businessId,
      );

      setState(() {
        _prefixController.text = settings.receiptCodePrefix;
        _codeFormat = settings.receiptCodeFormat;
        _autoSmsOnReceive = settings.autoSendSmsOnReceive;
        _autoSmsOnStatusChange = settings.autoSendSmsOnStatusChange;
        _autoEmailOnReceive = settings.autoSendEmailOnReceive;
        _autoEmailOnStatusChange = settings.autoSendEmailOnStatusChange;
        _defaultWarehouseId = settings.defaultWarehouseId;
        _serviceProduct = settings.defaultServiceProductId == null
            ? null
            : {'id': settings.defaultServiceProductId};
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppLocalizations.of(context).repairShopLoadSettingsError(
          ErrorExtractor.forContext(e, context),
        );
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
        'default_service_product_id': _serviceProduct?['id'],
        'default_warehouse_id': _defaultWarehouseId,
      };

      await _service.updateSettings(
        businessId: widget.businessId,
        settings: data,
      );

      if (mounted) {
        SnackBarHelper.show(
          context,
          message: AppLocalizations.of(context).repairShopSettingsSaved,
        );
        _loadSettings();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: AppLocalizations.of(context).repairShopSaveSettingsError(
            ErrorExtractor.forContext(e, context),
          ),
        );
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
    final t = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.businessSettingsRepairShop),
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
              tooltip: t.save,
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
                        child: Text(t.retry),
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
                        _buildSectionTitle(t.repairShopNumberingSection, Icons.numbers),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                // فرمت کد
                                DropdownButtonFormField<String>(
                                  initialValue: _codeFormat,
                                  decoration: InputDecoration(
                                    labelText: t.repairShopNumberingFormat,
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.format_list_numbered),
                                    helperText: t.repairShopNumberingFormatHelper,
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: 'sequential',
                                      child: Text(t.repairShopSequential),
                                    ),
                                    DropdownMenuItem(
                                      value: 'random',
                                      child: Text(t.repairShopRandom),
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
                                  decoration: InputDecoration(
                                    labelText: t.repairShopCodePrefix,
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.label),
                                    helperText: t.repairShopCodePrefixHelper,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return t.repairShopPrefixRequired;
                                    }
                                    if (value.length > 10) {
                                      return t.repairShopPrefixMaxLength;
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        _buildSectionTitle(t.repairShopInvoiceWarehouseSection, Icons.inventory_2),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                ProductComboboxWidget(
                                  businessId: widget.businessId,
                                  selectedProduct: _serviceProduct,
                                  label: t.repairShopServiceProduct,
                                  hintText: t.repairShopServiceProductHint,
                                  onChanged: (product) {
                                    setState(() => _serviceProduct = product);
                                  },
                                ),
                                const SizedBox(height: 16),
                                WarehouseComboboxWidget(
                                  businessId: widget.businessId,
                                  selectedWarehouseId: _defaultWarehouseId,
                                  label: t.repairShopDefaultPartsWarehouse,
                                  hintText: t.repairShopDefaultPartsWarehouseHint,
                                  onChanged: (id) {
                                    setState(() => _defaultWarehouseId = id);
                                  },
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  t.repairShopServiceProductAutoCreate,
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // بخش اعلان‌ها
                        _buildSectionTitle(t.repairShopAutoNotifications, Icons.notifications),
                        Card(
                          child: Column(
                            children: [
                              SwitchListTile(
                                title: Text(t.repairShopSmsOnReceive),
                                subtitle: Text(t.repairShopSmsOnReceiveHint),
                                value: _autoSmsOnReceive,
                                onChanged: (value) {
                                  setState(() => _autoSmsOnReceive = value);
                                },
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                title: Text(t.repairShopSmsOnStatus),
                                subtitle: Text(t.repairShopSmsOnStatusHint),
                                value: _autoSmsOnStatusChange,
                                onChanged: (value) {
                                  setState(() => _autoSmsOnStatusChange = value);
                                },
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                title: Text(t.repairShopEmailOnReceive),
                                subtitle: Text(t.repairShopEmailOnReceiveHint),
                                value: _autoEmailOnReceive,
                                onChanged: (value) {
                                  setState(() => _autoEmailOnReceive = value);
                                },
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                title: Text(t.repairShopEmailOnStatus),
                                subtitle: Text(t.repairShopEmailOnStatusHint),
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
                        _buildSectionTitle(t.repairShopHelp, Icons.info_outline),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildInfoRow(
                                  t.repairShopHelpSequentialTitle,
                                  t.repairShopHelpSequentialBody,
                                ),
                                const SizedBox(height: 12),
                                _buildInfoRow(
                                  t.repairShopHelpRandomTitle,
                                  t.repairShopHelpRandomBody,
                                ),
                                const SizedBox(height: 12),
                                _buildInfoRow(
                                  t.repairShopHelpNotifyTitle,
                                  t.repairShopHelpNotifyBody,
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
                          label: Text(_isSaving ? t.saving : t.repairShopSaveSettings),
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

