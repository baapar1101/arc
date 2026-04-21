import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// گزینه‌های ثابت نوع سند فاکتور (هم‌ارز API فیلد `document_type`)
class InvoiceDocumentTypeOption {
  const InvoiceDocumentTypeOption({
    required this.documentTypeValue,
    required this.icon,
    required this.label,
  });

  final String documentTypeValue;
  final IconData icon;
  final String Function(AppLocalizations t) label;
}

String _lSales(AppLocalizations t) => t.invoiceTypeSales;
String _lPurchase(AppLocalizations t) => t.invoiceTypePurchase;
String _lSalesReturn(AppLocalizations t) => t.invoiceTypeSalesReturn;
String _lPurchaseReturn(AppLocalizations t) => t.invoiceTypePurchaseReturn;
String _lProduction(AppLocalizations t) => t.invoiceTypeProduction;
String _lDirectConsumption(AppLocalizations t) => t.invoiceTypeDirectConsumption;
String _lWaste(AppLocalizations t) => t.invoiceTypeWaste;

final List<InvoiceDocumentTypeOption> kInvoiceDocumentTypeOptions = [
  InvoiceDocumentTypeOption(
    documentTypeValue: 'invoice_sales',
    icon: Icons.sell_outlined,
    label: _lSales,
  ),
  InvoiceDocumentTypeOption(
    documentTypeValue: 'invoice_purchase',
    icon: Icons.shopping_cart_outlined,
    label: _lPurchase,
  ),
  InvoiceDocumentTypeOption(
    documentTypeValue: 'invoice_sales_return',
    icon: Icons.undo_outlined,
    label: _lSalesReturn,
  ),
  InvoiceDocumentTypeOption(
    documentTypeValue: 'invoice_purchase_return',
    icon: Icons.undo,
    label: _lPurchaseReturn,
  ),
  InvoiceDocumentTypeOption(
    documentTypeValue: 'invoice_production',
    icon: Icons.factory_outlined,
    label: _lProduction,
  ),
  InvoiceDocumentTypeOption(
    documentTypeValue: 'invoice_direct_consumption',
    icon: Icons.dining_outlined,
    label: _lDirectConsumption,
  ),
  InvoiceDocumentTypeOption(
    documentTypeValue: 'invoice_waste',
    icon: Icons.delete_outline,
    label: _lWaste,
  ),
];

bool isKnownInvoiceDocumentType(String? type) {
  if (type == null || type.isEmpty) return false;
  return kInvoiceDocumentTypeOptions.any((o) => o.documentTypeValue == type);
}

String invoiceDocumentTypeLabel(AppLocalizations t, String? type) {
  if (type == null) return t.all;
  for (final o in kInvoiceDocumentTypeOptions) {
    if (o.documentTypeValue == type) return o.label(t);
  }
  return t.all;
}

/// نوار فیلتر سریع نوع سند بالای لیست فاکتورها (اسکرول افقی در عرض کم)
class InvoiceListDocumentTypeFilterBar extends StatelessWidget {
  final String? selectedDocumentType;
  final ValueChanged<String?> onDocumentTypeChanged;

  const InvoiceListDocumentTypeFilterBar({
    super.key,
    required this.selectedDocumentType,
    required this.onDocumentTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.65),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              t.documentType,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Scrollbar(
                thumbVisibility: false,
                thickness: 4,
                radius: const Radius.circular(4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  primary: false,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: FilterChip(
                          label: Text(t.all),
                          selected: selectedDocumentType == null,
                          onSelected: (_) => onDocumentTypeChanged(null),
                          showCheckmark: false,
                          avatar: Icon(
                            Icons.all_inclusive,
                            size: 18,
                            color: selectedDocumentType == null
                                ? theme.colorScheme.onSecondaryContainer
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      for (final o in kInvoiceDocumentTypeOptions)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: FilterChip(
                            label: Text(
                              o.label(t),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            selected: selectedDocumentType == o.documentTypeValue,
                            onSelected: (_) => onDocumentTypeChanged(o.documentTypeValue),
                            showCheckmark: false,
                            avatar: Icon(
                              o.icon,
                              size: 18,
                              color: selectedDocumentType == o.documentTypeValue
                                  ? theme.colorScheme.onSecondaryContainer
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
