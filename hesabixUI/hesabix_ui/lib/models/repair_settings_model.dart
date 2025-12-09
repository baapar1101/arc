/// مدل تنظیمات تعمیرگاه
class RepairShopSettings {
  final int id;
  final int businessId;
  final String receiptCodeFormat; // random, sequential, custom
  final String receiptCodePrefix;
  final bool autoSendSmsOnReceive;
  final bool autoSendSmsOnStatusChange;
  final bool autoSendEmailOnReceive;
  final bool autoSendEmailOnStatusChange;
  final Map<String, dynamic> smsTemplates;
  final Map<String, dynamic> emailTemplates;
  final int? defaultServiceProductId;
  final int? defaultWarehouseId;
  final Map<String, dynamic> extraSettings;

  RepairShopSettings({
    required this.id,
    required this.businessId,
    required this.receiptCodeFormat,
    required this.receiptCodePrefix,
    required this.autoSendSmsOnReceive,
    required this.autoSendSmsOnStatusChange,
    required this.autoSendEmailOnReceive,
    required this.autoSendEmailOnStatusChange,
    required this.smsTemplates,
    required this.emailTemplates,
    this.defaultServiceProductId,
    this.defaultWarehouseId,
    required this.extraSettings,
  });

  factory RepairShopSettings.fromJson(Map<String, dynamic> json) {
    return RepairShopSettings(
      id: json['id'] as int,
      businessId: json['business_id'] as int,
      receiptCodeFormat: json['receipt_code_format'] as String,
      receiptCodePrefix: json['receipt_code_prefix'] as String,
      autoSendSmsOnReceive: json['auto_send_sms_on_receive'] as bool,
      autoSendSmsOnStatusChange: json['auto_send_sms_on_status_change'] as bool,
      autoSendEmailOnReceive: json['auto_send_email_on_receive'] as bool,
      autoSendEmailOnStatusChange:
          json['auto_send_email_on_status_change'] as bool,
      smsTemplates: (json['sms_templates'] as Map<String, dynamic>?) ?? {},
      emailTemplates: (json['email_templates'] as Map<String, dynamic>?) ?? {},
      defaultServiceProductId: json['default_service_product_id'] as int?,
      defaultWarehouseId: json['default_warehouse_id'] as int?,
      extraSettings: (json['extra_settings'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_id': businessId,
      'receipt_code_format': receiptCodeFormat,
      'receipt_code_prefix': receiptCodePrefix,
      'auto_send_sms_on_receive': autoSendSmsOnReceive,
      'auto_send_sms_on_status_change': autoSendSmsOnStatusChange,
      'auto_send_email_on_receive': autoSendEmailOnReceive,
      'auto_send_email_on_status_change': autoSendEmailOnStatusChange,
      'sms_templates': smsTemplates,
      'email_templates': emailTemplates,
      'default_service_product_id': defaultServiceProductId,
      'default_warehouse_id': defaultWarehouseId,
      'extra_settings': extraSettings,
    };
  }

  RepairShopSettings copyWith({
    int? id,
    int? businessId,
    String? receiptCodeFormat,
    String? receiptCodePrefix,
    bool? autoSendSmsOnReceive,
    bool? autoSendSmsOnStatusChange,
    bool? autoSendEmailOnReceive,
    bool? autoSendEmailOnStatusChange,
    Map<String, dynamic>? smsTemplates,
    Map<String, dynamic>? emailTemplates,
    int? defaultServiceProductId,
    int? defaultWarehouseId,
    Map<String, dynamic>? extraSettings,
  }) {
    return RepairShopSettings(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      receiptCodeFormat: receiptCodeFormat ?? this.receiptCodeFormat,
      receiptCodePrefix: receiptCodePrefix ?? this.receiptCodePrefix,
      autoSendSmsOnReceive: autoSendSmsOnReceive ?? this.autoSendSmsOnReceive,
      autoSendSmsOnStatusChange:
          autoSendSmsOnStatusChange ?? this.autoSendSmsOnStatusChange,
      autoSendEmailOnReceive:
          autoSendEmailOnReceive ?? this.autoSendEmailOnReceive,
      autoSendEmailOnStatusChange:
          autoSendEmailOnStatusChange ?? this.autoSendEmailOnStatusChange,
      smsTemplates: smsTemplates ?? this.smsTemplates,
      emailTemplates: emailTemplates ?? this.emailTemplates,
      defaultServiceProductId:
          defaultServiceProductId ?? this.defaultServiceProductId,
      defaultWarehouseId: defaultWarehouseId ?? this.defaultWarehouseId,
      extraSettings: extraSettings ?? this.extraSettings,
    );
  }

  /// لیبل فرمت کد به فارسی
  String get receiptCodeFormatLabel {
    switch (receiptCodeFormat) {
      case 'sequential':
        return 'ترتیبی';
      case 'random':
        return 'تصادفی';
      case 'custom':
        return 'سفارشی';
      default:
        return receiptCodeFormat;
    }
  }
}



