import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/permission/permission_widgets.dart';
import '../../core/auth_store.dart';
import '../../services/product_attribute_service.dart';
import '../../utils/snackbar_helper.dart';

class ProductAttributeItem {
  final int id;
  final int businessId;
  final String title;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  // Display strings coming from backend when calendar = jalali/gregorian
  final String? createdAtDisplay;
  final String? updatedAtDisplay;

  ProductAttributeItem({
    required this.id,
    required this.businessId,
    required this.title,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.createdAtDisplay,
    this.updatedAtDisplay,
  });

  static ProductAttributeItem fromJson(Map<String, dynamic> json) {
    final dynamic createdRaw = json['created_at'];
    final dynamic updatedRaw = json['updated_at'];

    final String? createdDisplay = _extractDisplay(createdRaw);
    final String? updatedDisplay = _extractDisplay(updatedRaw);

    return ProductAttributeItem(
      id: json['id'] as int,
      businessId: json['business_id'] as int,
      title: json['title'] as String,
      description: json['description'] as String?,
      createdAt: _parseDate(createdRaw),
      updatedAt: _parseDate(updatedRaw),
      createdAtDisplay: createdDisplay,
      updatedAtDisplay: updatedDisplay,
    );
  }

  static DateTime _parseDate(dynamic v) {
    if (v is String) {
      // Try ISO first
      try { return DateTime.parse(v); } catch (_) {}
      // If looks like jalali formatted (e.g., 1403/07/01 ...), just return now for sorting fallback
      return DateTime.now();
    }
    if (v is Map<String, dynamic>) {
      // Try ISO-like fields first
      final s = (v['iso'] ?? v['date_time'] ?? '').toString();
      if (s.isNotEmpty) {
        try { return DateTime.parse(s); } catch (_) {}
      }
      // Fallback: construct from components (assumed Gregorian components)
      final y = v['year'];
      final m = v['month'];
      final d = v['day'];
      final hh = v['hour'] ?? 0;
      final mm = v['minute'] ?? 0;
      final ss = v['second'] ?? 0;
      if (y is int && m is int && d is int) {
        try { return DateTime(y, m, d, hh is int ? hh : 0, mm is int ? mm : 0, ss is int ? ss : 0); } catch (_) {}
      }
      return DateTime.now();
    }
    return DateTime.now();
  }

  static String? _extractDisplay(dynamic v) {
    if (v is String) {
      final trimmed = v.trim();
      if (trimmed.isEmpty) return null;
      // Extract only date part (remove time if present)
      return trimmed.split(' ').first.trim();
    }
    if (v is Map<String, dynamic>) {
      // First try to get date_only (without time)
      final dateOnly = v['date_only'];
      if (dateOnly != null && dateOnly.toString().isNotEmpty) {
        return dateOnly.toString();
      }
      // Fallback to formatted if date_only is not available
      final s = (v['formatted'] ?? v['date_time'] ?? '').toString();
      if (s.isEmpty) return null;
      // Extract only date part (remove time if present)
      return s.split(' ').first.trim();
    }
    return null;
  }
}

class ProductAttributesPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const ProductAttributesPage({super.key, required this.businessId, required this.authStore});

  @override
  State<ProductAttributesPage> createState() => _ProductAttributesPageState();
}

