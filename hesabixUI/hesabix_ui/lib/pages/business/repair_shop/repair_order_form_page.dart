import 'package:flutter/material.dart';
import '../../../services/repair_shop_service.dart';
import '../../../models/person_model.dart';
import '../../../core/api_client.dart';
import '../../../widgets/invoice/person_combobox_widget.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';


/// صفحه فرم ثبت/ویرایش سفارش تعمیر
class RepairOrderFormPage extends StatefulWidget {
  final int businessId;
  final int? orderId; // null = ایجاد جدید

  const RepairOrderFormPage({
    super.key,
    required this.businessId,
    this.orderId,
  });

  @override
  State<RepairOrderFormPage> createState() => _RepairOrderFormPageState();
}

class _RepairOrderFormPageState extends State<RepairOrderFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final RepairShopService _service;

  @override
  void initState() {
    super.initState();
    final apiClient = ApiClient();
    _service = RepairShopService(apiClient);
    if (widget.orderId != null) {
      _loadOrder();
    }
  }

  final _isLoading = false;
  bool _isSaving = false;

  // فیلدها
  Person? _selectedCustomer;
  final TextEditingController _productNameController = TextEditingController();
  final TextEditingController _productSerialController = TextEditingController();
  final TextEditingController _problemController = TextEditingController();
  final TextEditingController _customerNotesController = TextEditingController();
  final TextEditingController _estimatedCostController = TextEditingController();

  @override
  void dispose() {
    _productNameController.dispose();
    _productSerialController.dispose();
    _problemController.dispose();
    _customerNotesController.dispose();
    _estimatedCostController.dispose();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    // TODO: بارگذاری سفارش برای ویرایش
  }

  Future<void> _saveOrder() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedCustomer == null) {
      SnackBarHelper.show(context, message: 'لطفاً مشتری را انتخاب کنید');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final orderData = {
        'customer_person_id': _selectedCustomer!.id,
        'product_name': _productNameController.text,
        'product_serial': _productSerialController.text.isNotEmpty ? _productSerialController.text : null,
        'problem_description': _problemController.text,
        'customer_notes': _customerNotesController.text.isNotEmpty ? _customerNotesController.text : null,
        'estimated_cost': _estimatedCostController.text.isNotEmpty ? double.tryParse(_estimatedCostController.text) : null,
      };

      await _service.createOrder(
        businessId: widget.businessId,
        orderData: orderData,
      );

      if (mounted) {
        SnackBarHelper.show(context, message: 'سفارش تعمیر با موفقیت ثبت شد');
        Navigator.of(context).pop(true); // برگشت با موفقیت
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message:
              'خطا در ثبت سفارش: ${ErrorExtractor.forContext(e, context)}',
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.orderId == null ? 'سفارش تعمیر جدید' : 'ویرایش سفارش'),
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
              onPressed: _saveOrder,
              tooltip: 'ذخیره',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // انتخاب مشتری
                    PersonComboboxWidget(
                      businessId: widget.businessId,
                      showFinancialBalance: true,
                      selectedPerson: _selectedCustomer,
                      onChanged: (person) {
                        setState(() => _selectedCustomer = person);
                      },
                      label: 'مشتری',
                      hintText: 'جست‌وجو و انتخاب مشتری',
                      isRequired: true,
                      searchHint: 'جستجو بر اساس نام، تلفن یا ایمیل...',
                    ),

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),

                    // نام کالا
                    TextFormField(
                      controller: _productNameController,
                      decoration: const InputDecoration(
                        labelText: 'نام کالا/دستگاه',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.devices),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'نام کالا الزامی است';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // سریال کالا
                    TextFormField(
                      controller: _productSerialController,
                      decoration: const InputDecoration(
                        labelText: 'شماره سریال (اختیاری)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.qr_code),
                      ),
                    ),

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),

                    // شرح مشکل
                    TextFormField(
                      controller: _problemController,
                      decoration: const InputDecoration(
                        labelText: 'شرح مشکل',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.report_problem),
                      ),
                      maxLines: 3,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'شرح مشکل الزامی است';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // یادداشت مشتری
                    TextFormField(
                      controller: _customerNotesController,
                      decoration: const InputDecoration(
                        labelText: 'یادداشت مشتری (اختیاری)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.note),
                      ),
                      maxLines: 2,
                    ),

                    const SizedBox(height: 16),

                    // برآورد هزینه
                    TextFormField(
                      controller: _estimatedCostController,
                      decoration: const InputDecoration(
                        labelText: 'برآورد هزینه (اختیاری)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
                        helperText: 'به واحد ارز پیش‌فرض کسب‌وکار',
                      ),
                      keyboardType: TextInputType.number,
                    ),

                    const SizedBox(height: 32),

                    // دکمه ذخیره
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveOrder,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(_isSaving ? 'در حال ذخیره...' : 'ثبت سفارش'),
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
}
