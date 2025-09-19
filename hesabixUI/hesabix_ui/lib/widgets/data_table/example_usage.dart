import 'package:flutter/material.dart';
import 'data_table_config.dart';
import 'data_table_widget.dart';

/// Example usage of DataTableWidget with column settings in multiple pages
class DataTableExampleUsage {
  
  /// Page 1: Users Management
  static Widget buildUsersTable() {
    return DataTableWidget<User>(
      config: DataTableConfig<User>(
        endpoint: '/api/users',
        title: 'مدیریت کاربران',
        columns: [
          TextColumn('id', 'شناسه'),
          TextColumn('firstName', 'نام'),
          TextColumn('lastName', 'نام خانوادگی'),
          TextColumn('email', 'ایمیل'),
          DateColumn('createdAt', 'تاریخ عضویت'),
          ActionColumn('actions', 'عملیات', actions: [
            DataTableAction(
              icon: Icons.edit,
              label: 'ویرایش',
              onTap: (user) => print('Edit user: ${user.id}'),
            ),
          ]),
        ],
        // تنظیمات ستون فعال است (پیش‌فرض)
        enableColumnSettings: true,
        // دکمه تنظیمات ستون نمایش داده می‌شود (پیش‌فرض)
        showColumnSettingsButton: true,
        // شناسه منحصر به فرد: data_table_column_settings__api_users
      ),
      fromJson: (json) => User.fromJson(json),
    );
  }

  /// Page 2: Orders Management
  static Widget buildOrdersTable() {
    return DataTableWidget<Order>(
      config: DataTableConfig<Order>(
        endpoint: '/api/orders',
        title: 'مدیریت سفارشات',
        columns: [
          TextColumn('id', 'شماره سفارش'),
          TextColumn('customerName', 'نام مشتری'),
          NumberColumn('amount', 'مبلغ'),
          DateColumn('orderDate', 'تاریخ سفارش'),
          TextColumn('status', 'وضعیت'),
          ActionColumn('actions', 'عملیات', actions: [
            DataTableAction(
              icon: Icons.visibility,
              label: 'مشاهده',
              onTap: (order) => print('View order: ${order.id}'),
            ),
          ]),
        ],
        // شناسه منحصر به فرد: data_table_column_settings__api_orders
      ),
      fromJson: (json) => Order.fromJson(json),
    );
  }

  /// Page 3: Financial Reports
  static Widget buildReportsTable() {
    return DataTableWidget<Report>(
      config: DataTableConfig<Report>(
        endpoint: '/api/reports',
        tableId: 'financial_reports', // شناسه سفارشی
        title: 'گزارش‌های مالی',
        columns: [
          TextColumn('id', 'شناسه گزارش'),
          TextColumn('title', 'عنوان'),
          NumberColumn('income', 'درآمد'),
          NumberColumn('expense', 'هزینه'),
          NumberColumn('profit', 'سود'),
          DateColumn('reportDate', 'تاریخ گزارش'),
        ],
        // شناسه منحصر به فرد: data_table_column_settings_financial_reports
      ),
      fromJson: (json) => Report.fromJson(json),
    );
  }

  /// Page 4: Products Management
  static Widget buildProductsTable() {
    return DataTableWidget<Product>(
      config: DataTableConfig<Product>(
        endpoint: '/api/products',
        title: 'مدیریت محصولات',
        columns: [
          TextColumn('id', 'کد محصول'),
          TextColumn('name', 'نام محصول'),
          TextColumn('category', 'دسته‌بندی'),
          NumberColumn('price', 'قیمت'),
          NumberColumn('stock', 'موجودی'),
          DateColumn('createdAt', 'تاریخ ایجاد'),
        ],
        // شناسه منحصر به فرد: data_table_column_settings__api_products
      ),
      fromJson: (json) => Product.fromJson(json),
    );
  }

  /// Page 5: System Logs
  static Widget buildLogsTable() {
    return DataTableWidget<Log>(
      config: DataTableConfig<Log>(
        endpoint: '/api/logs',
        tableId: 'system_logs', // شناسه سفارشی
        title: 'لاگ‌های سیستم',
        columns: [
          TextColumn('id', 'شناسه'),
          TextColumn('level', 'سطح'),
          TextColumn('message', 'پیام'),
          DateColumn('timestamp', 'زمان'),
          TextColumn('source', 'منبع'),
        ],
        // شناسه منحصر به فرد: data_table_column_settings_system_logs
      ),
      fromJson: (json) => Log.fromJson(json),
    );
  }
}

/// Example data models
class User {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final DateTime createdAt;

  User({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      firstName: json['firstName']?.toString() ?? '',
      lastName: json['lastName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class Order {
  final String id;
  final String customerName;
  final double amount;
  final DateTime orderDate;
  final String status;

  Order({
    required this.id,
    required this.customerName,
    required this.amount,
    required this.orderDate,
    required this.status,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id']?.toString() ?? '',
      customerName: json['customerName']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      orderDate: DateTime.tryParse(json['orderDate']?.toString() ?? '') ?? DateTime.now(),
      status: json['status']?.toString() ?? '',
    );
  }
}

class Report {
  final String id;
  final String title;
  final double income;
  final double expense;
  final double profit;
  final DateTime reportDate;

  Report({
    required this.id,
    required this.title,
    required this.income,
    required this.expense,
    required this.profit,
    required this.reportDate,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      income: (json['income'] as num?)?.toDouble() ?? 0.0,
      expense: (json['expense'] as num?)?.toDouble() ?? 0.0,
      profit: (json['profit'] as num?)?.toDouble() ?? 0.0,
      reportDate: DateTime.tryParse(json['reportDate']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class Product {
  final String id;
  final String name;
  final String category;
  final double price;
  final int stock;
  final DateTime createdAt;

  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.stock,
    required this.createdAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class Log {
  final String id;
  final String level;
  final String message;
  final DateTime timestamp;
  final String source;

  Log({
    required this.id,
    required this.level,
    required this.message,
    required this.timestamp,
    required this.source,
  });

  factory Log.fromJson(Map<String, dynamic> json) {
    return Log(
      id: json['id']?.toString() ?? '',
      level: json['level']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      source: json['source']?.toString() ?? '',
    );
  }
}
