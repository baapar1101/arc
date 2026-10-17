enum QuickSalesPaymentTargetType { cashRegister, bank, person }

class QuickSalesShortcutProfile {
  final String? defaultShortcut;
  final String? userShortcut;
  final String? effectiveShortcut;
  final String source;
  final bool conflict;
  final bool userShortcutDisabled;

  const QuickSalesShortcutProfile({
    this.defaultShortcut,
    this.userShortcut,
    this.effectiveShortcut,
    this.source = 'none',
    this.conflict = false,
    this.userShortcutDisabled = false,
  });

  factory QuickSalesShortcutProfile.fromJson(Map<String, dynamic> json) =>
      QuickSalesShortcutProfile(
        defaultShortcut: json['default_shortcut']?.toString(),
        userShortcut: json['user_shortcut']?.toString(),
        effectiveShortcut: (json['effective_shortcut'] ?? json['shortcut'])
            ?.toString(),
        source: (json['shortcut_source'] ?? 'none').toString(),
        conflict: json['shortcut_conflict'] == true,
        userShortcutDisabled: json['user_shortcut_disabled'] == true,
      );
}

class QuickSalesPaymentButtonModel {
  final Object id;
  final int businessId;
  final String scope;
  final int? ownerUserId;
  final QuickSalesPaymentTargetType targetType;
  final int targetId;
  final String targetName;
  final String label;
  final String? defaultShortcut;
  final String? userShortcut;
  final String? shortcut;
  final String shortcutSource;
  final bool shortcutConflict;
  final bool userShortcutDisabled;
  final Map<String, QuickSalesShortcutProfile> shortcutProfiles;
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
    required this.defaultShortcut,
    required this.userShortcut,
    required this.shortcut,
    required this.shortcutSource,
    required this.shortcutConflict,
    required this.userShortcutDisabled,
    required this.shortcutProfiles,
    required this.position,
    required this.isSystem,
  });

  bool get isPersonal => scope == 'user';

  QuickSalesShortcutProfile shortcutProfile(String platform) =>
      shortcutProfiles[platform] ?? const QuickSalesShortcutProfile();

  String? shortcutForPlatform(String platform) =>
      shortcutProfile(platform).effectiveShortcut;

  factory QuickSalesPaymentButtonModel.fromJson(Map<String, dynamic> json) {
    final target = switch ((json['target_type'] ?? '').toString()) {
      'cash_register' => QuickSalesPaymentTargetType.cashRegister,
      'bank' => QuickSalesPaymentTargetType.bank,
      'person' => QuickSalesPaymentTargetType.person,
      _ => throw const FormatException(
        'Unsupported quick-sales payment target',
      ),
    };
    final rawProfiles = json['shortcut_profiles'];
    final profiles = <String, QuickSalesShortcutProfile>{};
    if (rawProfiles is Map) {
      for (final entry in rawProfiles.entries) {
        if (entry.value is Map) {
          profiles[entry.key.toString()] = QuickSalesShortcutProfile.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }
    profiles.putIfAbsent(
      'windows',
      () => QuickSalesShortcutProfile.fromJson(json),
    );
    return QuickSalesPaymentButtonModel(
      id: json['id'] ?? '',
      businessId: (json['business_id'] as num).toInt(),
      scope: (json['scope'] ?? 'user').toString(),
      ownerUserId: (json['owner_user_id'] as num?)?.toInt(),
      targetType: target,
      targetId: (json['target_id'] as num).toInt(),
      targetName: (json['target_name'] ?? '').toString(),
      label: (json['label'] ?? json['target_name'] ?? '').toString(),
      defaultShortcut: json['default_shortcut']?.toString(),
      userShortcut: json['user_shortcut']?.toString(),
      shortcut: (json['effective_shortcut'] ?? json['shortcut'])?.toString(),
      shortcutSource: (json['shortcut_source'] ?? 'none').toString(),
      shortcutConflict: json['shortcut_conflict'] == true,
      userShortcutDisabled: json['user_shortcut_disabled'] == true,
      shortcutProfiles: Map.unmodifiable(profiles),
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
