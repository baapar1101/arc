import 'package:flutter/material.dart';
import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;
import 'package:file_picker/file_picker.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/models/business_models.dart';
import 'package:hesabix_ui/services/business_api_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/core/api_client.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/business_subpage_back_leading.dart';

class BusinessInfoSettingsPage extends StatefulWidget {
  final int businessId;

  const BusinessInfoSettingsPage({super.key, required this.businessId});

  @override
  State<BusinessInfoSettingsPage> createState() => _BusinessInfoSettingsPageState();
}

class _BusinessInfoSettingsPageState extends State<BusinessInfoSettingsPage> {
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  BusinessResponse? _original;

  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _mobileController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _registrationNumberController = TextEditingController();
  final _economicIdController = TextEditingController();
  final _countryController = TextEditingController();
  final _provinceController = TextEditingController();
  final _cityController = TextEditingController();

  BusinessType? _businessType;
  BusinessField? _businessField;
  // تنظیمات اعتبار
  bool _checkCreditEnabledByDefault = false;
  final _defaultCreditLimitController = TextEditingController();

  // تنظیمات محاسبه سود فاکتور
  String? _invoiceProfitCalculationMethod;
  String? _invoiceProfitCalculationBasis;
  bool _invoiceProfitIncludeOverhead = false;
  String? _invoiceProfitOverheadType;
  final _invoiceProfitOverheadPercentController = TextEditingController();
  String? _invoiceProfitCalculationType;
  bool _recalculatingProfits = false;
  String? _invoiceProfitLedgerRecognitionBasis;
  /// perpetual_mixed | average_purchase_on_shortage
  String _invoiceProfitFifoShortageMode = 'perpetual_mixed';
  bool _backfillingProfitLedger = false;

  // همگام‌سازی قیمت پایه کالا از فاکتور قطعی (ارز کالا = ارز پیش‌فرض کسب‌وکار)
  bool _invoiceSyncUpdateSalesPriceEnabled = false;
  bool _invoiceSyncUpdatePurchasePriceEnabled = false;
  String? _invoiceSyncSalesPriceBasis;
  String? _invoiceSyncPurchasePriceBasis;
  /// none | draft | posted
  String _invoiceWarehouseReleaseMode = 'draft';
  String _invoiceGlobalDiscountPercentBasis = 'subtotal_after_line_discount';
  String _invoiceGlobalDiscountTaxMode = 'recalculate_tax_proportional';
  final _invoiceGlobalDiscountMaxPercentController = TextEditingController();
  final _invoiceGlobalDiscountMaxAmountController = TextEditingController();

  // سیاست موجودی منفی هنگام قطعی حواله
  bool _allowNegativeInventoryForBulk = false;
  bool _allowNegativeInventoryForUnique = false;
  bool _warehouseTransferRequirePositiveStock = true;

  // ارز پیش‌فرض
  int? _selectedDefaultCurrencyId;
  List<Map<String, dynamic>> _currencies = [];
  bool _loadingCurrencies = false;

  // فایل‌های گرافیکی
  Uint8List? _logoBytes;
  Uint8List? _stampBytes;
  bool _uploadingLogo = false;
  bool _uploadingStamp = false;

  late final ApiClient _apiClient;
  late final CurrencyService _currencyService;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _currencyService = CurrencyService(_apiClient);
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _mobileController.dispose();
    _postalCodeController.dispose();
    _nationalIdController.dispose();
    _registrationNumberController.dispose();
    _economicIdController.dispose();
    _countryController.dispose();
    _provinceController.dispose();
    _cityController.dispose();
    _defaultCreditLimitController.dispose();
    _invoiceProfitOverheadPercentController.dispose();
    _invoiceGlobalDiscountMaxPercentController.dispose();
    _invoiceGlobalDiscountMaxAmountController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await BusinessApiService.getBusiness(widget.businessId);
      _original = resp;
      _nameController.text = resp.name;
      _addressController.text = resp.address ?? '';
      _phoneController.text = resp.phone ?? '';
      _mobileController.text = resp.mobile ?? '';
      _postalCodeController.text = resp.postalCode ?? '';
      _nationalIdController.text = resp.nationalId ?? '';
      _registrationNumberController.text = resp.registrationNumber ?? '';
      _economicIdController.text = resp.economicId ?? '';
      _countryController.text = resp.country ?? '';
      _provinceController.text = resp.province ?? '';
      _cityController.text = resp.city ?? '';
      _businessType = _resolveBusinessType(resp.businessType);
      _businessField = _resolveBusinessField(resp.businessField);
      _checkCreditEnabledByDefault = resp.checkCreditEnabledByDefault;
      _defaultCreditLimitController.text = (resp.defaultCreditLimit ?? 0).toStringAsFixed(0);
      // تنظیمات محاسبه سود
      _invoiceProfitCalculationMethod = resp.invoiceProfitCalculationMethod ?? 'automatic';
      _invoiceProfitCalculationBasis = resp.invoiceProfitCalculationBasis ?? 'purchase_price';
      _invoiceProfitIncludeOverhead = resp.invoiceProfitIncludeOverhead;
      _invoiceProfitOverheadType = resp.invoiceProfitOverheadType ?? 'none';
      _invoiceProfitOverheadPercentController.text = (resp.invoiceProfitOverheadPercent ?? 0).toStringAsFixed(2);
      _invoiceProfitCalculationType = resp.invoiceProfitCalculationType ?? 'gross';
      _invoiceProfitLedgerRecognitionBasis =
          resp.invoiceProfitLedgerRecognitionBasis ?? 'warehouse_document_posting';
      _invoiceProfitFifoShortageMode = resp.invoiceProfitFifoShortageMode;
      _invoiceSyncUpdateSalesPriceEnabled = resp.invoiceSyncUpdateSalesPriceEnabled;
      _invoiceSyncUpdatePurchasePriceEnabled = resp.invoiceSyncUpdatePurchasePriceEnabled;
      _invoiceSyncSalesPriceBasis = resp.invoiceSyncSalesPriceBasis ?? 'net_after_line_discount';
      _invoiceSyncPurchasePriceBasis = resp.invoiceSyncPurchasePriceBasis ?? 'net_after_line_discount';
      _invoiceWarehouseReleaseMode = resp.invoiceWarehouseReleaseMode;
      _invoiceGlobalDiscountPercentBasis = resp.invoiceGlobalDiscountPercentBasis;
      _invoiceGlobalDiscountTaxMode = resp.invoiceGlobalDiscountTaxMode;
      _invoiceGlobalDiscountMaxPercentController.text =
          resp.invoiceGlobalDiscountMaxPercent != null
              ? resp.invoiceGlobalDiscountMaxPercent!.toString()
              : '';
      _invoiceGlobalDiscountMaxAmountController.text =
          resp.invoiceGlobalDiscountMaxAmount != null
              ? resp.invoiceGlobalDiscountMaxAmount!.toStringAsFixed(0)
              : '';
      _allowNegativeInventoryForBulk = resp.allowNegativeInventoryForBulk;
      _allowNegativeInventoryForUnique = resp.allowNegativeInventoryForUnique;
      _warehouseTransferRequirePositiveStock = resp.warehouseTransferRequirePositiveStock;

