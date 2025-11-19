import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:hesabix_ui/services/check_service.dart';
import 'package:hesabix_ui/services/business_storage_service.dart';
import 'package:hesabix_ui/widgets/attached_files/attached_files_widget.dart';
import 'package:hesabix_ui/widgets/document/document_details_dialog.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';

class CheckDetailsDialog extends StatefulWidget {
  final int checkId;
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;
  final Map<String, dynamic>? initialData;
  final VoidCallback? onEdit;

  const CheckDetailsDialog({
    super.key,
    required this.checkId,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
    this.initialData,
    this.onEdit,
  });

  @override
  State<CheckDetailsDialog> createState() => _CheckDetailsDialogState();
}

class _CheckDetailsDialogState extends State<CheckDetailsDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final CheckService _checkService = CheckService();
  late final BusinessStorageService _storageService;
  
  @override
  void initState() {
    super.initState();
    _storageService = BusinessStorageService(ApiClient());
    _tabController = TabController(length: 3, vsync: this);
    _loadCheckData();
  }
  final AttachedFilesWidgetKey _attachedFilesKey = AttachedFilesWidgetKey();
  
  Map<String, dynamic>? _checkData;
  Map<String, dynamic>? _historyData;
  bool _loading = true;
  bool _loadingHistory = false;
  bool _uploadingFile = false;
  String? _error;


  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCheckData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _checkService.getById(widget.checkId);
      if (mounted) {
        setState(() {
          _checkData = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'خطا در بارگذاری اطلاعات چک: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadHistory() async {
    if (_historyData != null) return; // قبلاً بارگذاری شده
    
    setState(() => _loadingHistory = true);
    
    try {
      final data = await _checkService.getHistory(widget.checkId);
      if (mounted) {
        setState(() {
          _historyData = data;
          _loadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingHistory = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در بارگذاری سوابق: $e')),
        );
      }
    }
  }

  Future<void> _attachFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final file = result.files.first;
      if (file.bytes == null) return;
      
      setState(() => _uploadingFile = true);
      
      try {
        await _storageService.uploadFile(
          businessId: widget.businessId,
          fileBytes: file.bytes!,
          filename: file.name,
          moduleContext: 'checks',
          contextId: widget.checkId.toString(),
        );
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فایل با موفقیت الصاق شد'),
              backgroundColor: Colors.green,
            ),
          );
          _attachedFilesKey.refresh();
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
          setState(() => _uploadingFile = false);
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
        setState(() => _uploadingFile = false);
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
                    _buildStorageInfoRow('محدودیت کل:', '${totalLimit.toStringAsFixed(3)} GB', theme),
                    _buildStorageInfoRow('استفاده شده:', '${currentUsage.toStringAsFixed(3)} GB', theme),
                    _buildStorageInfoRow('موجود:', '${available.toStringAsFixed(3)} GB', theme),
                    const Divider(height: 24),
                    _buildStorageInfoRow('حجم مورد نیاز:', '${required.toStringAsFixed(3)} GB', theme, isHighlight: true),
                    _buildStorageInfoRow('حجم اضافی:', '${overUsage.toStringAsFixed(3)} GB', theme, isHighlight: true, isError: true),
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
              context.go('/business/${widget.businessId}/storage-files');
            },
            icon: const Icon(Icons.storage_outlined),
            label: const Text('مدیریت ذخیره‌سازی'),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageInfoRow(String label, String value, ThemeData theme, {bool isHighlight = false, bool isError = false}) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.85,
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 800),
        child: Column(
          children: [
            // هدر
            _buildHeader(theme),
            
            // تب‌ها
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.info_outline), text: 'اطلاعات چک'),
                Tab(icon: Icon(Icons.history), text: 'سوابق و اسناد'),
                Tab(icon: Icon(Icons.attach_file), text: 'فایل‌ها'),
              ],
            ),
            
            // محتوای تب‌ها
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, size: 64, color: Colors.red),
                              const SizedBox(height: 16),
                              Text(_error!),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadCheckData,
                                child: const Text('تلاش مجدد'),
                              ),
                            ],
                          ),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildInfoTab(theme),
                            _buildHistoryTab(theme),
                            _buildFilesTab(theme),
                          ],
                        ),
            ),
            
            // دکمه‌های پایین
            _buildFooter(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final checkNumber = _checkData?['check_number']?.toString() ?? 
                        widget.initialData?['check_number']?.toString() ?? 
                        '-';
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'جزئیات چک - $checkNumber',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
          if (widget.authStore.canWriteSection('checks') && widget.onEdit != null) ...[
            const SizedBox(width: 8),
            FilledButton(
              onPressed: widget.onEdit,
              child: const Text('ویرایش'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoTab(ThemeData theme) {
    if (_checkData == null && widget.initialData == null) {
      return const Center(child: Text('اطلاعاتی یافت نشد'));
    }
    
    final data = _checkData ?? widget.initialData!;
    final checkNumber = data['check_number']?.toString() ?? '-';
    final type = data['type']?.toString() ?? '';
    final personName = data['person_name']?.toString() ?? '-';
    final issueDate = _formatDate(data['issue_date']);
    final dueDate = _formatDate(data['due_date']);
    final sayadCode = data['sayad_code']?.toString();
    final bankName = data['bank_name']?.toString();
    final branchName = data['branch_name']?.toString();
    final currency = data['currency']?.toString() ?? '-';
    final status = _formatStatus(data['status']?.toString() ?? '');
    final typeLabel = type == 'received' ? 'دریافتی' : (type == 'transferred' ? 'واگذار شده' : '-');
    final amountValue = data['amount'];
    final amountStr = _formatAmount(amountValue);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryHero(
            theme: theme,
            amount: amountStr,
            currency: currency,
            status: status,
            typeLabel: typeLabel,
            checkNumber: checkNumber,
          ),
          const SizedBox(height: 24),
          Text(
            'اطلاعات کلیدی',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildInfoCard(
                theme,
                title: 'شخص مرتبط',
                value: personName,
                icon: Icons.person_outline,
              ),
              _buildInfoCard(
                theme,
                title: 'شماره چک',
                value: checkNumber,
                icon: Icons.confirmation_number,
              ),
              _buildInfoCard(
                theme,
                title: 'تاریخ صدور',
                value: issueDate,
                icon: Icons.event_available,
              ),
              _buildInfoCard(
                theme,
                title: 'تاریخ سررسید',
                value: dueDate,
                icon: Icons.event_note,
              ),
              if (sayadCode != null && sayadCode.isNotEmpty)
                _buildInfoCard(
                  theme,
                  title: 'شناسه صیاد',
                  value: sayadCode,
                  icon: Icons.qr_code_2,
                ),
              if (bankName != null && bankName.isNotEmpty)
                _buildInfoCard(
                  theme,
                  title: 'بانک',
                  value: bankName,
                  icon: Icons.account_balance,
                ),
              if (branchName != null && branchName.isNotEmpty)
                _buildInfoCard(
                  theme,
                  title: 'شعبه',
                  value: branchName,
                  icon: Icons.location_city,
                ),
            ],
          ),
          const SizedBox(height: 28),
          _buildTimelineSection(theme, issueDate, dueDate),
        ],
      ),
    );
  }

  Widget _buildSummaryHero({
    required ThemeData theme,
    required String amount,
    required String currency,
    required String status,
    required String typeLabel,
    required String checkNumber,
  }) {
    final gradient = LinearGradient(
      colors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.7),
      ],
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'چک شماره $checkNumber',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildChip(status, theme, color: Colors.white, textColor: theme.colorScheme.primary),
              const SizedBox(width: 8),
              _buildChip(typeLabel, theme, color: Colors.white.withValues(alpha: 0.2)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                currency,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    ThemeData theme, {
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineSection(ThemeData theme, String issueDate, String dueDate) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'زمان‌بندی چک',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              _buildTimelineNode(
                theme,
                title: 'صدور',
                date: issueDate,
                icon: Icons.event_available,
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.secondary,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              _buildTimelineNode(
                theme,
                title: 'سررسید',
                date: dueDate,
                icon: Icons.event_note,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineNode(ThemeData theme, {required String title, required String date, required IconData icon}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          date,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildChip(String label, ThemeData theme, {Color? color, Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor ?? theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildHistoryTab(ThemeData theme) {
    return FutureBuilder<void>(
      future: _loadHistory(),
      builder: (context, snapshot) {
        if (_loadingHistory) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final history = _historyData?['history'] as List<dynamic>? ?? [];
        final documents = _historyData?['documents'] as List<dynamic>? ?? [];
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // سوابق چک
              Text(
                'سوابق چک',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (history.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'سابقه‌ای یافت نشد',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                )
              else
                ...history.map((item) => _buildHistoryItem(item, theme)),
              
              const SizedBox(height: 32),
              
              // اسناد حسابداری
              Text(
                'اسناد حسابداری مرتبط',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (documents.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'سندی یافت نشد',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                )
              else
                ...documents.map((doc) => _buildDocumentItem(doc, theme)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item, ThemeData theme) {
    final action = item['action']?.toString() ?? 'عملیات';
    final date = item['date']?.toString() ?? '-';
    final description = item['description']?.toString() ?? '';
    final documentCode = item['document_code']?.toString();
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.history, color: theme.colorScheme.primary),
        title: Text(action),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description.isNotEmpty) Text(description),
            const SizedBox(height: 4),
            Text(
              _formatDate(date),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        trailing: documentCode != null
            ? TextButton(
                onPressed: () {
                  final docId = item['document_id'] as int?;
                  if (docId != null) {
                    showDialog(
                      context: context,
                      builder: (ctx) => DocumentDetailsDialog(
                        documentId: docId,
                        calendarController: widget.calendarController,
                      ),
                    );
                  }
                },
                child: Text(documentCode),
              )
            : null,
      ),
    );
  }

  Widget _buildDocumentItem(Map<String, dynamic> doc, ThemeData theme) {
    final code = doc['code']?.toString() ?? '-';
    final docType = doc['document_type']?.toString() ?? '-';
    final date = doc['document_date']?.toString() ?? '-';
    final amount = doc['total_amount'] ?? 0;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.description, color: theme.colorScheme.primary),
        title: Text(code),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('نوع: $docType'),
            const SizedBox(height: 4),
            Text(
              'تاریخ: ${_formatDate(date)}',
              style: theme.textTheme.bodySmall,
            ),
            if (amount != null && amount > 0)
              Text(
                'مبلغ: ${formatWithThousands(amount)}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.visibility),
          onPressed: () {
            final docId = doc['id'] as int?;
            if (docId != null) {
              showDialog(
                context: context,
                builder: (ctx) => DocumentDetailsDialog(
                  documentId: docId,
                  calendarController: widget.calendarController,
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildFilesTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AttachedFilesWidget(
                  refreshKey: _attachedFilesKey,
                  businessId: widget.businessId,
                  moduleContext: 'checks',
                  contextId: widget.checkId.toString(),
                  title: 'فایل‌های الصاق شده',
                  autoLoad: true,
                  allowDelete: widget.authStore.canWriteSection('checks'),
                ),
              ),
            ],
          ),
          if (widget.authStore.canWriteSection('checks')) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _uploadingFile ? null : _attachFile,
              icon: _uploadingFile
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.attach_file),
              label: const Text('افزودن فایل'),
            ),
          ],
        ],
      ),
    );
  }

  String _formatAmount(num? value) {
    if (value == null) return '-';
    return formatWithThousands(value);
  }

  String _formatDate(dynamic value) {
    if (value == null) return '-';
    
    if (value is String) {
      try {
        final date = DateTime.parse(value.split('T').first);
        return HesabixDateUtils.formatForDisplay(date, widget.calendarController.isJalali);
      } catch (e) {
        return value;
      }
    } else if (value is Map<String, dynamic>) {
      if (value.containsKey('date_only')) {
        return value['date_only'].toString();
      } else if (value.containsKey('formatted')) {
        final formatted = value['formatted'].toString();
        return formatted.split(' ').first;
      }
    }
    return '-';
  }

  String _formatStatus(String status) {
    switch (status) {
      case 'RECEIVED_ON_HAND': return 'در دست (دریافتی)';
      case 'TRANSFERRED_ISSUED': return 'صادر شده (پرداختنی)';
      case 'DEPOSITED': return 'سپرده به بانک';
      case 'CLEARED': return 'پاس/وصول شده';
      case 'ENDORSED': return 'واگذار شده';
      case 'RETURNED': return 'عودت شده';
      case 'BOUNCED': return 'برگشت خورده';
      case 'CANCELLED': return 'ابطال';
      default: return status.isEmpty ? '-' : status;
    }
  }
}

