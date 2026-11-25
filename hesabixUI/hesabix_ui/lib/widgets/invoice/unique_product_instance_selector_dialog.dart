import 'package:flutter/material.dart';
import '../../services/warehouse_service.dart';
import '../../services/product_service.dart';
import '../../services/product_attribute_service.dart';
import '../../core/calendar_controller.dart';
import '../../utils/attribute_formatter.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';


/// Dialog for selecting unique product instances in invoice
class UniqueProductInstanceSelectorDialog extends StatefulWidget {
  final int businessId;
  final int productId;
  final String productName;
  final int? warehouseId;
  final List<int>? selectedInstanceIds;
  final int requiredQuantity;
  final CalendarController calendarController;
  final bool forReturn;
  final bool allowExpiredConfirm;
  final bool includeUnsellable;

  const UniqueProductInstanceSelectorDialog({
    super.key,
    required this.businessId,
    required this.productId,
    required this.productName,
    this.warehouseId,
    this.selectedInstanceIds,
    required this.requiredQuantity,
    required this.calendarController,
    this.forReturn = false,
    this.allowExpiredConfirm = false,
    this.includeUnsellable = false,
  });

  @override
  State<UniqueProductInstanceSelectorDialog> createState() =>
      _UniqueProductInstanceSelectorDialogState();
}

