import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../services/business_api_service.dart';
import '../../utils/error_extractor.dart';
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
        SnackBarHelper.showError(
        context,
        message:
            'خطا در دریافت اطلاعات: ${ErrorExtractor.forContext(e, context)}',
      );
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
    _nameController.clear();
    
    // لاگ برای دیباگ
    print('=== DELETE BUSINESS DEBUG ===');
    print('Business Name: "$businessName"');
    print('Business Name Length: ${businessName.length}');
    print('Business Name Code Units: ${businessName.codeUnits}');
    print('Business Name Trimmed: "${businessName.trim()}"');
    print('Business Name Trimmed Length: ${businessName.trim().length}');
    
    // تایید اول: نمایش دیالوگ هشدار
    final confirm1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // هدر هشدار
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'هشدار حذف کسب و کار',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // متن هشدار
                  Text(
                    'آیا از حذف کسب و کار "$businessName" مطمئن هستید؟',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'این عمل:',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildWarningItem(Icons.delete_forever, 'غیرقابل بازگشت است (بعد از 30 روز)'),
                        const SizedBox(height: 8),
                        _buildWarningItem(Icons.data_object, 'تمام داده‌های کسب و کار را حذف می‌کند'),
                        const SizedBox(height: 8),
                        _buildWarningItem(Icons.backup, 'یک بکاپ خودکار قبل از حذف ایجاد می‌شود'),
                        const SizedBox(height: 8),
                        _buildWarningItem(Icons.restore, 'شما 30 روز فرصت دارید آن را بازیابی کنید'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'لطفاً نام کسب و کار را برای تایید نهایی وارد کنید:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: 'نام کسب و کار',
                      prefixIcon: const Icon(Icons.business),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.red.shade300, width: 2),
                      ),
                    ),
                    onChanged: (value) {
                      print('--- TextField onChanged ---');
                      print('Entered Value: "$value"');
                      print('Entered Value Length: ${value.length}');
                      print('Entered Value Code Units: ${value.codeUnits}');
                      print('Entered Value Trimmed: "${value.trim()}"');
                      print('Entered Value Trimmed Length: ${value.trim().length}');
                      print('Business Name: "$businessName"');
                      print('Business Name Trimmed: "${businessName.trim()}"');
                      print('Are Equal: ${value.trim() == businessName.trim()}');
                      print('Are Equal (no trim): ${value == businessName}');
                      print('--- End onChanged ---');
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 24),
                  // دکمه‌ها
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('انصراف'),
                      ),
                      const SizedBox(width: 8),
                      Builder(
                        builder: (btnContext) {
                          final enteredText = _nameController.text.trim();
                          final isMatch = enteredText == businessName.trim();
                          
                          // لاگ برای بررسی وضعیت دکمه
                          print('--- Button State Check ---');
                          print('Entered Text: "$enteredText"');
                          print('Entered Text Length: ${enteredText.length}');
                          print('Business Name: "$businessName"');
                          print('Business Name Trimmed: "${businessName.trim()}"');
                          print('Business Name Trimmed Length: ${businessName.trim().length}');
                          print('Is Match: $isMatch');
                          print('Button Enabled: $isMatch');
                          print('--- End Button State Check ---');
                          
                          return FilledButton.icon(
                            onPressed: isMatch
                                ? () {
                                    print('Button Pressed - Proceeding with deletion');
                                    Navigator.of(ctx).pop(true);
                                  }
                                : null,
                            icon: const Icon(Icons.delete_forever),
                            label: const Text('ادامه'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    
    if (confirm1 != true) return;
    
    // تایید دوم: نمایش دیالوگ نهایی
    final confirm2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red.shade700,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'تایید نهایی',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'آیا واقعاً می‌خواهید این کسب و کار را حذف کنید؟',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'این آخرین فرصت شماست!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('انصراف'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('بله، حذف کن'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
        SnackBarHelper.showError(
        context,
        message:
            'خطا در حذف کسب و کار: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    } finally {
      if (mounted) {
        setState(() => _confirming = false);
      }
    }
  }
  
  Widget _buildWarningItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.orange.shade700),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
  
  void _showRestrictionError(Map<String, dynamic> restrictions) {
    final errors = <Widget>[];
    if (restrictions['has_finalized_invoices'] == true) {
      errors.add(_buildErrorItem(
        Icons.receipt_long,
        '${restrictions['finalized_invoices_count']} فاکتور نهایی شده وجود دارد',
      ));
    }
    if (restrictions['has_tax_workspace_invoices'] == true) {
      errors.add(_buildErrorItem(
        Icons.workspace_premium,
        '${restrictions['tax_workspace_invoices_count']} فاکتور در کارپوشه مودیان وجود دارد',
      ));
    }
    if (restrictions['has_locked_documents'] == true) {
      errors.add(_buildErrorItem(
        Icons.lock,
        '${restrictions['locked_documents_count']} سند قفل شده وجود دارد',
      ));
    }
    
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'امکان حذف وجود ندارد',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'نمی‌توان کسب و کار را حذف کرد زیرا:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              ...errors,
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('متوجه شدم'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildErrorItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t.deleteBusiness),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_deleteInfo == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t.deleteBusiness),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: cs.error),
              const SizedBox(height: 16),
              Text(
                'خطا در دریافت اطلاعات',
                style: TextStyle(color: cs.error, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }
    
    final restrictions = _deleteInfo!['restrictions'] as Map<String, dynamic>;
    final stats = _deleteInfo!['statistics'] as Map<String, dynamic>;
    final business = _deleteInfo!['business'] as Map<String, dynamic>;
    final canDelete = restrictions['can_delete'] == true;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(t.deleteBusiness),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // هدر هشدار
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.red.shade50, Colors.orange.shade50],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.shade200, width: 2),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 56,
                    color: Colors.red.shade700,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'حذف دائمی کسب و کار',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'این عمل غیرقابل بازگشت است',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.red.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // اطلاعات کسب و کار
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.business, color: cs.primary, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'کسب و کار',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                business['name'] as String,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // آمار کسب و کار
            Text(
              'آمار کسب و کار',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.description,
                    label: 'اسناد',
                    value: '${stats['total_documents']}',
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.person,
                    label: 'اشخاص',
                    value: '${stats['total_persons']}',
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.inventory_2,
                    label: 'محصولات',
                    value: '${stats['total_products']}',
                    color: Colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // نمایش محدودیت‌ها
            if (!canDelete) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.block, color: Colors.red.shade700, size: 28),
                        const SizedBox(width: 12),
                        Text(
                          'امکان حذف وجود ندارد',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (restrictions['has_finalized_invoices'] == true)
                      _buildRestrictionItem(
                        Icons.receipt_long,
                        '${restrictions['finalized_invoices_count']} فاکتور نهایی شده',
                      ),
                    if (restrictions['has_tax_workspace_invoices'] == true)
                      _buildRestrictionItem(
                        Icons.workspace_premium,
                        '${restrictions['tax_workspace_invoices_count']} فاکتور در کارپوشه مودیان',
                      ),
                    if (restrictions['has_locked_documents'] == true)
                      _buildRestrictionItem(
                        Icons.lock,
                        '${restrictions['locked_documents_count']} سند قفل شده',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
            
            // اطلاعات مهم
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'اطلاعات مهم',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInfoItem(Icons.backup, 'بکاپ خودکار قبل از حذف ایجاد می‌شود'),
                  const SizedBox(height: 8),
                  _buildInfoItem(Icons.restore, '30 روز فرصت برای بازیابی دارید'),
                  const SizedBox(height: 8),
                  _buildInfoItem(Icons.delete_forever, 'بعد از 30 روز حذف دائمی خواهد بود'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // دکمه حذف
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: canDelete && !_confirming ? _deleteBusiness : null,
                icon: _confirming
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.delete_forever),
                label: Text(
                  _confirming ? 'در حال حذف...' : t.deleteBusiness,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRestrictionItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: Colors.red.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoItem(IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

