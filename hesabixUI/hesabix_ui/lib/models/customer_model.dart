class Customer {
  final int id;
  final String name;
  final String? code;
  final String? phone;
  final String? email;
  final String? address;
  final bool isActive;
  final DateTime? createdAt;

  const Customer({
    required this.id,
    required this.name,
    this.code,
    this.phone,
    this.email,
    this.address,
    this.isActive = true,
    this.createdAt,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as int,
      name: json['name'] as String,
      code: json['code'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null 
          ? DateTime.tryParse(json['created_at'].toString()) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'phone': phone,
      'email': email,
      'address': address,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Customer && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => name;
}
