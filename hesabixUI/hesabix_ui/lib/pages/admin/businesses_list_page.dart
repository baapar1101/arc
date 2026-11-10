import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/widgets/data_table/data_table.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/utils/date_formatters.dart' as date_formatters;
import 'package:hesabix_ui/services/business_api_service.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import '../../core/api_client.dart';
import '../../services/document_monetization_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

class BusinessesListPage extends StatefulWidget {
  const BusinessesListPage({super.key});

  @override
  State<BusinessesListPage> createState() => _BusinessesListPageState();
}

class _BusinessesListPageState extends State<BusinessesListPage> {
  CalendarController? _calendarController;

  @override
  void initState() {
    super.initState();
    _initCalendarController();
  }

  Future<void> _initCalendarController() async {
    try {
      final cc = await CalendarController.load();
      if (mounted) {
        setState(() => _calendarController = cc);
      }
    } catch (_) {
      // Calendar controller not required for this page
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminCompactScaffold(
      title: adminTx(context, 'کسب‌وکارها', 'Businesses'),
      subtitle: adminTx(context, 'فهرست و مدیریت کسب‌وکارهای سیستم', 'List and manage system businesses'),
      body: DataTableWidget<Map<String, dynamic>>(
        config: DataTableConfig<Map<String, dynamic>>(
          endpoint: '/api/v1/admin/businesses/list',
          showTableIcon: false,
          columns: [
            TextColumn(
              'id',
              adminTx(context, 'شناسه', 'ID'),
              width: ColumnWidth.small,
              sortable: true,
            ),
            TextColumn(
              'name',
              adminTx(context, 'نام کسب‌وکار', 'Business name'),
              width: ColumnWidth.large,
              sortable: true,
              searchable: true,
            ),
            TextColumn(
              'business_type',
              adminTx(context, 'نوع کسب‌وکار', 'Business type'),
              width: ColumnWidth.medium,
              sortable: true,
            ),
            TextColumn(
              'business_field',
              adminTx(context, 'زمینه فعالیت', 'Field'),
              width: ColumnWidth.medium,
              sortable: true,
            ),
            CustomColumn(
              'owner',
              adminTx(context, 'مالک', 'Owner'),
              width: ColumnWidth.large,
              builder: (item, index) {
                final owner = item['owner'] as Map<String, dynamic>?;
                if (owner == null) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      adminTx(context, 'نامشخص', 'Unknown'),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                }
                
                final fullName = owner['full_name'] as String? ?? 
                                '${owner['first_name'] ?? ''} ${owner['last_name'] ?? ''}'.trim();
                final email = owner['email'] as String?;
                final mobile = owner['mobile'] as String?;
                
                // تمیز کردن شماره موبایل (حذف + و اضافه کردن 0 در صورت نیاز)
                String? cleanMobile;
                if (mobile != null && mobile.isNotEmpty) {
                  cleanMobile = mobile.replaceAll('+', '');
                  if (cleanMobile.startsWith('98') && cleanMobile.length == 12) {
                    cleanMobile = '0${cleanMobile.substring(2)}';
                  } else if (!cleanMobile.startsWith('0') && cleanMobile.length == 10) {
                    cleanMobile = '0$cleanMobile';
                  }
                }
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (fullName.isNotEmpty)
                        Text(
                          fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (email != null && email.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (cleanMobile != null && cleanMobile.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          cleanMobile,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            TextColumn(
              'phone',
              adminTx(context, 'تلفن', 'Phone'),
              width: ColumnWidth.medium,
              searchable: true,
              formatter: (item) => item['phone'] as String? ?? '-',
            ),
            TextColumn(
              'mobile',
              adminTx(context, 'موبایل', 'Mobile'),
              width: ColumnWidth.medium,
              searchable: true,
              formatter: (item) => item['mobile'] as String? ?? '-',
            ),
            TextColumn(
              'national_id',
              adminTx(context, 'شناسه ملی', 'National ID'),
              width: ColumnWidth.medium,
              searchable: true,
              formatter: (item) => item['national_id'] as String? ?? '-',
            ),
            TextColumn(
              'province',
              adminTx(context, 'استان', 'Province'),
              width: ColumnWidth.medium,
              sortable: true,
              formatter: (item) {
                final province = item['province'] as String?;
                final city = item['city'] as String?;
                if (province == null && city == null) return '-';
                if (province != null && city != null) return '$province، $city';
                return province ?? city ?? '-';
              },
            ),
            CustomColumn(
              'status',
              adminTx(context, 'وضعیت', 'Status'),
              width: ColumnWidth.medium,
              builder: (item, index) {
                final isDeleted = item['is_deleted'] as bool? ?? false;
                final isDeletionPending = item['is_deletion_pending'] as bool? ?? false;
                
                if (isDeleted || isDeletionPending) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: SemanticColorResolver.warning(context).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        adminTx(context, 'در حال حذف', 'Deleting'),
                        style: TextStyle(
                          color: SemanticColorResolver.warning(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: SemanticColorResolver.positive(context).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      adminTx(context, 'فعال', 'Active'),
                      style: TextStyle(
                        color: SemanticColorResolver.positive(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
            DateColumn(
              'created_at',
              adminTx(context, 'تاریخ ایجاد', 'Created'),
              width: ColumnWidth.medium,
              sortable: true,
              showTime: false,
            ),
          ],
          searchFields: ['name', 'phone', 'mobile', 'national_id', 'economic_id'],
          defaultSortBy: 'created_at',
          defaultSortDesc: true,
          defaultPageSize: 20,
          pageSizeOptions: const [10, 20, 50, 100],
          showSearch: true,
          showFilters: true,
          showPagination: true,
          enableSorting: true,
          enableGlobalSearch: true,
          showRefreshButton: true,
          showBackButton: false,
          emptyStateMessage: adminTx(context, 'کسب‌وکاری یافت نشد', 'No businesses found'),
          tableId: 'admin_businesses',
          onRowTap: (item) {
            // جلوگیری از ورود به کسب و کار حذف شده
            final isDeleted = item['is_deleted'] as bool? ?? false;
            if (isDeleted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    adminTx(
                      context,
                      'این کسب‌وکار حذف شده است. از جزئیات می‌توانید آن را بازیابی کنید.',
                      'This business is deleted. Open its details to restore it.',
                    ),
                  ),
                  backgroundColor: SemanticColorResolver.warning(context),
                ),
              );
              return;
            }
            _showBusinessDetailsDialog(context, item);
          },
        
        expandBodyHeightToFitRows: true,),
        fromJson: (json) => Map<String, dynamic>.from(json),
        calendarController: _calendarController,
      ),
    );
  }

  void _showBusinessDetailsDialog(BuildContext context, Map<String, dynamic> business) {
    showDialog(
      context: context,
      builder: (context) => _BusinessDetailsDialog(business: business),
    );
  }
}

class _BusinessDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> business;

  const _BusinessDetailsDialog({required this.business});

  @override
  State<_BusinessDetailsDialog> createState() => _BusinessDetailsDialogState();
}

class _BusinessDetailsDialogState extends State<_BusinessDetailsDialog> {
  bool _isRestoring = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final businessName = widget.business['name'] as String? ?? adminTx(context, 'نامشخص', 'Unknown');
    final isDeleted = widget.business['is_deleted'] as bool? ?? false;
    final isDeletionPending = widget.business['is_deletion_pending'] as bool? ?? false;
    final businessId = widget.business['id'] as int?;

    return Dialog(
      child: SizedBox(
        width: MediaQuery.of(context).size.width > 900 ? 800 : 600,
        height: MediaQuery.of(context).size.height > 700 ? 650 : 550,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(Icons.business, size: 18, color: theme.colorScheme.onSurface),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          businessName,
                          style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
                        ),
                        if (isDeleted || isDeletionPending)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: SemanticColorResolver.warning(context).withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                adminTx(context, 'در حال حذف', 'Deleting'),
                                style: TextStyle(
                                  color: SemanticColorResolver.warning(context),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isDeleted || isDeletionPending) ...[
                    SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isRestoring ? null : () => _handleRestore(context),
                      icon: _isRestoring
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Icon(Icons.restore, size: 18),
                      label: Text(_isRestoring ? adminTx(context, 'در حال بازیابی…', 'Restoring…') : adminTx(context, 'بازیابی', 'Restore')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SemanticColorResolver.positive(context),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                  IconButton(
                    icon: Icon(Icons.close, color: theme.colorScheme.onSurface),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Tabs
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    TabBar(
                      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      unselectedLabelStyle: const TextStyle(fontSize: 12),
                      tabs: [
                        Tab(text: adminTx(context, 'اطلاعات کسب‌وکار', 'Business')),
                        Tab(text: adminTx(context, 'کیف پول', 'Wallet')),
                        Tab(text: adminTx(context, 'سیاست‌ها و پکیج‌ها', 'Policies')),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildBusinessInfoTab(theme),
                          _WalletTab(businessId: widget.business['id'] as int),
                          _BusinessPoliciesTab(businessId: widget.business['id'] as int),
                        ],
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
  }

  Future<void> _handleRestore(BuildContext context) async {
    if (widget.business['id'] == null) return;
    final pageContext = context;

    final confirmed = await showDialog<bool>(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(adminTx(pageContext, 'بازیابی کسب‌وکار', 'Restore business')),
        content: Text(
          adminTx(
            pageContext,
            'کسب‌وکار «${widget.business['name']}» بازیابی شود؟',
            'Restore “${widget.business['name']}”?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(adminTx(pageContext, 'انصراف', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: SemanticColorResolver.positive(dialogContext)),
            child: Text(adminTx(pageContext, 'بازیابی', 'Restore')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isRestoring = true;
    });

    try {
      await BusinessApiService.restoreBusiness(widget.business['id'] as int);

      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(
          content: Text(adminTx(pageContext, 'کسب‌وکار بازیابی شد', 'Business restored')),
          backgroundColor: SemanticColorResolver.positive(context),
        ),
      );
      Navigator.of(pageContext).pop();
    } catch (e) {
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(
          content: Text(
            '${adminTx(pageContext, 'خطا در بازیابی کسب‌وکار', 'Could not restore the business')}: ${ErrorExtractor.forContext(e, pageContext)}',
          ),
          backgroundColor: SemanticColorResolver.negative(context),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRestoring = false;
        });
      }
    }
  }

  Widget _buildBusinessInfoTab(ThemeData theme) {
    final owner = widget.business['owner'] as Map<String, dynamic>?;
    final defaultCurrency = widget.business['default_currency'] as Map<String, dynamic>?;
    final currencies = widget.business['currencies'] as List<dynamic>? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(theme, adminTx(context, 'اطلاعات اصلی', 'Basics')),
          _buildInfoCard(
            theme,
            [
              _buildInfoRow(theme, adminTx(context, 'شناسه', 'ID'), widget.business['id']?.toString() ?? '-'),
              _buildInfoRow(theme, adminTx(context, 'نام کسب‌وکار', 'Business name'), widget.business['name'] ?? '-'),
              _buildInfoRow(theme, adminTx(context, 'نوع کسب‌وکار', 'Business type'), widget.business['business_type'] ?? '-'),
              _buildInfoRow(theme, adminTx(context, 'زمینه فعالیت', 'Field'), widget.business['business_field'] ?? '-'),
            ],
          ),
          const SizedBox(height: 16),
          
          if (owner != null) ...[
            _buildSectionTitle(theme, adminTx(context, 'اطلاعات مالک', 'Owner')),
            _buildInfoCard(
              theme,
              [
                _buildInfoRow(theme, adminTx(context, 'نام کامل', 'Full name'), owner['full_name'] ?? '-'),
                _buildInfoRow(theme, adminTx(context, 'ایمیل', 'Email'), owner['email'] ?? '-'),
                _buildInfoRow(theme, adminTx(context, 'موبایل', 'Mobile'), _cleanMobileNumber(owner['mobile'])),
              ],
            ),
            const SizedBox(height: 16),
          ],
          
          _buildSectionTitle(theme, adminTx(context, 'اطلاعات تماس', 'Contact')),
          _buildInfoCard(
            theme,
            [
              _buildInfoRow(theme, adminTx(context, 'تلفن', 'Phone'), widget.business['phone'] ?? '-'),
              _buildInfoRow(theme, adminTx(context, 'موبایل', 'Mobile'), widget.business['mobile'] ?? '-'),
              _buildInfoRow(theme, adminTx(context, 'آدرس', 'Address'), widget.business['address'] ?? '-'),
              if (widget.business['province'] != null || widget.business['city'] != null)
                _buildInfoRow(
                  theme,
                  adminTx(context, 'موقعیت', 'Location'),
                  '${widget.business['province'] ?? ''}${widget.business['province'] != null && widget.business['city'] != null ? '، ' : ''}${widget.business['city'] ?? ''}',
                ),
              _buildInfoRow(theme, adminTx(context, 'کد پستی', 'Postal code'), widget.business['postal_code'] ?? '-'),
            ],
          ),
          const SizedBox(height: 16),
          
          _buildSectionTitle(theme, adminTx(context, 'اطلاعات ثبت', 'Registration')),
          _buildInfoCard(
            theme,
            [
              _buildInfoRow(theme, adminTx(context, 'شناسه ملی', 'National ID'), widget.business['national_id'] ?? '-'),
              _buildInfoRow(theme, adminTx(context, 'شماره ثبت', 'Registration number'), widget.business['registration_number'] ?? '-'),
              _buildInfoRow(theme, adminTx(context, 'شناسه اقتصادی', 'Economic ID'), widget.business['economic_id'] ?? '-'),
              _buildInfoRow(
                theme,
                adminTx(context, 'تاریخ ایجاد', 'Created'),
                date_formatters.DateFormatters.formatServerDateTime(widget.business['created_at']),
              ),
              _buildInfoRow(
                theme,
                adminTx(context, 'آخرین بروزرسانی', 'Updated'),
                date_formatters.DateFormatters.formatServerDateTime(widget.business['updated_at']),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          if (defaultCurrency != null || currencies.isNotEmpty) ...[
            _buildSectionTitle(theme, adminTx(context, 'اطلاعات ارز', 'Currencies')),
            _buildInfoCard(
              theme,
              [
                if (defaultCurrency != null)
                  _buildInfoRow(
                    theme,
                    adminTx(context, 'ارز پیش‌فرض', 'Default currency'),
                    '${defaultCurrency['title']} (${defaultCurrency['symbol']})',
                  ),
                if (currencies.isNotEmpty)
                  _buildInfoRow(
                    theme,
                    adminTx(context, 'ارزهای فعال', 'Active currencies'),
                    currencies
                        .map((c) => '${c['title']} (${c['symbol']})')
                        .join('، '),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.primary),
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme, List<Widget> children) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _cleanMobileNumber(dynamic mobile) {
    if (mobile == null || mobile.toString().isEmpty) return '-';
    String cleaned = mobile.toString().replaceAll('+', '');
    if (cleaned.startsWith('98') && cleaned.length == 12) {
      cleaned = '0${cleaned.substring(2)}';
    } else if (!cleaned.startsWith('0') && cleaned.length == 10) {
      cleaned = '0$cleaned';
    }
    return cleaned;
  }
}

class _WalletTab extends StatefulWidget {
  final int businessId;

  const _WalletTab({required this.businessId});

  @override
  State<_WalletTab> createState() => _WalletTabState();
}

class _WalletTabState extends State<_WalletTab> {
  Map<String, dynamic>? _walletData;
  bool _isLoading = false;
  bool _isLoadingWallet = true;
  String? _errorMessage;

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _reasonController = TextEditingController();
  final _giftConfirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadWalletData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _reasonController.dispose();
    _giftConfirmController.dispose();
    super.dispose();
  }

  Future<void> _loadWalletData() async {
    setState(() {
      _isLoadingWallet = true;
      _errorMessage = null;
    });

    try {
      final data = await BusinessApiService.getBusinessWalletAdmin(widget.businessId);
      if (mounted) {
        setState(() {
          _walletData = data;
          _isLoadingWallet = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ErrorExtractor.forContext(e, context);
          _isLoadingWallet = false;
        });
      }
    }
  }

  Future<void> _addGiftBalance() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // استفاده از parseFormattedDouble برای تبدیل مقدار فرمت‌شده به عدد
      final amount = parseFormattedDouble(_amountController.text);
      if (amount == null || amount <= 0) {
        throw Exception(adminTx(context, 'مبلغ نامعتبر است', 'Amount is invalid'));
      }

      await BusinessApiService.addGiftBalanceAdmin(
        businessId: widget.businessId,
        amount: amount,
        description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
        reason: _reasonController.text.isEmpty ? null : _reasonController.text,
        confirmation: _giftConfirmController.text.trim(),
      );

      // پاک کردن فرم
      _amountController.clear();
      _descriptionController.clear();
      _reasonController.clear();
      _giftConfirmController.clear();

      // بارگذاری مجدد اطلاعات کیف‌پول
      await _loadWalletData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(adminTx(context, 'موجودی هدیه اضافه شد', 'Gift balance added')),
            backgroundColor: SemanticColorResolver.positive(context),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ErrorExtractor.forContext(e, context);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoadingWallet) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _walletData == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: SemanticColorResolver.negative(context)),
            const SizedBox(height: 16),
            Text(
              adminTx(context, 'خطا در دریافت اطلاعات کیف‌پول', 'Could not load the wallet'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadWalletData,
              icon: const Icon(Icons.refresh),
              label: Text(adminTx(context, 'تلاش مجدد', 'Retry')),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // نمایش اطلاعات کیف‌پول
          if (_walletData != null) ...[
            _buildSectionTitle(theme, adminTx(context, 'وضعیت کیف‌پول', 'Wallet')),
            _buildWalletInfoCard(theme, _walletData!),
            const SizedBox(height: 24),
          ],

          // فرم افزودن موجودی هدیه
          _buildSectionTitle(theme, adminTx(context, 'افزودن موجودی هدیه', 'Add gift balance')),
          _buildGiftForm(theme),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.primary),
      ),
    );
  }

  Widget _buildWalletInfoCard(ThemeData theme, Map<String, dynamic> walletData) {
    final availableBalance = walletData['available_balance'] as double? ?? 0.0;
    final pendingBalance = walletData['pending_balance'] as double? ?? 0.0;
    final status = walletData['status'] as String? ?? 'active';
    final currencyCode = walletData['base_currency_code'] as String? ?? 'IRR';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(
              theme,
              adminTx(context, 'موجودی قابل استفاده', 'Available'),
              _formatCurrency(availableBalance, currencyCode),
              SemanticColorResolver.positive(context),
              FontWeight.bold,
            ),
            const Divider(height: 24),
            _buildInfoRow(
              theme,
              adminTx(context, 'موجودی در انتظار', 'Pending'),
              _formatCurrency(pendingBalance, currencyCode),
              SemanticColorResolver.warning(context),
            ),
            const Divider(height: 24),
            _buildInfoRow(
              theme,
              adminTx(context, 'وضعیت', 'Status'),
              status == 'active' ? adminTx(context, 'فعال', 'Active') : adminTx(context, 'معلق', 'Suspended'),
              status == 'active' ? SemanticColorResolver.positive(context) : SemanticColorResolver.negative(context),
            ),
            const Divider(height: 24),
            _buildInfoRow(theme, adminTx(context, 'ارز پایه', 'Currency'), currencyCode),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    ThemeData theme,
    String label,
    String value, [
    Color? valueColor,
    FontWeight? valueFontWeight,
  ]) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: valueColor,
            fontWeight: valueFontWeight ?? FontWeight.normal,
          ),
        ),
      ],
    );
  }

  String _formatCurrency(double amount, String currencyCode) {
    final formatted = amount.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$formatted $currencyCode';
  }

  Widget _buildGiftForm(ThemeData theme) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: adminTx(context, 'مبلغ *', 'Amount *'),
                  hintText: adminTx(context, 'مثلاً 1,000,000', 'For example 1,000,000'),
                  prefixIcon: const Icon(Icons.attach_money),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  const EnglishDigitsFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'^[\d,]*\.?\d*')),
                  const ThousandsSeparatorInputFormatter(allowDecimal: true),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return adminTx(context, 'مبلغ الزامی است', 'Amount is required');
                  }
                  final amount = parseFormattedDouble(value);
                  if (amount == null || amount <= 0) {
                    return adminTx(context, 'مبلغ باید بزرگ‌تر از صفر باشد', 'Amount must be greater than zero');
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: adminTx(context, 'توضیحات', 'Description'),
                  hintText: adminTx(context, 'اختیاری', 'Optional'),
                  prefixIcon: const Icon(Icons.description),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reasonController,
                decoration: InputDecoration(
                  labelText: adminTx(context, 'دلیل', 'Reason'),
                  hintText: adminTx(context, 'اختیاری', 'Optional'),
                  prefixIcon: const Icon(Icons.info_outline),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _giftConfirmController,
                decoration: InputDecoration(
                  labelText: adminTx(context, 'عبارت تأیید', 'Confirmation phrase'),
                  hintText: adminTx(context, 'برای شارژ، هدیه یا GIFT را بنویسید', 'Type هدیه or GIFT'),
                  prefixIcon: const Icon(Icons.verified_user_outlined),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text != 'هدیه' && text != 'GIFT') {
                    return adminTx(context, 'عبارت تأیید باید هدیه یا GIFT باشد', 'Type هدیه or GIFT');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SemanticColorResolver.negative(context).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: SemanticColorResolver.negative(context)!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: SemanticColorResolver.negative(context)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: SemanticColorResolver.negative(context)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _addGiftBalance,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.card_giftcard),
                label: Text(_isLoading
                    ? adminTx(context, 'در حال افزودن…', 'Adding…')
                    : adminTx(context, 'افزودن موجودی هدیه', 'Add gift balance')),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessPoliciesTab extends StatefulWidget {
  final int businessId;
  const _BusinessPoliciesTab({required this.businessId});

  @override
  State<_BusinessPoliciesTab> createState() => _BusinessPoliciesTabState();
}

class _BusinessPoliciesTabState extends State<_BusinessPoliciesTab> {
  final DocumentMonetizationService _service = DocumentMonetizationService(ApiClient());
  bool _loading = true;
  bool _assigningPlan = false;
  bool _deleting = false;
  String? _error;
  int? _selectedPlanId;
  List<Map<String, dynamic>> _policies = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _plans = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final policies = await _service.listBusinessPoliciesAdmin(widget.businessId);
      final plans = await _service.listSubscriptionPlans(onlyActive: true);
      setState(() {
        _policies = policies;
        _plans = plans;
        if (_selectedPlanId == null && plans.isNotEmpty) {
          _selectedPlanId = plans.first['id'] as int?;
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  Future<void> _assignPlan() async {
    if (_selectedPlanId == null) {
      _showSnack(adminTx(context, 'پلن را انتخاب کنید', 'Choose a plan'));
      return;
    }
    setState(() => _assigningPlan = true);
    try {
      await _service.assignSubscriptionToBusiness(
        widget.businessId,
        {'plan_id': _selectedPlanId, 'auto_renew': false},
      );
      _showSnack(adminTx(context, 'پلن اعمال شد', 'Plan applied'));
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        '${adminTx(context, 'خطا در اعمال پلن', 'Could not apply the plan')}: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) {
        setState(() => _assigningPlan = false);
      }
    }
  }

  Future<void> _deletePolicy(int policyId) async {
    setState(() => _deleting = true);
    try {
      await _service.deleteBusinessPolicyAdmin(widget.businessId, policyId);
      await _loadData();
      _showSnack(adminTx(context, 'سیاست حذف شد', 'Policy deleted'));
    } catch (e) {
      if (mounted) {
        _showSnack(
          '${adminTx(context, 'خطا در حذف سیاست', 'Could not delete the policy')}: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  Future<void> _openPolicyDialog({Map<String, dynamic>? initial}) async {
    final formKey = GlobalKey<FormState>();
    final pageContext = context;
    final titleCtrl = TextEditingController(text: initial?['title'] ?? '');
    final priorityCtrl = TextEditingController(text: initial?['priority']?.toString() ?? '120');
    final configCtrl = TextEditingController(
      text: initial == null ? '{\n  "fee_amount": 0\n}' : const JsonEncoder.withIndent('  ').convert(initial['config'] ?? {}),
    );
    bool isActive = initial?['is_active'] ?? true;
    String policyType = (initial?['policy_type'] ?? 'per_document') as String;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setInnerState) => AlertDialog(
            title: Text(initial == null
                ? adminTx(pageContext, 'سیاست جدید', 'New policy')
                : adminTx(pageContext, 'ویرایش سیاست', 'Edit policy')),
            content: SizedBox(
              width: 480,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: titleCtrl,
                        decoration: InputDecoration(isDense: true, labelText: adminTx(pageContext, 'عنوان', 'Title')),
                        validator: (v) => (v == null || v.isEmpty) ? adminTx(pageContext, 'عنوان الزامی است', 'Title is required') : null,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: policyType,
                        decoration: InputDecoration(isDense: true, labelText: adminTx(pageContext, 'نوع سیاست', 'Policy type')),
                        items: [
                          DropdownMenuItem(value: 'free', child: Text(adminTx(pageContext, 'رایگان', 'Free'))),
                          DropdownMenuItem(value: 'subscription', child: Text(adminTx(pageContext, 'اشتراک', 'Subscription'))),
                          DropdownMenuItem(value: 'per_document', child: Text(adminTx(pageContext, 'به‌ازای هر سند', 'Per document'))),
                          DropdownMenuItem(value: 'volume', child: Text(adminTx(pageContext, 'حجمی', 'Volume'))),
                          DropdownMenuItem(value: 'hybrid', child: Text(adminTx(pageContext, 'ترکیبی', 'Hybrid'))),
                        ],
                        onChanged: (v) => setInnerState(() => policyType = v ?? policyType),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: priorityCtrl,
                        decoration: InputDecoration(isDense: true, labelText: adminTx(pageContext, 'اولویت', 'Priority')),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) => (v == null || v.isEmpty) ? adminTx(pageContext, 'اولویت الزامی است', 'Priority is required') : null,
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(adminTx(pageContext, 'فعال', 'Active')),
                        value: isActive,
                        onChanged: (v) => setInnerState(() => isActive = v),
                      ),
                      TextFormField(
                        controller: configCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: adminTx(pageContext, 'پیکربندی (JSON)', 'Configuration (JSON)'),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 8,
                        validator: (v) {
                          if (v == null || v.isEmpty) return adminTx(pageContext, 'پیکربندی الزامی است', 'Configuration is required');
                          try {
                            jsonDecode(v);
                            return null;
                          } catch (_) {
                            return adminTx(pageContext, 'فرمت JSON نامعتبر است', 'Invalid JSON');
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(adminTx(pageContext, 'انصراف', 'Cancel')),
              ),
              FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  if (!context.mounted) return;
                  final ctx = context;
                  try {
                    final config = jsonDecode(configCtrl.text) as Map<String, dynamic>;
                    final payload = <String, dynamic>{
                      'title': titleCtrl.text.trim(),
                      'policy_type': policyType,
                      'priority': int.parse(priorityCtrl.text.trim()),
                      'is_active': isActive,
                      'config': config,
                    };
                    if (initial != null) {
                      payload['id'] = initial['id'];
                    }
                    await _service.saveBusinessPolicyAdmin(widget.businessId, payload);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    _loadData();
                  } catch (e) {
                    if (pageContext.mounted) {
                      _showSnack(
                        '${adminTx(pageContext, 'خطا در ذخیره سیاست', 'Could not save the policy')}: ${ErrorExtractor.forContext(e, pageContext)}',
                      );
                    }
                  }
                },
                child: Text(adminTx(pageContext, 'ذخیره', 'Save')),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: SemanticColorResolver.negative(context), size: 32),
            const SizedBox(height: 8),
            Text(_error!),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: Text(adminTx(context, 'تلاش مجدد', 'Retry')),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: context.settingsHub.pagePadding,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          adminTx(context, 'پکیج اشتراک کسب‌وکار', 'Business subscription package'),
                          style: context.settingsHub.cardTitleStyle(
                            Theme.of(context).textTheme,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: adminTx(context, 'بازخوانی پلن‌ها', 'Refresh plans'),
                        onPressed: _loadData,
                      ),
                    ],
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: _selectedPlanId,
                    items: _plans
                        .map(
                          (plan) => DropdownMenuItem<int>(
                            value: plan['id'] as int?,
                            child: Text('${plan['name']} (${plan['period_months']} ${adminTx(context, 'ماه', 'mo')})'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedPlanId = v),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: adminTx(context, 'انتخاب پکیج', 'Choose a package'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _assigningPlan ? null : _assignPlan,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(_assigningPlan
                        ? adminTx(context, 'در حال اعمال…', 'Applying…')
                        : adminTx(context, 'اعمال پکیج', 'Apply package')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          adminTx(context, 'سیاست‌های فعال', 'Active policies'),
                          style: context.settingsHub.cardTitleStyle(
                            Theme.of(context).textTheme,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _openPolicyDialog(),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(adminTx(context, 'سیاست جدید', 'New policy')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_policies.isEmpty)
                    Text(
                      adminTx(context, 'سیاستی ثبت نشده است', 'No policies yet'),
                      textAlign: TextAlign.center,
                      style: context.settingsHub.cardSubtitleStyle(
                        Theme.of(context).textTheme,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    ..._policies.map((policy) {
                      final status = policy['is_active'] == true
                          ? adminTx(context, 'فعال', 'Active')
                          : adminTx(context, 'غیرفعال', 'Inactive');
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          dense: true,
                          title: Text(policy['title'] as String? ?? '-'),
                          subtitle: Text(
                            '${adminTx(context, 'نوع', 'Type')}: ${policy['policy_type']} · ${adminTx(context, 'اولویت', 'Priority')}: ${policy['priority']} · ${adminTx(context, 'وضعیت', 'Status')}: $status',
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                tooltip: adminTx(context, 'ویرایش', 'Edit'),
                                onPressed: () => _openPolicyDialog(initial: policy),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                tooltip: _deleting
                                    ? adminTx(context, 'در حال حذف…', 'Deleting…')
                                    : adminTx(context, 'حذف', 'Delete'),
                                onPressed: _deleting ? null : () => _deletePolicy(policy['id'] as int),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    SnackBarHelper.show(context, message: message);
  }
}