class _ProductAttributesPageState extends State<ProductAttributesPage> {
  final _service = ProductAttributeService();
  final GlobalKey _tableKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!widget.authStore.canReadSection('product_attributes')) {
      return const AccessDeniedPage();
    }

    return Scaffold(
      body: DataTableWidget<ProductAttributeItem>(
        key: _tableKey,
        config: _buildConfig(t),
        fromJson: ProductAttributeItem.fromJson,
      ),
    );
  }

  void _refreshTable() {
    if (!mounted) return;
    // Use addPostFrameCallback to ensure refresh happens after dialog is closed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = _tableKey.currentState;
      if (state != null) {
        // ignore: avoid_dynamic_calls
        (state as dynamic).refresh();
      }
    });
  }

  DataTableConfig<ProductAttributeItem> _buildConfig(AppLocalizations t) {
    return DataTableConfig<ProductAttributeItem>(
      endpoint: '/api/v1/product-attributes/business/${widget.businessId}/search',
      title: t.productAttributes,
      showBackButton: true,
      onBack: () {
        if (!mounted) return;
        if (context.canPop()) {
          context.pop();
        }
      },
      showTableIcon: false,
      columns: [
        TextColumn('title', t.title, width: ColumnWidth.large, formatter: (e) => e.title),
        TextColumn('description', t.description, width: ColumnWidth.extraLarge, formatter: (e) => e.description ?? '-'),
        DateColumn('created_at', t.createdAt, formatter: (e) => _formatDateFromItem(e, context, isUpdated: false)),
        DateColumn('updated_at', t.updatedAt, formatter: (e) => _formatDateFromItem(e, context, isUpdated: true)),
        ActionColumn('actions', t.actions, actions: [
          DataTableAction(icon: Icons.edit, label: t.edit, onTap: (e) => _openForm(editing: e)),
          DataTableAction(icon: Icons.delete, label: t.delete, color: Colors.red, onTap: (e) => _confirmDelete(e)),
        ]),
      ],
      searchFields: ['title', 'description'],
      defaultPageSize: 20,
      customHeaderActions: [
        PermissionButton(
          section: 'product_attributes',
          action: 'add',
          authStore: widget.authStore,
          child: Tooltip(
            message: t.addAttribute,
            child: IconButton(onPressed: () => _openForm(), icon: const Icon(Icons.add)),
          ),
        ),
      ],
    );
  }

  static String _formatDate(DateTime dt, BuildContext context) {
    // Only show date, without time
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  static String _formatDateFromItem(ProductAttributeItem e, BuildContext context, {required bool isUpdated}) {
    final display = isUpdated ? e.updatedAtDisplay : e.createdAtDisplay;
    if (display != null && display.isNotEmpty) {
      // Extract only date part (remove time if present)
      // If display contains space, take only the first part (date)
      final dateOnly = display.split(' ').first.trim();
      return dateOnly;
    }
    return _formatDate(isUpdated ? e.updatedAt : e.createdAt, context);
  }

  void _openForm({ProductAttributeItem? editing}) async {
    final t = AppLocalizations.of(context);
    final titleCtrl = TextEditingController(text: editing?.title ?? '');
    final descCtrl = TextEditingController(text: editing?.description ?? '');
    

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(editing == null ? t.add : t.edit),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleCtrl, decoration: InputDecoration(labelText: t.title)),
              const SizedBox(height: 8),
              TextField(controller: descCtrl, maxLines: 3, decoration: InputDecoration(labelText: t.description)),
              const SizedBox(height: 8),
              const SizedBox.shrink(),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.save)),
        ],
      ),
    );
    if (result == true && mounted) {
      try {
        if (editing == null) {
          await _service.create(businessId: widget.businessId, title: titleCtrl.text.trim(), description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim());
        } else {
          await _service.update(businessId: widget.businessId, id: editing.id, title: titleCtrl.text.trim(), description: descCtrl.text.trim());
        }
        if (mounted) {
          _refreshTable();
          SnackBarHelper.show(
            context,
            message: editing == null ? 'ویژگی با موفقیت اضافه شد' : 'ویژگی با موفقیت ویرایش شد',
            isError: false,
          );
        }
      } on DioException catch (e) {
        if (!mounted) return;
        String errorMessage = 'خطا در ذخیره ویژگی';
        final response = e.response;
        if (response != null && response.data is Map) {
          final data = response.data as Map<String, dynamic>;
          if (data.containsKey('error') && data['error'] is Map) {
            final errorMap = data['error'] as Map;
            if (errorMap.containsKey('message')) {
              errorMessage = errorMap['message'] as String;
            }
          }
        }
        SnackBarHelper.showError(context, message: errorMessage);
      } catch (e) {
        if (!mounted) return;
        SnackBarHelper.showError(context, message: 'خطا در ذخیره ویژگی: $e');
      }
    }
  }

  void _confirmDelete(ProductAttributeItem item) {
    final t = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.delete),
        content: Text(t.deleteConfirm(item.title)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
          TextButton(onPressed: () async {
            Navigator.pop(context);
            if (!mounted) return;
            try {
              await _service.delete(businessId: widget.businessId, id: item.id);
              if (mounted) {
                _refreshTable();
                SnackBarHelper.show(
                  context,
                  message: 'ویژگی با موفقیت حذف شد',
                  isError: false,
                );
              }
            } on DioException catch (e) {
              if (!mounted) return;
              String errorMessage = 'خطا در حذف ویژگی';
              final response = e.response;
              if (response != null && response.data is Map) {
                final data = response.data as Map<String, dynamic>;
                if (data.containsKey('error') && data['error'] is Map) {
                  final errorMap = data['error'] as Map;
                  if (errorMap.containsKey('message')) {
                    errorMessage = errorMap['message'] as String;
                  }
                }
              }
              SnackBarHelper.showError(context, message: errorMessage);
            } catch (e) {
              if (!mounted) return;
              SnackBarHelper.showError(context, message: 'خطا در حذف ویژگی: $e');
            }
          }, style: TextButton.styleFrom(foregroundColor: Colors.red), child: Text(t.delete)),
        ],
      ),
    );
  }
}


