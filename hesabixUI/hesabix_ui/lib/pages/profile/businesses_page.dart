import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../services/business_dashboard_service.dart';
import '../../services/business_user_service.dart';
import '../../services/business_api_service.dart';
import '../../core/api_client.dart';
import '../../models/business_dashboard_models.dart';
import '../../models/business_user_model.dart';
import '../../core/auth_store.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/responsive_helper.dart';

class BusinessesPage extends StatefulWidget {
  const BusinessesPage({super.key});

  @override
  State<BusinessesPage> createState() => _BusinessesPageState();
}

class _BusinessesPageState extends State<BusinessesPage> {
  final BusinessDashboardService _service = BusinessDashboardService(ApiClient());
  List<BusinessWithPermission> _businesses = [];
  bool _loading = true;
  bool _isLoadingMore = false;
  String? _error;
  final AuthStore _authStore = AuthStore();
  final ScrollController _scrollController = ScrollController();
  
  // Pagination state
  int _skip = 0;
  static const int _pageSize = 10;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _init();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // جلوگیری از فراخوانی همزمان
    if (_isLoadingMore || !_hasMore || _loading) return;
    
    // بررسی اینکه آیا به انتهای لیست نزدیک شده‌ایم
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final threshold = maxScroll - 200; // 200 پیکسل مانده به آخر
    
