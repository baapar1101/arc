enum InvoiceType {
  sales('sales', 'فروش'),
  salesReturn('sales_return', 'برگشت از فروش'),
  purchase('purchase', 'خرید'),
  purchaseReturn('purchase_return', 'برگشت از خرید'),
  waste('waste', 'ضایعات'),
  directConsumption('direct_consumption', 'مصرف مستقیم'),
  production('production', 'تولید');

  const InvoiceType(this.value, this.label);

  final String value;
  final String label;

  static InvoiceType? fromValue(String value) {
    for (final type in InvoiceType.values) {
      if (type.value == value) {
        return type;
      }
    }
    return null;
  }

  static List<InvoiceType> get allTypes => InvoiceType.values;
}
