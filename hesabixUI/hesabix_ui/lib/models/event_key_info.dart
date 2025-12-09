import 'package:flutter/material.dart';

/// اطلاعات کلید رویداد برای نمایش در فرم قالب ناتیفیکیشن
class EventKeyInfo {
  final String key;
  final String category; // 'auth', 'support', 'invoice', etc.
  final String title; // نام فارسی
  final String description; // توضیح کامل
  final String when; // زمان ارسال
  final String recipient; // گیرنده
  final List<String> availableParams; // پارامترهای موجود
  final Map<String, String> paramExamples; // مثال‌های پارامترها
  final IconData icon;

  const EventKeyInfo({
    required this.key,
    required this.category,
    required this.title,
    required this.description,
    required this.when,
    required this.recipient,
    required this.availableParams,
    required this.paramExamples,
    required this.icon,
  });
}

/// لیست کلیدهای رویداد از پیش تعریف‌شده
const List<EventKeyInfo> eventKeysList = [
  EventKeyInfo(
    key: 'auth.otp_login',
    category: 'auth',
    title: 'ورود با OTP',
    description: 'این رویداد هنگام ارسال کد یک‌بارمصرف برای ورود کاربر فعال می‌شود.',
    when: 'هنگام درخواست ورود با OTP',
    recipient: 'کاربر درخواست‌دهنده',
    availableParams: ['code', 'expiry_minutes'],
    paramExamples: {
      'code': '31524',
      'expiry_minutes': '5',
    },
    icon: Icons.lock_outline,
  ),
  EventKeyInfo(
    key: 'auth.password_reset',
    category: 'auth',
    title: 'فراموشی کلمه عبور',
    description: 'این رویداد هنگام درخواست بازیابی کلمه عبور توسط کاربر فعال می‌شود.',
    when: 'هنگام درخواست فراموشی کلمه عبور',
    recipient: 'کاربر درخواست‌دهنده',
    availableParams: ['token', 'user_name', 'user_email', 'expiry_hours'],
    paramExamples: {
      'token': 'reset_abc123xyz',
      'user_name': 'علی احمدی',
      'user_email': 'ali@example.com',
      'expiry_hours': '24',
    },
    icon: Icons.lock_reset,
  ),
  EventKeyInfo(
    key: 'support.ticket_created',
    category: 'support',
    title: 'ایجاد تیکت جدید',
    description: 'این رویداد هنگام ایجاد تیکت جدید توسط کاربر فعال می‌شود.',
    when: 'هنگام ایجاد تیکت جدید',
    recipient: 'تمام اپراتورهای پشتیبانی',
    availableParams: [
      'ticket_id',
      'ticket_title',
      'user_name',
      'user_email',
      'category',
      'priority',
      'message',
    ],
    paramExamples: {
      'ticket_id': '123',
      'ticket_title': 'مشکل در پرداخت',
      'user_name': 'علی احمدی',
      'user_email': 'ali@example.com',
      'category': 'پشتیبانی',
      'priority': 'بالا',
      'message': 'متن پیام تیکت...',
    },
    icon: Icons.support_agent,
  ),
  EventKeyInfo(
    key: 'support.user_reply',
    category: 'support',
    title: 'پاسخ کاربر به تیکت',
    description: 'این رویداد هنگام پاسخ کاربر به تیکت موجود فعال می‌شود.',
    when: 'هنگام پاسخ کاربر به تیکت',
    recipient: 'اپراتور تخصیص‌یافته یا تمام اپراتورها',
    availableParams: [
      'ticket_id',
      'ticket_title',
      'user_name',
      'user_email',
      'message_preview',
    ],
    paramExamples: {
      'ticket_id': '123',
      'ticket_title': 'مشکل در پرداخت',
      'user_name': 'علی احمدی',
      'user_email': 'ali@example.com',
      'message_preview': 'لطفاً بررسی کنید...',
    },
    icon: Icons.reply,
  ),
  EventKeyInfo(
    key: 'support.operator_reply',
    category: 'support',
    title: 'پاسخ اپراتور به تیکت',
    description: 'این رویداد هنگام پاسخ اپراتور به تیکت فعال می‌شود.',
    when: 'هنگام پاسخ اپراتور به تیکت',
    recipient: 'کاربر صاحب تیکت',
    availableParams: [
      'ticket_id',
      'ticket_title',
      'operator_name',
      'message_preview',
    ],
    paramExamples: {
      'ticket_id': '123',
      'ticket_title': 'مشکل در پرداخت',
      'operator_name': 'محمد رضایی',
      'message_preview': 'مشکل شما بررسی شد...',
    },
    icon: Icons.support,
  ),
];

/// حالت ورودی کلید رویداد
enum EventKeyInputMode {
  selection, // انتخاب از لیست
  custom, // تایپ دستی
}

/// تابع کمکی برای ساخت مثال قالب
String buildExampleTemplate(EventKeyInfo info) {
  if (info.key == 'auth.otp_login') {
    return 'کد ورود شما: {{ code }}\nاین کد تا {{ expiry_minutes }} دقیقه اعتبار دارد.';
  } else if (info.key == 'auth.password_reset') {
    return 'سلام {{ user_name }} عزیز،\nبرای بازیابی کلمه عبور خود از لینک زیر استفاده کنید:\n{{ token }}\nاین لینک تا {{ expiry_hours }} ساعت معتبر است.';
  } else if (info.key == 'support.ticket_created') {
    return 'تیکت جدید: {{ ticket_title }}\nکاربر: {{ user_name }}\nشماره تیکت: #{{ ticket_id }}';
  } else if (info.key == 'support.user_reply') {
    return 'کاربر {{ user_name }} به تیکت #{{ ticket_id }} پاسخ داد:\n{{ message_preview }}';
  } else if (info.key == 'support.operator_reply') {
    return 'اپراتور {{ operator_name }} به تیکت #{{ ticket_id }} پاسخ داد:\n{{ message_preview }}';
  }
  return '{{ param1 }}\n{{ param2 }}';
}

