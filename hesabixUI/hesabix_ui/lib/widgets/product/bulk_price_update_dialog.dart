import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/bulk_price_update_data.dart';
import '../../services/bulk_price_update_service.dart';
import '../../services/category_service.dart';
import '../../services/currency_service.dart';
import '../../services/price_list_service.dart';
import '../../utils/number_formatters.dart';
import '../../utils/number_normalizer.dart';
import '../../widgets/category/category_picker_field.dart';
import '../../utils/snackbar_helper.dart';
import '../../services/errors/api_error.dart';
import '../../utils/responsive_helper.dart';

class BulkPriceUpdateDialog extends StatefulWidget {
  final int businessId;
  final List<int>? selectedProductIds;
  final VoidCallback? onSuccess;

  const BulkPriceUpdateDialog({
    super.key,
    required this.businessId,
    this.selectedProductIds,
    this.onSuccess,
  });

  @override
  State<BulkPriceUpdateDialog> createState() => _BulkPriceUpdateDialogState();
}

class _BulkPriceUpdateDialogState extends State<BulkPriceUpdateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _apiClient = ApiClient();
  final _valueController = TextEditingController();
  final _scrollController = ScrollController();
  
  late final BulkPriceUpdateService _bulkPriceService;
  late final CategoryService _categoryService;
  late final CurrencyService _currencyService;
  late final PriceListService _priceListService;

  // فرم داده‌ها
  BulkPriceUpdateType _updateType = BulkPriceUpdateType.percentage;
  BulkPriceUpdateTarget _target = BulkPriceUpdateTarget.salesPrice;
  BulkPriceUpdateDirection _direction = BulkPriceUpdateDirection.increase;
  double _value = 0.0;
  
  // فیلترها
  List<int> _selectedCategoryIds = [];
  List<int> _selectedCurrencyIds = [];
  List<int> _selectedPriceListIds = [];
  List<String> _selectedItemTypes = [];
  bool _onlyProductsWithInventory = false;
  bool _onlyProductsWithBasePrice = true;

  // داده‌های مرجع
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _currencies = [];
  List<Map<String, dynamic>> _priceLists = [];
  
  // وضعیت
  bool _isLoading = false;
  bool _isPreviewLoading = false;
  BulkPriceUpdatePreviewResponse? _previewResponse;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadReferenceData();
    _updateValueController();
  }

  @override
  void dispose() {
    _valueController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _updateValueController() {
    _valueController.text = _updateType == BulkPriceUpdateType.percentage 
        ? _value.toString() 
        : formatWithThousands(_value);
  }

  void _initializeServices() {
    _bulkPriceService = BulkPriceUpdateService(apiClient: _apiClient);
    _categoryService = CategoryService(_apiClient);
    _currencyService = CurrencyService(_apiClient);
    _priceListService = PriceListService(apiClient: _apiClient);
  }

  Future<void> _loadReferenceData() async {
    setState(() => _isLoading = true);
    try {
      final futures = await Future.wait([
        _categoryService.getTree(businessId: widget.businessId),
        _currencyService.listBusinessCurrencies(businessId: widget.businessId),
        _priceListService.listPriceLists(businessId: widget.businessId),
      ]);

      setState(() {
        _categories = (futures[0] as List<dynamic>).map((e) => Map<String, dynamic>.from(e)).toList();
        _currencies = (futures[1] as List<dynamic>).map((e) => Map<String, dynamic>.from(e)).toList();
        _priceLists = (futures[2] as Map<String, dynamic>)['items'] != null 
            ? ((futures[2] as Map<String, dynamic>)['items'] as List<dynamic>)
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : <Map<String, dynamic>>[];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(context, message: '${t.dataLoadingError}: $e');
      }
    }
  }

  Future<void> _previewChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isPreviewLoading = true);
    try {
      final request = BulkPriceUpdateRequest(
        updateType: _updateType,
        direction: _direction,
        target: _target,
        value: _value,
        categoryIds: _selectedCategoryIds.isNotEmpty ? _selectedCategoryIds : null,
        currencyIds: _selectedCurrencyIds.isNotEmpty ? _selectedCurrencyIds : null,
        priceListIds: _selectedPriceListIds.isNotEmpty ? _selectedPriceListIds : null,
        itemTypes: _selectedItemTypes.isNotEmpty ? _selectedItemTypes : null,
        productIds: widget.selectedProductIds,
        onlyProductsWithInventory: _onlyProductsWithInventory ? true : null,
        onlyProductsWithBasePrice: _onlyProductsWithBasePrice,
      );

      final response = await _bulkPriceService.previewBulkPriceUpdate(
        businessId: widget.businessId,
        payload: request.toJson(),
      );

      setState(() {
        _previewResponse = BulkPriceUpdatePreviewResponse.fromJson(response);
        _isPreviewLoading = false;
      });
    } catch (e) {
      setState(() => _isPreviewLoading = false);
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(context, message: _formatBulkPriceUpdateError(e, t));
      }
    }
  }

  Future<void> _applyChanges() async {
    if (_previewResponse == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).confirmChangesTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(ctx).confirmApplyChangesForNProducts(_previewResponse!.affectedProducts.length)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(ctx).irreversibleWarning,
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(AppLocalizations.of(ctx).confirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final request = BulkPriceUpdateRequest(
        updateType: _updateType,
        direction: _direction,
        target: _target,
        value: _value,
        categoryIds: _selectedCategoryIds.isNotEmpty ? _selectedCategoryIds : null,
        currencyIds: _selectedCurrencyIds.isNotEmpty ? _selectedCurrencyIds : null,
        priceListIds: _selectedPriceListIds.isNotEmpty ? _selectedPriceListIds : null,
        itemTypes: _selectedItemTypes.isNotEmpty ? _selectedItemTypes : null,
        productIds: widget.selectedProductIds,
        onlyProductsWithInventory: _onlyProductsWithInventory ? true : null,
        onlyProductsWithBasePrice: _onlyProductsWithBasePrice,
      );

      final result = await _bulkPriceService.applyBulkPriceUpdate(
        businessId: widget.businessId,
        payload: request.toJson(),
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        widget.onSuccess?.call();
        final t = AppLocalizations.of(context);
        SnackBarHelper.showSuccess(
          context,
          message: result['message']?.toString() ?? t.operationSuccessful,
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(context, message: _formatBulkPriceUpdateError(e, t));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final surface = theme.colorScheme.surface;
    final primary = theme.colorScheme.primary;
    final onPrimary = theme.colorScheme.onPrimary;
    final isMobile = ResponsiveHelper.isMobile(context);

    return Dialog(
      insetPadding: ResponsiveHelper.getDialogPadding(context),
      shape: isMobile ? const RoundedRectangleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: ResponsiveHelper.getDialogConstraints(context),
        child: ClipRRect(
          borderRadius: isMobile ? BorderRadius.zero : BorderRadius.circular(16),
          child: Container(
            color: surface,
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final maxW = constraints.maxWidth;
                final isCompact = maxW < 720; // چینش تک‌ستونه برای عرض کم
                final bodyPadding = EdgeInsets.all(isMobile ? 12 : 20);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [primary.withValues(alpha: 0.90), primary.withValues(alpha: 0.75)],
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: onPrimary.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.price_change, color: onPrimary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.bulkPriceUpdateTitle,
                                  style: theme.textTheme.titleLarge?.copyWith(color: onPrimary, fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  t.bulkPriceUpdateSubtitle,
                                  style: theme.textTheme.bodySmall?.copyWith(color: onPrimary.withValues(alpha: 0.9)),
                                  maxLines: isMobile ? 2 : 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: t.close,
                            onPressed: () => Navigator.of(context).pop(),
                            style: IconButton.styleFrom(foregroundColor: onPrimary),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),

                    // Body
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : Scrollbar(
                              controller: _scrollController,
                              thumbVisibility: !isMobile,
                              child: SingleChildScrollView(
                                controller: _scrollController,
                                padding: bodyPadding,
                                child: Form(
                                  key: _formKey,
                                  autovalidateMode: AutovalidateMode.onUserInteraction,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      _buildSectionCard(
                                        title: t.changeTypeAndDirection,
                                        icon: Icons.tune,
                                        child: _buildUpdateTypeSection(isCompact: isCompact),
                                      ),
                                      const SizedBox(height: 14),
                                      _buildSectionCard(
                                        title: t.changeTarget,
                                        icon: Icons.track_changes,
                                        child: _buildTargetSection(),
                                      ),
                                      const SizedBox(height: 14),
                                      _buildSectionCard(
                                        title: t.changeAmount,
                                        icon: Icons.calculate,
                                        child: _buildValueSection(),
                                      ),
                                      const SizedBox(height: 14),
                                      _buildSectionCard(
                                        title: t.filters,
                                        icon: Icons.filter_list,
                                        child: _buildFiltersSection(isCompact: isCompact),
                                      ),
                                      if (_previewResponse != null) ...[
                                        const SizedBox(height: 14),
                                        _buildSectionCard(
                                          title: t.previewChanges,
                                          icon: Icons.preview,
                                          child: _buildPreviewSection(isCompact: isCompact),
                                        ),
                                      ],
                                      if (isMobile) const SizedBox(height: 8), // فضای نفس برای موبایل
                                    ],
                                  ),
                                ),
                              ),
                            ),
                    ),

                    // Footer actions
                    Container(
                      padding: EdgeInsets.fromLTRB(isMobile ? 12 : 16, 10, isMobile ? 12 : 16, isMobile ? 12 : 16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4))),
                      ),
                      child: isMobile
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _isPreviewLoading ? null : _previewChanges,
                                  icon: _isPreviewLoading
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.visibility),
                                  label: Text(t.preview),
                                ),
                                const SizedBox(height: 8),
                                FilledButton.icon(
                                  onPressed: _isLoading || _previewResponse == null ? null : _applyChanges,
                                  icon: _isLoading
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.check_circle),
                                  label: Text(t.applyChanges),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _isPreviewLoading ? null : _previewChanges,
                                  icon: _isPreviewLoading
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.visibility),
                                  label: Text(t.preview),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  onPressed: _isLoading || _previewResponse == null ? null : _applyChanges,
                                  icon: _isLoading
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.check_circle),
                                  label: Text(t.applyChanges),
                                ),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUpdateTypeSection({required bool isCompact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<BulkPriceUpdateType>(
          segments: const [
            ButtonSegment(
              value: BulkPriceUpdateType.percentage,
              label: Text('درصدی'),
              icon: Icon(Icons.percent),
            ),
            ButtonSegment(
              value: BulkPriceUpdateType.amount,
              label: Text('مقداری'),
              icon: Icon(Icons.numbers),
            ),
          ],
          selected: {_updateType},
          onSelectionChanged: (selection) {
            final newValue = selection.first;
            setState(() => _updateType = newValue);
            _updateValueController();
          },
        ),
        const SizedBox(height: 12),
        SegmentedButton<BulkPriceUpdateDirection>(
          segments: const [
            ButtonSegment(
              value: BulkPriceUpdateDirection.increase,
              label: Text('افزایش'),
              icon: Icon(Icons.trending_up),
            ),
            ButtonSegment(
              value: BulkPriceUpdateDirection.decrease,
              label: Text('کاهش'),
              icon: Icon(Icons.trending_down),
            ),
          ],
          selected: {_direction},
          onSelectionChanged: (selection) {
            setState(() => _direction = selection.first);
          },
        ),
      ],
    );
  }

  Widget _buildTargetSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<BulkPriceUpdateTarget>(
          segments: const [
            ButtonSegment(
              value: BulkPriceUpdateTarget.salesPrice,
              label: Text('قیمت فروش'),
            ),
            ButtonSegment(
              value: BulkPriceUpdateTarget.purchasePrice,
              label: Text('قیمت خرید'),
            ),
            ButtonSegment(
              value: BulkPriceUpdateTarget.both,
              label: Text('هر دو'),
            ),
          ],
          selected: {_target},
          onSelectionChanged: (selection) {
            setState(() => _target = selection.first);
          },
        ),
      ],
    );
  }

  Widget _buildValueSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _valueController,
          decoration: InputDecoration(
            labelText: 'مبلغ/درصد',
            helperText: _updateType == BulkPriceUpdateType.percentage
                ? 'مثلاً 10؛ درصد اعمال می‌شود'
                : 'مثلاً 1,000,000؛ مبلغ اعمال می‌شود',
            helperMaxLines: 2,
            suffixText: _updateType == BulkPriceUpdateType.percentage ? '%' : null,
            border: const OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
          inputFormatters: _updateType == BulkPriceUpdateType.percentage
              ? [
                  const EnglishDigitsFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ThousandsSeparatorInputFormatter(),
                ]
              : [
                  const EnglishDigitsFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'^[\d,]*\.?\d*')),
                  ThousandsSeparatorInputFormatter(),
                ],
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'مقدار تغییر ضروری است';
            }
            
            // برای درصد، مستقیماً پارس کن
            if (_updateType == BulkPriceUpdateType.percentage) {
              final parsed = double.tryParse(value.replaceAll(',', ''));
              if (parsed == null) {
                return 'مقدار نامعتبر';
              }
              if (parsed < 0) {
                return 'مقدار نمیتواند منفی باشد';
              }
              if (parsed == 0) {
                return 'مقدار تغییر باید بزرگتر از صفر باشد';
              }
              return null;
            }
            
            // برای مبلغ، جداکننده هزارگان را حذف کن و سپس پارس کن
            final cleanValue = value.replaceAll(',', '');
            final parsed = double.tryParse(cleanValue);
            if (parsed == null) {
              return 'مقدار نامعتبر';
            }
            if (parsed < 0) {
              return 'مقدار نمیتواند منفی باشد';
            }
            if (parsed == 0) {
              return 'مقدار تغییر باید بزرگتر از صفر باشد';
            }
            return null;
          },
          onChanged: (value) {
            if (_updateType == BulkPriceUpdateType.percentage) {
              final parsed = double.tryParse(value.replaceAll(',', ''));
              if (parsed != null) {
                setState(() => _value = parsed);
              }
            } else {
              // برای مبلغ، جداکننده هزارگان را حذف کن
              final cleanValue = value.replaceAll(',', '');
              final parsed = double.tryParse(cleanValue);
              if (parsed != null) {
                setState(() => _value = parsed);
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildFiltersSection({required bool isCompact}) {
    final gap = isCompact ? 12.0 : 16.0;
    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCategoryFilter(),
          SizedBox(height: gap),
          _buildCurrencyFilter(),
          SizedBox(height: gap),
          _buildPriceListFilter(),
          SizedBox(height: gap),
          _buildItemTypeFilter(),
          SizedBox(height: gap),
          _buildOptionsFilter(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildCategoryFilter()),
            SizedBox(width: gap),
            Expanded(child: _buildCurrencyFilter()),
          ],
        ),
        SizedBox(height: gap),
        Row(
          children: [
            Expanded(child: _buildPriceListFilter()),
            SizedBox(width: gap),
            Expanded(child: _buildItemTypeFilter()),
          ],
        ),
        SizedBox(height: gap),
        _buildOptionsFilter(),
      ],
    );
  }

  Widget _buildCategoryFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('دسته‌بندی'),
        const SizedBox(height: 4),
        CategoryPickerField(
          businessId: widget.businessId,
          categoriesTree: _categories,
          initialValue: _selectedCategoryIds.isNotEmpty ? _selectedCategoryIds.first : null,
          label: 'انتخاب دسته‌بندی',
          onChanged: (value) {
            setState(() {
              _selectedCategoryIds = value != null ? [value] : [];
            });
          },
        ),
      ],
    );
  }

  Widget _buildCurrencyFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ارز'),
        const SizedBox(height: 4),
        DropdownButtonFormField<int?>(
          initialValue: _selectedCurrencyIds.isNotEmpty ? _selectedCurrencyIds.first : null,
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('همه ارزها'),
            ),
            ..._currencies.map((currency) => DropdownMenuItem<int>(
              value: currency['id'] as int,
              child: Text('${currency['title'] ?? 'بدون نام'} (${currency['code'] ?? 'بدون کد'})'),
            )),
          ],
          onChanged: (value) {
            setState(() {
              _selectedCurrencyIds = value != null ? [value] : [];
            });
          },
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildPriceListFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('لیست قیمت'),
        const SizedBox(height: 4),
        DropdownButtonFormField<int?>(
          initialValue: _selectedPriceListIds.isNotEmpty ? _selectedPriceListIds.first : null,
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('همه لیست‌ها'),
            ),
            ..._priceLists.map((priceList) => DropdownMenuItem<int>(
              value: priceList['id'] as int,
              child: Text(priceList['name']?.toString() ?? 'بدون نام'),
            )),
          ],
          onChanged: (value) {
            setState(() {
              _selectedPriceListIds = value != null ? [value] : [];
            });
          },
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildItemTypeFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('نوع آیتم'),
        const SizedBox(height: 4),
        DropdownButtonFormField<String?>(
          initialValue: _selectedItemTypes.isNotEmpty ? _selectedItemTypes.first : null,
          items: const [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('همه انواع'),
            ),
            DropdownMenuItem<String>(
              value: 'کالا',
              child: Text('کالا'),
            ),
            DropdownMenuItem<String>(
              value: 'خدمت',
              child: Text('خدمت'),
            ),
          ],
          onChanged: (value) {
            setState(() {
              _selectedItemTypes = value != null ? [value] : [];
            });
          },
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildOptionsFilter() {
    return Column(
      children: [
        CheckboxListTile(
          title: const Text('فقط کالاهای با موجودی'),
          subtitle: const Text('فقط کالاهایی که موجودی آن‌ها کنترل می‌شود'),
          value: _onlyProductsWithInventory,
          onChanged: (value) {
            setState(() => _onlyProductsWithInventory = value ?? false);
          },
          controlAffinity: ListTileControlAffinity.leading,
        ),
        CheckboxListTile(
          title: const Text('فقط کالاهای با قیمت پایه'),
          subtitle: const Text('فقط کالاهایی که قیمت پایه دارند'),
          value: _onlyProductsWithBasePrice,
          onChanged: (value) {
            setState(() => _onlyProductsWithBasePrice = value ?? true);
          },
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ],
    );
  }

  Widget _buildPreviewSection({required bool isCompact}) {
    if (_previewResponse == null) return const SizedBox.shrink();
    final isMobile = ResponsiveHelper.isMobile(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Text(
                    'خلاصه تغییرات',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              isCompact
                  ? Column(
                      children: [
                        _buildSummaryItem(
                          'کل کالاها',
                          _previewResponse!.totalProducts.toString(),
                          Icons.inventory_2,
                        ),
                        const SizedBox(height: 8),
                        _buildSummaryItem(
                          'کالاهای تأثیرپذیر',
                          _previewResponse!.affectedProducts.length.toString(),
                          Icons.touch_app,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _buildSummaryItem(
                            'کل کالاها',
                            _previewResponse!.totalProducts.toString(),
                            Icons.inventory_2,
                          ),
                        ),
                        Expanded(
                          child: _buildSummaryItem(
                            'کالاهای تأثیرپذیر',
                            _previewResponse!.affectedProducts.length.toString(),
                            Icons.touch_app,
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 8),
              isCompact
                  ? Column(
                      children: [
                        _buildSummaryItem(
                          'تغییرات قیمت فروش',
                          _previewResponse!.summary['products_with_sales_change']?.toString() ?? '0',
                          Icons.sell,
                        ),
                        const SizedBox(height: 8),
                        _buildSummaryItem(
                          'تغییرات قیمت خرید',
                          _previewResponse!.summary['products_with_purchase_change']?.toString() ?? '0',
                          Icons.shopping_cart,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _buildSummaryItem(
                            'تغییرات قیمت فروش',
                            _previewResponse!.summary['products_with_sales_change']?.toString() ?? '0',
                            Icons.sell,
                          ),
                        ),
                        Expanded(
                          child: _buildSummaryItem(
                            'تغییرات قیمت خرید',
                            _previewResponse!.summary['products_with_purchase_change']?.toString() ?? '0',
                            Icons.shopping_cart,
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: isMobile ? 260 : 240,
          child: ListView.builder(
            itemCount: _previewResponse!.affectedProducts.length,
            itemBuilder: (context, index) {
              final product = _previewResponse!.affectedProducts[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(product.productName),
                  subtitle: Text('کد: ${product.productCode}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (product.salesPriceChange != null)
                        Text(
                          'فروش: ${formatWithThousands(product.currentSalesPrice ?? 0)} → ${formatWithThousands(product.newSalesPrice ?? 0)}',
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (product.purchasePriceChange != null)
                        Text(
                          'خرید: ${formatWithThousands(product.currentPurchasePrice ?? 0)} → ${formatWithThousands(product.newPurchasePrice ?? 0)}',
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 16, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  String _formatBulkPriceUpdateError(Object e, AppLocalizations t) {
    ApiErrorDetails? apiError;
    if (e is DioException && e.error is ApiErrorDetails) {
      apiError = e.error as ApiErrorDetails;
    } else if (e is ApiErrorDetails) {
      apiError = e;
    }

    if (apiError?.code == 'VALIDATION_ERROR') {
      final details = apiError?.details?['details'];
      if (details is List) {
        final messages = <String>[];
        for (final item in details) {
          if (item is Map) {
            final loc = item['loc'];
            final msg = item['msg']?.toString();
            final field = _extractFieldName(loc);
            final label = _bulkPriceFieldLabel(field);
            if (msg != null && msg.isNotEmpty) {
              messages.add(label != null ? '$label: $msg' : msg);
            }
          }
        }
        if (messages.isNotEmpty) {
          return 'لطفاً موارد زیر را اصلاح کنید:\n- ${messages.join('\n- ')}';
        }
      }
      return apiError?.message ?? t.operationFailed;
    }

    return '${t.operationFailed}: ${apiError?.message ?? e.toString()}';
  }

  String? _extractFieldName(dynamic loc) {
    if (loc is List) {
      // ساختار معمول: ["body", "field_name", ...]
      for (final part in loc) {
        final s = part?.toString();
        if (s != null && s.isNotEmpty && s != 'body' && s != 'query' && s != 'path') {
          return s;
        }
      }
    }
    return null;
  }

  String? _bulkPriceFieldLabel(String? field) {
    switch (field) {
      case 'update_type':
        return 'نوع تغییر';
      case 'direction':
        return 'جهت تغییر';
      case 'target':
        return 'هدف تغییر';
      case 'value':
        return 'مقدار تغییر';
      case 'product_ids':
        return 'کالاهای انتخاب‌شده';
      case 'category_ids':
        return 'دسته‌بندی';
      case 'currency_ids':
        return 'ارز';
      case 'price_list_ids':
        return 'لیست قیمت';
      case 'item_types':
        return 'نوع آیتم';
      case 'only_products_with_inventory':
        return 'فقط کالاهای با موجودی';
      case 'only_products_with_base_price':
        return 'فقط کالاهای با قیمت پایه';
    }
    return null;
  }
}
