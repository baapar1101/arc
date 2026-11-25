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
import 'package:hesabix_ui/l10n/app_localizations.dart';

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
        message: AppLocalizations.of(context).repairShopLoadOrderError(
          ErrorExtractor.forContext(e, context),
        ),
      );
    }
  }

  Future<void> _saveOrder() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_isEdit && _selectedCustomer == null) {
      SnackBarHelper.show(
        context,
        message: AppLocalizations.of(context).repairShopSelectCustomer,
      );
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
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(
          context,
          message: _isEdit ? t.repairShopOrderUpdated : t.repairShopOrderCreated,
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: AppLocalizations.of(context).repairShopSaveOrderError(
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
    return ListenableBuilder(
      listenable: widget.calendarController,
      builder: (context, _) {
        final t = AppLocalizations.of(context);
        return Scaffold(
          appBar: AppBar(
            title: Text(_isEdit ? t.repairShopEditOrderTitle : t.repairShopNewOrderTitle),
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
                  tooltip: t.save,
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
                            label: t.repairShopCustomer,
                            hintText: t.repairShopCustomerHint,
                            isRequired: true,
                            searchHint: t.repairShopCustomerSearchHint,
                          )
                        else if (_selectedCustomer != null)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.person),
                              title: Text(_selectedCustomer!.displayName),
                              subtitle: Text(t.repairShopCustomerSubtitle),
                            ),
                          ),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),
                        ProductComboboxWidget(
                          businessId: widget.businessId,
                          selectedProduct: _selectedProduct,
                          label: t.repairShopCatalogProduct,
                          hintText: t.repairShopCatalogProductHint,
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
                          decoration: InputDecoration(
                            labelText: t.repairShopProductName,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.devices),
                            helperText: t.repairShopProductNameHint,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return t.repairShopProductNameRequired;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _warrantyCodeController,
                          decoration: InputDecoration(
                            labelText: t.repairShopWarrantyCodeId,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.verified_user_outlined),
                            helperText: t.repairShopWarrantyCodeHelper,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _productSerialController,
                          decoration: InputDecoration(
                            labelText: t.repairShopSerialOptional,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.qr_code),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _problemController,
                          decoration: InputDecoration(
                            labelText: t.repairShopProblemDescription,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.report_problem),
                          ),
                          maxLines: 3,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return t.repairShopProblemRequired;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _customerNotesController,
                          decoration: InputDecoration(
                            labelText: t.repairShopCustomerNotesOptional,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.note),
                          ),
                          maxLines: 2,
                        ),
                        if (_isEdit) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _technicianNotesController,
                            decoration: InputDecoration(
                              labelText: t.repairShopTechnicianNotesOptional,
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.engineering),
                            ),
                            maxLines: 2,
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _estimatedCostController,
                          decoration: InputDecoration(
                            labelText: t.repairShopEstimatedCostOptional,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.attach_money),
                            helperText: t.repairShopEstimatedCostHelper,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                        DateInputField(
                          labelText: t.repairShopEstimatedDeliveryOptional,
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
                              ? t.saving
                              : (_isEdit ? t.repairShopSaveChanges : t.repairShopSubmitOrder)),
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
