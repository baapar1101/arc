import 'package:flutter/material.dart';
import 'identity_inquiry_dialog.dart';

/// مثال استفاده از دیالوگ استعلام اطلاعات هویتی
/// Example usage of Identity Inquiry Dialog
/// 
/// این فایل نمونه‌هایی از نحوه استفاده از دیالوگ را نشان می‌دهد

class IdentityInquiryDialogExample extends StatelessWidget {
  final int businessId;

  const IdentityInquiryDialogExample({
    super.key,
    required this.businessId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مثال دیالوگ استعلام هویتی'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // دکمه برای نمایش دیالوگ به صورت ساده
            ElevatedButton.icon(
              onPressed: () => _showDialog(context),
              icon: const Icon(Icons.person_search),
              label: const Text('استعلام اطلاعات هویتی'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // دکمه برای نمایش دیالوگ و دریافت نتیجه
            ElevatedButton.icon(
              onPressed: () => _showDialogWithResult(context),
              icon: const Icon(Icons.search),
              label: const Text('استعلام و دریافت نتیجه'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
            
            const SizedBox(height: 40),
            
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'این دیالوگ شامل:\n'
                '• فرم ورودی زیبا و کاربرپسند\n'
                '• اعتبارسنجی کامل کد ملی و تاریخ تولد\n'
                '• نمایش نتایج با طراحی مدرن\n'
                '• پشتیبانی کامل از دو زبان فارسی و انگلیسی\n'
                '• مدیریت خطاها با پیام‌های واضح\n'
                '• قابلیت کپی اطلاعات',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// نمایش دیالوگ به صورت ساده
  Future<void> _showDialog(BuildContext context) async {
    await IdentityInquiryDialog.show(
      context,
      businessId: businessId,
    );
  }

  /// نمایش دیالوگ و دریافت نتیجه
  Future<void> _showDialogWithResult(BuildContext context) async {
    final result = await IdentityInquiryDialog.show(
      context,
      businessId: businessId,
    );
    
    if (result != null && context.mounted) {
      // استفاده از نتیجه
      final responseBody = result['result']?['response_body'] as Map<String, dynamic>?;
      final data = responseBody?['data'] as Map<String, dynamic>?;
      final matched = data?['matched'] as bool? ?? false;
      
      if (matched) {
        final firstName = data?['first_name']?.toString() ?? '';
        final lastName = data?['last_name']?.toString() ?? '';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('استعلام موفق: $firstName $lastName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }
}

// ========================================
// روش‌های مختلف استفاده در پروژه
// ========================================

/// 1. استفاده در یک صفحه یا ویجت
/// 
/// ```dart
/// ElevatedButton(
///   onPressed: () async {
///     await IdentityInquiryDialog.show(
///       context,
///       businessId: currentBusinessId,
///     );
///   },
///   child: const Text('استعلام هویتی'),
/// )
/// ```

/// 2. استفاده در منوی استعلامات
///
/// ```dart
/// ListTile(
///   leading: const Icon(Icons.person_search),
///   title: const Text('استعلام اطلاعات هویتی'),
///   subtitle: const Text('Identity Inquiry'),
///   onTap: () async {
///     await IdentityInquiryDialog.show(
///       context,
///       businessId: widget.businessId,
///     );
///   },
/// )
/// ```

/// 3. استفاده با دریافت و پردازش نتیجه
///
/// ```dart
/// final result = await IdentityInquiryDialog.show(
///   context,
///   businessId: businessId,
/// );
/// 
/// if (result != null) {
///   // پردازش نتیجه
///   final data = result['result']?['response_body']?['data'];
///   if (data != null) {
///     // ذخیره در دیتابیس یا استفاده در فرم
///     setState(() {
///       customerName = '${data['first_name']} ${data['last_name']}';
///       customerNationalCode = data['national_code'];
///     });
///   }
/// }
/// ```

/// 4. استفاده در Floating Action Button
///
/// ```dart
/// floatingActionButton: FloatingActionButton.extended(
///   onPressed: () => IdentityInquiryDialog.show(
///     context,
///     businessId: businessId,
///   ),
///   icon: const Icon(Icons.person_search),
///   label: const Text('استعلام هویتی'),
/// )
/// ```

/// 5. استفاده در AppBar Actions
///
/// ```dart
/// actions: [
///   IconButton(
///     icon: const Icon(Icons.person_search),
///     tooltip: 'استعلام اطلاعات هویتی',
///     onPressed: () => IdentityInquiryDialog.show(
///       context,
///       businessId: businessId,
///     ),
///   ),
/// ]
/// ```


