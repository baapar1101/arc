import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../models/product_form_data.dart';
import '../../../services/tax_product_code_service.dart';
import '../../../utils/number_normalizer.dart';
import '../../../utils/product_form_validator.dart';
import '../tax_code_search_sheet.dart';

class ProductTaxSection extends StatefulWidget {
  final ProductFormData formData;
  final ValueChanged<ProductFormData> onChanged;
  final List<Map<String, dynamic>> taxTypes;
  final List<Map<String, dynamic>> taxUnits;

  const ProductTaxSection({
    super.key,
    required this.formData,
    required this.onChanged,
    required this.taxTypes,
    required this.taxUnits,
  });

  @override
  State<ProductTaxSection> createState() => _ProductTaxSectionState();
}

class _ProductTaxSectionState extends State<ProductTaxSection> {
  late final TextEditingController _taxCodeController;
  final TaxProductCodeService _taxCodeService = TaxProductCodeService();
  Timer? _taxCodeDebounce;
  String? _taxCodeDescription;
  bool _isFetchingTaxCode = false;

  @override
  void initState() {
    super.initState();
    _taxCodeController = TextEditingController(text: widget.formData.taxCode ?? '');
    if ((widget.formData.taxCode ?? '').isNotEmpty) {
      _fetchTaxCodeDescription(widget.formData.taxCode!);
    }
  }

