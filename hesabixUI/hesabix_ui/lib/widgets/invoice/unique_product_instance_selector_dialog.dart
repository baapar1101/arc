import 'package:flutter/material.dart';
import '../../services/warehouse_service.dart';
import '../../services/product_service.dart';
import '../../services/product_attribute_service.dart';
import '../../core/calendar_controller.dart';
import '../../utils/attribute_formatter.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';


/// Dialog for selecting unique product instances in invoice
class UniqueProductInstanceSelectorDialog extends StatefulWidget {
  final int businessId;
  final int productId;
  final String productName;
  final int? warehouseId;
  final List<int>? selectedInstanceIds;
  final int requiredQuantity;
  final CalendarController calendarController;

  const UniqueProductInstanceSelectorDialog({
    super.key,
    required this.businessId,
    required this.productId,
    required this.productName,
    this.warehouseId,
    this.selectedInstanceIds,
    required this.requiredQuantity,
    required this.calendarController,
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
        final attrsResult = await _attributeService.search(
          businessId: widget.businessId,
          limit: 1000,
        );
        final allAttributes = (attrsResult['items'] as List<dynamic>?) ?? [];
        final productAttrs = allAttributes
            .where((attr) {
              final attrId = attr['id'] as int?;
              return attrId != null && attributeIds.contains(attrId);
            })
            .map((attr) => Map<String, dynamic>.from(attr as Map))
            .toList();

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

      // Load instances
      final result = await _svc.getAvailableInstances(
        businessId: widget.businessId,
        productId: widget.productId,
        warehouseId: widget.warehouseId,
      );

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

  void _toggleSelection(int instanceId) {
    setState(() {
      if (_selectedIds.contains(instanceId)) {
        _selectedIds.remove(instanceId);
      } else {
        // Check if we can add more
        if (_selectedIds.length < widget.requiredQuantity) {
          _selectedIds.add(instanceId);
        } else {
          SnackBarHelper.show(context, message: 'شما فقط می‌توانید ${widget.requiredQuantity} کالا انتخاب کنید',);
        }
      }
    });
  }

  void _confirmSelection() {
    if (_selectedIds.isEmpty) {
      SnackBarHelper.show(context, message: 'لطفاً حداقل یک کالا انتخاب کنید');
      return;
    }

    if (_selectedIds.length != widget.requiredQuantity) {
      SnackBarHelper.show(context, message: 'لطفاً دقیقاً ${widget.requiredQuantity} کالا انتخاب کنید (${_selectedIds.length} انتخاب شده)');
      return;
    }

    Navigator.of(context).pop(_selectedIds.toList());
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
                          'انتخاب کالاهای یونیک',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          widget.productName,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          'نیاز: ${widget.requiredQuantity} کالا',
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
                    tooltip: 'بستن',
                  ),
                ],
              ),
            ),
            // Search
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'جستجو (سریال/بارکد/ویژگی‌ها)',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            // List
            Flexible(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('خطا: $_error'),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadData,
                                child: const Text('تلاش مجدد'),
                              ),
                            ],
                          ),
                        )
                      : _filteredInstances.isEmpty
                          ? const Center(child: Text('کالای یونیکی یافت نشد'))
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
                                      'سریال: $serial',
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
                                            child: Text('بارکد: $barcode'),
                                          ),
                                        if (warehouseName != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text('انبار: $warehouseName'),
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
                        '${_selectedIds.length} از ${widget.requiredQuantity} کالا انتخاب شده',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (_selectedIds.length != widget.requiredQuantity)
                        Text(
                          'لطفاً ${widget.requiredQuantity - _selectedIds.length} کالای دیگر انتخاب کنید',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.orange,
                              ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('انصراف'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _confirmSelection,
                        child: const Text('تأیید'),
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