    if (currentScroll >= threshold && maxScroll > 0) {
      // وقتی به 200 پیکسل مانده به آخر رسید، صفحات بعدی را لود کن
      _loadMore();
    }
  }

  Future<void> _init() async {
    // اطمینان از bind بودن AuthStore برای ApiClient
    ApiClient.bindAuthStore(_authStore);
    await _authStore.load();
    await _loadBusinesses();
  }

  Future<void> _loadBusinesses({bool reset = true}) async {
    try {
      setState(() {
        if (reset) {
          _loading = true;
          _skip = 0;
          _hasMore = true;
          _businesses = [];
        }
        _error = null;
      });

      // استفاده از _skip فعلی (0 در reset، یا مقدار قبلی)
      final currentSkip = reset ? 0 : _skip;
      
      final result = await _service.getUserBusinessesPaginated(
        take: _pageSize,
        skip: currentSkip,
        sortBy: 'created_at',
        sortDesc: true,
      );

      if (mounted) {
        final newBusinesses = result['items'] as List<BusinessWithPermission>;
        final pagination = result['pagination'] as Map<String, dynamic>?;
        
        setState(() {
          if (reset) {
            _businesses = newBusinesses;
            _skip = newBusinesses.length; // به‌روزرسانی skip به تعداد آیتم‌های دریافت شده
          } else {
            _businesses.addAll(newBusinesses);
            _skip += newBusinesses.length; // اضافه کردن به skip موجود
          }
          _loading = false;
          
          // بررسی اینکه آیا صفحات بیشتری وجود دارد
          if (pagination != null) {
            _hasMore = pagination['has_next'] as bool? ?? false;
          } else {
            // اگر pagination وجود نداشت، بر اساس تعداد آیتم‌ها تصمیم بگیر
            _hasMore = newBusinesses.length >= _pageSize;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        final err = ErrorExtractor.forContext(e, context);
        setState(() {
          _loading = false;
          _error = err;
        });
        SnackBarHelper.showError(
          context,
          message:
              '${AppLocalizations.of(context).dataLoadingError}: $err',
        );
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _loading) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      // استفاده از _skip فعلی برای دریافت صفحه بعدی
      final result = await _service.getUserBusinessesPaginated(
        take: _pageSize,
        skip: _skip,
        sortBy: 'created_at',
        sortDesc: true,
      );

      if (mounted) {
        final newBusinesses = result['items'] as List<BusinessWithPermission>;
        final pagination = result['pagination'] as Map<String, dynamic>?;
        
        setState(() {
          _businesses.addAll(newBusinesses);
          _skip += newBusinesses.length; // به‌روزرسانی skip
          _isLoadingMore = false;
          
          // بررسی اینکه آیا صفحات بیشتری وجود دارد
          if (pagination != null) {
            _hasMore = pagination['has_next'] as bool? ?? false;
          } else {
            // اگر pagination وجود نداشت، بر اساس تعداد آیتم‌ها تصمیم بگیر
            _hasMore = newBusinesses.length >= _pageSize;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
        SnackBarHelper.showError(
          context,
          message:
              'خطا در بارگذاری صفحات بعدی: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    }
  }

  void _navigateToBusiness(int businessId) {
    // بررسی اینکه کسب و کار حذف نشده باشد
    final business = _businesses.firstWhere(
      (b) => b.id == businessId,
      orElse: () => throw Exception('کسب و کار یافت نشد'),
    );
    
    if (business.isDeletionPending) {
      SnackBarHelper.showError(
        context,
        message: 'این کسب و کار در حال حذف است و نمی‌توان به آن دسترسی داشت. می‌توانید آن را بازیابی کنید.',
      );
      return;
    }
    
    context.go('/business/$businessId/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final padding = ResponsiveHelper.getPadding(context);
    final gridSpacing = ResponsiveHelper.getGridSpacing(context);

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header - responsive
            if (!isMobile) _buildDesktopHeader(t, context),
            if (isMobile) _buildMobileHeader(t, context),
            
            SizedBox(height: padding),
            
            // Content
            if (_loading)
              Expanded(
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Expanded(
                child: _buildErrorState(t, context, padding),
              )
            else if (_businesses.isEmpty)
              Expanded(
                child: _buildEmptyState(t, context, padding),
              )
            else
              Expanded(
                child: _buildContent(context, gridSpacing),
              ),
          ],
        ),
      ),
      // FloatingActionButton فقط در موبایل
      floatingActionButton: isMobile && !_loading && _error == null
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/user/profile/new-business'),
              icon: const Icon(Icons.add),
              label: Text(t.newBusiness),
            )
          : null,
    );
  }

  Widget _buildDesktopHeader(AppLocalizations t, BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            t.businesses,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontSize: ResponsiveHelper.responsiveValue(
                context,
                mobile: 24,
                tablet: 26,
                desktop: 28,
              ),
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: () => context.go('/user/profile/new-business'),
          icon: const Icon(Icons.add),
          label: Text(t.newBusiness),
        ),
      ],
    );
  }

  Widget _buildMobileHeader(AppLocalizations t, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.businesses,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontSize: 24,
          ),
        ),
        // دکمه در موبایل در FloatingActionButton است
      ],
    );
  }

  Widget _buildErrorState(AppLocalizations t, BuildContext context, double padding) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(padding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: ResponsiveHelper.responsiveValue(
                context,
                mobile: 64,
                tablet: 72,
                desktop: 80,
              ),
              color: Colors.red,
            ),
            SizedBox(height: padding),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            SizedBox(height: padding),
            FilledButton.icon(
              onPressed: _loadBusinesses,
              icon: const Icon(Icons.refresh),
              label: Text(t.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations t, BuildContext context, double padding) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(padding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.business_outlined,
              size: ResponsiveHelper.responsiveValue(
                context,
                mobile: 64,
                tablet: 72,
                desktop: 80,
              ),
              color: Colors.grey,
            ),
            SizedBox(height: padding),
            Text(
              t.noBusinessesFound,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            SizedBox(height: padding),
            if (!ResponsiveHelper.isMobile(context))
              FilledButton.icon(
                onPressed: () => context.go('/user/profile/new-business'),
                icon: const Icon(Icons.add),
                label: Text(t.createFirstBusiness),
              )
            else
              FilledButton(
                onPressed: () => context.go('/user/profile/new-business'),
                child: Text(t.createFirstBusiness),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, double spacing) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // استفاده از ResponsiveHelper برای تعیین تعداد ستون‌ها
        int crossAxisCount;
        double childAspectRatio;
        
        if (ResponsiveHelper.isMobile(context)) {
          crossAxisCount = 1;
          // نسبت کمتر برای ارتفاع بیشتر کارت روی موبایل و جلوگیری از به‌هم‌ریختگی محتوا
          childAspectRatio = 2.4; // wide card با ارتفاع مناسب‌تر
        } else if (ResponsiveHelper.isTablet(context)) {
          final bp = ResponsiveHelper.breakpoint(context);
          if (bp == 'sm') {
            crossAxisCount = 2;
            childAspectRatio = 1.35;
          } else {
            // md
            crossAxisCount = 2;
            childAspectRatio = 1.25;
          }
        } else {
          // Desktop
          final bp = ResponsiveHelper.breakpoint(context);
          if (bp == 'lg') {
            crossAxisCount = 3;
            childAspectRatio = 1.25;
          } else {
            // xl
            crossAxisCount = 4;
            childAspectRatio = 1.2;
          }
        }
        
        return GridView.builder(
          controller: _scrollController,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: childAspectRatio,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
          ),
          itemCount: _businesses.length + (_isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            // نمایش loading indicator در آخر لیست
            if (index >= _businesses.length) {
              return Center(
                child: Padding(
                  padding: EdgeInsets.all(spacing),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            
            final business = _businesses[index];
            return _BusinessCard(
              business: business,
              onTap: () => _navigateToBusiness(business.id),
              authStore: _authStore,
              isCompact: crossAxisCount > 1,
              isMobile: crossAxisCount == 1,
              onLeave: () => _loadBusinesses(),
            );
          },
        );
      },
    );
  }
}

