import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/business_storage_service.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// صفحه مدیریت فایل‌های کسب‌وکار
class StorageFilesPage extends StatefulWidget {
  final int businessId;

  const StorageFilesPage({
    super.key,
    required this.businessId,
  });

  @override
  State<StorageFilesPage> createState() => _StorageFilesPageState();
}

class _StorageFilesPageState extends State<StorageFilesPage> with SingleTickerProviderStateMixin {
  late final BusinessStorageService _storageService;
  late final TabController _tabController;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _files = const <Map<String, dynamic>>[];
  Map<String, dynamic>? _usageInfo;
  String? _selectedModuleContext;
  bool _uploading = false;
  
  List<Map<String, dynamic>> _activeSubscriptions = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _availablePlans = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _invoices = const <Map<String, dynamic>>[];
  bool _loadingPlans = false;
  bool _loadingInvoices = false;

  @override
  void initState() {
    super.initState();
    _storageService = BusinessStorageService(ApiClient());
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == 1 && _availablePlans.isEmpty) {
          _loadPlans();
        } else if (_tabController.index == 2 && _invoices.isEmpty) {
          _loadInvoices();
        }
      }
    });
    _load();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final usageInfo = await _storageService.getUsageInfo(widget.businessId);
      final subscriptions = await _storageService.getActiveSubscriptions(widget.businessId);
      final files = await _storageService.listFiles(
        businessId: widget.businessId,
        moduleContext: _selectedModuleContext,
      );
      setState(() {
        _usageInfo = usageInfo;
        _activeSubscriptions = subscriptions;
        _files = files;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }
  
  Future<void> _loadPlans() async {
    setState(() => _loadingPlans = true);
    try {
      final plans = await _storageService.getAvailablePlans(widget.businessId);
      setState(() {
        _availablePlans = plans;
        _loadingPlans = false;
      });
    } catch (e) {
      setState(() => _loadingPlans = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در دریافت پلن‌ها: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  Future<void> _loadInvoices() async {
    setState(() => _loadingInvoices = true);
    try {
      final result = await _storageService.listInvoices(businessId: widget.businessId);
      setState(() {
        _invoices = (result['items'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        _loadingInvoices = false;
      });
    } catch (e) {
      setState(() => _loadingInvoices = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در دریافت صورتحساب‌ها: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  Future<void> _subscribeToPlan(int planId) async {
    try {
      final result = await _storageService.subscribeToPlan(
        businessId: widget.businessId,
        planId: planId,
      );
      final invoice = (result['invoice'] as Map?)?.cast<String, dynamic>();
      final invoiceStatus = invoice?['status']?.toString().toLowerCase();
      final bool isPaid = invoiceStatus == 'paid';
      
      if (mounted) {
        final message = isPaid
            ? 'پلن با موفقیت خریداری و پرداخت شد.'
            : 'اشتراک با موفقیت ایجاد شد. لطفاً صورتحساب را پرداخت کنید.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.green),
        );
        _load();
        _loadInvoices();
        if (!isPaid) {
          _tabController.animateTo(2); // رفتن به تب صورتحساب‌ها برای مشاهده پرداخت دستی
        }
      }
    } on DioException catch (e) {
      if (mounted) {
        String errorMessage = 'خطا در اشتراک';
        if (e.response?.data is Map) {
          final data = e.response!.data as Map<String, dynamic>;
          if (data.containsKey('error') && data['error'] is Map) {
            final error = data['error'] as Map;
            if (error['code'] == 'FREE_PLAN_ALREADY_ACTIVE') {
              errorMessage = error['message'] as String? ?? 'این پلن رایگان قبلاً فعال شده است';
            } else if (error['code'] == 'INSUFFICIENT_WALLET_FUNDS') {
              errorMessage = error['message'] as String? ?? 'موجودی کیف پول کافی نیست';
            } else if (error.containsKey('message')) {
              errorMessage = error['message'] as String;
            }
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در اشتراک: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  Future<void> _payInvoice(int invoiceId) async {
    try {
      await _storageService.payInvoice(
        businessId: widget.businessId,
        invoiceId: invoiceId,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('صورتحساب با موفقیت پرداخت شد'),
            backgroundColor: Colors.green,
          ),
        );
        _loadInvoices();
        _load();
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'خطا در پرداخت';
        if (e.toString().contains('insufficient_funds')) {
          errorMessage = 'موجودی کیف پول کافی نیست';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) return;

      setState(() => _uploading = true);

      try {
        await _storageService.uploadFile(
          businessId: widget.businessId,
          fileBytes: file.bytes!,
          filename: file.name,
          moduleContext: _selectedModuleContext ?? 'accounting',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فایل با موفقیت آپلود شد'),
              backgroundColor: Colors.green,
            ),
          );
          _load();
        }
      } on DioException catch (e) {
        if (mounted) {
          await _handleUploadError(e);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطا در آپلود فایل: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _uploading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _uploading = false);
      }
    }
  }
  
  Future<void> _handleUploadError(DioException e) async {
    final response = e.response;
    if (response != null && response.data is Map) {
      final data = response.data as Map<String, dynamic>;
      final error = data['error'];
      
      if (error is Map && error['code'] == 'STORAGE_LIMIT_EXCEEDED') {
        await _showStorageLimitDialog(Map<String, dynamic>.from(error));
        return;
      }
    }
    
    String errorMessage = 'خطا در آپلود فایل';
    if (response?.data is Map) {
      final data = response!.data as Map<String, dynamic>;
      if (data.containsKey('message')) {
        errorMessage = data['message'] as String;
      } else if (data.containsKey('error') && data['error'] is Map) {
        final errorMap = data['error'] as Map;
        if (errorMap.containsKey('message')) {
          errorMessage = errorMap['message'] as String;
        }
      }
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage),
        backgroundColor: Colors.red,
      ),
    );
  }
  
  Future<void> _showStorageLimitDialog(Map<String, dynamic> error) async {
    final totalLimit = (error['total_limit_gb'] as num?)?.toDouble() ?? 0.0;
    final currentUsage = (error['current_usage_gb'] as num?)?.toDouble() ?? 0.0;
    final available = (error['available_gb'] as num?)?.toDouble() ?? 0.0;
    final overUsage = (error['over_usage_gb'] as num?)?.toDouble() ?? 0.0;
    final required = (error['required_gb'] as num?)?.toDouble() ?? 0.0;
    
    final theme = Theme.of(context);
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'محدودیت ذخیره‌سازی',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                error['message'] as String? ?? 'حجم فایل از محدودیت ذخیره‌سازی تجاوز می‌کند',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('محدودیت کل:', '${totalLimit.toStringAsFixed(3)} GB', theme),
                    _buildInfoRow('استفاده شده:', '${currentUsage.toStringAsFixed(3)} GB', theme),
                    _buildInfoRow('موجود:', '${available.toStringAsFixed(3)} GB', theme),
                    const Divider(height: 24),
                    _buildInfoRow('حجم مورد نیاز:', '${required.toStringAsFixed(3)} GB', theme, isHighlight: true),
                    _buildInfoRow('حجم اضافی:', '${overUsage.toStringAsFixed(3)} GB', theme, isHighlight: true, isError: true),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'برای آپلود این فایل، لطفاً پلن ذخیره‌سازی خود را ارتقا دهید یا فایل کوچکتری انتخاب کنید.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('متوجه شدم'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _tabController.animateTo(1); // رفتن به تب پلن‌ها
            },
            icon: const Icon(Icons.storage_outlined),
            label: const Text('مشاهده پلن‌ها'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value, ThemeData theme, {bool isHighlight = false, bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
              color: isError 
                  ? Colors.red 
                  : isHighlight 
                      ? theme.colorScheme.primary 
                      : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadZip() async {
    try {
      final url = '/api/v1/business/${widget.businessId}/storage/export-zip';
      if (_selectedModuleContext != null) {
        final fullUrl = '$url?module_context=$_selectedModuleContext';
        html.window.open(fullUrl, '_blank');
      } else {
        html.window.open(url, '_blank');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در دانلود: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('فضای ذخیره‌سازی'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/business/${widget.businessId}/dashboard'),
        ),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'بروزرسانی',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('تلاش مجدد'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Header با اطلاعات استفاده
                    _buildHeader(theme),
                    // تب‌ها
                    Container(
                      color: theme.colorScheme.surface,
                      child: TabBar(
                        controller: _tabController,
                        tabs: const [
                          Tab(icon: Icon(Icons.folder), text: 'فایل‌ها'),
                          Tab(icon: Icon(Icons.storage), text: 'پلن‌ها'),
                          Tab(icon: Icon(Icons.receipt), text: 'صورتحساب‌ها'),
                        ],
                      ),
                    ),
                    // محتوای تب‌ها
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildFilesTab(theme),
                          _buildPlansTab(theme),
                          _buildInvoicesTab(theme),
                        ],
                      ),
                    ),
                  ],
                ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _uploading ? null : _uploadFile,
              icon: _uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(_uploading ? 'در حال آپلود...' : 'آپلود فایل'),
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
            )
          : null,
    );
  }

  Widget _buildHeader(ThemeData theme) {
    if (_usageInfo == null) return const SizedBox.shrink();
    
    final totalLimit = (_usageInfo!['total_limit_gb'] as num?)?.toDouble() ?? 0.0;
    final currentUsage = (_usageInfo!['current_usage_gb'] as num?)?.toDouble() ?? 0.0;
    final usagePercent = totalLimit > 0 ? (currentUsage / totalLimit * 100).clamp(0.0, 100.0) : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.storage, color: theme.colorScheme.onPrimary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${currentUsage.toStringAsFixed(2)} / ${totalLimit.toStringAsFixed(2)} GB',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${usagePercent.toStringAsFixed(1)}%',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: usagePercent / 100,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.onPrimary.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      usagePercent > 90
                          ? Colors.red.shade300
                          : usagePercent > 70
                              ? Colors.orange.shade300
                              : Colors.green.shade300,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_activeSubscriptions.isNotEmpty) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade300, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${_activeSubscriptions.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilesTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // فیلترها
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _selectedModuleContext,
                      decoration: const InputDecoration(
                        labelText: 'فیلتر بر اساس بخش',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('همه بخش‌ها')),
                        DropdownMenuItem(value: 'accounting', child: Text('حسابداری')),
                        DropdownMenuItem(value: 'tickets', child: Text('تیکت‌ها')),
                        DropdownMenuItem(value: 'business_logo', child: Text('لوگو کسب‌وکار')),
                      ],
                      onChanged: (v) {
                        setState(() => _selectedModuleContext = v);
                        _load();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _downloadZip,
                    icon: const Icon(Icons.download),
                    label: const Text('دانلود ZIP'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // لیست فایل‌ها
          if (_files.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 64,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'هیچ فایلی یافت نشد',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'برای آپلود فایل روی دکمه + کلیک کنید',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  ..._files.asMap().entries.map((entry) {
                    final file = entry.value;
                    final isLast = entry.key == _files.length - 1;
                    return Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            _getFileIcon(file['mime_type'] ?? ''),
                            color: theme.colorScheme.primary,
                          ),
                          title: Text(file['original_name'] ?? '-'),
                          subtitle: Text(
                            '${_formatFileSize(file['file_size'] ?? 0)} • ${file['module_context'] ?? '-'}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _deleteFile(file['id']),
                          ),
                        ),
                        if (!isLast) const Divider(height: 1),
                      ],
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlansTab(ThemeData theme) {
    if (_loadingPlans) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_availablePlans.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.storage_outlined,
                        size: 64,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'هیچ پلنی در دسترس نیست',
                        style: theme.textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ..._availablePlans.map((plan) {
              final planId = (plan['id'] as num?)?.toInt() ?? 0;
              final planName = plan['name'] ?? 'نامشخص';
              final storageLimit = (plan['storage_limit_gb'] as num?)?.toDouble() ?? 0.0;
              final price = (plan['price'] as num?)?.toDouble() ?? 0.0;
              final isFree = plan['is_free'] == true;
              final period = plan['period'] ?? 'monthly';
              final periodMonths = plan['period_months'] as int?;
              final currencyCode = plan['currency_code'] ?? 'IRR';
              final description = plan['description'] as String?;
              
              // بررسی اینکه آیا این پلن رایگان قبلاً فعال شده
              final isAlreadyActive = _activeSubscriptions.any((sub) => sub['plan_id'] == planId);
              
              String periodText = '';
              if (period == 'lifetime') {
                periodText = 'مادام‌العمر';
              } else if (period == 'monthly') {
                periodText = periodMonths != null ? '$periodMonths ماهه' : 'ماهانه';
              } else if (period == 'yearly') {
                periodText = periodMonths != null ? '${(periodMonths / 12).toStringAsFixed(0)} ساله' : 'سالانه';
              }
              
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 2,
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
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.storage,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  planName,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${storageLimit.toStringAsFixed(2)} GB • $periodText',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (isFree)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'رایگان',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  '${formatWithThousands(price.toInt())} $currencyCode',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (isAlreadyActive)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'این پلن در حال حاضر فعال است',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        FilledButton.icon(
                          onPressed: () => _subscribeToPlan(planId),
                          icon: const Icon(Icons.shopping_cart),
                          label: Text(isFree ? 'فعال‌سازی رایگان' : 'خرید پلن'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
  
  Widget _buildInvoicesTab(ThemeData theme) {
    if (_loadingInvoices) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_invoices.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 64,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'هیچ صورتحسابی یافت نشد',
                        style: theme.textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ..._invoices.map((invoice) {
              final invoiceId = (invoice['id'] as num?)?.toInt() ?? 0;
              final invoiceType = invoice['invoice_type'] ?? 'unknown';
              final total = (invoice['total'] as num?)?.toDouble() ?? 0.0;
              final status = invoice['status'] ?? 'pending';
              final createdAt = invoice['created_at'] ?? '';
              final currencyCode = invoice['currency_code'] ?? 'IRR';
              
              String typeText = '';
              IconData typeIcon = Icons.receipt;
              if (invoiceType == 'subscription') {
                typeText = 'اشتراک';
                typeIcon = Icons.storage;
              } else if (invoiceType == 'over_usage') {
                typeText = 'استفاده اضافی';
                typeIcon = Icons.warning;
              } else if (invoiceType == 'renewal') {
                typeText = 'تمدید';
                typeIcon = Icons.refresh;
              }
              
              Color statusColor = Colors.orange;
              String statusText = 'در انتظار پرداخت';
              if (status == 'paid') {
                statusColor = Colors.green;
                statusText = 'پرداخت شده';
              } else if (status == 'cancelled') {
                statusColor = Colors.red;
                statusText = 'لغو شده';
              }
              
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(typeIcon, color: theme.colorScheme.primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  typeText,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'تاریخ: $createdAt',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${formatWithThousands(total.toInt())} $currencyCode',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  statusText,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (status == 'pending') ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => _payInvoice(invoiceId),
                          icon: const Icon(Icons.payment),
                          label: const Text('پرداخت از کیف پول'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 40),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  IconData _getFileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.video_file;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('word') || mimeType.contains('document')) return Icons.description;
    if (mimeType.contains('excel') || mimeType.contains('spreadsheet')) return Icons.table_chart;
    return Icons.insert_drive_file;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _deleteFile(String fileId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف فایل'),
        content: const Text('آیا از حذف این فایل اطمینان دارید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _storageService.deleteFile(fileId);
      if (mounted) {
        _load();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فایل با موفقیت حذف شد'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
