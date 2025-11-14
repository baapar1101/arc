String formatWithThousands(dynamic value, {int? decimalPlaces}) {
  if (value == null) return '-';
  num? n;
  if (value is num) {
    n = value;
  } else if (value is String) {
    n = num.tryParse(value);
  }
  if (n == null) return value.toString();
  
  // Determine effective decimal digits
  int effectiveDecimalDigits = decimalPlaces ?? (n is int ? 0 : 2);
  if (decimalPlaces != null && decimalPlaces > 0) {
    final fixed = n.toStringAsFixed(decimalPlaces);
    final parts = fixed.split('.');
    if (parts.length == 2) {
      final fractional = parts[1];
      final isAllZeros = fractional.replaceAll('0', '').isEmpty;
      if (isAllZeros) {
        effectiveDecimalDigits = 0;
      }
    }
  }
  
  final parts = n.toStringAsFixed(effectiveDecimalDigits).split('.');
  final intPart = parts[0];
  final decPart = parts.length > 1 ? parts[1] : null;
  final reg = RegExp(r'\B(?=(\d{3})+(?!\d))');
  final grouped = intPart.replaceAllMapped(reg, (m) => ',');
  return decPart == null || decPart.isEmpty ? grouped : '$grouped.$decPart';
}

