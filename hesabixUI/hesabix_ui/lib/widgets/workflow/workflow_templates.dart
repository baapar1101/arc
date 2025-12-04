import 'package:flutter/material.dart';
import '../../models/workflow_editor_models.dart';

/// کلاس برای مدیریت Workflow Templates
class WorkflowTemplates {
  /// دریافت لیست templateهای موجود
  static List<WorkflowTemplate> getTemplates() {
    return [
      // Template برای فاکتور فروش
      WorkflowTemplate(
        id: 'invoice_sales_notification',
        name: 'اطلاع‌رسانی فاکتور فروش',
        description: 'بعد از ایجاد فاکتور فروش، ایمیل و تلگرام ارسال می‌شود',
        triggerType: 'invoice.sales.created',
        category: 'فاکتور',
        icon: Icons.receipt,
        workflowData: {
          'nodes': [
            {
              'id': 'trigger_1',
              'type': 'trigger',
              'label': 'ایجاد فاکتور فروش',
              'key': 'invoice.sales.created',
              'position': {'x': 100, 'y': 100},
              'config': {
                'trigger_type': 'invoice.sales.created',
                'enabled': true,
                'min_amount': null,
                'status_filter': ['confirmed'],
              },
            },
            {
              'id': 'action_1',
              'type': 'action',
              'label': 'ارسال ایمیل',
              'key': 'send_email',
              'position': {'x': 100, 'y': 250},
              'config': {
                'action_type': 'send_email',
                'to': '\$trigger_1.person_email',
                'subject': 'فاکتور فروش شماره \$trigger_1.invoice_number',
                'body': 'فاکتور فروش شما با مبلغ \$trigger_1.total_amount ایجاد شد.',
              },
            },
            {
              'id': 'action_2',
              'type': 'action',
              'label': 'ارسال تلگرام',
              'key': 'send_telegram',
              'position': {'x': 100, 'y': 400},
              'config': {
                'action_type': 'send_telegram',
                'user_id': '\$trigger_1.user_id',
                'message': 'فاکتور فروش شما ایجاد شد. شماره: \$trigger_1.invoice_number',
              },
            },
          ],
          'connections': [
            {'source': 'trigger_1', 'target': 'action_1'},
            {'source': 'action_1', 'target': 'action_2'},
          ],
        },
      ),
      
      // Template برای موجودی کم
      WorkflowTemplate(
        id: 'inventory_low_alert',
        name: 'هشدار موجودی کم',
        description: 'زمانی که موجودی محصول کم شود، notification ارسال می‌شود',
        triggerType: 'inventory.low',
        category: 'موجودی',
        icon: Icons.inventory_2,
        workflowData: {
          'nodes': [
            {
              'id': 'trigger_1',
              'type': 'trigger',
              'label': 'موجودی کم',
              'key': 'inventory.low',
              'position': {'x': 100, 'y': 100},
              'config': {
                'trigger_type': 'inventory.low',
                'enabled': true,
                'threshold_type': 'fixed',
                'threshold_value': 10,
              },
            },
            {
              'id': 'action_1',
              'type': 'action',
              'label': 'ایجاد Notification',
              'key': 'create_notification',
              'position': {'x': 100, 'y': 250},
              'config': {
                'action_type': 'create_notification',
                'event_key': 'inventory.low',
                'title': 'هشدار موجودی کم',
                'message': 'موجودی محصول \$trigger_1.product_name به \$trigger_1.current_quantity رسیده است.',
                'channels': ['inapp', 'email'],
                'priority': 'high',
              },
            },
          ],
          'connections': [
            {'source': 'trigger_1', 'target': 'action_1'},
          ],
        },
      ),
      
      // Template برای دریافت/پرداخت
      WorkflowTemplate(
        id: 'receipt_payment_log',
        name: 'ثبت لاگ دریافت/پرداخت',
        description: 'بعد از ثبت دریافت/پرداخت، لاگ ثبت می‌شود',
        triggerType: 'receipt_payment.created',
        category: 'مالی',
        icon: Icons.payment,
        workflowData: {
          'nodes': [
            {
              'id': 'trigger_1',
              'type': 'trigger',
              'label': 'ایجاد دریافت/پرداخت',
              'key': 'receipt_payment.created',
              'position': {'x': 100, 'y': 100},
              'config': {
                'trigger_type': 'receipt_payment.created',
                'enabled': true,
                'min_amount': 1000000, // فقط برای مبالغ بالای 1 میلیون
              },
            },
            {
              'id': 'action_1',
              'type': 'action',
              'label': 'ثبت لاگ',
              'key': 'log',
              'position': {'x': 100, 'y': 250},
              'config': {
                'action_type': 'log',
                'level': 'info',
                'message': 'دریافت/پرداخت ثبت شد: \$trigger_1.amount',
                'include_context': true,
              },
            },
          ],
          'connections': [
            {'source': 'trigger_1', 'target': 'action_1'},
          ],
        },
      ),
      
      // Template برای شخص جدید
      WorkflowTemplate(
        id: 'person_welcome',
        name: 'خوش‌آمدگویی شخص جدید',
        description: 'بعد از ایجاد شخص جدید، پیام خوش‌آمدگویی ارسال می‌شود',
        triggerType: 'person.created',
        category: 'اشخاص',
        icon: Icons.person_add,
        workflowData: {
          'nodes': [
            {
              'id': 'trigger_1',
              'type': 'trigger',
              'label': 'ایجاد شخص',
              'key': 'person.created',
              'position': {'x': 100, 'y': 100},
              'config': {
                'trigger_type': 'person.created',
                'enabled': true,
                'person_type': 'customer',
              },
            },
            {
              'id': 'action_1',
              'type': 'action',
              'label': 'ارسال ایمیل خوش‌آمدگویی',
              'key': 'send_email',
              'position': {'x': 100, 'y': 250},
              'config': {
                'action_type': 'send_email',
                'to': '\$trigger_1.email',
                'subject': 'خوش آمدید به سیستم ما',
                'body': 'سلام \$trigger_1.name، به سیستم ما خوش آمدید!',
              },
            },
          ],
          'connections': [
            {'source': 'trigger_1', 'target': 'action_1'},
          ],
        },
      ),
    ];
  }

  /// دریافت template بر اساس ID
  static WorkflowTemplate? getTemplateById(String id) {
    return getTemplates().firstWhere(
      (template) => template.id == id,
      orElse: () => throw StateError('Template not found'),
    );
  }

  /// دریافت templateهای یک دسته
  static List<WorkflowTemplate> getTemplatesByCategory(String category) {
    return getTemplates().where((t) => t.category == category).toList();
  }

  /// دریافت دسته‌های موجود
  static List<String> getCategories() {
    return getTemplates().map((t) => t.category).toSet().toList();
  }
}

/// مدل یک Workflow Template
class WorkflowTemplate {
  final String id;
  final String name;
  final String description;
  final String triggerType;
  final String category;
  final IconData icon;
  final Map<String, dynamic> workflowData;

  const WorkflowTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.triggerType,
    required this.category,
    required this.icon,
    required this.workflowData,
  });
}

