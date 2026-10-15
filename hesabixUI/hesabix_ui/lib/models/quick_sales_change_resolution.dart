enum QuickSalesChangeSourceType { cashRegister, bank, person }

extension QuickSalesChangeSourceTypeValue on QuickSalesChangeSourceType {
  String get value => switch (this) {
    QuickSalesChangeSourceType.cashRegister => 'cash_register',
    QuickSalesChangeSourceType.bank => 'bank',
    QuickSalesChangeSourceType.person => 'person',
  };

  String get label => switch (this) {
    QuickSalesChangeSourceType.cashRegister => 'صندوق',
    QuickSalesChangeSourceType.bank => 'بانک',
    QuickSalesChangeSourceType.person => 'شخص',
  };

  static QuickSalesChangeSourceType? tryParse(Object? value) =>
      switch (value?.toString()) {
        'cash_register' => QuickSalesChangeSourceType.cashRegister,
        'bank' => QuickSalesChangeSourceType.bank,
        'person' => QuickSalesChangeSourceType.person,
        _ => null,
      };
}

class QuickSalesChangeAllocation {
  final String id;
  final QuickSalesChangeSourceType sourceType;
  final int sourceId;
  final String sourceName;
  final num amount;
  final num commission;

  const QuickSalesChangeAllocation({
    required this.id,
    required this.sourceType,
    required this.sourceId,
    required this.sourceName,
    required this.amount,
    this.commission = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'source_type': sourceType.value,
    'source_id': sourceId,
    'source_name': sourceName,
    'amount': amount,
    if (sourceType == QuickSalesChangeSourceType.bank) 'commission': commission,
  };

  factory QuickSalesChangeAllocation.fromJson(Map<String, dynamic> json) {
    final type = QuickSalesChangeSourceTypeValue.tryParse(json['source_type']);
    if (type == null) {
      throw const FormatException('Invalid quick sale change source type');
    }
    return QuickSalesChangeAllocation(
      id: json['id']?.toString() ?? '',
      sourceType: type,
      sourceId: (json['source_id'] as num?)?.toInt() ?? 0,
      sourceName: json['source_name']?.toString() ?? '',
      amount: (json['amount'] as num?) ?? 0,
      commission: (json['commission'] as num?) ?? 0,
    );
  }
}

class QuickSalesChangeResolution {
  final num overpaymentAmount;
  final List<QuickSalesChangeAllocation> allocations;
  final num creditAmount;

  const QuickSalesChangeResolution({
    required this.overpaymentAmount,
    required this.allocations,
    required this.creditAmount,
  });

  num get returnedAmount =>
      allocations.fold<num>(0, (sum, allocation) => sum + allocation.amount);

  num get bankCommission => allocations.fold<num>(
    0,
    (sum, allocation) => sum + allocation.commission,
  );

  num get resolvedAmount => returnedAmount + creditAmount;

  bool isValidFor(num amount, num epsilon) {
    if ((overpaymentAmount - amount).abs() > epsilon) return false;
    if ((resolvedAmount - amount).abs() > epsilon) return false;
    if (creditAmount < 0) return false;
    return allocations.every(
      (row) =>
          row.sourceId > 0 &&
          row.amount > 0 &&
          row.commission >= 0 &&
          (row.sourceType == QuickSalesChangeSourceType.bank ||
              row.commission == 0),
    );
  }

  Map<String, dynamic> toJson() => {
    'amount': overpaymentAmount,
    'allocations': allocations.map((row) => row.toJson()).toList(),
    'credit_amount': creditAmount,
    'confirmed': true,
  };

  factory QuickSalesChangeResolution.fromJson(Map<String, dynamic> json) {
    final allocations = <QuickSalesChangeAllocation>[];
    final rawRows = json['allocations'];
    if (rawRows is List) {
      for (final raw in rawRows) {
        if (raw is! Map) continue;
        try {
          allocations.add(
            QuickSalesChangeAllocation.fromJson(Map<String, dynamic>.from(raw)),
          );
        } catch (_) {}
      }
    }
    return QuickSalesChangeResolution(
      overpaymentAmount: (json['amount'] as num?) ?? 0,
      allocations: allocations,
      creditAmount: (json['credit_amount'] as num?) ?? 0,
    );
  }
}
