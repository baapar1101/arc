import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/business_storage_service.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;
import '../../utils/snackbar_helper.dart';

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
  late final ApiClient _apiClient;
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
    _apiClient = ApiClient();
    _storageService = BusinessStorageService(_apiClient);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFFF9800).withValues(alpha: 0.15),
                const Color(0xFFFF9800).withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFFF9800),
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'محدودیت ذخیره‌سازی',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                error['message'] as String? ?? 'حجم فایل از محدودیت ذخیره‌سازی تجاوز می‌کند',
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('محدودیت کل:', '${totalLimit.toStringAsFixed(3)} GB', theme),
                    const SizedBox(height: 12),
                    _buildInfoRow('استفاده شده:', '${currentUsage.toStringAsFixed(3)} GB', theme),
                    const SizedBox(height: 12),
                    _buildInfoRow('موجود:', '${available.toStringAsFixed(3)} GB', theme),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(),
                    ),
                    _buildInfoRow('حجم مورد نیاز:', '${required.toStringAsFixed(3)} GB', theme, isHighlight: true),
                    const SizedBox(height: 12),
                    _buildInfoRow('حجم اضافی:', '${overUsage.toStringAsFixed(3)} GB', theme, isHighlight: true, isError: true),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      color: theme.colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'برای آپلود این فایل، لطفاً پلن ذخیره‌سازی خود را ارتقا دهید.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('متوجه شدم'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _tabController.animateTo(1);
            },
            icon: const Icon(Icons.upgrade_rounded),
            label: const Text('مشاهده پلن‌ها'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 2,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value, ThemeData theme, {bool isHighlight = false, bool isError = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isError
                    ? const Color(0xFFEF5350)
                    : isHighlight
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w600,
            color: isError
                ? const Color(0xFFEF5350)
                : isHighlight
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Future<void> _downloadZip() async {
    try {
      // نمایش پیغام در حال دانلود
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('در حال آماده‌سازی فایل ZIP...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final baseUrl = '/api/v1/business/${widget.businessId}/storage/export-zip';
      final queryParams = _selectedModuleContext != null 
          ? {'module_context': _selectedModuleContext}
          : null;
      
      if (kIsWeb) {
        // دانلود فایل از طریق API با authentication header
        final response = await _apiClient.get<List<int>>(
          baseUrl,
          query: queryParams,
          responseType: ResponseType.bytes,
          options: Options(
            headers: {
              'Accept': 'application/zip',
            },
          ),
        );

        if (response.statusCode == 200 && response.data != null) {
          // ذخیره فایل در مرورگر
          await web_utils.saveBytesAsFileWeb(
            response.data!,
            'hesabix_files_${widget.businessId}.zip',
            mimeType: 'application/zip',
          );
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('فایل ZIP با موفقیت دانلود شد'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('دانلود فایل فقط در نسخه وب پشتیبانی می‌شود'),
            ),
          );
        }
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
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_upload_rounded, size: 24),
              label: Text(
                _uploading ? 'در حال آپلود...' : 'آپلود فایل',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  letterSpacing: 0.5,
                ),
              ),
              backgroundColor: _uploading
                  ? theme.colorScheme.primary.withValues(alpha: 0.7)
                  : theme.colorScheme.primary,
              foregroundColor: Colors.white,
              elevation: _uploading ? 2 : 6,
              extendedPadding: const EdgeInsets.symmetric(horizontal: 24),
            )
          : null,
    );
  }

  Widget _buildHeader(ThemeData theme) {
    if (_usageInfo == null) return const SizedBox.shrink();
    
    final totalLimit = (_usageInfo!['total_limit_gb'] as num?)?.toDouble() ?? 0.0;
    final currentUsage = (_usageInfo!['current_usage_gb'] as num?)?.toDouble() ?? 0.0;
    final usagePercent = totalLimit > 0 ? (currentUsage / totalLimit * 100).clamp(0.0, 100.0) : 0.0;
    final available = totalLimit - currentUsage;

    // رنگ‌های بهبود یافته بر اساس درصد استفاده
    Color progressColor;
    Color progressBgColor;
    IconData statusIcon;
    
    if (usagePercent > 90) {
      progressColor = const Color(0xFFEF5350); // Red 400
      progressBgColor = const Color(0xFFFFCDD2); // Red 100
      statusIcon = Icons.warning_rounded;
    } else if (usagePercent > 70) {
      progressColor = const Color(0xFFFF9800); // Orange 500
      progressBgColor = const Color(0xFFFFE0B2); // Orange 100
      statusIcon = Icons.info_rounded;
    } else {
      progressColor = const Color(0xFF66BB6A); // Green 400
      progressBgColor = const Color(0xFFC8E6C9); // Green 100
      statusIcon = Icons.check_circle_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.9),
            theme.colorScheme.primaryContainer,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                // آیکون اصلی با container زیبا
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.cloud_circle_rounded,
                    color: theme.colorScheme.onPrimary,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 20),
                // اطلاعات استفاده
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'فضای ذخیره‌سازی',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimary.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            currentUsage.toStringAsFixed(2),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                          Text(
                            ' / ${totalLimit.toStringAsFixed(2)} GB',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // درصد استفاده با badge زیبا
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onPrimary,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        statusIcon,
                        color: progressColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${usagePercent.toStringAsFixed(0)}%',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Progress bar بهبود یافته
            Stack(
              children: [
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: usagePercent / 100,
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          progressColor,
                          progressColor.withValues(alpha: 0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: progressColor.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // اطلاعات تکمیلی
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildHeaderInfoChip(
                  theme,
                  Icons.check_circle_outline_rounded,
                  'موجود',
                  '${available.toStringAsFixed(2)} GB',
                ),
                if (_activeSubscriptions.isNotEmpty)
                  _buildHeaderInfoChip(
                    theme,
                    Icons.workspace_premium_rounded,
                    'اشتراک فعال',
                    '${_activeSubscriptions.length}',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderInfoChip(ThemeData theme, IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.onPrimary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: theme.colorScheme.onPrimary, size: 18),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
                  fontSize: 10,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
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
          // فیلترها و actions با طراحی بهبود یافته
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.filter_list_rounded,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'فیلتر و عملیات',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    // Dropdown filter
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 200, maxWidth: 300),
                      child: DropdownButtonFormField<String?>(
                        value: _selectedModuleContext,
                        decoration: InputDecoration(
                          labelText: 'فیلتر بر اساس بخش',
                          prefixIcon: Icon(
                            Icons.category_rounded,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          isDense: true,
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
                    // دکمه دانلود
                    OutlinedButton.icon(
                      onPressed: _downloadZip,
                      icon: const Icon(Icons.download_rounded, size: 20),
                      label: const Text('دانلود ZIP'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    // دکمه فایل منیجر
                    FilledButton.icon(
                      onPressed: () {
                        context.go('/business/${widget.businessId}/storage-files/file-manager');
                      },
                      icon: const Icon(Icons.folder_open_rounded, size: 20),
                      label: const Text('فایل منیجر'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // لیست فایل‌ها با طراحی card-based
          if (_files.isEmpty)
            Container(
              padding: const EdgeInsets.all(64),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.1),
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.cloud_upload_rounded,
                        size: 64,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'هیچ فایلی یافت نشد',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'برای شروع، اولین فایل خود را آپلود کنید',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _uploadFile,
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: const Text('آپلود فایل'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        side: BorderSide(color: theme.colorScheme.primary, width: 2),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 350,
                childAspectRatio: 1.4,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: _files.length,
              itemBuilder: (context, index) {
                final file = _files[index];
                final mimeType = file['mime_type'] ?? '';
                final isImage = mimeType.startsWith('image/');
                final fileName = file['original_name'] ?? '-';
                final fileSize = file['file_size'] ?? 0;
                final moduleContext = file['module_context'] ?? '-';
                
                // رنگ بر اساس نوع فایل
                Color fileColor;
                IconData fileIcon = _getFileIcon(mimeType);
                
                if (isImage) {
                  fileColor = const Color(0xFF42A5F5); // Blue
                } else if (mimeType.contains('pdf')) {
                  fileColor = const Color(0xFFEF5350); // Red
                } else if (mimeType.contains('word') || mimeType.contains('document')) {
                  fileColor = const Color(0xFF42A5F5); // Blue
                } else if (mimeType.contains('excel') || mimeType.contains('spreadsheet')) {
                  fileColor = const Color(0xFF66BB6A); // Green
                } else if (mimeType.startsWith('video/')) {
                  fileColor = const Color(0xFF9C27B0); // Purple
                } else {
                  fileColor = const Color(0xFF78909C); // Blue Grey
                }

                return Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // هدر فایل با آیکون
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                fileColor.withValues(alpha: 0.15),
                                fileColor.withValues(alpha: 0.05),
                              ],
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: fileColor.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: fileColor.withValues(alpha: 0.3),
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  fileIcon,
                                  color: fileColor,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                fileName,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        // اطلاعات فایل
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.data_usage_rounded,
                                          size: 16,
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            _formatFileSize(fileSize),
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.category_rounded,
                                          size: 16,
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            moduleContext,
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                // دکمه حذف
                                OutlinedButton.icon(
                                  onPressed: () => _deleteFile(file),
                                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                  label: const Text('حذف'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFEF5350),
                                    side: BorderSide(
                                      color: const Color(0xFFEF5350).withValues(alpha: 0.5),
                                    ),
                                    minimumSize: const Size(double.infinity, 36),
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
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
            Container(
              padding: const EdgeInsets.all(64),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.1),
                  width: 2,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                            theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                          ],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.inventory_2_rounded,
                        size: 64,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'هیچ پلنی در دسترس نیست',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'در حال حاضر پلن ذخیره‌سازی جدیدی موجود نیست',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
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
              
              // طراحی بهبود یافته کارت پلن
              final bool isPopular = storageLimit >= 50.0 && !isFree;
              
              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: isAlreadyActive
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF66BB6A).withValues(alpha: 0.1),
                            const Color(0xFF4CAF50).withValues(alpha: 0.05),
                          ],
                        )
                      : (isFree
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                theme.colorScheme.surfaceContainerHighest,
                                theme.colorScheme.surfaceContainer,
                              ],
                            )
                          : LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                                theme.colorScheme.surface,
                              ],
                            )),
                  border: Border.all(
                    color: isAlreadyActive
                        ? const Color(0xFF66BB6A)
                        : (isPopular
                            ? theme.colorScheme.primary.withValues(alpha: 0.5)
                            : theme.colorScheme.outline.withValues(alpha: 0.2)),
                    width: isAlreadyActive || isPopular ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isAlreadyActive || isPopular)
                          ? theme.colorScheme.primary.withValues(alpha: 0.15)
                          : Colors.black.withValues(alpha: 0.05),
                      blurRadius: isAlreadyActive || isPopular ? 16 : 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // هدر کارت با آیکون و badge
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // آیکون بزرگ و زیبا
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: isFree
                                        ? [
                                            const Color(0xFF66BB6A),
                                            const Color(0xFF4CAF50),
                                          ]
                                        : [
                                            theme.colorScheme.primary,
                                            theme.colorScheme.primary.withValues(alpha: 0.7),
                                          ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (isFree ? const Color(0xFF66BB6A) : theme.colorScheme.primary)
                                          .withValues(alpha: 0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  isFree ? Icons.card_giftcard_rounded : Icons.cloud_upload_rounded,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 16),
                              // نام و جزئیات پلن
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      planName,
                                      style: theme.textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.storage_rounded,
                                          size: 16,
                                          color: theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${storageLimit.toStringAsFixed(0)} GB',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Icon(
                                          Icons.schedule_rounded,
                                          size: 16,
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          periodText,
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          
                          // قیمت با طراحی جذاب
                          if (!isFree) ...[
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    formatWithThousands(price.toInt()),
                                    style: theme.textTheme.headlineLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    currencyCode,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // توضیحات
                          if (description != null && description.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 18,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      description,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),

                          // دکمه action یا status
                          if (isAlreadyActive)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF66BB6A), Color(0xFF4CAF50)],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF66BB6A).withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 24),
                                  const SizedBox(width: 12),
                                  Text(
                                    'پلن فعال شما',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            FilledButton.icon(
                              onPressed: () => _subscribeToPlan(planId),
                              icon: Icon(isFree ? Icons.card_giftcard_rounded : Icons.shopping_cart_rounded),
                              label: Text(
                                isFree ? 'دریافت رایگان' : 'خرید پلن',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 56),
                                backgroundColor: isFree ? const Color(0xFF66BB6A) : theme.colorScheme.primary,
                                foregroundColor: Colors.white,
                                elevation: 4,
                                shadowColor: (isFree ? const Color(0xFF66BB6A) : theme.colorScheme.primary)
                                    .withValues(alpha: 0.4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Badge برای محبوب یا رایگان
                    if (isPopular && !isAlreadyActive)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                theme.colorScheme.primary,
                                theme.colorScheme.primary.withValues(alpha: 0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: Colors.white, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                'محبوب',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (isFree && !isAlreadyActive)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF66BB6A), Color(0xFF4CAF50)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF66BB6A).withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                'رایگان',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
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
            Container(
              padding: const EdgeInsets.all(64),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.1),
                  width: 2,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF66BB6A).withValues(alpha: 0.2),
                            const Color(0xFF66BB6A).withValues(alpha: 0.05),
                          ],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.receipt_long_rounded,
                        size: 64,
                        color: const Color(0xFF66BB6A),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'صورتحسابی وجود ندارد',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'تمام صورتحساب‌های شما پرداخت شده است',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
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
              
              // طراحی بهبود یافته کارت صورتحساب
              Color borderColor;
              if (status == 'paid') {
                borderColor = const Color(0xFF66BB6A);
              } else if (status == 'cancelled') {
                borderColor = const Color(0xFFEF5350);
              } else {
                borderColor = const Color(0xFFFF9800);
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      // نوار رنگی سمت راست
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 5,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                borderColor,
                                borderColor.withValues(alpha: 0.6),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // آیکون با container زیبا
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        borderColor.withValues(alpha: 0.2),
                                        borderColor.withValues(alpha: 0.1),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: borderColor.withValues(alpha: 0.3),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Icon(
                                    typeIcon,
                                    color: borderColor,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // اطلاعات اصلی
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        typeText,
                                        style: theme.textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_today_rounded,
                                            size: 14,
                                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            createdAt,
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Status badge بهبود یافته
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        borderColor,
                                        borderColor.withValues(alpha: 0.8),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: borderColor.withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        status == 'paid'
                                            ? Icons.check_circle_rounded
                                            : status == 'cancelled'
                                                ? Icons.cancel_rounded
                                                : Icons.schedule_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        statusText,
                                        style: theme.textTheme.labelLarge?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // قیمت با طراحی جذاب
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.colorScheme.outline.withValues(alpha: 0.1),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.payments_rounded,
                                        color: theme.colorScheme.primary,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'مبلغ:',
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        formatWithThousands(total.toInt()),
                                        style: theme.textTheme.headlineSmall?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        currencyCode,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // دکمه پرداخت برای صورتحساب‌های pending
                            if (status == 'pending') ...[
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () => _payInvoice(invoiceId),
                                icon: const Icon(Icons.account_balance_wallet_rounded),
                                label: const Text(
                                  'پرداخت از کیف پول',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 50),
                                  backgroundColor: const Color(0xFF66BB6A),
                                  foregroundColor: Colors.white,
                                  elevation: 3,
                                  shadowColor: const Color(0xFF66BB6A).withValues(alpha: 0.4),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ],
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

  Future<void> _deleteFile(Map<String, dynamic> file) async {
    final confirmed = await _showDeleteConfirmation(file);
    if (confirmed != true) return;

    try {
      await _storageService.deleteFile(
        businessId: widget.businessId,
        fileId: file['id'] as String,
      );
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

  Future<bool?> _showDeleteConfirmation(Map<String, dynamic> file) async {
    List<Map<String, dynamic>> dependencies = <Map<String, dynamic>>[];
    String? usageError;
    try {
      final usage = await _storageService.getFileUsage(
        businessId: widget.businessId,
        fileId: file['id'] as String,
      );
      dependencies = (usage['dependencies'] as List?)
              ?.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          <Map<String, dynamic>>[];
    } catch (e) {
      usageError = '$e';
    }

    if (!mounted) return false;

    final theme = Theme.of(context);

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف فایل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'آیا از حذف "${file['original_name'] ?? ''}" اطمینان دارید؟',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (usageError != null)
              Text(
                'خطا در دریافت وابستگی‌ها: $usageError',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
              )
            else if (dependencies.isEmpty)
              Text(
                'این فایل در هیچ بخشی استفاده نشده است.',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              Text(
                'این فایل در بخش‌های زیر استفاده شده است:',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 150,
                child: ListView.builder(
                  itemCount: dependencies.length,
                  itemBuilder: (context, index) {
                    final dep = dependencies[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.link, color: theme.colorScheme.primary, size: 20),
                      title: Text(dep['description'] as String? ?? '-', style: theme.textTheme.bodyMedium),
                      subtitle: Text(
                        '${dep['module'] ?? ''} • ${dep['entity_type'] ?? ''} • ${dep['entity_id'] ?? ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'با حذف فایل، لینک‌های بالا به صورت خودکار پاک می‌شوند.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
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
  }
}
