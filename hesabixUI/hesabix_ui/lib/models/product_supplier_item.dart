import 'package:hesabix_ui/models/person_social_platforms.dart';

class ProductSupplierSocialContact {
  final int? id;
  final String platformKey;
  final String? customLabel;
  final String value;
  final int sortOrder;

  const ProductSupplierSocialContact({
    this.id,
    this.platformKey = 'telegram',
    this.customLabel,
    this.value = '',
    this.sortOrder = 0,
  });

  factory ProductSupplierSocialContact.fromJson(Map<String, dynamic> json) {
    return ProductSupplierSocialContact(
      id: json['id'] as int?,
      platformKey: (json['platform_key'] as String?)?.trim() ?? 'telegram',
      customLabel: json['custom_label'] as String?,
      value: (json['value'] as String?) ?? '',
      sortOrder: (json['sort_order'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toApiWrite() {
    return {
      'platform_key': platformKey,
      if (customLabel != null && customLabel!.trim().isNotEmpty) 'custom_label': customLabel!.trim(),
      'value': value.trim(),
    };
  }

  ProductSupplierSocialContact copyWith({
    int? id,
    String? platformKey,
    String? customLabel,
    String? value,
    int? sortOrder,
  }) {
    return ProductSupplierSocialContact(
      id: id ?? this.id,
      platformKey: platformKey ?? this.platformKey,
      customLabel: customLabel ?? this.customLabel,
      value: value ?? this.value,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

class ProductSupplierItem {
  final int? id;
  final int? personId;
  final String? personName;
  final String name;
  final String? website;
  final String? phone;
  final String? email;
  final String? notes;
  final bool isPreferred;
  final int sortOrder;
  final List<ProductSupplierSocialContact> socialContacts;

  const ProductSupplierItem({
    this.id,
    this.personId,
    this.personName,
    this.name = '',
    this.website,
    this.phone,
    this.email,
    this.notes,
    this.isPreferred = false,
    this.sortOrder = 0,
    this.socialContacts = const [],
  });

  bool get isEffectivelyEmpty {
    final hasName = name.trim().isNotEmpty;
    final hasPerson = personId != null;
    final hasContact = website?.trim().isNotEmpty == true ||
        phone?.trim().isNotEmpty == true ||
        email?.trim().isNotEmpty == true ||
        notes?.trim().isNotEmpty == true ||
        socialContacts.any((s) => s.value.trim().isNotEmpty);
    return !hasName && !hasPerson && !hasContact;
  }

  factory ProductSupplierItem.fromJson(Map<String, dynamic> json) {
    return ProductSupplierItem(
      id: json['id'] as int?,
      personId: json['person_id'] as int?,
      personName: json['person_name'] as String?,
      name: (json['name'] as String?) ?? '',
      website: json['website'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      notes: json['notes'] as String?,
      isPreferred: json['is_preferred'] == true,
      sortOrder: (json['sort_order'] as int?) ?? 0,
      socialContacts: (json['social_contacts'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((e) => ProductSupplierSocialContact.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toApiWrite({required int sortOrder}) {
    return {
      if (personId != null) 'person_id': personId,
      if (name.trim().isNotEmpty) 'name': name.trim(),
      if (website?.trim().isNotEmpty == true) 'website': website!.trim(),
      if (phone?.trim().isNotEmpty == true) 'phone': phone!.trim(),
      if (email?.trim().isNotEmpty == true) 'email': email!.trim(),
      if (notes?.trim().isNotEmpty == true) 'notes': notes!.trim(),
      'is_preferred': isPreferred,
      'sort_order': sortOrder,
      'social_contacts': socialContacts
          .where((s) {
            final v = s.value.trim();
            if (v.isEmpty) return false;
            if (s.platformKey == 'other' && (s.customLabel == null || s.customLabel!.trim().isEmpty)) {
              return false;
            }
            return s.platformKey.isNotEmpty;
          })
          .map((s) => s.toApiWrite())
          .toList(),
    };
  }

  ProductSupplierItem copyWith({
    int? id,
    int? personId,
    String? personName,
    String? name,
    String? website,
    String? phone,
    String? email,
    String? notes,
    bool? isPreferred,
    int? sortOrder,
    List<ProductSupplierSocialContact>? socialContacts,
    bool clearPerson = false,
  }) {
    return ProductSupplierItem(
      id: id ?? this.id,
      personId: clearPerson ? null : (personId ?? this.personId),
      personName: clearPerson ? null : (personName ?? this.personName),
      name: name ?? this.name,
      website: website ?? this.website,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      notes: notes ?? this.notes,
      isPreferred: isPreferred ?? this.isPreferred,
      sortOrder: sortOrder ?? this.sortOrder,
      socialContacts: socialContacts ?? this.socialContacts,
    );
  }

  String displayLabel() {
    final n = name.trim();
    if (n.isNotEmpty) return n;
    if (personName != null && personName!.trim().isNotEmpty) return personName!.trim();
    return 'تأمین‌کننده';
  }
}

String productSupplierPlatformLabel(String platformKey, {String? customLabel}) {
  return personSocialPlatformLabelFa(platformKey, customLabel: customLabel);
}