class _UniqueProductInstanceSelectorDialogState
    extends State<UniqueProductInstanceSelectorDialog> {
  final _svc = WarehouseService();
  final _productService = ProductService();
  final _attributeService = ProductAttributeService();
  final _searchController = TextEditingController();
  
  List<Map<String, dynamic>> _instances = [];
  Map<String, Map<String, dynamic>> _attributesMap = {};
  Set<int> _selectedIds = {};
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _product;

  @override
  void initState() {
    super.initState();
    if (widget.selectedInstanceIds != null) {
      _selectedIds = Set<int>.from(widget.selectedInstanceIds!);
    }
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Load product info
      final product = await _productService.getProduct(
        businessId: widget.businessId,
        productId: widget.productId,
      );
      if (mounted) {
        setState(() {
          _product = product;
        });
      }

      // Load product attributes if product has attribute_ids
      final attributeIds = product['attribute_ids'] as List<dynamic>? ?? [];
      if (attributeIds.isNotEmpty) {
        final productAttrs = await _attributeService.getByIds(
          businessId: widget.businessId,
          ids: attributeIds,
        );

        // Create map by title
        final attrsMap = <String, Map<String, dynamic>>{};
        for (var attr in productAttrs) {
          final title = attr['title']?.toString();
          if (title != null) {
            attrsMap[title] = attr;
          }
        }
        if (mounted) {
          setState(() {
            _attributesMap = attrsMap;
          });
        }
      }

      final Map<String, dynamic> result;
      if (widget.forReturn) {
        result = await _svc.searchProductInstances(
          businessId: widget.businessId,
          productId: widget.productId,
          status: 'sold',
        );
      } else {
        result = await _svc.getAvailableInstances(
          businessId: widget.businessId,
          productId: widget.productId,
          warehouseId: widget.warehouseId,
          includeExpired: widget.includeUnsellable ||
              (widget.allowExpiredConfirm &&
                  product['expired_sale_policy']?.toString() == 'manager_confirm'),
        );
      }

      final items = (result['items'] as List<dynamic>?) ?? [];
      if (mounted) {
        setState(() {
          _instances = items.map((item) => Map<String, dynamic>.from(item as Map)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ErrorExtractor.forContext(e, context);
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredInstances {
    final searchTerm = _searchController.text.toLowerCase();
    if (searchTerm.isEmpty) return _instances;

    return _instances.where((inst) {
      final serial = inst['serial_number']?.toString().toLowerCase() ?? '';
      final barcode = inst['barcode']?.toString().toLowerCase() ?? '';
      
      // Also search in formatted attributes
      final attrs = inst['custom_attributes'] as Map<String, dynamic>? ?? {};
      final attrsText = AttributeFormatter.formatAttributesForDisplay(
        attrs,
        _attributesMap,
        widget.calendarController.isJalali,
      ).toLowerCase();
      
      return serial.contains(searchTerm) || 
             barcode.contains(searchTerm) ||
             attrsText.contains(searchTerm);
    }).toList();
  }

  bool _canSelectExpired() =>
      widget.includeUnsellable ||
      (widget.allowExpiredConfirm &&
          _product?['expired_sale_policy']?.toString() == 'manager_confirm');

  bool _isExpired(Map<String, dynamic> inst) => inst['is_expired'] == true;

  Map<String, dynamic>? _instanceById(int instanceId) {
    for (final row in _instances) {
      final raw = row['id'];
      final id = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
      if (id == instanceId) return row;
    }
    return null;
  }

  void _toggleSelection(int instanceId) {
    final inst = _instanceById(instanceId);
    if (inst != null &&
        !widget.forReturn &&
        _isExpired(inst) &&
        !_canSelectExpired() &&
        !_selectedIds.contains(instanceId)) {
      SnackBarHelper.show(
        context,
        message: AppLocalizations.of(context).quickSalesExpiredInstanceBlocked,
      );
      return;
    }
    setState(() {
      if (_selectedIds.contains(instanceId)) {
        _selectedIds.remove(instanceId);
      } else {
        // Check if we can add more
        if (_selectedIds.length < widget.requiredQuantity) {
          _selectedIds.add(instanceId);
        } else {
          SnackBarHelper.show(
            context,
            message: AppLocalizations.of(context).uniqueInstanceMaxCount(widget.requiredQuantity),
          );
        }
      }
    });
  }

  void _confirmSelection() {
    if (_selectedIds.isEmpty) {
      SnackBarHelper.show(context, message: AppLocalizations.of(context).uniqueInstanceMinOne);
      return;
    }

    if (_selectedIds.length != widget.requiredQuantity) {
      SnackBarHelper.show(
        context,
        message: AppLocalizations.of(context).uniqueInstanceSelectExact(
          widget.requiredQuantity,
          _selectedIds.length,
        ),
      );
      return;
    }

    final allowExpired = _selectedIds.any((id) {
      final inst = _instanceById(id);
      return inst != null && _isExpired(inst);
    });
    Navigator.of(context).pop({
      'ids': _selectedIds.toList(),
      'allow_expired_lot_sale': allowExpired && _canSelectExpired(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final isJalali = widget.calendarController.isJalali;
    
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.qr_code_scanner,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.forReturn
                              ? AppLocalizations.of(context).uniqueInstanceReturnTitle
                              : AppLocalizations.of(context).uniqueInstanceSelectTitle,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          widget.productName,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          AppLocalizations.of(context).uniqueInstanceNeedCount(widget.requiredQuantity),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: AppLocalizations.of(context).close,
                  ),
                ],
              ),
            ),
            // Search
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).uniqueInstanceSearchHint,
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: ListenableBuilder(
                      listenable: _searchController,
                      builder: (context, _) {
                        if (_searchController.text.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchController.clear(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            // List
            Flexible(
              child: ListenableBuilder(
                listenable: _searchController,
                builder: (context, _) {
                  return _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('${AppLocalizations.of(context).error}: $_error'),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: _loadData,
                                    child: Text(AppLocalizations.of(context).retry),
                                  ),
                                ],
                              ),
                            )
                          : _filteredInstances.isEmpty
                              ? Center(child: Text(AppLocalizations.of(context).uniqueInstanceNotFound))
                              : ListView.builder(
                              itemCount: _filteredInstances.length,
                              itemBuilder: (context, index) {
                                final inst = _filteredInstances[index];
                                final instId = inst['id'] as int?;
                                final serial = inst['serial_number']?.toString() ?? '-';
                                final barcode = inst['barcode']?.toString();
                                final warehouseName = inst['warehouse_name']?.toString();
                                final attrs = inst['custom_attributes'] as Map<String, dynamic>? ?? {};
                                final isSelected = instId != null && _selectedIds.contains(instId);
                                
                                // Format attributes
                                final formattedAttrs = _attributesMap.isNotEmpty
                                    ? AttributeFormatter.formatAttributesForDisplay(
                                        attrs,
                                        _attributesMap,
                                        isJalali,
                                      )
                                    : null;

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
                                      : null,
                                  child: CheckboxListTile(
                                    value: isSelected,
                                    onChanged: instId != null
                                        ? (value) => _toggleSelection(instId)
                                        : null,
                                    title: Text(
                                      AppLocalizations.of(context).uniqueSerialPrefix(serial),
                                      style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (barcode != null && barcode.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(AppLocalizations.of(context).uniqueBarcodePrefix(barcode)),
                                          ),
                                        if (inst['manufacturing_date'] != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text('${AppLocalizations.of(context).expiryColManufacturing}: ${inst['manufacturing_date']}'),
                                          ),
                                        if (inst['expiry_date'] != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              inst['is_expired'] == true
                                                  ? '${AppLocalizations.of(context).expiryColExpiry}: ${inst['expiry_date']} (${AppLocalizations.of(context).expiryStatusExpired})'
                                                  : '${AppLocalizations.of(context).expiryColExpiry}: ${inst['expiry_date']}',
                                              style: inst['is_expired'] == true
                                                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                                                  : null,
                                            ),
                                          ),
                                        if (warehouseName != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(AppLocalizations.of(context).uniqueWarehousePrefix(warehouseName)),
                                          ),
                                        if (formattedAttrs != null &&
                                            formattedAttrs.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[100],
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                formattedAttrs,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    secondary: isSelected
                                        ? Icon(
                                            Icons.check_circle,
                                            color: Theme.of(context).colorScheme.primary,
                                          )
                                        : const Icon(Icons.radio_button_unchecked),
                                  ),
                                );
                              },
                            );
                },
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).uniqueInstanceSelectedOf(
                          _selectedIds.length,
                          widget.requiredQuantity,
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (_selectedIds.length != widget.requiredQuantity)
                        Text(
                          AppLocalizations.of(context).uniqueInstanceNeedMore(
                            widget.requiredQuantity - _selectedIds.length,
                          ),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: SemanticColorResolver.warning(context),
                              ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(AppLocalizations.of(context).cancel),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _confirmSelection,
                        child: Text(AppLocalizations.of(context).confirm),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

