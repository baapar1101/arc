class AccountTreeNode {
  final int id;
  final String code;
  final String name;
  final String? accountType;
  final int? parentId;
  final int? level;
  final List<AccountTreeNode> children;

  const AccountTreeNode({
    required this.id,
    required this.code,
    required this.name,
    this.accountType,
    this.parentId,
    this.level,
    this.children = const [],
  });

  factory AccountTreeNode.fromJson(Map<String, dynamic> json) {
    return AccountTreeNode(
      id: json['id'] as int,
      code: json['code'] as String,
      name: json['name'] as String,
      accountType: json['account_type'] as String?,
      parentId: json['parent_id'] as int?,
      level: json['level'] as int?,
      children: (json['children'] as List<dynamic>?)
          ?.map((child) => AccountTreeNode.fromJson(child as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'account_type': accountType,
      'parent_id': parentId,
      'level': level,
      'children': children.map((child) => child.toJson()).toList(),
    };
  }

  /// بررسی می‌کند که آیا این حساب فرزند دارد یا نه
  bool get hasChildren => children.isNotEmpty;

  /// دریافت تمام حساب‌های قابل انتخاب (بدون فرزند) به صورت تخت
  List<AccountTreeNode> getSelectableAccounts() {
    List<AccountTreeNode> selectable = [];
    
    if (!hasChildren) {
      selectable.add(this);
    } else {
      for (final child in children) {
        selectable.addAll(child.getSelectableAccounts());
      }
    }
    
    return selectable;
  }

  /// دریافت تمام حساب‌ها به صورت تخت (شامل همه سطوح)
  List<AccountTreeNode> getAllAccounts() {
    List<AccountTreeNode> all = [this];
    
    for (final child in children) {
      all.addAll(child.getAllAccounts());
    }
    
    return all;
  }

  /// جستجو در درخت حساب‌ها بر اساس نام یا کد
  List<AccountTreeNode> searchAccounts(String query) {
    final lowerQuery = query.toLowerCase();
    return getAllAccounts().where((account) {
      return account.name.toLowerCase().contains(lowerQuery) ||
             account.code.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  @override
  String toString() {
    return '$code - $name';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AccountTreeNode && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
