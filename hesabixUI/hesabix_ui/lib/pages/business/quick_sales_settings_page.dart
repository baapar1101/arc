import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../services/quick_sales_service.dart';
import '../../core/auth_store.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/invoice/customer_combobox_widget.dart';
import '../../widgets/invoice/warehouse_combobox_widget.dart';
import '../../widgets/invoice/cash_register_combobox_widget.dart';
import '../../widgets/invoice/price_list_combobox_widget.dart';
import '../../widgets/banking/currency_picker_widget.dart';
import '../../models/customer_model.dart';
import '../../models/cash_register.dart';

class QuickSalesSettingsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const QuickSalesSettingsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<QuickSalesSettingsPage> createState() => _QuickSalesSettingsPageState();
}

class _QuickSalesSettingsPageState extends State<QuickSalesSettingsPage> {
  final QuickSalesService _service = QuickSalesService();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _settings;

  // Controllers
  final _anonymousCustomerNameController = TextEditingController();
  Customer? _selectedAnonymousCustomer;
  int? _selectedWarehouseId;
  String? _selectedCashRegisterId;
  int? _selectedCurrencyId;
  int? _selectedPriceListId;

  // Boolean settings
  bool _autoCreateAnonymousCustomer = true;
  bool _autoPrint = false;
  bool _enableWarehouseDocument = true;
  String _warehouseDocumentType = 'posted'; // 'draft' or 'posted'
  bool _autoPostWarehouse = true; // برای سازگاری با گذشته
  bool _showInventory = true;
  bool _autoCreatePaymentDocument = true;
  bool _showPurchasePrice = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _anonymousCustomerNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await _service.getSettings(businessId: widget.businessId);
      setState(() {
        _settings = settings;
        _anonymousCustomerNameController.text = settings['anonymous_customer_name'] ?? 'مشتری ناشناس';
        _autoCreateAnonymousCustomer = settings['auto_create_anonymous_customer'] ?? true;
        _selectedWarehouseId = settings['default_warehouse_id'];
        _selectedCashRegisterId = settings['default_cash_register_id']?.toString();
        _selectedCurrencyId = settings['default_currency_id'];
        _selectedPriceListId = settings['default_price_list_id'];
        _autoPrint = settings['auto_print'] ?? false;
        _enableWarehouseDocument = settings['enable_warehouse_document'] ?? true;
        _warehouseDocumentType = settings['warehouse_document_type'] ?? 'posted';
        _autoPostWarehouse = settings['auto_post_warehouse'] ?? true;
        _showInventory = settings['show_inventory'] ?? true;
        _autoCreatePaymentDocument = settings['auto_create_payment_document'] ?? true;
        _showPurchasePrice = settings['show_purchase_price'] ?? false;
      });
      