      // بررسی اینکه آیا کسب‌وکار ارز پیش‌فرض دارد یا نه
      if (resp.defaultCurrency == null) {
        // اگر ارز پیش‌فرض ندارد، لیست ارزها را بارگذاری کن
        await _loadCurrencies();
      }

      // بارگذاری پیش‌نمایش لوگو و مهر در صورت وجود
      await _loadBrandingImages(resp);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  BusinessType? _resolveBusinessType(String value) {
    for (final t in BusinessType.values) {
      if (t.displayName == value) return t;
    }
    return null;
  }

  BusinessField? _resolveBusinessField(String value) {
    for (final f in BusinessField.values) {
      if (f.displayName == value) return f;
    }
    return null;
  }

  Future<void> _loadCurrencies() async {
    setState(() {
      _loadingCurrencies = true;
    });
    try {
      final currencies = await _currencyService.listCurrencies();
      setState(() {
        _currencies = currencies;
        _loadingCurrencies = false;
      });
    } catch (e) {
      setState(() {
        _loadingCurrencies = false;
      });
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در بارگذاری ارزها: $e');
      }
    }
  }

  Map<String, dynamic> _buildUpdatePayload() {
    final orig = _original!;
    final payload = <String, dynamic>{};

    if (_nameController.text.trim() != orig.name) payload['name'] = _nameController.text.trim();
    if (_businessType != null && _businessType!.displayName != orig.businessType) {
      payload['business_type'] = _businessType!.displayName;
    }
    if (_businessField != null && _businessField!.displayName != orig.businessField) {
      payload['business_field'] = _businessField!.displayName;
    }
    final addr = _addressController.text.trim();
    if ((orig.address ?? '') != addr) payload['address'] = addr.isEmpty ? null : addr;
    final phone = _phoneController.text.trim();
    if ((orig.phone ?? '') != phone) payload['phone'] = phone.isEmpty ? null : phone;
    final mobile = _mobileController.text.trim();
    if ((orig.mobile ?? '') != mobile) payload['mobile'] = mobile.isEmpty ? null : mobile;
    final postal = _postalCodeController.text.trim();
    if ((orig.postalCode ?? '') != postal) payload['postal_code'] = postal.isEmpty ? null : postal;
    final nid = _nationalIdController.text.trim();
    if ((orig.nationalId ?? '') != nid) payload['national_id'] = nid.isEmpty ? null : nid;
    final reg = _registrationNumberController.text.trim();
    if ((orig.registrationNumber ?? '') != reg) payload['registration_number'] = reg.isEmpty ? null : reg;
    final eco = _economicIdController.text.trim();
    if ((orig.economicId ?? '') != eco) payload['economic_id'] = eco.isEmpty ? null : eco;
    final country = _countryController.text.trim();
    if ((orig.country ?? '') != country) payload['country'] = country.isEmpty ? null : country;
    final province = _provinceController.text.trim();
    if ((orig.province ?? '') != province) payload['province'] = province.isEmpty ? null : province;
    final city = _cityController.text.trim();
    if ((orig.city ?? '') != city) payload['city'] = city.isEmpty ? null : city;
    // تنظیمات اعتبار
    final defaultCreditLimitStr = _defaultCreditLimitController.text.trim();
    final parsedLimit = double.tryParse(defaultCreditLimitStr.replaceAll(',', ''));
    if ((orig.defaultCreditLimit ?? 0) != (parsedLimit ?? 0)) {
      payload['default_credit_limit'] = parsedLimit;
    }
    if (orig.checkCreditEnabledByDefault != _checkCreditEnabledByDefault) {
      payload['check_credit_enabled_by_default'] = _checkCreditEnabledByDefault;
    }
    // تنظیمات محاسبه سود
    if (_invoiceProfitCalculationMethod != null && _invoiceProfitCalculationMethod != orig.invoiceProfitCalculationMethod) {
      payload['invoice_profit_calculation_method'] = _invoiceProfitCalculationMethod;
    }
    if (_invoiceProfitCalculationBasis != null && _invoiceProfitCalculationBasis != orig.invoiceProfitCalculationBasis) {
      payload['invoice_profit_calculation_basis'] = _invoiceProfitCalculationBasis;
    }
    if (_invoiceProfitIncludeOverhead != orig.invoiceProfitIncludeOverhead) {
      payload['invoice_profit_include_overhead'] = _invoiceProfitIncludeOverhead;
    }
    if (_invoiceProfitOverheadType != null && _invoiceProfitOverheadType != orig.invoiceProfitOverheadType) {
      payload['invoice_profit_overhead_type'] = _invoiceProfitOverheadType;
    }
    final overheadPercentStr = _invoiceProfitOverheadPercentController.text.trim();
    final parsedOverheadPercent = double.tryParse(overheadPercentStr.replaceAll(',', ''));
    if (parsedOverheadPercent != null && parsedOverheadPercent != (orig.invoiceProfitOverheadPercent ?? 0)) {
      payload['invoice_profit_overhead_percent'] = parsedOverheadPercent;
    }
    if (_invoiceProfitCalculationType != null && _invoiceProfitCalculationType != orig.invoiceProfitCalculationType) {
      payload['invoice_profit_calculation_type'] = _invoiceProfitCalculationType;
    }
    final origLedgerBasis =
        orig.invoiceProfitLedgerRecognitionBasis ?? 'warehouse_document_posting';
    if (_invoiceProfitLedgerRecognitionBasis != null &&
        _invoiceProfitLedgerRecognitionBasis != origLedgerBasis) {
      payload['invoice_profit_ledger_recognition_basis'] = _invoiceProfitLedgerRecognitionBasis;
    }
    if (_invoiceProfitFifoShortageMode != orig.invoiceProfitFifoShortageMode) {
      payload['invoice_profit_fifo_shortage_mode'] = _invoiceProfitFifoShortageMode;
    }
    if (_invoiceSyncUpdateSalesPriceEnabled != orig.invoiceSyncUpdateSalesPriceEnabled) {
      payload['invoice_sync_update_sales_price_enabled'] = _invoiceSyncUpdateSalesPriceEnabled;
    }
    if (_invoiceSyncUpdatePurchasePriceEnabled != orig.invoiceSyncUpdatePurchasePriceEnabled) {
      payload['invoice_sync_update_purchase_price_enabled'] = _invoiceSyncUpdatePurchasePriceEnabled;
    }
    if (_invoiceSyncSalesPriceBasis != null && _invoiceSyncSalesPriceBasis != orig.invoiceSyncSalesPriceBasis) {
      payload['invoice_sync_sales_price_basis'] = _invoiceSyncSalesPriceBasis;
    }
    if (_invoiceSyncPurchasePriceBasis != null && _invoiceSyncPurchasePriceBasis != orig.invoiceSyncPurchasePriceBasis) {
      payload['invoice_sync_purchase_price_basis'] = _invoiceSyncPurchasePriceBasis;
    }
    if (_invoiceWarehouseReleaseMode != orig.invoiceWarehouseReleaseMode) {
      payload['invoice_warehouse_release_mode'] = _invoiceWarehouseReleaseMode;
    }
    if (_invoiceGlobalDiscountPercentBasis != orig.invoiceGlobalDiscountPercentBasis) {
      payload['invoice_global_discount_percent_basis'] = _invoiceGlobalDiscountPercentBasis;
    }
    if (_invoiceGlobalDiscountTaxMode != orig.invoiceGlobalDiscountTaxMode) {
      payload['invoice_global_discount_tax_mode'] = _invoiceGlobalDiscountTaxMode;
    }
    final maxPctStr = _invoiceGlobalDiscountMaxPercentController.text.trim();
    final maxPctParsed = double.tryParse(maxPctStr.replaceAll(',', ''));
    final origPct = orig.invoiceGlobalDiscountMaxPercent;
    if ((maxPctParsed ?? -1) != (origPct ?? -1)) {
      payload['invoice_global_discount_max_percent'] = maxPctParsed;
    }
    final maxAmtStr = _invoiceGlobalDiscountMaxAmountController.text.trim();
    final maxAmtParsed = double.tryParse(maxAmtStr.replaceAll(',', ''));
    final origAmt = orig.invoiceGlobalDiscountMaxAmount;
    if ((maxAmtParsed ?? -1) != (origAmt ?? -1)) {
      payload['invoice_global_discount_max_amount'] = maxAmtParsed;
    }
    if (_allowNegativeInventoryForBulk != orig.allowNegativeInventoryForBulk) {
      payload['allow_negative_inventory_for_bulk'] = _allowNegativeInventoryForBulk;
    }
    if (_allowNegativeInventoryForUnique != orig.allowNegativeInventoryForUnique) {
      payload['allow_negative_inventory_for_unique'] = _allowNegativeInventoryForUnique;
    }
    if (_warehouseTransferRequirePositiveStock != orig.warehouseTransferRequirePositiveStock) {
      payload['warehouse_transfer_require_positive_stock'] = _warehouseTransferRequirePositiveStock;
    }

    // ارز پیش‌فرض (فقط اگر کسب‌وکار ارز پیش‌فرض ندارد)
    if (orig.defaultCurrency == null && _selectedDefaultCurrencyId != null) {
      payload['default_currency_id'] = _selectedDefaultCurrencyId;
    }

    return payload;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_original == null) return;
    final payload = _buildUpdatePayload();
    if (payload.isEmpty) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'بدون تغییر');
      }
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final resp = await _apiClient.put('/api/v1/businesses/${widget.businessId}', data: payload);
      if (resp.data['success'] == true) {
        if (mounted) {
          SnackBarHelper.show(context, message: 'با موفقیت ذخیره شد');
          context.go('/business/${widget.businessId}/settings');
        }
      } else {
        throw Exception(resp.data['message'] ?? 'خطا در ذخیره تغییرات');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
      if (mounted) {
        SnackBarHelper.showError(context, message: _error!);
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _loadBrandingImages(BusinessResponse resp) async {
    _logoBytes = null;
    _stampBytes = null;
    try {
      if (resp.logoFileId != null && resp.logoFileId!.isNotEmpty) {
        final res = await _apiClient.get<List<int>>(
          '/api/v1/businesses/${widget.businessId}/logo',
          options: dio.Options(responseType: dio.ResponseType.bytes),
        );
        final data = res.data;
        if (data != null && data.isNotEmpty) {
          _logoBytes = Uint8List.fromList(data);
        }
      }
    } catch (_) {
      _logoBytes = null;
    }
    try {
      if (resp.stampFileId != null && resp.stampFileId!.isNotEmpty) {
        final res = await _apiClient.get<List<int>>(
          '/api/v1/businesses/${widget.businessId}/stamp',
          options: dio.Options(responseType: dio.ResponseType.bytes),
        );
        final data = res.data;
        if (data != null && data.isNotEmpty) {
          _stampBytes = Uint8List.fromList(data);
        }
      }
    } catch (_) {
      _stampBytes = null;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pickAndUploadLogo() async {
    if (_uploadingLogo) return;
    setState(() {
      _uploadingLogo = true;
    });
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      final f = res?.files.isNotEmpty == true ? res!.files.first : null;
      if (f == null || f.bytes == null) return;
      final bytes = f.bytes!;
      await BusinessApiService.uploadLogo(
        businessId: widget.businessId,
        filename: f.name,
        bytes: bytes,
      );
      _logoBytes = Uint8List.fromList(bytes);
      if (mounted) {
        SnackBarHelper.show(context, message: 'لوگو با موفقیت ذخیره شد');
      }
    } on dio.DioException catch (e) {
      if (mounted) {
        await _handleUploadError(e);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در آپلود لوگو: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingLogo = false;
        });
      }
    }
  }

  Future<void> _pickAndUploadStamp() async {
    if (_uploadingStamp) return;
    setState(() {
      _uploadingStamp = true;
    });
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      final f = res?.files.isNotEmpty == true ? res!.files.first : null;
      if (f == null || f.bytes == null) return;
      final bytes = f.bytes!;
      await BusinessApiService.uploadStamp(
        businessId: widget.businessId,
        filename: f.name,
        bytes: bytes,
      );
      _stampBytes = Uint8List.fromList(bytes);
      if (mounted) {
        SnackBarHelper.show(context, message: 'مهر/امضا با موفقیت ذخیره شد');
      }
    } on dio.DioException catch (e) {
      if (mounted) {
        await _handleUploadError(e);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در آپلود مهر/امضا: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingStamp = false;
        });
      }
    }
  }

  Future<void> _handleUploadError(dio.DioException e) async {
    final response = e.response;
    if (response != null && response.data is Map) {
      final data = response.data as Map<String, dynamic>;
      final error = data['error'];
      
      if (error is Map && error['code'] == 'STORAGE_LIMIT_EXCEEDED') {
        await _showStorageLimitDialog(Map<String, dynamic>.from(error));
        return;
      }
    }
    
    String errorMessage = 'خطا در آپلود فایل';
    if (response?.data is Map) {
      final data = response!.data as Map<String, dynamic>;
      if (data.containsKey('message')) {
        errorMessage = data['message'] as String;
      } else if (data.containsKey('error') && data['error'] is Map) {
        final errorMap = data['error'] as Map;
        if (errorMap.containsKey('message')) {
          errorMessage = errorMap['message'] as String;
        }
      }
    }
    
    SnackBarHelper.showError(context, message: errorMessage);
  }

  Future<void> _showStorageLimitDialog(Map<String, dynamic> error) async {
    final totalLimit = (error['total_limit_gb'] as num?)?.toDouble() ?? 0.0;
    final currentUsage = (error['current_usage_gb'] as num?)?.toDouble() ?? 0.0;
    final available = (error['available_gb'] as num?)?.toDouble() ?? 0.0;
    final overUsage = (error['over_usage_gb'] as num?)?.toDouble() ?? 0.0;
    final required = (error['required_gb'] as num?)?.toDouble() ?? 0.0;
    
    final theme = Theme.of(context);
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFFF9800).withValues(alpha: 0.15),
                const Color(0xFFFF9800).withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFFF9800),
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'محدودیت ذخیره‌سازی',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                error['message'] as String? ?? 'حجم فایل از محدودیت ذخیره‌سازی تجاوز می‌کند',
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('محدودیت کل:', '${totalLimit.toStringAsFixed(3)} GB', theme),
                    const SizedBox(height: 12),
                    _buildInfoRow('استفاده شده:', '${currentUsage.toStringAsFixed(3)} GB', theme),
                    const SizedBox(height: 12),
                    _buildInfoRow('موجود:', '${available.toStringAsFixed(3)} GB', theme),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(),
                    ),
                    _buildInfoRow('حجم مورد نیاز:', '${required.toStringAsFixed(3)} GB', theme, isHighlight: true),
                    const SizedBox(height: 12),
                    _buildInfoRow('حجم اضافی:', '${overUsage.toStringAsFixed(3)} GB', theme, isHighlight: true, isError: true),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      color: theme.colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'برای آپلود این فایل، لطفاً پلن ذخیره‌سازی خود را ارتقا دهید.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('متوجه شدم'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, ThemeData theme, {bool isHighlight = false, bool isError = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isError
                    ? const Color(0xFFEF5350)
                    : isHighlight
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w600,
            color: isError
                ? const Color(0xFFEF5350)
                : isHighlight
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t.businessSettings),
          leading: businessSubpageBackLeading(context, widget.businessId),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t.businessSettings),
          leading: businessSubpageBackLeading(context, widget.businessId),
        ),
        body: Center(child: Text(_error!)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.businessSettings),
        leading: businessSubpageBackLeading(context, widget.businessId),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
              label: Text(t.save),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(t.generalSettings, cs),
              const SizedBox(height: 8),
              _buildTextField(controller: _nameController, label: t.businessName, required: true),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = ResponsiveHelper.isMobile(context);
                  if (isMobile) {
                    return Column(
                      children: [
                        _buildBusinessTypeDropdown(t),
                        const SizedBox(height: 12),
                        _buildBusinessFieldDropdown(t),
                      ],
                    );
                  } else {
                    return Row(
                      children: [
                        Expanded(child: _buildBusinessTypeDropdown(t)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildBusinessFieldDropdown(t)),
                      ],
                    );
                  }
                },
              ),

              const SizedBox(height: 24),
              _buildSectionTitle(t.businessContactInfo, cs),
              const SizedBox(height: 8),
              _buildTextField(controller: _addressController, label: t.address, maxLines: 2),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = ResponsiveHelper.isMobile(context);
                  if (isMobile) {
                    return Column(
                      children: [
                        _buildTextField(controller: _phoneController, label: t.phone),
                        const SizedBox(height: 12),
                        _buildTextField(controller: _mobileController, label: t.mobile),
                      ],
                    );
                  } else {
                    return Row(
                      children: [
                        Expanded(child: _buildTextField(controller: _phoneController, label: t.phone)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildTextField(controller: _mobileController, label: t.mobile)),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              _buildTextField(controller: _postalCodeController, label: t.postalCode),

              const SizedBox(height: 24),
              _buildSectionTitle(t.businessLegalInfo, cs),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = ResponsiveHelper.isMobile(context);
                  if (isMobile) {
                    return Column(
                      children: [
                        _buildTextField(controller: _nationalIdController, label: t.nationalId),
                        const SizedBox(height: 12),
                        _buildTextField(controller: _registrationNumberController, label: t.registrationNumber),
                      ],
                    );
                  } else {
                    return Row(
                      children: [
                        Expanded(child: _buildTextField(controller: _nationalIdController, label: t.nationalId)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildTextField(controller: _registrationNumberController, label: t.registrationNumber)),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              _buildTextField(controller: _economicIdController, label: t.economicId),

              const SizedBox(height: 24),
              _buildSectionTitle('لوگو و مهر کسب‌وکار', cs),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = ResponsiveHelper.isMobile(context);
                  if (isMobile) {
                    return Column(
                      children: [
                        _buildLogoCard(cs),
                        const SizedBox(height: 12),
                        _buildStampCard(cs),
                      ],
                    );
                  } else {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildLogoCard(cs)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildStampCard(cs)),
                      ],
                    );
                  }
                },
              ),

              const SizedBox(height: 24),
              _buildSectionTitle(t.businessGeographicInfo, cs),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = ResponsiveHelper.isMobile(context);
                  if (isMobile) {
                    return Column(
                      children: [
                        _buildTextField(controller: _countryController, label: t.country),
                        const SizedBox(height: 12),
                        _buildTextField(controller: _provinceController, label: t.province),
                      ],
                    );
                  } else {
                    return Row(
                      children: [
                        Expanded(child: _buildTextField(controller: _countryController, label: t.country)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildTextField(controller: _provinceController, label: t.province)),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              _buildTextField(controller: _cityController, label: t.city),
              
              // بخش ارز پیش‌فرض (فقط برای کسب‌وکارهایی که ارز پیش‌فرض ندارند)
              if (_original?.defaultCurrency == null) ...[
                const SizedBox(height: 24),
                _buildSectionTitle('ارز پیش‌فرض', cs),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: cs.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'کسب‌وکار شما ارز پیش‌فرض تنظیم نکرده است. لطفاً یک ارز پیش‌فرض انتخاب کنید تا بتوانید سند حسابداری ثبت کنید.',
                              style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_loadingCurrencies)
                        const Center(child: CircularProgressIndicator())
                      else
                        DropdownButtonFormField<int>(
                          value: _selectedDefaultCurrencyId,
                          decoration: const InputDecoration(
                            labelText: 'ارز پیش‌فرض *',
                            border: OutlineInputBorder(),
                            helperText: 'این ارز به صورت پیش‌فرض در تمام اسناد حسابداری استفاده می‌شود',
                          ),
                          items: _currencies.map((currency) {
                            return DropdownMenuItem<int>(
                              value: currency['id'] as int,
                              child: Text('${currency['title']} (${currency['code']})'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedDefaultCurrencyId = value;
                            });
                          },
                          validator: (value) {
                            if (value == null) {
                              return 'لطفاً ارز پیش‌فرض را انتخاب کنید';
                            }
                            return null;
                          },
                        ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              _buildSectionTitle('تنظیمات اعتبار مشتریان', cs),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('بررسی اعتبار مشتریان (پیش‌فرض)'),
                subtitle: const Text('در صورت روشن بودن، به‌صورت پیش‌فرض اعتبار مشتریان بررسی می‌شود'),
                value: _checkCreditEnabledByDefault,
                onChanged: (v) => setState(() => _checkCreditEnabledByDefault = v),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _defaultCreditLimitController,
                decoration: const InputDecoration(
                  labelText: 'سقف اعتبار پیش‌فرض (ریال)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),

              const SizedBox(height: 24),
              _buildSectionTitle('تنظیمات محاسبه سود فاکتور', cs),
              const SizedBox(height: 8),
              _buildProfitCalculationSettings(cs),

              const SizedBox(height: 24),
              _buildSectionTitle('به‌روزرسانی قیمت کالا از فاکتور', cs),
              const SizedBox(height: 8),
              _buildInvoicePriceSyncSettings(cs),

              const SizedBox(height: 24),
              _buildSectionTitle(AppLocalizations.of(context).businessSettingsInvoiceGlobalDiscountTitle, cs),
              const SizedBox(height: 8),
              _buildInvoiceGlobalDiscountBusinessSettings(cs),

              const SizedBox(height: 24),
              _buildSectionTitle(AppLocalizations.of(context).invoiceWarehouseReleaseBusinessTitle, cs),
              const SizedBox(height: 8),
              _buildInvoiceWarehouseReleaseSettings(cs),

              const SizedBox(height: 24),
              _buildSectionTitle(AppLocalizations.of(context).inventoryNegativePolicySectionTitle, cs),
              const SizedBox(height: 8),
              _buildInventoryNegativePolicySettings(cs),

            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfitCalculationSettings(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // روش محاسبه
            DropdownButtonFormField<String>(
              value: _invoiceProfitCalculationMethod,
              decoration: const InputDecoration(
                labelText: 'روش محاسبه سود',
                helperText: 'نحوه محاسبه سود فاکتورها را انتخاب کنید',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'automatic', child: Text('خودکار')),
                DropdownMenuItem(value: 'manual', child: Text('دستی')),
                DropdownMenuItem(value: 'disabled', child: Text('غیرفعال')),
              ],
              onChanged: (value) {
                setState(() {
                  _invoiceProfitCalculationMethod = value;
                });
              },
            ),
            const SizedBox(height: 16),
            // مبنای محاسبه (فقط اگر روش automatic باشد)
            if (_invoiceProfitCalculationMethod == 'automatic') ...[
              DropdownButtonFormField<String>(
                value: _invoiceProfitCalculationBasis,
                decoration: const InputDecoration(
                  labelText: 'مبنای محاسبه هزینه',
                  helperText: 'مبنای محاسبه هزینه برای سود را انتخاب کنید',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'purchase_price',
                    child: Text('قیمت خرید محصول'),
                  ),
                  DropdownMenuItem(
                    value: 'cost_price',
                    child: Text('قیمت تمام شده (از انبار)'),
                  ),
                  DropdownMenuItem(
                    value: 'actual_cost',
                    child: Text('هزینه واقعی'),
                  ),
                  DropdownMenuItem(
                    value: 'average_cost',
                    child: Text('میانگین قیمت خرید'),
                  ),
                  DropdownMenuItem(
                    value: 'fifo',
                    child: Text('FIFO (اول ورود، اول خروج)'),
                  ),
                  DropdownMenuItem(
                    value: 'lifo',
                    child: Text('LIFO (آخر ورود، اول خروج)'),
                  ),
                  DropdownMenuItem(
                    value: 'weighted_average',
                    child: Text('میانگین وزنی خریدها (تا تاریخ سند)'),
                  ),
                  DropdownMenuItem(
                    value: 'moving_weighted_average',
                    child: Text('میانگین موزون متحرک (WMA دائمی)'),
                  ),
                  DropdownMenuItem(
                    value: 'standard_cost',
                    child: Text('هزینه استاندارد'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _invoiceProfitCalculationBasis = value;
                  });
                },
              ),
              if (_invoiceProfitCalculationBasis == 'fifo' ||
                  _invoiceProfitCalculationBasis == 'lifo' ||
                  _invoiceProfitCalculationBasis == 'moving_weighted_average') ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _invoiceProfitFifoShortageMode,
                  decoration: const InputDecoration(
                    labelText: 'سیاست کسری (FIFO / LIFO / WMA)',
                    helperText:
                        'در کمبود موجودی: آخرین بهای موزون / لایه، یا میانگین خرید تا تاریخ سند',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'perpetual_mixed',
                      child: Text('لایه‌ها + آخرین قیمت لایه (پیش‌فرض قبلی)'),
                    ),
                    DropdownMenuItem(
                      value: 'average_purchase_on_shortage',
                      child: Text('میانگین خرید برای بخش بدون لایه'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _invoiceProfitFifoShortageMode = value;
                    });
                  },
                ),
              ],
              const SizedBox(height: 16),
              // نوع محاسبه سود
              DropdownButtonFormField<String>(
                value: _invoiceProfitCalculationType,
                decoration: const InputDecoration(
                  labelText: 'نوع محاسبه سود',
                  helperText: 'نوع سود مورد نظر را انتخاب کنید',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'gross',
                    child: Text('سود ناخالص (بدون هزینه‌ها)'),
                  ),
                  DropdownMenuItem(
                    value: 'net',
                    child: Text('سود خالص (با هزینه‌ها)'),
                  ),
                  DropdownMenuItem(
                    value: 'both',
                    child: Text('هر دو (ناخالص و خالص)'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _invoiceProfitCalculationType = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _invoiceProfitLedgerRecognitionBasis,
                decoration: const InputDecoration(
                  labelText: 'شناسایی بهای تمام‌شده قطعی (دفتر)',
                  helperText:
                      '«تحلیلی» در gross_profit همیشه با تنظیمات جاری محاسبه می‌شود؛ این گزینه تعیین می‌کند ثبت قطعی روی خط فاکتور چه زمانی انجام شود.',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'warehouse_document_posting',
                    child: Text('هنگام قطعی شدن حواله انبار مرتبط با فاکتور'),
                  ),
                  DropdownMenuItem(
                    value: 'sales_invoice_document',
                    child: Text('هنگام ثبت فاکتور قطعی (بدون انتظار برای حواله)'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _invoiceProfitLedgerRecognitionBasis = value;
                  });
                },
              ),
              // شامل کردن هزینه‌های سربار
              if (_invoiceProfitCalculationType != null && _invoiceProfitCalculationType != 'gross') ...[
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('شامل کردن هزینه‌های سربار'),
                  subtitle: const Text('آیا هزینه‌های سربار در محاسبه سود خالص لحاظ شود؟'),
                  value: _invoiceProfitIncludeOverhead,
                  onChanged: (value) {
                    setState(() {
                      _invoiceProfitIncludeOverhead = value;
                    });
                  },
                ),
              ],
              // نوع هزینه‌های سربار
              if (_invoiceProfitCalculationType != null && 
                  _invoiceProfitCalculationType != 'gross' && 
                  _invoiceProfitIncludeOverhead) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _invoiceProfitOverheadType,
                  decoration: const InputDecoration(
                    labelText: 'نوع هزینه‌های سربار',
                    helperText: 'نوع هزینه‌های سربار را انتخاب کنید',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'none',
                      child: Text('بدون سربار'),
                    ),
                    DropdownMenuItem(
                      value: 'production_overhead',
                      child: Text('فقط سربار تولید'),
                    ),
                    DropdownMenuItem(
                      value: 'all_overhead',
                      child: Text('تمام هزینه‌های سربار'),
                    ),
                    DropdownMenuItem(
                      value: 'custom_percent',
                      child: Text('درصد سفارشی'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _invoiceProfitOverheadType = value;
                    });
                  },
                ),
                // درصد سفارشی
                if (_invoiceProfitOverheadType == 'custom_percent') ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _invoiceProfitOverheadPercentController,
                    decoration: const InputDecoration(
                      labelText: 'درصد هزینه سربار',
                      helperText: 'درصد هزینه سربار از هزینه کل (0-100)',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (_invoiceProfitOverheadType == 'custom_percent' && 
                          (value == null || value.isEmpty)) {
                        return 'لطفاً درصد را وارد کنید';
                      }
                      final percent = double.tryParse(value ?? '');
                      if (percent != null && (percent < 0 || percent > 100)) {
                        return 'درصد باید بین 0 تا 100 باشد';
                      }
                      return null;
                    },
                  ),
                ],
              ],
              // دکمه به‌روزرسانی سود فاکتورها
              if (_invoiceProfitCalculationMethod != null && _invoiceProfitCalculationMethod != 'disabled') ...[
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: cs.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'به‌روزرسانی سود فاکتورها',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'بعد از تغییر تنظیمات محاسبه سود، می‌توانید سود تمام فاکتورهای موجود را با تنظیمات جدید به‌روزرسانی کنید.',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _recalculatingProfits ? null : _recalculateAllProfits,
                        icon: _recalculatingProfits
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(_recalculatingProfits ? 'در حال به‌روزرسانی...' : 'به‌روزرسانی سود تمام فاکتورها'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _backfillingProfitLedger ? null : _backfillProfitLedgerForOldDocuments,
                        icon: _backfillingProfitLedger
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.savings_outlined),
                        label: Text(
                          _backfillingProfitLedger
                              ? 'در حال ثبت مقادیر قطعی...'
                              : 'ثبت بهای تمام‌شده قطعی برای اسناد قبلی',
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'دکمه بالا مقادیر ledger_* را برای فاکتورهای قطعی قبلی ذخیره می‌کند '
                        '(بر اساس مبنای انتخاب‌شده و وجود حواله قطعی در صورت نیاز).',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static const _invoiceSyncBasisItems = <DropdownMenuItem<String>>[
    DropdownMenuItem(
      value: 'unit_price',
      child: Text('قیمت واحد فاکتور (قبل از تخفیف خط)'),
    ),
    DropdownMenuItem(
      value: 'net_after_line_discount',
      child: Text('میانگین پس از تخفیف خط (بدون مالیات)'),
    ),
    DropdownMenuItem(
      value: 'net_with_tax',
      child: Text('میانگین با مالیات (جمع ردیف ÷ تعداد)'),
    ),
    DropdownMenuItem(
      value: 'cost_price',
      child: Text('قیمت تمام‌شده ردیف (خرید) / در فروش همان قیمت واحد'),
    ),
  ];

  Widget _buildInventoryNegativePolicySettings(ColorScheme cs) {
    final t = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.inventoryNegativePolicyIntro,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              title: Text(t.inventoryNegativePolicyBulkTitle),
              subtitle: Text(t.inventoryNegativePolicyBulkSubtitle),
              value: _allowNegativeInventoryForBulk,
              onChanged: (v) => setState(() => _allowNegativeInventoryForBulk = v),
            ),
            SwitchListTile(
              title: Text(t.inventoryNegativePolicyUniqueTitle),
              subtitle: Text(t.inventoryNegativePolicyUniqueSubtitle),
              value: _allowNegativeInventoryForUnique,
              onChanged: (v) => setState(() => _allowNegativeInventoryForUnique = v),
            ),
            SwitchListTile(
              title: Text(t.inventoryNegativePolicyTransferTitle),
              subtitle: Text(t.inventoryNegativePolicyTransferSubtitle),
              value: _warehouseTransferRequirePositiveStock,
              onChanged: (v) => setState(() => _warehouseTransferRequirePositiveStock = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceGlobalDiscountBusinessSettings(ColorScheme cs) {
    final t = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: _invoiceGlobalDiscountPercentBasis,
              decoration: InputDecoration(
                labelText: t.businessSettingsInvoiceGlobalDiscountBasisLabel,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'subtotal_after_line_discount',
                  child: Text(t.businessSettingsInvoiceGlobalDiscountBasisSubtotalAfterLines),
                ),
                DropdownMenuItem(
                  value: 'gross_before_line_discount',
                  child: Text(t.businessSettingsInvoiceGlobalDiscountBasisGrossBeforeLines),
                ),
                DropdownMenuItem(
                  value: 'total_after_lines_including_tax',
                  child: Text(t.businessSettingsInvoiceGlobalDiscountBasisTotalWithTax),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _invoiceGlobalDiscountPercentBasis = v);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _invoiceGlobalDiscountTaxMode,
              decoration: InputDecoration(
                labelText: t.businessSettingsInvoiceGlobalDiscountTaxModeLabel,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'recalculate_tax_proportional',
                  child: Text(t.businessSettingsInvoiceGlobalDiscountTaxModeRecalculate),
                ),
                DropdownMenuItem(
                  value: 'keep_line_taxes',
                  child: Text(t.businessSettingsInvoiceGlobalDiscountTaxModeKeep),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _invoiceGlobalDiscountTaxMode = v);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _invoiceGlobalDiscountMaxPercentController,
              decoration: InputDecoration(
                labelText: t.businessSettingsInvoiceGlobalDiscountMaxPercent,
                border: const OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _invoiceGlobalDiscountMaxAmountController,
              decoration: InputDecoration(
                labelText: t.businessSettingsInvoiceGlobalDiscountMaxAmount,
                border: const OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceWarehouseReleaseSettings(ColorScheme cs) {
    final t = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.invoiceWarehouseReleaseBusinessSubtitle,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              t.invoiceWarehouseReleaseStockHint,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: <ButtonSegment<String>>[
                ButtonSegment<String>(
                  value: 'none',
                  label: Text(t.invoiceWarehouseReleaseNone),
                ),
                ButtonSegment<String>(
                  value: 'draft',
                  label: Text(t.invoiceWarehouseReleaseDraft),
                ),
                ButtonSegment<String>(
                  value: 'posted',
                  label: Text(t.invoiceWarehouseReleasePosted),
                ),
              ],
              selected: <String>{_invoiceWarehouseReleaseMode},
              onSelectionChanged: (Set<String> next) {
                setState(() {
                  _invoiceWarehouseReleaseMode = next.first;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoicePriceSyncSettings(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'با ثبت فاکتور قطعی (غیر پیش‌فاکتور)، قیمت فروش یا خرید پایه کالا در کارت کالا به‌روز می‌شود. '
              'این مقادیر همیشه به ارز پیش‌فرض کسب‌وکار ذخیره می‌شوند؛ اگر ارز فاکتور غیر از ارز پیش‌فرض باشد، '
              'همگام‌سازی برای آن فاکتور انجام نمی‌شود.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('به‌روزرسانی قیمت فروش از فاکتور فروش'),
              subtitle: const Text('فقط فاکتور فروش قطعی'),
              value: _invoiceSyncUpdateSalesPriceEnabled,
              onChanged: (v) => setState(() => _invoiceSyncUpdateSalesPriceEnabled = v),
            ),
            if (_invoiceSyncUpdateSalesPriceEnabled) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _invoiceSyncSalesPriceBasis,
                decoration: const InputDecoration(
                  labelText: 'مبنای محاسبه قیمت فروش',
                  border: OutlineInputBorder(),
                ),
                items: _invoiceSyncBasisItems,
                onChanged: (value) => setState(() => _invoiceSyncSalesPriceBasis = value),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('به‌روزرسانی قیمت خرید از فاکتور خرید'),
              subtitle: const Text('فقط فاکتور خرید قطعی'),
              value: _invoiceSyncUpdatePurchasePriceEnabled,
              onChanged: (v) => setState(() => _invoiceSyncUpdatePurchasePriceEnabled = v),
            ),
            if (_invoiceSyncUpdatePurchasePriceEnabled) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _invoiceSyncPurchasePriceBasis,
                decoration: const InputDecoration(
                  labelText: 'مبنای محاسبه قیمت خرید',
                  border: OutlineInputBorder(),
                ),
                items: _invoiceSyncBasisItems,
                onChanged: (value) => setState(() => _invoiceSyncPurchasePriceBasis = value),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _backfillProfitLedgerForOldDocuments() async {
    if (_backfillingProfitLedger) return;

    setState(() {
      _backfillingProfitLedger = true;
    });

    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/invoices/business/${widget.businessId}/backfill-profit-ledger',
        data: <String, dynamic>{
          'use_background': false,
        },
      );

      final data = response.data?['data'] as Map<String, dynamic>?;

      if (!mounted) return;

      if (data != null && data['job_id'] != null) {
        SnackBarHelper.show(
          context,
          message: 'ثبت مقادیر قطعی در پس‌زمینه آغاز شد.',
          duration: const Duration(seconds: 5),
        );
      } else {
        final processed = data?['processed'] as int? ?? 0;
        final skipped = data?['skipped'] as int? ?? 0;
        SnackBarHelper.show(
          context,
          message: 'ثبت قطعی انجام شد: $processed فاکتور پردازش شد، $skipped رد شد.',
          duration: const Duration(seconds: 5),
        );
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: 'خطا در ثبت بهای قطعی: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _backfillingProfitLedger = false;
        });
      }
    }
  }

  Future<void> _recalculateAllProfits() async {
    if (_recalculatingProfits) return;
    
    setState(() {
      _recalculatingProfits = true;
    });

    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/invoices/business/${widget.businessId}/recalculate-all-profits',
      );

      final data = response.data?['data'] as Map<String, dynamic>?;
      
      if (!mounted) return;

      if (data != null && data['job_id'] != null) {
        // Background job شروع شده
        SnackBarHelper.show(
          context,
          message: 'به‌روزرسانی سود فاکتورها در پس‌زمینه شروع شد. این فرآیند ممکن است چند دقیقه طول بکشد.',
          duration: const Duration(seconds: 5),
        );
      } else {
        // به صورت sync انجام شد
        final processed = data?['processed'] as int? ?? 0;
        final skipped = data?['skipped'] as int? ?? 0;
        final total = data?['total'] as int? ?? 0;
        
        SnackBarHelper.show(
          context,
          message: 'به‌روزرسانی سود انجام شد. $processed از $total فاکتور به‌روزرسانی شد${skipped > 0 ? ' ($skipped فاکتور رد شد)' : ''}.',
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: 'خطا در به‌روزرسانی سود فاکتورها: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _recalculatingProfits = false;
        });
      }
    }
  }

  Widget _buildSectionTitle(String title, ColorScheme cs) {
    return Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface));
  }

  Widget _buildLogoCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.image_outlined, color: cs.primary),
                const SizedBox(width: 8),
                const Text('لوگو', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(8),
                color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
              ),
              alignment: Alignment.center,
              child: _logoBytes != null
                  ? Image.memory(
                      _logoBytes!,
                      fit: BoxFit.contain,
                    )
                  : Text(
                      'لوگویی ثبت نشده است',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _uploadingLogo ? null : _pickAndUploadLogo,
                icon: _uploadingLogo
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file),
                label: const Text('انتخاب و آپلود لوگو'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStampCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_outlined, color: cs.primary),
                const SizedBox(width: 8),
                const Text('مهر / امضای شرکت', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(8),
                color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
              ),
              alignment: Alignment.center,
              child: _stampBytes != null
                  ? Image.memory(
                      _stampBytes!,
                      fit: BoxFit.contain,
                    )
                  : Text(
                      'مهر/امضایی ثبت نشده است',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _uploadingStamp ? null : _pickAndUploadStamp,
                icon: _uploadingStamp
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file),
                label: const Text('انتخاب و آپلود مهر / امضا'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    bool required = false,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      validator: (val) {
        if (required && (val == null || val.trim().isEmpty)) {
          return label;
        }
        return null;
      },
    );
  }

  Widget _buildBusinessTypeDropdown(AppLocalizations t) {
    return DropdownButtonFormField<BusinessType>(
      initialValue: _businessType,
      decoration: InputDecoration(labelText: t.businessType),
      items: BusinessType.values
          .map((e) => DropdownMenuItem(value: e, child: Text(e.displayName)))
          .toList(),
      onChanged: (val) => setState(() => _businessType = val),
      validator: (val) => val == null ? t.businessType : null,
    );
  }

  Widget _buildBusinessFieldDropdown(AppLocalizations t) {
    return DropdownButtonFormField<BusinessField>(
      initialValue: _businessField,
      decoration: InputDecoration(labelText: t.businessField),
      items: BusinessField.values
          .map((e) => DropdownMenuItem(value: e, child: Text(e.displayName)))
          .toList(),
      onChanged: (val) => setState(() => _businessField = val),
      validator: (val) => val == null ? t.businessField : null,
    );
  }
}


