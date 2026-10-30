import 'package:flutter/material.dart';
import '../../../services/repair_shop_service.dart';
import '../../../services/person_service.dart';
import '../../../models/person_model.dart';
import '../../../core/api_client.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart';
import '../../../widgets/invoice/person_combobox_widget.dart';
import '../../../widgets/invoice/product_combobox_widget.dart';
import '../../../widgets/date_input_field.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/business_subpage_back_leading.dart';

class RepairOrderFormPage extends StatefulWidget {
  final int businessId;
  final int? orderId;
  final CalendarController calendarController;

  const RepairOrderFormPage({
    super.key,
    required this.businessId,
    this.orderId,
    required this.calendarController,
  });

  @override
  State<RepairOrderFormPage> createState() => _RepairOrderFormPageState();
}

class _RepairOrderFormPageState extends State<RepairOrderFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final RepairShopService _service;
  late final PersonService _personService;

  bool _isLoading = false;
  bool _isSaving = false;

  Person? _selectedCustomer;
  Map<String, dynamic>? _selectedProduct;
  DateTime? _estimatedDeliveryAt;
  final TextEditingController _productNameController = TextEditingController();
  final TextEditingController _productSerialController = TextEditingController();
  final TextEditingController _problemController = TextEditingController();
  final TextEditingController _customerNotesController = TextEditingController();
  final TextEditingController _technicianNotesController =
      TextEditingController();
  final TextEditingController _estimatedCostController = TextEditingController();
  final TextEditingController _warrantyCodeController = TextEditingController();

  bool get _isEdit => widget.orderId != null;

  @override
  void initState() {
    super.initState();
    final apiClient = ApiClient();
    _service = RepairShopService(apiClient);
    _personService = PersonService(apiClient: apiClient);
    if (_isEdit) {
      _loadOrder();
    }
  }

  @override
  void dispose() {
    _productNameController.dispose();
    _productSerialController.dispose();
    _problemController.dispose();
    _customerNotesController.dispose();
    _technicianNotesController.dispose();
    _estimatedCostController.dispose();
    _warrantyCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    setState(() => _isLoading = true);
    try {
      final order = await _service.getOrder(
        businessId: widget.businessId,
        orderId: widget.orderId!,
      );
      Person? customer;
      try {
        customer = await _personService.getPerson(order.customerPersonId);
      } catch (_) {
        customer = null;
      }
      if (!mounted) return;
      setState(() {
        _selectedCustomer = customer;
        _productNameController.text = order.productName;
        _productSerialController.text = order.productSerial ?? '';
        _problemController.text = order.problemDescription;
        _customerNotesController.text = order.customerNotes ?? '';
        _technicianNotesController.text = order.technicianNotes ?? '';
        _estimatedCostController.text = order.estimatedCost != null
            ? order.estimatedCost!.toStringAsFixed(0)
            : '';
        _warrantyCodeController.text =
            order.warrantyCodeId != null ? order.warrantyCodeId.toString() : '';
        _estimatedDeliveryAt = order.estimatedDeliveryAt;
        if (order.productId != null) {
          _selectedProduct = {
            'id': order.productId,
            'name': order.productName,
          };
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      SnackBarHelper.show(
        context,
        message: 'خطا در بارگذاری سفارش: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  Future<void> _saveOrder() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_isEdit && _selectedCustomer == null) {
      SnackBarHelper.show(context, message: 'لطفاً مشتری را انتخاب کنید');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final orderData = <String, dynamic>{
        'product_name': _productNameController.text.trim(),
        'product_serial': _productSerialController.text.trim().isNotEmpty
            ? _productSerialController.text.trim()
            : null,
        'product_id': _selectedProduct?['id'],
        'problem_description': _problemController.text.trim(),
        'customer_notes': _customerNotesController.text.trim().isNotEmpty
            ? _customerNotesController.text.trim()
            : null,
        'estimated_cost': _estimatedCostController.text.trim().isNotEmpty
            ? double.tryParse(
                _estimatedCostController.text.replaceAll(',', '').trim())
            : null,
        'warranty_code_id': int.tryParse(_warrantyCodeController.text.trim()),
      };

      if (_estimatedDeliveryAt != null) {
        orderData['estimated_delivery_at'] =
            '${HesabixDateUtils.formatForApiDate(_estimatedDeliveryAt!)}T00:00:00';
      }

      if (_isEdit) {
        if (_technicianNotesController.text.trim().isNotEmpty) {
          orderData['technician_notes'] =
              _technicianNotesController.text.trim();
        }
        await _service.updateOrder(
          businessId: widget.businessId,
          orderId: widget.orderId!,
          orderData: orderData,
        );
      } else {
        orderData['customer_person_id'] = _selectedCustomer!.id;
        await _service.createOrder(
          businessId: widget.businessId,
          orderData: orderData,
        );
      }

      if (mounted) {
        SnackBarHelper.show(
          context,
          message: _isEdit
              ? 'سفارش با موفقیت ویرایش شد'
              : 'سفارش تعمیر با موفقیت ثبت شد',
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message:
              'خطا در ذخیره سفارش: ${ErrorExtractor.forContext(e, context)}',
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
    return ListenableBuilder(
      listenable: widget.calendarController,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(_isEdit ? 'ویرایش سفارش' : 'سفارش تعمیر جدید'),
            leading: hesabixBackAppBarLeading(context,
                businessId: widget.businessId),
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
                        if (!_isEdit)
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
                          )
                        else if (_selectedCustomer != null)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.person),
                              title: Text(_selectedCustomer!.displayName),
                              subtitle: const Text('مشتری سفارش'),
                            ),
                          ),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),
                        ProductComboboxWidget(
                          businessId: widget.businessId,
                          selectedProduct: _selectedProduct,
                          label: 'کالا از کاتالوگ (اختیاری)',
                          hintText: 'جست‌وجو در کالاها',
                          onChanged: (product) {
                            setState(() {
                              _selectedProduct = product;
                              final name = product?['name']?.toString();
                              if (name != null && name.isNotEmpty) {
                                _productNameController.text = name;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _productNameController,
                          decoration: const InputDecoration(
                            labelText: 'نام کالا/دستگاه',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.devices),
                            helperText:
                                'اگر کالا در کاتالوگ نیست، نام را دستی وارد کنید',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'نام کالا الزامی است';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _warrantyCodeController,
                          decoration: const InputDecoration(
                            labelText: 'شناسه کد گارانتی (اختیاری)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.verified_user_outlined),
                            helperText: 'اگر دستگاه تحت گارانتی است، شناسه کد گارانتی را وارد کنید',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
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
                        TextFormField(
                          controller: _problemController,
                          decoration: const InputDecoration(
                            labelText: 'شرح مشکل',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.report_problem),
                          ),
                          maxLines: 3,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'شرح مشکل الزامی است';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _customerNotesController,
                          decoration: const InputDecoration(
                            labelText: 'یادداشت مشتری (اختیاری)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.note),
                          ),
                          maxLines: 2,
                        ),
                        if (_isEdit) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _technicianNotesController,
                            decoration: const InputDecoration(
                              labelText: 'یادداشت تعمیرکار (اختیاری)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.engineering),
                            ),
                            maxLines: 2,
                          ),
                        ],
                        const SizedBox(height: 16),
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
                        const SizedBox(height: 16),
                        DateInputField(
                          labelText: 'تاریخ تحویل تقریبی (اختیاری)',
                          value: _estimatedDeliveryAt,
                          calendarController: widget.calendarController,
                          onChanged: (value) {
                            setState(() => _estimatedDeliveryAt = value);
                          },
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveOrder,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.check),
                          label: Text(_isSaving
                              ? 'در حال ذخیره...'
                              : (_isEdit ? 'ذخیره تغییرات' : 'ثبت سفارش')),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}
