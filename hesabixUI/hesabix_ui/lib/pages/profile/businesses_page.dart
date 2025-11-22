import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../services/business_dashboard_service.dart';
import '../../core/api_client.dart';
import '../../models/business_dashboard_models.dart';
import '../../core/auth_store.dart';
import '../../utils/snackbar_helper.dart';

class BusinessesPage extends StatefulWidget {
  const BusinessesPage({super.key});

  @override
  State<BusinessesPage> createState() => _BusinessesPageState();
}

class _BusinessesPageState extends State<BusinessesPage> {
  final BusinessDashboardService _service = BusinessDashboardService(ApiClient());
  List<BusinessWithPermission> _businesses = [];
  bool _loading = true;
  String? _error;
  final AuthStore _authStore = AuthStore();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // اطمینان از bind بودن AuthStore برای ApiClient
    ApiClient.bindAuthStore(_authStore);
    await _authStore.load();
    await _loadBusinesses();
  }

  Future<void> _loadBusinesses() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final businesses = await _service.getUserBusinesses();

      if (mounted) {
        setState(() {
          _businesses = businesses;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
        SnackBarHelper.showError(context, message: '${AppLocalizations.of(context).dataLoadingError}: $e');
      }
    }
  }

  void _navigateToBusiness(int businessId) {
    context.go('/business/$businessId/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t.businesses,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              ElevatedButton.icon(
                onPressed: () => context.go('/user/profile/new-business'),
                icon: const Icon(Icons.add),
                label: Text(t.newBusiness),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Center(
              child: Column(
                children: [
                  Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(_error!),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadBusinesses,
                    child: Text(t.retry),
                  ),
                ],
              ),
            )
          else if (_businesses.isEmpty)
            Center(
              child: Column(
                children: [
                  Icon(Icons.business, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(t.noBusinessesFound),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.go('/user/profile/new-business'),
                    child: Text(t.createFirstBusiness),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Responsive grid based on screen width
                  int crossAxisCount;
                  if (constraints.maxWidth > 1200) {
                    crossAxisCount = 4;
                  } else if (constraints.maxWidth > 900) {
                    crossAxisCount = 3;
                  } else if (constraints.maxWidth > 600) {
                    crossAxisCount = 2;
                  } else {
                    crossAxisCount = 1;
                  }
                  
                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: crossAxisCount == 1 ? 4.0 : 1.3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _businesses.length,
                    itemBuilder: (context, index) {
                      final business = _businesses[index];
                      return _BusinessCard(
                        business: business,
                        onTap: () => _navigateToBusiness(business.id),
                        authStore: _authStore,
                        isCompact: crossAxisCount > 1,
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _BusinessCard extends StatefulWidget {
  final BusinessWithPermission business;
  final VoidCallback onTap;
  final bool isCompact;
  final AuthStore authStore;

  const _BusinessCard({
    required this.business,
    required this.onTap,
    required this.authStore,
    this.isCompact = true,
  });

  @override
  State<_BusinessCard> createState() => _BusinessCardState();
}

class _BusinessCardState extends State<_BusinessCard> {
  String? _localCurrencyCode;

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
    if (widget.isCompact) {
      return _buildCompactCard(context);
    } else {
      return _buildWideCard(context);
    }
  }

  Widget _buildCompactCard(BuildContext context) {
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Header with icon and role badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
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
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 6),
              
              // Business name
              Text(
                widget.business.name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 3),
              
              // Business type and field
              Text(
                '${_translateBusinessType(widget.business.businessType, context)} • ${_translateBusinessField(widget.business.businessField, context)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 6),
              
              // Footer with currency selector and arrow
              Row(
                children: [
                  Expanded(
                    child: _buildCurrencyDropdown(context),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
 
  Widget _buildWideCard(BuildContext context) {
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(12),
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
                  size: 24,
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.business.name,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 4),
                    
                            Text(
                              '${_translateBusinessType(widget.business.businessType, context)} • ${_translateBusinessField(widget.business.businessField, context)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    const SizedBox(height: 8),
                    
                    Text(
                      'تأسیس: ${_formatDate(widget.business.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Currency selector and Arrow
              SizedBox(
                width: 220,
                child: _buildCurrencyDropdown(context),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
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