      // بارگذاری مشتری ناشناس اگر وجود دارد
      if (settings['default_anonymous_customer_id'] != null) {
        // TODO: بارگذاری اطلاعات مشتری
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_settings == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload = <String, dynamic>{
        'anonymous_customer_name': _anonymousCustomerNameController.text.trim().isEmpty 
            ? null 
            : _anonymousCustomerNameController.text.trim(),
        'auto_create_anonymous_customer': _autoCreateAnonymousCustomer,
        if (_selectedAnonymousCustomer != null)
          'default_anonymous_customer_id': _selectedAnonymousCustomer!.id,
        if (_selectedWarehouseId != null)
          'default_warehouse_id': _selectedWarehouseId,
        if (_selectedCashRegisterId != null)
          'default_cash_register_id': int.tryParse(_selectedCashRegisterId!),
        if (_selectedCurrencyId != null)
          'default_currency_id': _selectedCurrencyId,
        if (_selectedPriceListId != null)
          'default_price_list_id': _selectedPriceListId,
        'auto_print': _autoPrint,
        'enable_warehouse_document': _enableWarehouseDocument,
        'warehouse_document_type': _warehouseDocumentType,
        'auto_post_warehouse': _autoPostWarehouse,
        'show_inventory': _showInventory,
        'auto_create_payment_document': _autoCreatePaymentDocument,
        'show_purchase_price': _showPurchasePrice,
      };
      
      final saved = await _service.updateSettings(
        businessId: widget.businessId,
        payload: payload,
      );
      setState(() {
        _settings = saved;
      });
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      SnackBarHelper.show(context, message: t.savedSuccessfully);
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تنظیمات فروش سریع'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // بخش مشتری ناشناس
                      _buildSection(
                        title: 'مشتری ناشناس',
                        icon: Icons.person_outline,
                        children: [
                          CustomerComboboxWidget(
                            selectedCustomer: _selectedAnonymousCustomer,
                            onCustomerChanged: (customer) {
                              setState(() {
                                _selectedAnonymousCustomer = customer;
                              });
                            },
                            businessId: widget.businessId,
                            authStore: widget.authStore,
                            isRequired: false,
                            label: 'مشتری پیش‌فرض',
                            hintText: 'انتخاب مشتری برای فروش ناشناس',
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _anonymousCustomerNameController,
                            decoration: const InputDecoration(
                              labelText: 'نام مشتری ناشناس',
                              border: OutlineInputBorder(),
                              helperText: 'نامی که برای مشتری ناشناس استفاده می‌شود',
                            ),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            title: const Text('ایجاد خودکار مشتری ناشناس'),
                            subtitle: const Text('در صورت عدم وجود مشتری ناشناس، به صورت خودکار ایجاد شود'),
                            value: _autoCreateAnonymousCustomer,
                            onChanged: (v) {
                              setState(() {
                                _autoCreateAnonymousCustomer = v;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // بخش انبار و صندوق
                      _buildSection(
                        title: 'انبار و صندوق',
                        icon: Icons.inventory_2_outlined,
                        children: [
                          WarehouseComboboxWidget(
                            businessId: widget.businessId,
                            selectedWarehouseId: _selectedWarehouseId,
                            onChanged: (id) {
                              setState(() {
                                _selectedWarehouseId = id;
                              });
                            },
                            label: 'انبار پیش‌فرض',
                            hintText: 'انتخاب انبار برای فروش سریع',
                          ),
                          const SizedBox(height: 16),
                          CashRegisterComboboxWidget(
                            businessId: widget.businessId,
                            selectedRegisterId: _selectedCashRegisterId,
                            onChanged: (option) {
                              setState(() {
                                _selectedCashRegisterId = option?.id;
                              });
                            },
                            label: 'صندوق پیش‌فرض',
                            hintText: 'انتخاب صندوق برای پرداخت نقدی',
                          ),
                          const SizedBox(height: 16),
                          CurrencyPickerWidget(
                            businessId: widget.businessId,
                            selectedCurrencyId: _selectedCurrencyId,
                            onChanged: (currencyId) {
                              setState(() {
                                _selectedCurrencyId = currencyId;
                              });
                            },
                            label: 'ارز پیش‌فرض',
                            hintText: 'انتخاب ارز برای فاکتورهای فروش سریع',
                          ),
                          const SizedBox(height: 16),
                          PriceListComboboxWidget(
                            businessId: widget.businessId,
                            selectedPriceListId: _selectedPriceListId,
                            onChanged: (priceList) {
                              setState(() {
                                _selectedPriceListId = priceList?['id'] as int?;
                              });
                            },
                            label: 'لیست قیمت پیش‌فرض',
                            hintText: 'انتخاب لیست قیمت برای فروش سریع',
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // بخش تنظیمات چاپ
                      _buildSection(
                        title: 'تنظیمات چاپ',
                        icon: Icons.print_outlined,
                        children: [
                          SwitchListTile(
                            title: const Text('چاپ خودکار پس از ثبت'),
                            subtitle: const Text('فاکتور به صورت خودکار چاپ شود'),
                            value: _autoPrint,
                            onChanged: (v) {
                              setState(() {
                                _autoPrint = v;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // بخش تنظیمات موجودی
                      _buildSection(
                        title: 'تنظیمات موجودی',
                        icon: Icons.warehouse_outlined,
                        children: [
                          SwitchListTile(
                            title: const Text('صدور حواله انبار'),
                            subtitle: const Text('صدور سند حواله انبار هنگام فروش'),
                            value: _enableWarehouseDocument,
                            onChanged: (v) {
                              setState(() {
                                _enableWarehouseDocument = v;
                              });
                            },
                          ),
                          if (_enableWarehouseDocument) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: cs.outline.withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'نوع سند حواله انبار:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    RadioListTile<String>(
                                      title: const Text('پیش‌نویس'),
                                      subtitle: const Text('حواله ایجاد می‌شود اما تاثیری در موجودی ندارد'),
                                      value: 'draft',
                                      groupValue: _warehouseDocumentType,
                                      onChanged: (value) {
                                        setState(() {
                                          _warehouseDocumentType = value!;
                                        });
                                      },
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    RadioListTile<String>(
                                      title: const Text('قطعی'),
                                      subtitle: const Text('حواله ایجاد و بلافاصله قطعی می‌شود (موجودی کم می‌شود)'),
                                      value: 'posted',
                                      groupValue: _warehouseDocumentType,
                                      onChanged: (value) {
                                        setState(() {
                                          _warehouseDocumentType = value!;
                                        });
                                      },
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          SwitchListTile(
                            title: const Text('نمایش موجودی'),
                            subtitle: const Text('موجودی کالاها در صفحه فروش سریع نمایش داده شود'),
                            value: _showInventory,
                            onChanged: (v) {
                              setState(() {
                                _showInventory = v;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // بخش تنظیمات حسابداری
                      _buildSection(
                        title: 'تنظیمات حسابداری',
                        icon: Icons.account_balance_outlined,
                        children: [
                          SwitchListTile(
                            title: const Text('ثبت خودکار سند پرداخت'),
                            subtitle: const Text('سند پرداخت به صورت جداگانه و خودکار ایجاد شود'),
                            value: _autoCreatePaymentDocument,
                            onChanged: (v) {
                              setState(() {
                                _autoCreatePaymentDocument = v;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // بخش تنظیمات نمایش
                      _buildSection(
                        title: 'تنظیمات نمایش',
                        icon: Icons.visibility_outlined,
                        children: [
                          SwitchListTile(
                            title: const Text('نمایش قیمت خرید'),
                            subtitle: const Text('قیمت خرید کالاها نمایش داده شود'),
                            value: _showPurchasePrice,
                            onChanged: (v) {
                              setState(() {
                                _showPurchasePrice = v;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // دکمه‌های ذخیره
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving 
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.save),
                            label: Text(t.save),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _loading ? null : _load,
                            icon: const Icon(Icons.refresh),
                            label: Text(t.reload),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: cs.primary, size: 24),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}