  @override
  void didUpdateWidget(covariant ProductTaxSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.formData.taxCode != oldWidget.formData.taxCode) {
      _taxCodeController.text = widget.formData.taxCode ?? '';
      if ((widget.formData.taxCode ?? '').isNotEmpty) {
        _fetchTaxCodeDescription(widget.formData.taxCode!);
      } else {
        setState(() {
          _taxCodeDescription = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _taxCodeDebounce?.cancel();
    _taxCodeController.dispose();
    super.dispose();
  }

  Future<void> _fetchTaxCodeDescription(String code) async {
    setState(() {
      _isFetchingTaxCode = true;
    });
    try {
      final info = await _taxCodeService.getTaxCodeByCode(code);
      if (!mounted) return;
      setState(() {
        _taxCodeDescription = info?['description']?.toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _taxCodeDescription = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingTaxCode = false;
        });
      }
    }
  }

  Future<void> _openTaxCodeSearch({bool clearSelection = false}) async {
    if (clearSelection) {
      _taxCodeController.clear();
      widget.onChanged(widget.formData.copyWith(taxCode: null));
      setState(() {
        _taxCodeDescription = null;
      });
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => TaxCodeSearchSheet(service: _taxCodeService),
    );
    if (selected != null && mounted) {
      final code = selected['code']?.toString();
      if (code != null && code.isNotEmpty) {
        _taxCodeController.text = code;
        widget.onChanged(widget.formData.copyWith(taxCode: code));
        setState(() {
          _taxCodeDescription = selected['description']?.toString();
        });
      }
    }
  }

  String? _buildTaxCodeHelperText() {
    if (_isFetchingTaxCode) {
      return 'در حال دریافت شرح کد...';
    }
    if (_taxCodeDescription != null && _taxCodeDescription!.isNotEmpty) {
      return _taxCodeDescription;
    }
    if (widget.formData.taxCode?.isNotEmpty == true) {
      return 'کد وارد شده ثبت می‌شود. برای مشاهده جزئیات دقیق جستجو کنید.';
    }
    return 'برای انتخاب دقیق‌تر از دکمه جستجو استفاده کنید.';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.taxTitle, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 16),
        _buildTaxCodeTypeUnitRow(context),
        const SizedBox(height: 24),
        _buildSalesTaxSection(context),
        const SizedBox(height: 24),
        _buildPurchaseTaxSection(context),
      ],
    );
  }

  Widget _buildTaxCodeTypeUnitRow(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 1000;
        if (isDesktop) {
          return Row(
            children: [
              Expanded(child: _buildTaxCodeField(context)),
              const SizedBox(width: 12),
              Expanded(child: _buildTaxTypeDropdown(context)),
              const SizedBox(width: 12),
              Expanded(child: _buildTaxUnitDropdown(context)),
            ],
          );
        }
        return Column(
          children: [
            _buildTaxCodeField(context),
            const SizedBox(height: 12),
            _buildTaxTypeDropdown(context),
            const SizedBox(height: 12),
            _buildTaxUnitDropdown(context),
          ],
        );
      },
    );
  }

  Widget _buildTaxCodeField(BuildContext context) {
    final t = AppLocalizations.of(context);
    final hasSelection = widget.formData.taxCode?.isNotEmpty == true;
    final displayText = hasSelection
        ? '${widget.formData.taxCode}'
        : 'برای انتخاب از جست‌وجو استفاده کنید';

    return GestureDetector(
      onTap: () => _openTaxCodeSearch(),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: t.taxCode,
          helperText: _buildTaxCodeHelperText(),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasSelection)
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'حذف انتخاب',
                  onPressed: () => _openTaxCodeSearch(clearSelection: true),
                ),
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'جستجوی کد مالیاتی',
                onPressed: () => _openTaxCodeSearch(),
              ),
            ],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                displayText,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: hasSelection
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).hintColor,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesTaxSection(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: widget.formData.isSalesTaxable,
          onChanged: (value) => widget.onChanged(widget.formData.copyWith(isSalesTaxable: value)),
          title: Text(t.isSalesTaxable),
        ),
        if (widget.formData.isSalesTaxable) ...[
          const SizedBox(height: 16),
          TextFormField(
            initialValue: widget.formData.salesTaxRate?.toString(),
            decoration: InputDecoration(labelText: t.salesTaxRate),
            keyboardType: TextInputType.number,
            inputFormatters: [
              const EnglishDigitsFormatter(),
              FilteringTextInputFormatter.digitsOnly,
            ],
            validator: (value) => ProductFormValidator.validateTaxRate(value, fieldName: t.salesTaxRate),
            onChanged: (value) => widget.onChanged(widget.formData.copyWith(salesTaxRate: num.tryParse(value))),
          ),
        ],
      ],
    );
  }

  Widget _buildPurchaseTaxSection(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: widget.formData.isPurchaseTaxable,
          onChanged: (value) => widget.onChanged(widget.formData.copyWith(isPurchaseTaxable: value)),
          title: Text(t.isPurchaseTaxable),
        ),
        if (widget.formData.isPurchaseTaxable) ...[
          const SizedBox(height: 16),
          TextFormField(
            initialValue: widget.formData.purchaseTaxRate?.toString(),
            decoration: InputDecoration(labelText: t.purchaseTaxRate),
            keyboardType: TextInputType.number,
            inputFormatters: [
              const EnglishDigitsFormatter(),
              FilteringTextInputFormatter.digitsOnly,
            ],
            validator: (value) => ProductFormValidator.validateTaxRate(value, fieldName: t.purchaseTaxRate),
            onChanged: (value) => widget.onChanged(widget.formData.copyWith(purchaseTaxRate: num.tryParse(value))),
          ),
        ],
      ],
    );
  }

  Widget _buildTaxTypeDropdown(BuildContext context) {
    final t = AppLocalizations.of(context);
    final List<Map<String, dynamic>> effectiveTaxTypes = widget.taxTypes.isNotEmpty ? widget.taxTypes : _fallbackTaxTypes();
    return DropdownButtonFormField<int?>(
      value: widget.formData.taxTypeId,
      items: [
        DropdownMenuItem<int?>(
          value: null,
          child: Text('انتخاب ${t.taxType}'),
        ),
        ...effectiveTaxTypes
            .map((taxType) => DropdownMenuItem<int?>(
                  value: (taxType['id'] as num).toInt(),
                  child: Text((taxType['title'] ?? taxType['name'] ?? 'نوع ${taxType['id']}').toString()),
                )),
      ],
      onChanged: (value) => widget.onChanged(widget.formData.copyWith(taxTypeId: value)),
      decoration: InputDecoration(
        labelText: t.taxType,
        suffixIcon: widget.formData.taxTypeId != null
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'حذف انتخاب',
                onPressed: () => widget.onChanged(widget.formData.copyWith(taxTypeId: null)),
              )
            : null,
      ),
    );
  }

  Widget _buildTaxUnitDropdown(BuildContext context) {
    final List<Map<String, dynamic>> effectiveTaxUnits = widget.taxUnits.isNotEmpty ? widget.taxUnits : _fallbackTaxUnits();
    if (effectiveTaxUnits.isNotEmpty) {
      final t = AppLocalizations.of(context);
      return DropdownButtonFormField<int?>(
        value: widget.formData.taxUnitId,
        items: [
          DropdownMenuItem<int?>(
            value: null,
            child: Text('انتخاب ${t.taxUnit}'),
          ),
          ...effectiveTaxUnits
              .map((taxUnit) => DropdownMenuItem<int?>(
                    value: (taxUnit['id'] as num).toInt(),
                    child: Text((taxUnit['title'] ?? taxUnit['name'] ?? 'واحد ${taxUnit['id']}').toString()),
                  )),
        ],
        onChanged: (value) => widget.onChanged(widget.formData.copyWith(taxUnitId: value)),
        decoration: InputDecoration(
          labelText: t.taxUnit,
          suffixIcon: widget.formData.taxUnitId != null
              ? IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'حذف انتخاب',
                  onPressed: () => widget.onChanged(widget.formData.copyWith(taxUnitId: null)),
                )
              : null,
        ),
      );
    } else {
      final t = AppLocalizations.of(context);
      return TextFormField(
        initialValue: widget.formData.taxUnitId?.toString(),
        decoration: InputDecoration(labelText: t.taxUnitId),
        keyboardType: TextInputType.number,
        onChanged: (value) => widget.onChanged(widget.formData.copyWith(taxUnitId: int.tryParse(value))),
      );
    }
  }

  List<Map<String, dynamic>> _fallbackTaxTypes() {
    final titles = [
      '۱- دارو',
      '۲- دخانیات',
      '۳- موبایل',
      '۴- لوازم خانگی برقی',
      '۵- قطعات مصرفی و یدکی وسایل نقلیه',
      '۶- فراورده ها و مشتقات نفتی و گازی و پتروشیمیایی',
      '۷- طلا اعم از شمش ،مسکوکات و مصنوعات زینتی',
      '۸- منسوجات و پوشاک',
      '۹- اسباب بازی',
      '۱۰- دام زنده، گوشت سفید و قرمز',
      '۱۱- محصولات اساسی کشاورزی',
      '۱۲- سایر کالا ها',
    ];
    return List.generate(titles.length, (i) => {
          'id': i + 1,
          'title': titles[i],
        });
  }

  List<Map<String, dynamic>> _fallbackTaxUnits() {
    final titles = [
      'بانكه', 'برگ', 'بسته', 'بشكه', 'بطری', 'بندیل', 'پاکت', 'پالت',
      'تانكر', 'تخته', 'تن', 'تن کیلومتر', 'توپ', 'تیوب', 'ثانیه', 'ثوب',
      'جام', 'جعبه', 'جفت', 'جلد', 'چلیك', 'حلب', 'حلقه (رول)', 'حلقه (دیسک)',
      'حلقه (رینگ)', 'دبه', 'دست', 'دستگاه', 'دقیقه', 'دوجین', 'روز', 'رول',
      'ساشه', 'ساعت', 'سال', 'سانتی متر', 'سانتی متر مربع', 'سبد', 'ست', 'سطل',
      'سیلندر', 'شاخه', 'شانه', 'شعله', 'شیت', 'صفحه', 'طاقه', 'طغرا', 'عدد',
      'عدل', 'فاقد بسته بندی', 'فروند', 'فوت مربع', 'قالب', 'قراص', 'قراصه (bundle)',
      'قرقره', 'قطعه', 'قوطي', 'قیراط', 'کارتن', 'کارتن (master case)', 'کلاف', 'کپسول',
      'کیسه', 'کیلوگرم', 'کیلومتر', 'کیلووات ساعت', 'گالن', 'گرم', 'گیگابایت بر ثانیه',
      'لنگه', 'لیتر', 'لیوان', 'ماه', 'متر', 'متر مربع', 'متر مكعب', 'مخزن',
      'مگاوات ساعت', 'ميلي گرم', 'ميلي لیتر', 'ميلي متر', 'نخ', 'نسخه (جلد)',
      'نفر', 'نفر- ساعت', 'نوبت', 'نیم دوجین', 'واحد', 'ورق', 'ویال'
    ];
    // Generate predictable ids starting from 1
    return List.generate(titles.length, (i) => {
      'id': i + 1,
      'title': titles[i],
    });
  }

}
