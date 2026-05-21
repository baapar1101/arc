import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import '../../services/business_user_service.dart';
import '../../models/business_user_model.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/business_subpage_back_leading.dart';
import '../../widgets/jalali_date_picker.dart';

DateTime _membershipEndOfLocalDayUtc(DateTime d) {
  final endLocal = DateTime(d.year, d.month, d.day, 23, 59, 59);
  return endLocal.toUtc();
}

class UsersPermissionsPage extends StatefulWidget {
  final String businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const UsersPermissionsPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<UsersPermissionsPage> createState() => _UsersPermissionsPageState();
}

class _UsersPermissionsPageState extends State<UsersPermissionsPage> {
  final BusinessUserService _userService = BusinessUserService(ApiClient());
  final TextEditingController _emailOrPhoneController = TextEditingController();
  
  List<BusinessUser> _users = [];
  bool _loading = true;
  bool _isLeaving = false;
  String? _error;
  bool _addMembershipUnlimited = true;
  DateTime? _addMembershipEndDate;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _emailOrPhoneController.dispose();
    super.dispose();
  }

  Future<void> _pickAddMembershipEndDate() async {
    final t = AppLocalizations.of(context);
    final now = DateTime.now();
    final initial = _addMembershipEndDate ?? now.add(const Duration(days: 1));
    final picked = await showAdaptiveDatePicker(
      context: context,
      calendarController: widget.calendarController,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: t.businessMembershipPickDate,
    );
    if (picked != null && mounted) {
      setState(() {
        _addMembershipEndDate = picked;
        _addMembershipUnlimited = false;
      });
    }
  }

  Future<void> _loadUsers() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final response = await _userService.getBusinessUsers(int.parse(widget.businessId));
      
      if (mounted) {
        setState(() {
          _users = response.users;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = ErrorExtractor.forContext(e, context);
        });
        _showErrorSnackBar(
          '${AppLocalizations.of(context).dataLoadingError}: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    }
  }

  Future<void> _addUser() async {
    if (_emailOrPhoneController.text.trim().isEmpty) {
      _showErrorSnackBar(AppLocalizations.of(context).userEmailOrPhoneHint);
      return;
    }

    // Normalize phone number if it's a phone number (not email)
    String emailOrPhone = _emailOrPhoneController.text.trim();
    if (_isPhoneNumber(emailOrPhone)) {
      emailOrPhone = normalizeIranianMobileToE164(emailOrPhone);
    }

    // Check if trying to add business owner
    if (_isTryingToAddOwner(emailOrPhone)) {
      _showOwnerWarning();
      return;
    }

    // Check if user already exists
    if (_isUserAlreadyAdded(emailOrPhone)) {
      _showAlreadyAddedWarning();
      return;
    }

    if (!context.mounted) return;
    final ctx = context;
    final t = AppLocalizations.of(ctx);
    if (!_addMembershipUnlimited) {
      if (_addMembershipEndDate == null) {
        _showErrorSnackBar(t.businessMembershipEndDateRequired);
        return;
      }
    }
    DateTime? membershipExpiresAt;
    if (!_addMembershipUnlimited && _addMembershipEndDate != null) {
      membershipExpiresAt = _membershipEndOfLocalDayUtc(_addMembershipEndDate!);
    }
    try {
      final request = AddUserRequest(
        businessId: int.parse(widget.businessId),
        emailOrPhone: emailOrPhone,
        membershipExpiresAt: membershipExpiresAt,
      );

      final response = await _userService.addUser(request);
      
      if (response.success) {
        _showSuccessSnackBar(response.message);
        _emailOrPhoneController.clear();
        setState(() {
          _addMembershipUnlimited = true;
          _addMembershipEndDate = null;
        });
        _loadUsers(); // Refresh the list
      } else {
        _showErrorSnackBar(response.message);
      }
    } catch (e) {
      if (!ctx.mounted) return;
      _showErrorSnackBar(
        '${AppLocalizations.of(ctx).userAddFailed}: ${ErrorExtractor.forContext(e, ctx)}',
      );
    }
  }

  /// بررسی می‌کند که آیا ورودی یک شماره تلفن است یا ایمیل
  bool _isPhoneNumber(String input) {
    // اگر شامل @ باشد، ایمیل است
    if (input.contains('@')) {
      return false;
    }
    
    // حذف کاراکترهای غیرعددی (به جز +)
    String cleaned = input.replaceAll(RegExp(r'[^\d+]'), '');
    
    // اگر فقط اعداد (و احتمالاً +) دارد و طول آن مناسب است، شماره تلفن است
    return cleaned.length >= 10 && RegExp(r'^[\d+]+$').hasMatch(cleaned);
  }


  Future<void> _removeUser(BusinessUser user) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.removeUser),
        content: Text(t.removeUserConfirm),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => context.pop(true),
            child: Text(t.removeUser),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final request = RemoveUserRequest(
        businessId: int.parse(widget.businessId),
        userId: user.userId,
      );

      final response = await _userService.removeUser(request);
      
      if (response.success) {
        _showSuccessSnackBar(response.message);
        _loadUsers(); // Refresh the list
      } else {
        _showErrorSnackBar(response.message);
      }
    } catch (e) {
      _showErrorSnackBar('${t.userRemoveFailed}: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  void _showErrorSnackBar(String message) {
    SnackBarHelper.showError(context, message: message);
  }

  void _showSuccessSnackBar(String message) {
    SnackBarHelper.showSuccess(context, message: message);
  }

  bool _isTryingToAddOwner(String emailOrPhone) {
    // Check if the current user is trying to add themselves (as owner)
    final currentUserId = widget.authStore.currentUserId;
    if (currentUserId == null) return false;
    
    // Find the owner in the users list
    final owner = _users.where((user) => user.role == 'owner').firstOrNull;
    if (owner == null) return false;
    
    // Check if the email/phone matches the owner's email/phone
    return owner.userEmail == emailOrPhone || 
           (owner.userPhone != null && owner.userPhone == emailOrPhone);
  }

  bool _isUserAlreadyAdded(String emailOrPhone) {
    // Check if user already exists in the users list
    return _users.any((user) => 
        user.userEmail == emailOrPhone || 
        (user.userPhone != null && user.userPhone == emailOrPhone));
  }

  void _showOwnerWarning() {
    final t = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            const SizedBox(width: 8),
            Text(t.ownerWarningTitle),
          ],
        ),
        content: Text(t.ownerWarning),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(t.cancel),
          ),
        ],
      ),
    );
  }

  void _showAlreadyAddedWarning() {
    final t = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info, color: Colors.blue),
            const SizedBox(width: 8),
            Text(t.alreadyAddedWarningTitle),
          ],
        ),
        content: Text(t.alreadyAddedWarning),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(t.cancel),
          ),
        ],
      ),
    );
  }

  List<BusinessUser> get _filteredUsers {
    return _users;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Header Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  businessSubpageBackLeading(context, int.parse(widget.businessId)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.people_alt_outlined,
                      size: 24,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.usersAndPermissions,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.businessUsers,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_users.length} ${t.user}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Leave button for members (non-owners)
                  if (_isCurrentUserMember()) ...[
                    const SizedBox(width: 8),
                    _buildLeaveButton(context, theme, colorScheme),
                  ],
                ],
              ),
            ),

            // Content Area
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Add User Section
                    _buildAddUserSection(t, theme, colorScheme),
                    const SizedBox(height: 24),

                    // Users List
                    _buildUsersList(t, theme, colorScheme),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddUserSection(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
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
                Icons.person_add_outlined,
                size: 20,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                t.addNewUser,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = ResponsiveHelper.isMobile(context);
              if (isMobile) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _emailOrPhoneController,
                      decoration: InputDecoration(
                        labelText: t.userEmailOrPhone,
                        hintText: t.userEmailOrPhoneHint,
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _addUser,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(t.addUser),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                );
              } else {
                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _emailOrPhoneController,
                        decoration: InputDecoration(
                          labelText: t.userEmailOrPhone,
                          hintText: t.userEmailOrPhoneHint,
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _addUser,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(t.addUser),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t.businessMembershipUnlimited),
            value: _addMembershipUnlimited,
            onChanged: (v) {
              setState(() {
                _addMembershipUnlimited = v;
                if (v) {
                  _addMembershipEndDate = null;
                }
              });
            },
          ),
          if (!_addMembershipUnlimited) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _addMembershipEndDate == null
                        ? t.businessMembershipLimited
                        : HesabixDateUtils.formatForDisplay(
                            _addMembershipEndDate!,
                            widget.calendarController.isJalali,
                          ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickAddMembershipEndDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(t.businessMembershipPickDate),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }



  Widget _buildUsersList(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    if (_loading) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                t.loading,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadUsers,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(t.retry),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.errorContainer,
                  foregroundColor: colorScheme.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredUsers.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.people_outline,
                size: 48,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                t.noUsersFound,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredUsers.length,
      itemBuilder: (context, index) {
        final user = _filteredUsers[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildUserCard(user, t, theme, colorScheme),
        );
      },
    );
  }


  Widget _buildUserCard(BusinessUser user, AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  user.userName.isNotEmpty ? user.userName[0].toUpperCase() : 'U',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // User Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.userName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.role == 'owner') ...[
                        const SizedBox(width: 8),
                        _buildOwnerChip(theme, colorScheme),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.userEmail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (user.userPhone != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      user.userPhone!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  if (user.role != 'owner') ...[
                    const SizedBox(height: 2),
                    Text(
                      _membershipLineForUserCard(user, t),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: user.membershipActive ? colorScheme.primary : colorScheme.error,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Actions Menu
            if (user.role != 'owner')
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'permissions':
                      _showPermissionsDialog(user);
                      break;
                    case 'remove':
                      _removeUser(user);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'permissions',
                    child: Row(
                      children: [
                        Icon(
                          Icons.security_outlined,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Text(t.editPermissions),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: colorScheme.error,
                        ),
                        const SizedBox(width: 12),
                        Text(t.removeUser),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _membershipLineForUserCard(BusinessUser user, AppLocalizations t) {
    if (user.membershipUnlimited) {
      return t.businessMembershipUnlimited;
    }
    if (!user.membershipActive) {
      return t.businessMembershipExpired;
    }
    final d = user.membershipExpiresAt;
    if (d == null) {
      return t.businessMembershipUnlimited;
    }
    final formatted = HesabixDateUtils.formatForDisplay(d, widget.calendarController.isJalali);
    return t.businessMembershipUntil(formatted);
  }

  Widget _buildOwnerChip(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star,
            color: Colors.orange,
            size: 12,
          ),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.of(context).owner,
            style: TextStyle(
              color: Colors.orange.shade700,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showPermissionsDialog(BusinessUser user) async {
    
    // Load fresh user data with permissions
    try {
      final freshUser = await _userService.getUserDetails(int.parse(widget.businessId), user.userId);
      
      if (mounted) {
    showDialog(
      context: context,
          builder: (context) => _PermissionsDialog(
            user: freshUser,
            businessId: widget.businessId,
            userService: _userService,
            calendarController: widget.calendarController,
            onPermissionsUpdated: () {
              // Refresh the users list after permissions are updated
              _loadUsers();
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(
        'خطا در بارگذاری دسترسی‌ها: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    }
  }

  bool _isCurrentUserMember() {
    final currentUserId = widget.authStore.currentUserId;
    if (currentUserId == null) return false;
    
    // Check if current user is in the list and is not the owner
    final currentUser = _users.firstWhere(
      (user) => user.userId == currentUserId,
      orElse: () => BusinessUser(
        id: 0,
        businessId: 0,
        userId: 0,
        userName: '',
        userEmail: '',
        userPhone: null,
        role: '',
        status: '',
        addedAt: DateTime.now(),
        lastActive: null,
        permissions: {},
        membershipExpiresAt: null,
        membershipUnlimited: true,
        membershipActive: true,
      ),
    );
    
    return currentUser.userId != 0 && currentUser.role != 'owner';
  }

  Widget _buildLeaveButton(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    return IconButton(
      icon: _isLeaving
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.error),
              ),
            )
          : Icon(
              Icons.exit_to_app,
              color: colorScheme.error,
            ),
      tooltip: 'خروج از کسب و کار',
      onPressed: _isLeaving ? null : () => _handleLeave(context),
    );
  }

  Future<void> _handleLeave(BuildContext context) async {
    final t = AppLocalizations.of(context);
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('خروج از کسب و کار'),
        content: const Text(
          'آیا مطمئن هستید که می‌خواهید از این کسب و کار خارج شوید؟\n\n'
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
      final request = LeaveBusinessRequest(businessId: int.parse(widget.businessId));
      final response = await _userService.leaveBusiness(request);

      if (response.success && mounted) {
        _showSuccessSnackBar(response.message);
        
        // Clear current business if it's the one we're leaving
        if (widget.authStore.currentBusiness?.id == int.parse(widget.businessId)) {
          await widget.authStore.clearCurrentBusiness();
        }
        
        // Navigate to businesses list
        if (mounted) {
          context.go('/user/profile/businesses');
        }
      } else if (mounted) {
        _showErrorSnackBar(response.message);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(
        'خطا در خروج از کسب و کار: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLeaving = false;
        });
      }
    }
  }

}

/// دیالوگ مدیریت دسترسی‌ها
class _PermissionsDialog extends StatefulWidget {
  final BusinessUser user;
  final String businessId;
  final BusinessUserService userService;
  final CalendarController calendarController;
  final VoidCallback onPermissionsUpdated;

  const _PermissionsDialog({
    required this.user,
    required this.businessId,
    required this.userService,
    required this.calendarController,
    required this.onPermissionsUpdated,
  });

  @override
  State<_PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<_PermissionsDialog> {
  late Map<String, dynamic> _currentPermissions;
  bool _isUpdating = false;
  late bool _membershipUnlimited;
  DateTime? _membershipEndDate;
  bool _membershipTouched = false;

  @override
  void initState() {
    super.initState();
    _currentPermissions = _mergePermissions(widget.user.permissions);
    _membershipEndDate = widget.user.membershipExpiresAt;
    _membershipUnlimited = widget.user.membershipUnlimited;
  }

  /// ساختار کامل دسترسی‌های سیستم
  Map<String, Map<String, String>> _getAllPermissions(AppLocalizations t) {
    return {
      'people': {
        'add': '${t.add} ${t.people}',
        'view': '${t.view} ${t.people}',
        'edit': '${t.edit} ${t.people}',
        'delete': '${t.delete} ${t.people}',
      },
      // Combined: receipts + payments of people as a single unit
      'people_transactions': {
        'add': '${t.add} ${t.receiptsAndPayments} ${t.people}',
        'view': '${t.view} ${t.receiptsAndPayments} ${t.people}',
        'edit': '${t.edit} ${t.receiptsAndPayments} ${t.people}',
        'delete': '${t.delete} ${t.receiptsAndPayments} ${t.people}',
        'draft': '${t.draft} ${t.receiptsAndPayments} ${t.people}',
      },
      'products': {
        'add': '${t.add} ${t.products}',
        'view': '${t.view} ${t.products}',
        'edit': '${t.edit} ${t.products}',
        'delete': '${t.delete} ${t.products}',
        'export': '${t.export} ${t.products}',
      },
      'price_lists': {
        'add': '${t.add} ${t.priceLists}',
        'view': '${t.view} ${t.priceLists}',
        'edit': '${t.edit} ${t.priceLists}',
        'delete': '${t.delete} ${t.priceLists}',
      },
      'categories': {
        'add': '${t.add} ${t.categories}',
        'view': '${t.view} ${t.categories}',
        'edit': '${t.edit} ${t.categories}',
        'delete': '${t.delete} ${t.categories}',
      },
      'product_attributes': {
        'add': '${t.add} ${t.productAttributes}',
        'view': '${t.view} ${t.productAttributes}',
        'edit': '${t.edit} ${t.productAttributes}',
        'delete': '${t.delete} ${t.productAttributes}',
      },
      'bank_accounts': {
        'add': '${t.add} ${t.bankAccounts}',
        'view': '${t.view} ${t.bankAccounts}',
        'edit': '${t.edit} ${t.bankAccounts}',
        'delete': '${t.delete} ${t.bankAccounts}',
      },
      'cash': {
        'add': '${t.add} ${t.cash}',
        'view': '${t.view} ${t.cash}',
        'edit': '${t.edit} ${t.cash}',
        'delete': '${t.delete} ${t.cash}',
      },
      'petty_cash': {
        'add': '${t.add} ${t.pettyCash}',
        'view': '${t.view} ${t.pettyCash}',
        'edit': '${t.edit} ${t.pettyCash}',
        'delete': '${t.delete} ${t.pettyCash}',
      },
      'checks': {
        'add': '${t.add} ${t.checks}',
        'view': '${t.view} ${t.checks}',
        'edit': '${t.edit} ${t.checks}',
        'delete': '${t.delete} ${t.checks}',
        'collect': '${t.collect} ${t.checks}',
        'transfer': '${t.transfer} ${t.checks}',
        'return': t.returnChecks,
      },
      'wallet': {
        'view': '${t.view} ${t.wallet}',
        'charge': '${t.charge} ${t.wallet}',
      },
      'transfers': {
        'add': '${t.add} ${t.transfers}',
        'view': '${t.view} ${t.transfers}',
        'edit': '${t.edit} ${t.transfers}',
        'delete': '${t.delete} ${t.transfers}',
        'draft': '${t.draft} ${t.transfers}',
      },
      'invoices': {
        'add': '${t.add} ${t.invoices}',
        'view': '${t.view} ${t.invoices}',
        'edit': '${t.edit} ${t.invoices}',
        'delete': '${t.delete} ${t.invoices}',
        'draft': '${t.draft} ${t.invoices}',
        'export': '${t.export} ${t.invoices}',
        'change_unit_price': t.permissionInvoiceChangeUnitPrice,
      },
      'invoice_types': {
        'sales': t.invoiceTypeSales,
        'sales_return': t.invoiceTypeSalesReturn,
        'purchase': t.invoiceTypePurchase,
        'purchase_return': t.invoiceTypePurchaseReturn,
        'waste': t.invoiceTypeWaste,
        'direct_consumption': t.invoiceTypeDirectConsumption,
        'production': t.invoiceTypeProduction,
      },
      'pricing': {
        'sales_price_view': '${t.view} ${t.salesPrice}',
        'purchase_price_view': '${t.view} ${t.purchasePrice}',
      },
      'expenses_income': {
        'add': '${t.add} ${t.expensesIncome}',
        'view': '${t.view} ${t.expensesIncome}',
        'edit': '${t.edit} ${t.expensesIncome}',
        'delete': '${t.delete} ${t.expensesIncome}',
        'draft': '${t.draft} ${t.expensesIncome}',
      },
      'accounting_documents': {
        'add': '${t.add} ${t.accountingDocuments}',
        'view': '${t.view} ${t.accountingDocuments}',
        'edit': '${t.edit} ${t.accountingDocuments}',
        'delete': '${t.delete} ${t.accountingDocuments}',
        'draft': '${t.draft} ${t.accountingDocuments}',
      },
      'chart_of_accounts': {
        'add': '${t.add} ${t.chartOfAccounts}',
        'view': '${t.view} ${t.chartOfAccounts}',
        'edit': '${t.edit} ${t.chartOfAccounts}',
        'delete': '${t.delete} ${t.chartOfAccounts}',
      },
      'currency_revaluation': {
        'add': '${t.add} ${t.currencyRevaluation}',
        'view': '${t.view} ${t.currencyRevaluation}',
        'edit': '${t.edit} ${t.currencyRevaluation}',
        'delete': '${t.delete} ${t.currencyRevaluation}',
      },
      'opening_balance': {
        'view': '${t.view} ${t.openingBalance}',
        'edit': '${t.edit} ${t.openingBalance}',
      },
      'warehouses': {
        'add': '${t.add} ${t.warehouses}',
        'view': '${t.view} ${t.warehouses}',
        'edit': '${t.edit} ${t.warehouses}',
        'delete': '${t.delete} ${t.warehouses}',
      },
      'warehouse_transfers': {
        'add': '${t.add} ${t.warehouseTransfers}',
        'view': '${t.view} ${t.warehouseTransfers}',
        'edit': '${t.edit} ${t.warehouseTransfers}',
        'delete': '${t.delete} ${t.warehouseTransfers}',
        'draft': '${t.draft} ${t.warehouseTransfers}',
      },
      'settings': {
        'business': t.businessSettings,
        'print': t.printSettings,
        'history': t.eventHistory,
        'users': t.usersAndPermissions,
        'manage_ftp': t.settingsPermissionManageFtp,
      },
      'storage': {
        'view': '${t.view} ${t.storageSpace}',
        'delete': '${t.delete} ${t.deleteFiles}',
      },
      'sms': {
        'history': t.viewSmsHistory,
        'templates': t.manageSmsTemplates,
      },
      'marketplace': {
        'view': t.viewMarketplace,
        'buy': t.buyPlugins,
        'invoices': t.viewInvoices,
      },
      'reports': {
        'view': '${t.view} ${t.reports}',
        'export': '${t.export} ${t.reports}',
      },
      'fiscal_years': {
        'view': '${t.view} ${t.fiscalYears}',
        'edit': t.permissionFiscalYearEditCurrent,
        'close': t.permissionFiscalYearClose,
        'rollback': t.permissionFiscalYearRollbackDangerous,
      },
      'warranty': {
        'read': '${t.view} ${t.warranty}',
        'write': '${t.edit} ${t.warranty}',
        'delete': '${t.delete} ${t.warranty}',
        'manage': '${t.manage} ${t.warranty}',
      },
      'customer_club': {
        'view': '${t.view} ${t.customerClubTitle}',
        'manage': t.customerClubPermissionManageSettings(t.customerClubTitle),
        'adjust': t.customerClubPermissionAdjustManual(t.customerClubTitle),
        'redeem': t.customerClubPermissionRedeemInvoice(t.customerClubTitle),
      },
      'crm': {
        'view': '${t.view} ${t.workflowCategoryCrm}',
        'write': t.permissionCrmEditAndAdd,
        'reports': t.permissionCrmViewReports,
        'reports_team': t.permissionCrmTeamPerformanceReports,
      },
      'crm_web_chat': {
        'view': t.permissionCrmWebChatView,
        'reply': t.permissionCrmWebChatReply,
        'manage_widgets': t.permissionCrmWebChatManageWidgets,
        'edit_conversations': t.permissionCrmWebChatEditConversations,
        'delete_messages': t.permissionCrmWebChatDeleteMessages,
      },
      'distribution': {
        'view': '${t.view} ${t.distributionMenu}',
        'manage': t.distributionPermissionManage,
        'operate': t.distributionPermissionOperate,
        'reports_team': t.distributionPermissionReportsTeam,
      },
      'basalam': {
        'view': t.localeName.startsWith('fa') ? 'مشاهدهٔ اتصال باسلام' : 'View Basalam integration',
        'manage': t.localeName.startsWith('fa') ? 'مدیریت تنظیمات باسلام' : 'Manage Basalam settings',
        'sync': t.localeName.startsWith('fa') ? 'همگام‌سازی و انتشار باسلام' : 'Basalam sync & publish',
      },
      'woocommerce': {
        'view': t.permissionWooCommerceView,
        'manage': t.permissionWooCommerceManage,
      },
      'moadian': {
        'view': t.moadianPermissionView,
        'operate': t.moadianPermissionOperate,
        'manage_settings': t.moadianPermissionManageSettings,
        'export_reports': t.moadianPermissionExportReports,
      },
    };
  }

  /// ادغام دسترسی‌های دیتابیس با ساختار کامل
  Map<String, dynamic> _mergePermissions(Map<String, dynamic> dbPermissions) {
    final t = AppLocalizations.of(context);
    final allPermissions = _getAllPermissions(t);
    final mergedPermissions = <String, dynamic>{};
    
    for (final section in allPermissions.keys) {
      final sectionPermissions = <String, bool>{};
      
      for (final action in allPermissions[section]!.keys) {
        // فقط از سکشن جدید استفاده می‌کنیم؛ بدون OR با کلیدهای قدیمی
        late bool sectionPermissionsValue;
        if (section == 'invoices' && action == 'change_unit_price') {
          if (dbPermissions.containsKey(section) &&
              dbPermissions[section] is Map<String, dynamic> &&
              (dbPermissions[section] as Map<String, dynamic>).containsKey(action)) {
            sectionPermissionsValue = dbPermissions[section][action] == true;
          } else {
            // پیش‌فرض سازگاری: بدون این کلید مثل قبل اجازهٔ تغییر فی
            sectionPermissionsValue = true;
          }
        } else if (dbPermissions.containsKey(section) &&
            dbPermissions[section] is Map<String, dynamic> &&
            (dbPermissions[section] as Map<String, dynamic>).containsKey(action)) {
          sectionPermissionsValue = dbPermissions[section][action] == true;
        } else {
          sectionPermissionsValue = false;
        }
        sectionPermissions[action] = sectionPermissionsValue;
      }
      
      mergedPermissions[section] = sectionPermissions;
    }
    
    return mergedPermissions;
  }

  /// دریافت دسترسی
  bool _getPermission(Map<String, dynamic> permissions, String section, String action) {
    if (!permissions.containsKey(section)) return false;
    final sectionPerms = permissions[section] as Map<String, dynamic>?;
    if (sectionPerms == null) return false;
    return sectionPerms[action] == true;
  }

  /// تنظیم دسترسی
  void _setPermission(Map<String, dynamic> permissions, String section, String action, bool value) {
    if (!permissions.containsKey(section)) {
      permissions[section] = {};
    }
    // Enforce dependency: view is prerequisite for other actions
    if (action != 'view' && value == true) {
      permissions[section]['view'] = true;
    }

    // Prevent disabling view while dependent actions are enabled
    if (action == 'view' && value == false) {
      final sectionPerms = (permissions[section] as Map<String, dynamic>?) ?? {};
      final hasAnyOtherEnabled = sectionPerms.entries.any((e) => e.key != 'view' && e.value == true);
      if (hasAnyOtherEnabled) {
        // Keep view enabled; do not change
        permissions[section]['view'] = true;
        return;
      }
    }

    permissions[section][action] = value;

    // وابستگی CRM: reports_team مستلزم reports است
    if (section == 'crm' && action == 'reports_team' && value == true) {
      permissions[section]['reports'] = true;
    }
    if (section == 'crm' && action == 'reports' && value == false) {
      permissions[section]['reports_team'] = false;
    }

    if (section == 'crm_web_chat' && action != 'view' && value == true) {
      permissions[section]['view'] = true;
    }

    if (section == 'distribution' && action == 'reports_team' && value == true) {
      permissions[section]['view'] = true;
    }

    // دیگر mirroring به کلیدهای قدیمی انجام نمی‌شود
    if (section == 'people_transactions') {
      // no-op: فقط روی people_transactions ذخیره می‌کنیم
    }
  }

  bool _hasAnyNonViewEnabled(String sectionKey) {
    final sectionPerms = (_currentPermissions[sectionKey] as Map<String, dynamic>?) ?? {};
    for (final entry in sectionPerms.entries) {
      if (entry.key != 'view' && entry.value == true) return true;
    }
    return false;
  }

  Widget _buildMembershipSection(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              t.businessMembershipSectionTitle,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.businessMembershipUnlimited),
          value: _membershipUnlimited,
          onChanged: (v) {
            setState(() {
              _membershipUnlimited = v;
              _membershipTouched = true;
              if (v) {
                _membershipEndDate = null;
              }
            });
          },
        ),
        if (!_membershipUnlimited) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  _membershipEndDate == null
                      ? t.businessMembershipLimited
                      : HesabixDateUtils.formatForDisplay(
                          _membershipEndDate!,
                          widget.calendarController.isJalali,
                        ),
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
              TextButton.icon(
                onPressed: _pickDialogMembershipEndDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(t.businessMembershipPickDate),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _pickDialogMembershipEndDate() async {
    final t = AppLocalizations.of(context);
    final now = DateTime.now();
    final initial = _membershipEndDate ?? now.add(const Duration(days: 1));
    final picked = await showAdaptiveDatePicker(
      context: context,
      calendarController: widget.calendarController,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: t.businessMembershipPickDate,
    );
    if (picked != null && mounted) {
      setState(() {
        _membershipEndDate = picked;
        _membershipUnlimited = false;
        _membershipTouched = true;
      });
    }
  }

  /// به‌روزرسانی دسترسی‌ها
  Future<void> _updatePermissions() async {
    if (_isUpdating) return;
    final t = AppLocalizations.of(context);
    if (widget.user.role != 'owner' && _membershipTouched && !_membershipUnlimited && _membershipEndDate == null) {
      _showErrorSnackBar(t.businessMembershipEndDateRequired);
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      final request = UpdatePermissionsRequest(
        businessId: int.parse(widget.businessId),
        userId: widget.user.userId,
        permissions: _currentPermissions,
        applyMembershipExpiry: _membershipTouched,
        membershipExpiresAt: _membershipUnlimited
            ? null
            : (_membershipEndDate != null ? _membershipEndOfLocalDayUtc(_membershipEndDate!) : null),
      );

      final response = await widget.userService.updatePermissions(request);
      
      if (mounted) {
        if (response.success) {
          _showSuccessSnackBar(response.message);
          widget.onPermissionsUpdated();
          Navigator.of(context).pop();
        } else {
          _showErrorSnackBar(response.message);
        }
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        _showErrorSnackBar(
          t.permissionsUpdateError(ErrorExtractor.forContext(e, context)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    SnackBarHelper.showError(context, message: message);
  }

  void _showSuccessSnackBar(String message) {
    SnackBarHelper.showSuccess(context, message: message);
  }

  /// ترتیب فعال‌سازی: ابتدا `view` تا قوانین پیش‌نیاز `_setPermission` رعایت شود.
  List<String> _orderedActionsForEnable(Iterable<String> actions) {
    final list = actions.toList();
    final viewFirst = list.where((a) => a == 'view').toList();
    final rest = list.where((a) => a != 'view').toList()..sort();
    return [...viewFirst, ...rest];
  }

  void _applyAllPermissions(bool enable) {
    final t = AppLocalizations.of(context);
    final all = _getAllPermissions(t);
    for (final entry in all.entries) {
      final section = entry.key;
      final actionKeys = entry.value.keys.toList();
      if (enable) {
        for (final action in _orderedActionsForEnable(actionKeys)) {
          _setPermission(_currentPermissions, section, action, true);
        }
      } else {
        final nonView = actionKeys.where((a) => a != 'view').toList()..sort();
        final onlyView = actionKeys.where((a) => a == 'view').toList();
        for (final action in nonView) {
          _setPermission(_currentPermissions, section, action, false);
        }
        for (final action in onlyView) {
          _setPermission(_currentPermissions, section, action, false);
        }
      }
    }
    setState(() {});
  }

  void _applyCategoryPermissions(List<String> sectionKeys, bool enable) {
    final t = AppLocalizations.of(context);
    final all = _getAllPermissions(t);
    for (final section in sectionKeys) {
      final def = all[section];
      if (def == null) continue;
      final actionKeys = def.keys.toList();
      if (enable) {
        for (final action in _orderedActionsForEnable(actionKeys)) {
          _setPermission(_currentPermissions, section, action, true);
        }
      } else {
        final nonView = actionKeys.where((a) => a != 'view').toList()..sort();
        final onlyView = actionKeys.where((a) => a == 'view').toList();
        for (final action in nonView) {
          _setPermission(_currentPermissions, section, action, false);
        }
        for (final action in onlyView) {
          _setPermission(_currentPermissions, section, action, false);
        }
      }
    }
    setState(() {});
  }

  Future<void> _confirmAndApplyAllPermissions(bool enable) async {
    if (enable) {
      _applyAllPermissions(true);
      return;
    }
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.permissionsConfirmDisableAllTitle),
        content: SingleChildScrollView(
          child: Text(t.permissionsConfirmDisableAllBody),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.confirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _applyAllPermissions(false);
  }

  Future<void> _confirmAndApplyCategoryPermissions(
    List<String> sectionKeys,
    String categoryTitle,
    bool enable,
  ) async {
    if (enable) {
      _applyCategoryPermissions(sectionKeys, true);
      return;
    }
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.permissionsConfirmDisableCategoryTitle),
        content: SingleChildScrollView(
          child: Text(t.permissionsConfirmDisableCategoryBody(categoryTitle)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.confirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _applyCategoryPermissions(sectionKeys, false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
          
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
      child: SizedBox(
        width: 800,
        height: 700,
              child: Column(
                children: [
                  // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.security, color: colorScheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${t.userPermissions} - ${widget.user.userName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: t.dialogClose,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, color: colorScheme.onSurfaceVariant, size: 18),
                    ),
                  ),
                ],
              ),
            ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 0,
                        alignment: WrapAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _isUpdating ? null : () => _confirmAndApplyAllPermissions(true),
                            child: Text(t.permissionsEnableAll),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: colorScheme.error,
                            ),
                            onPressed: _isUpdating ? null : () => _confirmAndApplyAllPermissions(false),
                            child: Text(t.permissionsDisableAll),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                  children: [
                    if (widget.user.role != 'owner') ...[
                      _buildMembershipSection(t, theme, colorScheme),
                      const SizedBox(height: 20),
                    ],
                    ..._buildAllPermissionSections(t, theme, colorScheme),
                  ],
                ),
                    ),
                  ),

                  // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _isUpdating ? null : () => Navigator.of(context).pop(),
                    child: Text(t.cancel),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isUpdating ? null : _updatePermissions,
                    icon: _isUpdating
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save, size: 16),
                    label: Text(
                      _isUpdating ? t.saving : t.savePermissions,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
            ),
                ],
              ),
            ),
          );
  }

  /// ساخت تمام بخش‌های دسترسی به صورت پویا
  List<Widget> _buildAllPermissionSections(
    AppLocalizations t,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final sections = <Widget>[];
    
    // تعریف بخش‌ها و آیکون‌هایشان
    final sectionConfigs = [
      {
        'title': t.people,
        'icon': Icons.people,
        'sections': ['people', 'people_transactions'],
      },
      {
        'title': t.products,
        'icon': Icons.inventory,
        'sections': ['products', 'price_lists', 'categories', 'product_attributes'],
      },
      {
        'title': t.banking,
        'icon': Icons.account_balance,
        'sections': ['bank_accounts', 'cash', 'petty_cash', 'checks', 'wallet', 'transfers'],
      },
      {
        'title': t.permissionsCategoryInvoicesAndExpenses,
        'icon': Icons.receipt,
        'sections': ['invoices', 'invoice_types', 'pricing', 'expenses_income'],
      },
      {
        'title': t.accounting,
        'icon': Icons.calculate,
        'sections': ['accounting_documents', 'chart_of_accounts', 'opening_balance', 'currency_revaluation'],
      },
      {
        'title': t.warehouseManagement,
        'icon': Icons.warehouse,
        'sections': ['warehouses', 'warehouse_transfers'],
        'permissionHintKey': 'warehouse_inventory_bridge',
      },
      {
        'title': t.reports,
        'icon': Icons.assessment,
        'sections': ['reports'],
      },
      {
        'title': t.workflowCategoryCrm,
        'icon': Icons.handshake_outlined,
        'sections': ['crm', 'crm_web_chat'],
      },
      {
        'title': t.settings,
        'icon': Icons.settings,
        'sections': ['settings', 'storage', 'sms', 'marketplace', 'fiscal_years'],
      },
      {
        'title': t.warranty,
        'icon': Icons.verified_user,
        'sections': ['warranty'],
      },
      {
        'title': t.customerClubMenu,
        'icon': Icons.card_giftcard,
        'sections': ['customer_club'],
      },
      {
        'title': t.distributionMenu,
        'icon': Icons.local_shipping_outlined,
        'sections': ['distribution'],
      },
      {
        'title': t.localeName.startsWith('fa') ? 'اتصال فروشگاه' : 'Store integrations',
        'icon': Icons.store_mall_directory_outlined,
        'sections': ['basalam', 'woocommerce'],
      },
      {
        'title': t.moadianMenuSection,
        'icon': Icons.account_balance_outlined,
        'sections': ['moadian'],
      },
    ];
    
    for (int i = 0; i < sectionConfigs.length; i++) {
      final config = sectionConfigs[i];
      final sectionWidgets = <Widget>[];
      
      // ساخت گروه‌های دسترسی برای هر بخش
      for (final sectionKey in config['sections'] as List<String>) {
        final allPermissions = _getAllPermissions(t);
        if (allPermissions.containsKey(sectionKey)) {
          final sectionPermissions = allPermissions[sectionKey]!;
          final permissionItems = <Widget>[];
          
          for (final action in sectionPermissions.keys) {
            permissionItems.add(
              _buildPermissionItem(
                sectionKey,
                action,
                _localizeAction(t, sectionKey, action),
                sectionPermissions[action]!,
                _getPermission(_currentPermissions, sectionKey, action),
                (value) {
                  _setPermission(_currentPermissions, sectionKey, action, value);
                  setState(() {});
                },
                theme,
                colorScheme,
              ),
            );
          }
          
          final String? groupInfo = switch (sectionKey) {
            'checks' => t.permissionsGroupHintChecks,
            'accounting_documents' => t.permissionsGroupHintAccountingDocuments,
            _ => null,
          };
          sectionWidgets.add(
            _buildPermissionGroup(
              _getSectionTitle(t, sectionKey),
              permissionItems,
              theme,
              colorScheme,
              groupInfo: groupInfo,
            ),
          );
        }
      }

      final hintKey = config['permissionHintKey'] as String?;
      final String? hintText = hintKey == 'warehouse_inventory_bridge'
          ? t.permissionsWarehouseInventoryHint
          : null;
      
      sections.add(
        _buildPermissionSection(
          config['title'] as String,
          config['icon'] as IconData,
          sectionWidgets,
          theme,
          colorScheme,
          hintText: hintText,
          categorySectionKeys: List<String>.from(config['sections'] as List<String>),
          l10n: t,
        ),
      );
      
      // اضافه کردن فاصله بین بخش‌ها
      if (i < sectionConfigs.length - 1) {
        sections.add(const SizedBox(height: 20));
      }
    }
    
    return sections;
  }

  /// دریافت عنوان بخش بر اساس کلید
  String _getSectionTitle(AppLocalizations t, String sectionKey) {
    switch (sectionKey) {
      case 'people':
        return t.people;
      case 'people_receipts':
        return t.receipts;
      case 'people_payments':
        return t.payments;
      case 'people_transactions':
        return '${t.receiptsAndPayments} ${t.people}';
      case 'products':
        return t.products;
      case 'price_lists':
        return t.priceLists;
      case 'categories':
        return t.categories;
      case 'product_attributes':
        return t.productAttributes;
      case 'bank_accounts':
        return t.bankAccounts;
      case 'cash':
        return t.cash;
      case 'petty_cash':
        return t.pettyCash;
      case 'checks':
        return t.checks;
      case 'wallet':
        return t.wallet;
      case 'transfers':
        return t.transfers;
      case 'invoices':
        return t.invoices;
      case 'invoice_types':
        return t.permissionSectionInvoiceTypes;
      case 'pricing':
        return t.permissionSectionPricing;
      case 'expenses_income':
        return t.expensesIncome;
      case 'accounting_documents':
        return t.accountingDocuments;
      case 'chart_of_accounts':
        return t.chartOfAccounts;
      case 'currency_revaluation':
        return t.currencyRevaluation;
      case 'opening_balance':
        return t.openingBalance;
      case 'warehouses':
        return t.warehouses;
      case 'warehouse_transfers':
        return t.warehouseTransfers;
      case 'settings':
        return t.settings;
      case 'storage':
        return t.storageSpace;
      case 'sms':
        return t.smsPanel;
      case 'marketplace':
        return t.marketplace;
      case 'reports':
        return t.reports;
      case 'fiscal_years':
        return t.fiscalYears;
      case 'warranty':
        return t.warranty;
      case 'customer_club':
        return t.customerClubMenu;
      case 'distribution':
        return t.distributionMenu;
      case 'basalam':
        return t.localeName.startsWith('fa') ? 'اتصال باسلام' : 'Basalam';
      case 'woocommerce':
        return t.permissionSectionWooCommerce;
      case 'moadian':
        return t.moadianMenuSection;
      case 'crm':
        return t.workflowCategoryCrm;
      case 'crm_web_chat':
        return t.permissionSectionCrmWebChat;
      default:
        return sectionKey;
    }
  }

  String _localizeAction(AppLocalizations t, String sectionKey, String action) {
    switch (action) {
      case 'sales':
        return t.invoiceTypeSales;
      case 'sales_return':
        return t.invoiceTypeSalesReturn;
      case 'purchase':
        return t.invoiceTypePurchase;
      case 'purchase_return':
        return t.invoiceTypePurchaseReturn;
      case 'waste':
        return t.invoiceTypeWaste;
      case 'direct_consumption':
        return t.invoiceTypeDirectConsumption;
      case 'production':
        return t.invoiceTypeProduction;
      case 'sales_price_view':
        return '${t.view} ${t.salesPrice}';
      case 'purchase_price_view':
        return '${t.view} ${t.purchasePrice}';
      case 'add':
        return t.add;
      case 'view':
        return t.view;
      case 'edit':
        return sectionKey == 'fiscal_years' ? t.permissionFiscalYearEditCurrent : t.edit;
      case 'delete':
        return t.delete;
      case 'draft':
        return t.draft;
      case 'read':
        return t.view;
      case 'write':
        if (sectionKey == 'crm') {
          return t.permissionCrmEditAndAdd;
        }
        return t.edit;
      case 'buy':
        return t.buy;
      case 'invoices':
        return t.invoices;
      case 'templates':
        return t.templates;
      case 'history':
        return t.history;
      case 'print':
        return t.print;
      case 'users':
        return t.users;
      case 'business':
        return t.business;
      case 'manage_ftp':
        return t.settingsPermissionManageFtp;
      case 'collect':
        return t.collect;
      case 'transfer':
        return t.transfer;
      case 'charge':
        return t.charge;
      case 'return':
        return t.returnChecks;
      case 'close':
        return sectionKey == 'fiscal_years' ? t.permissionFiscalYearClose : action;
      case 'rollback':
        return sectionKey == 'fiscal_years' ? t.permissionFiscalYearRollbackDangerous : action;
      case 'export':
        return t.export;
      case 'change_unit_price':
        return t.permissionInvoiceChangeUnitPrice;
      case 'manage':
        return t.manage;
      case 'adjust':
        return t.customerClubActionAdjust;
      case 'redeem':
        return t.customerClubActionRedeem;
      case 'reply':
        return t.permissionCrmWebChatReply;
      case 'manage_widgets':
        return t.permissionCrmWebChatManageWidgets;
      case 'edit_conversations':
        return t.permissionCrmWebChatEditConversations;
      case 'delete_messages':
        return t.permissionCrmWebChatDeleteMessages;
      case 'operate':
        return t.distributionPermissionOperate;
      case 'sync':
        if (sectionKey == 'basalam') {
          return t.localeName.startsWith('fa') ? 'همگام‌سازی باسلام' : 'Basalam sync';
        }
        return action;
      case 'reports_team':
        if (sectionKey == 'crm') {
          return t.permissionCrmTeamPerformanceReports;
        }
        return t.distributionPermissionReportsTeam;
      case 'reports':
        return sectionKey == 'crm' ? t.permissionCrmViewReports : t.reports;
      default:
        return action;
    }
  }

  Widget _buildPermissionSection(
    String title,
    IconData icon,
    List<Widget> permissions,
    ThemeData theme,
    ColorScheme colorScheme, {
    String? hintText,
    List<String>? categorySectionKeys,
    AppLocalizations? l10n,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                if (categorySectionKeys != null &&
                    categorySectionKeys.isNotEmpty &&
                    l10n != null) ...[
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _isUpdating
                        ? null
                        : () => _confirmAndApplyCategoryPermissions(
                              categorySectionKeys,
                              title,
                              true,
                            ),
                    child: Text(l10n.permissionsEnableAll),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _isUpdating
                        ? null
                        : () => _confirmAndApplyCategoryPermissions(
                              categorySectionKeys,
                              title,
                              false,
                            ),
                    child: Text(l10n.permissionsDisableAll),
                  ),
                ],
              ],
            ),
          ),
          if (hintText != null && hintText.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _buildPermissionHintBox(theme, colorScheme, hintText),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: permissions,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionHintBox(
    ThemeData theme,
    ColorScheme colorScheme,
    String text,
  ) {
    final border = colorScheme.secondary.withValues(alpha: 0.35);
    final bg = colorScheme.secondaryContainer.withValues(alpha: 0.25);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 20,
              color: colorScheme.secondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionGroup(
    String groupTitle,
    List<Widget> permissions,
    ThemeData theme,
    ColorScheme colorScheme, {
    String? groupInfo,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            groupTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
          if (groupInfo != null) ...[
            const SizedBox(height: 8),
            Text(
              groupInfo,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ...permissions,
        ],
      ),
    );
  }

  Widget _buildPermissionItem(
    String sectionKey,
    String actionKey,
    String title,
    String description,
    bool value,
    ValueChanged<bool> onChanged,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isViewItem = actionKey == 'view';
    final mustKeepViewEnabled = isViewItem && _hasAnyNonViewEnabled(sectionKey);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Switch(
            value: value,
            onChanged: mustKeepViewEnabled ? null : onChanged,
            activeThumbColor: colorScheme.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
