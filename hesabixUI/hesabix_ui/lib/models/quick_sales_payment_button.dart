enum QuickSalesPaymentTargetType { cashRegister, bank, person }

class QuickSalesPaymentButtonModel {
  final Object id;
  final int businessId;
  final String scope;
  final int? ownerUserId;
  final QuickSalesPaymentTargetType targetType;
  final int targetId;
  final String targetName;
  final String label;
  final String? shortcut;
  final int position;
  final bool isSystem;

  const QuickSalesPaymentButtonModel({
    required this.id,
    required this.businessId,
    required this.scope,
    required this.ownerUserId,
    required this.targetType,
    required this.targetId,
    required this.targetName,
    required this.label,
    required this.shortcut,
    required this.position,
    required this.isSystem,
  });

  bool get isPersonal => scope == 'user';

  factory QuickSalesPaymentButtonModel.fromJson(Map<String, dynamic> json) {
    final target = switch ((json['target_type'] ?? '').toString()) {
      'cash_register' => QuickSalesPaymentTargetType.cashRegister,
      'bank' => QuickSalesPaymentTargetType.bank,
      'person' => QuickSalesPaymentTargetType.person,
      _ => throw const FormatException(
        'Unsupported quick-sales payment target',
      ),
    };
    return QuickSalesPaymentButtonModel(
      id: json['id'] ?? '',
      businessId: (json['business_id'] as num).toInt(),
      scope: (json['scope'] ?? 'user').toString(),
      ownerUserId: (json['owner_user_id'] as num?)?.toInt(),
      targetType: target,
      targetId: (json['target_id'] as num).toInt(),
      targetName: (json['target_name'] ?? '').toString(),
      label: (json['label'] ?? json['target_name'] ?? '').toString(),
      shortcut: json['shortcut']?.toString(),
      position: (json['position'] as num?)?.toInt() ?? 0,
      isSystem: json['is_system'] == true,
    );
  }

  static String targetTypeValue(QuickSalesPaymentTargetType type) =>
      switch (type) {
        QuickSalesPaymentTargetType.cashRegister => 'cash_register',
        QuickSalesPaymentTargetType.bank => 'bank',
        QuickSalesPaymentTargetType.person => 'person',
      };
}
