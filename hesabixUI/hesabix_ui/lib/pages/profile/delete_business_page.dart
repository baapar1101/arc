import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../services/business_api_service.dart';
import '../../utils/snackbar_helper.dart';

class DeleteBusinessPage extends StatefulWidget {
  final int businessId;
  
  const DeleteBusinessPage({
    super.key,
    required this.businessId,
  });

  @override
  State<DeleteBusinessPage> createState() => _DeleteBusinessPageState();
}

class _DeleteBusinessPageState extends State<DeleteBusinessPage> {
  Map<String, dynamic>? _deleteInfo;
  bool _loading = true;
  bool _confirming = false;
  final TextEditingController _nameController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _loadDeleteInfo();
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
  
  Future<void> _loadDeleteInfo() async {
    try {
      final info = await BusinessApiService.getBusinessDeleteInfo(widget.businessId);
      if (mounted) {
        setState(() {
          _deleteInfo = info;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        SnackBarHelper.showError(context, message: 'خطا در دریافت اطلاعات: $e');
      }
    }
  }
  
  Future<void> _deleteBusiness() async {
    if (_deleteInfo == null) return;
    
    final restrictions = _deleteInfo!['restrictions'] as Map<String, dynamic>;
    if (restrictions['can_delete'] != true) {
      _showRestrictionError(restrictions);
      return;
    }
    
    final businessName = _deleteInfo!['business']['name'] as String;
    
    // تایید اول: نمایش دیالوگ هشدار
    final confirm1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ هشدار حذف کسب و کار'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('آیا از حذف کسب و کار "$businessName" مطمئن هستید؟'),
              const SizedBox(height: 16),
              const Text('این عمل:'),
              const SizedBox(height: 8),
              const Text('• غیرقابل بازگشت است (بعد از 30 روز)'),
              const Text('• تمام داده‌های کسب و کار را حذف می‌کند'),
              const Text('• یک بکاپ خودکار قبل از حذف ایجاد می‌شود'),
              const Text('• شما 30 روز فرصت دارید آن را بازیابی کنید'),
              const SizedBox(height: 16),
              const Text('لطفاً نام کسب و کار را برای تایید نهایی وارد کنید:'),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'نام کسب و کار',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton.tonal(
            onPressed: () {
              if (_nameController.text.trim() == businessName) {
                Navigator.of(ctx).pop(true);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('نام کسب و کار مطابقت ندارد')),
                );
              }
            },
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    
    if (confirm1 != true) return;
    
    // تایید دوم: نمایش دیالوگ نهایی
    final confirm2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ تایید نهایی'),
        content: const Text('آیا واقعاً می‌خواهید این کسب و کار را حذف کنید؟\n\nاین آخرین فرصت شماست!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('بله، حذف کن'),
          ),
        ],
      ),
    );
    
    if (confirm2 != true) return;
    
    // انجام حذف
    setState(() => _confirming = true);
    try {
      await BusinessApiService.deleteBusiness(businessId: widget.businessId);
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: 'کسب و کار با موفقیت حذف شد. شما 30 روز فرصت دارید آن را بازیابی کنید.',
        );
        // هدایت به صفحه لیست کسب و کارها
        context.go('/user/profile/businesses');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در حذف کسب و کار: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _confirming = false);
      }
    }
  }
  
  void _showRestrictionError(Map<String, dynamic> restrictions) {
    final errors = <String>[];
    if (restrictions['has_finalized_invoices'] == true) {
      errors.add('${restrictions['finalized_invoices_count']} فاکتور نهایی شده وجود دارد');
    }
    if (restrictions['has_tax_workspace_invoices'] == true) {
      errors.add('${restrictions['tax_workspace_invoices_count']} فاکتور در کارپوشه مودیان وجود دارد');
    }
    if (restrictions['has_locked_documents'] == true) {
      errors.add('${restrictions['locked_documents_count']} سند قفل شده وجود دارد');
    }
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ امکان حذف وجود ندارد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('نمی‌توان کسب و کار را حذف کرد زیرا:'),
            const SizedBox(height: 8),
            ...errors.map((e) => Text('• $e')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('متوجه شدم'),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(t.deleteBusiness)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_deleteInfo == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t.deleteBusiness)),
        body: const Center(child: Text('خطا در دریافت اطلاعات')),
      );
    }
    
    final restrictions = _deleteInfo!['restrictions'] as Map<String, dynamic>;
    final stats = _deleteInfo!['statistics'] as Map<String, dynamic>;
    final business = _deleteInfo!['business'] as Map<String, dynamic>;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(t.deleteBusiness),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // نمایش اطلاعات کسب و کار
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      business['name'] as String,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    const Text('آمار کسب و کار:'),
                    const SizedBox(height: 8),
                    Text('• ${stats['total_documents']} سند'),
                    Text('• ${stats['total_persons']} شخص'),
                    Text('• ${stats['total_products']} محصول'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // نمایش محدودیت‌ها
            if (!restrictions['can_delete'])
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '⚠️ امکان حذف وجود ندارد',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      if (restrictions['has_finalized_invoices'] == true)
                        Text('• ${restrictions['finalized_invoices_count']} فاکتور نهایی شده'),
                      if (restrictions['has_tax_workspace_invoices'] == true)
                        Text('• ${restrictions['tax_workspace_invoices_count']} فاکتور در کارپوشه مودیان'),
                      if (restrictions['has_locked_documents'] == true)
                        Text('• ${restrictions['locked_documents_count']} سند قفل شده'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            // دکمه حذف
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: restrictions['can_delete'] && !_confirming ? _deleteBusiness : null,
                style: FilledButton.styleFrom(
                  foregroundColor: Colors.red,
                  backgroundColor: Colors.red.shade50,
                ),
                child: _confirming
                    ? const CircularProgressIndicator()
                    : Text(t.deleteBusiness),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

