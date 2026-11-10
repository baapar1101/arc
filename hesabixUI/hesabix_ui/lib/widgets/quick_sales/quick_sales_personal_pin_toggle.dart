import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/auth_store.dart';
import '../../services/quick_sales_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/quick_sales_pinned_products.dart';
import '../../utils/snackbar_helper.dart';

class QuickSalesPersonalPinToggle extends StatefulWidget {
  final int businessId;
  final int productId;
  final AuthStore? authStore;

  const QuickSalesPersonalPinToggle({
    super.key,
    required this.businessId,
    required this.productId,
    this.authStore,
  });

  @override
  State<QuickSalesPersonalPinToggle> createState() =>
      _QuickSalesPersonalPinToggleState();
}

class _QuickSalesPersonalPinToggleState
    extends State<QuickSalesPersonalPinToggle> {
  final QuickSalesService _service = QuickSalesService();
  bool _loading = true;
  bool _saving = false;
  bool _pinned = false;
  List<int> _ids = const [];
  int _maxCount = kQuickSalesMaxPinnedProducts;

  bool get _canUseQuickSales {
    final auth = widget.authStore;
    if (auth == null) return false;
    return auth.hasBusinessPermission('invoices', 'add');
  }

  @override
  void initState() {
    super.initState();
    if (_canUseQuickSales) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    try {
      final data = await _service.listPinnedProducts(
        businessId: widget.businessId,
      );
      if (!mounted) return;
      final ids = normalizePinnedProductIds(data['product_ids'] as List? ?? const []);
      setState(() {
        _ids = ids;
        _pinned = ids.contains(widget.productId);
        _maxCount = (data['max_count'] as num?)?.toInt() ??
            kQuickSalesMaxPinnedProducts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _onChanged(bool value) async {
    if (_saving) return;
    final t = AppLocalizations.of(context);
    if (value) {
      final result = pinProductId(_ids, widget.productId, max: _maxCount);
      if (result.atLimit) {
        SnackBarHelper.show(
          context,
          message: t.quickSalesPinnedLimitReached(_maxCount),
          isError: true,
        );
        return;
      }
      await _save(result.ids, pinned: true);
      return;
    }
    await _save(unpinProductId(_ids, widget.productId), pinned: false);
  }

  Future<void> _save(List<int> ids, {required bool pinned}) async {
    setState(() => _saving = true);
    try {
      final data = await _service.updatePinnedProducts(
        businessId: widget.businessId,
        productIds: ids,
      );
      if (!mounted) return;
      final nextIds = normalizePinnedProductIds(
        data['product_ids'] as List? ?? ids,
      );
      setState(() {
        _ids = nextIds;
        _pinned = nextIds.contains(widget.productId);
        _maxCount = (data['max_count'] as num?)?.toInt() ?? _maxCount;
      });
      SnackBarHelper.show(
        context,
        message: pinned
            ? AppLocalizations.of(context).quickSalesProductPinned
            : AppLocalizations.of(context).quickSalesProductUnpinned,
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: ErrorExtractor.forContext(e, context),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canUseQuickSales) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _pinned,
      onChanged: _loading || _saving ? null : _onChanged,
      title: Text(t.quickSalesPinProduct),
      subtitle: Text(t.quickSalesPinProductHint),
      secondary: _loading || _saving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
    );
  }
}