class _BusinessCard extends StatefulWidget {
  final BusinessWithPermission business;
  final VoidCallback onTap;
  final bool isCompact;
  final bool isMobile;
  final AuthStore authStore;
  final VoidCallback? onLeave;

  const _BusinessCard({
    required this.business,
    required this.onTap,
    required this.authStore,
    this.isCompact = true,
    this.isMobile = false,
    this.onLeave,
  });

  @override
  State<_BusinessCard> createState() => _BusinessCardState();
}

class _BusinessCardState extends State<_BusinessCard> {
  String? _localCurrencyCode;
  bool _isLeaving = false;
  bool _isRestoring = false;
  final BusinessUserService _userService = BusinessUserService(ApiClient());

  @override
  void initState() {
    super.initState();
    _localCurrencyCode = _resolveInitialCurrency();
  }

  String? _resolveInitialCurrency() {
    final codes = widget.business.currencies.map((c) => c.code).toSet();
    final authCode = widget.authStore.selectedCurrencyCode;
    if (authCode != null && codes.contains(authCode)) return authCode;
    return widget.business.defaultCurrency?.code ?? (widget.business.currencies.isNotEmpty ? widget.business.currencies.first.code : null);
  }

  @override
  Widget build(BuildContext context) {
    final padding = ResponsiveHelper.getPadding(context);
    
    if (widget.isCompact) {
      return _buildCompactCard(context, padding);
    } else {
      return _buildWideCard(context, padding);
    }
  }

  Widget _buildCompactCard(BuildContext context, double padding) {
    final cardPadding = ResponsiveHelper.responsiveValue(
      context,
      mobile: padding * 1.0,
      tablet: padding * 0.75,
      desktop: padding * 0.5,
    );
    
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Header with icon and role badge
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(cardPadding),
                    decoration: BoxDecoration(
                      color: widget.business.isOwner 
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                          : Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      widget.business.isOwner ? Icons.business : Icons.business_outlined,
                      color: widget.business.isOwner 
                          ? Theme.of(context).colorScheme.primary 
                          : Theme.of(context).colorScheme.secondary,
                      size: ResponsiveHelper.responsiveValue(
                        context,
                        mobile: 20,
                        tablet: 22,
                        desktop: 24,
                      ),
                    ),
                  ),
                  SizedBox(width: cardPadding),
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: cardPadding * 0.75,
                        vertical: cardPadding * 0.25,
                      ),
                      decoration: BoxDecoration(
                        color: widget.business.isOwner 
                            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                            : Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        widget.business.isOwner ? AppLocalizations.of(context).owner : AppLocalizations.of(context).member,
                        style: TextStyle(
                          color: widget.business.isOwner 
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.secondary,
                          fontSize: ResponsiveHelper.responsiveValue(
                            context,
                            mobile: 10,
                            tablet: 11,
                            desktop: 12,
                          ),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              SizedBox(height: cardPadding * 0.75),
              
              // Business name with deletion status
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.business.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: ResponsiveHelper.responsiveValue(
                          context,
                          mobile: 14,
                          tablet: 15,
                          desktop: 16,
                        ),
                        decoration: widget.business.isDeletionPending 
                            ? TextDecoration.lineThrough 
                            : null,
                        color: widget.business.isDeletionPending 
                            ? Theme.of(context).colorScheme.onSurfaceVariant 
                            : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.business.isDeletionPending && widget.business.isOwner)
                    Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'در حال حذف',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              
              SizedBox(height: cardPadding * 0.375),
              
              // Business type and field
              Text(
                '${_translateBusinessType(widget.business.businessType, context)} • ${_translateBusinessField(widget.business.businessField, context)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: ResponsiveHelper.responsiveValue(
                    context,
                    mobile: 11,
                    tablet: 12,
                    desktop: 13,
                  ),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              
              SizedBox(height: cardPadding * 0.75),
              
              // Footer with restore button (for deleted businesses)
              // یا چینش مرتب‌تر ارز و دکمه خروج در دو ردیف برای جلوگیری از شلوغی
              if (widget.business.isDeletionPending && widget.business.isOwner)
                _buildRestoreButton(context, cardPadding)
              else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _buildCurrencyDropdown(context),
                    ),
                    SizedBox(width: cardPadding * 0.5),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: ResponsiveHelper.responsiveValue(
                        context,
                        mobile: 12,
                        tablet: 14,
                        desktop: 16,
                      ),
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
                if (!widget.business.isOwner) ...[
                  SizedBox(height: cardPadding * 0.5),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: _buildLeaveButton(context, cardPadding),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
 
  Widget _buildWideCard(BuildContext context, double padding) {
    final isMobile = widget.isMobile;
    final cardPadding = isMobile ? padding * 1.5 : padding * 2;
    
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: widget.business.isDeletionPending ? null : widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(cardPadding),
          child: Row(
            children: [
              // Icon
              Container(
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                decoration: BoxDecoration(
                  color: widget.business.isOwner 
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                      : Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.business.isOwner ? Icons.business : Icons.business_outlined,
                  color: widget.business.isOwner 
                      ? Theme.of(context).colorScheme.primary 
                      : Theme.of(context).colorScheme.secondary,
                  size: isMobile ? 24 : 28,
                ),
              ),
              
              SizedBox(width: isMobile ? 12 : 16),
              
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.business.name,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: isMobile ? 16 : 18,
                                    decoration: widget.business.isDeletionPending 
                                        ? TextDecoration.lineThrough 
                                        : null,
                                    color: widget.business.isDeletionPending 
                                        ? Theme.of(context).colorScheme.onSurfaceVariant 
                                        : null,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.business.isDeletionPending && widget.business.isOwner)
                                Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'در حال حذف',
                                      style: TextStyle(
                                        color: Colors.orange.shade900,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(width: 8),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 8 : 10,
                            vertical: isMobile ? 4 : 5,
                          ),
                          decoration: BoxDecoration(
                            color: widget.business.isOwner 
                                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                                : Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            widget.business.isOwner ? AppLocalizations.of(context).owner : AppLocalizations.of(context).member,
                            style: TextStyle(
                              color: widget.business.isOwner 
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.secondary,
                              fontSize: isMobile ? 11 : 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    SizedBox(height: isMobile ? 4 : 6),
                    
                    Text(
                      '${_translateBusinessType(widget.business.businessType, context)} • ${_translateBusinessField(widget.business.businessField, context)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: isMobile ? 13 : 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    if (!isMobile) ...[
                      SizedBox(height: 8),
                      Text(
                        'تأسیس: ${_formatDate(widget.business.createdAt)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    
                    SizedBox(height: isMobile ? 8 : 12),
                    
                    // Restore button (for deleted businesses) or currency selector and leave button
                    if (widget.business.isDeletionPending && widget.business.isOwner)
                      _buildRestoreButton(context, isMobile ? 12.0 : 16.0)
                    else ...[
                      // Currency selector - در موبایل کوچکتر
                      _buildCurrencyDropdown(context),
                      
                      // Leave button for members
                      if (!widget.business.isOwner) ...[
                        SizedBox(height: isMobile ? 8 : 12),
                        _buildLeaveButton(context, isMobile ? 12.0 : 16.0),
                      ],
                    ],
                  ],
                ),
              ),
              
              SizedBox(width: isMobile ? 8 : 12),
              
              // Arrow (only if not deleted)
              if (!widget.business.isDeletionPending)
                Icon(
                  Icons.arrow_forward_ios,
                  size: isMobile ? 16 : 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrencyDropdown(BuildContext context) {
    final items = widget.business.currencies;
    final value = _localCurrencyCode ?? _resolveInitialCurrency();
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        hint: const Text('انتخاب ارز'),
        items: items
            .map((c) => DropdownMenuItem<String>(
                  value: c.code,
                  child: Text('${c.title} (${c.code})'),
                ))
            .toList(),
        onChanged: (val) async {
          if (val == null) return;
          setState(() {
            _localCurrencyCode = val;
          });
          final selected = items.firstWhere((c) => c.code == val, orElse: () => items.first);
          await widget.authStore.setSelectedCurrency(code: selected.code, id: selected.id);
        },
      ),
    );
  }

  Widget _buildLeaveButton(BuildContext context, double size) {
    final theme = Theme.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    
    // برای موبایل: دکمه کوچکتر با آیکون
    if (isMobile) {
      return IconButton(
        icon: _isLeaving
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.error),
                ),
              )
            : Icon(
                Icons.exit_to_app,
                size: 20,
                color: theme.colorScheme.error,
              ),
        tooltip: 'خروج از کسب و کار',
        onPressed: _isLeaving ? null : () => _handleLeave(context),
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
      );
    }
    
    // برای دسکتاپ: دکمه بزرگتر با متن
    return OutlinedButton.icon(
      onPressed: _isLeaving ? null : () => _handleLeave(context),
      icon: _isLeaving
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.error),
              ),
            )
          : Icon(
              Icons.exit_to_app,
              size: 16,
              color: theme.colorScheme.error,
            ),
      label: const Text(
        'خروج',
        style: TextStyle(fontSize: 12),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.colorScheme.error,
        side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildRestoreButton(BuildContext context, double size) {
    final theme = Theme.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    
    // محاسبه مهلت باقی‌مانده
    String? remainingDaysText;
    if (widget.business.autoDeleteAt != null) {
      try {
        final autoDeleteDate = DateTime.parse(widget.business.autoDeleteAt!);
        final now = DateTime.now();
        final difference = autoDeleteDate.difference(now);
        if (difference.inDays > 0) {
          remainingDaysText = '${difference.inDays} روز باقی مانده';
        } else if (difference.inHours > 0) {
          remainingDaysText = '${difference.inHours} ساعت باقی مانده';
        } else {
          remainingDaysText = 'مهلت به پایان رسیده';
        }
      } catch (e) {
        remainingDaysText = null;
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (remainingDaysText != null) ...[
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.orange.shade900),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    remainingDaysText,
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed: _isRestoring ? null : () => _handleRestore(context),
          icon: _isRestoring
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.onPrimary),
                  ),
                )
              : Icon(Icons.restore, size: 16),
          label: Text(
            _isRestoring ? 'در حال بازیابی...' : 'بازیابی کسب و کار',
            style: TextStyle(fontSize: isMobile ? 12 : 14),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Future<void> _handleRestore(BuildContext context) async {
    final pageContext = context;
    final t = AppLocalizations.of(pageContext);

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: pageContext,
      builder: (context) => AlertDialog(
        title: const Text('بازیابی کسب و کار'),
        content: Text(
          'آیا مطمئن هستید که می‌خواهید کسب و کار "${widget.business.name}" را بازیابی کنید؟\n\n'
          'پس از بازیابی، دسترسی شما به این کسب و کار بازگردانده خواهد شد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('بازیابی'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isRestoring = true;
    });

    try {
      await BusinessApiService.restoreBusiness(widget.business.id);

      if (!pageContext.mounted) return;
      SnackBarHelper.showSuccess(
        pageContext,
        message: 'کسب و کار با موفقیت بازیابی شد',
      );

      // Refresh businesses list
      widget.onLeave?.call();
    } catch (e) {
      if (!pageContext.mounted) return;
      SnackBarHelper.showError(
        pageContext,
        message:
            'خطا در بازیابی کسب و کار: ${ErrorExtractor.forContext(e, pageContext)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRestoring = false;
        });
      }
    }
  }

  Future<void> _handleLeave(BuildContext context) async {
    final pageContext = context;
    final t = AppLocalizations.of(pageContext);

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: pageContext,
      builder: (context) => AlertDialog(
        title: const Text('خروج از کسب و کار'),
        content: Text(
          'آیا مطمئن هستید که می‌خواهید از کسب و کار "${widget.business.name}" خارج شوید؟\n\n'
          'پس از خروج، دسترسی شما به این کسب و کار حذف خواهد شد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('خروج'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLeaving = true;
    });

    try {
      final request = LeaveBusinessRequest(businessId: widget.business.id);
      final response = await _userService.leaveBusiness(request);

      if (response.success) {
        if (!pageContext.mounted) return;
        SnackBarHelper.showSuccess(
          pageContext,
          message: response.message,
        );

        // Clear current business if it's the one we're leaving
        if (widget.authStore.currentBusiness?.id == widget.business.id) {
          await widget.authStore.clearCurrentBusiness();
        }

        if (!pageContext.mounted) return;
        // Trigger refresh in parent to reload the list
        widget.onLeave?.call();
      } else {
        if (!pageContext.mounted) return;
        SnackBarHelper.showError(
          pageContext,
          message: response.message,
        );
      }
    } catch (e) {
      if (!pageContext.mounted) return;
      SnackBarHelper.showError(
        pageContext,
        message:
            'خطا در خروج از کسب و کار: ${ErrorExtractor.forContext(e, pageContext)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLeaving = false;
        });
      }
    }
  }
}

String _formatDate(String dateString) {
  try {
    final date = DateTime.parse(dateString);
    return '${date.year}/${date.month}/${date.day}';
  } catch (e) {
    return dateString;
  }
}

String _translateBusinessType(String type, BuildContext context) {
  final l10n = AppLocalizations.of(context);
  switch (type) {
    case 'شرکت':
      return l10n.company;
    case 'مغازه':
      return l10n.shop;
    case 'فروشگاه':
      return l10n.store;
    case 'اتحادیه':
      return l10n.union;
    case 'باشگاه':
      return l10n.club;
    case 'موسسه':
      return l10n.institute;
    case 'شخصی':
      return l10n.individual;
    default:
      return type;
  }
}

String _translateBusinessField(String field, BuildContext context) {
  final l10n = AppLocalizations.of(context);
  switch (field) {
    case 'تولیدی':
      return l10n.manufacturing;
    case 'بازرگانی':
      return l10n.trading;
    case 'خدماتی':
      return l10n.service;
    case 'سایر':
      return l10n.other;
    default:
      return field;
  }
}


