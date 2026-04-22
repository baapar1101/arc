import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../services/business_user_service.dart';
import '../../models/business_user_model.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/business_subpage_back_leading.dart';


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
          _error = e.toString();
        });
        _showErrorSnackBar('${AppLocalizations.of(context).dataLoadingError}: $e');
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
    try {
      final request = AddUserRequest(
        businessId: int.parse(widget.businessId),
        emailOrPhone: emailOrPhone,
      );

      final response = await _userService.addUser(request);
      
      if (response.success) {
        _showSuccessSnackBar(response.message);
        _emailOrPhoneController.clear();
        _loadUsers(); // Refresh the list
      } else {
        _showErrorSnackBar(response.message);
      }
    } catch (e) {
      if (!ctx.mounted) return;
      _showErrorSnackBar('${AppLocalizations.of(ctx).userAddFailed}: $e');
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
      _showErrorSnackBar('${t.userRemoveFailed}: $e');
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
            onPermissionsUpdated: () {
              // Refresh the users list after permissions are updated
              _loadUsers();
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('خطا در بارگذاری دسترسی‌ها: $e');
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
        _showErrorSnackBar('خطا در خروج از کسب و کار: $e');
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
  final VoidCallback onPermissionsUpdated;

  const _PermissionsDialog({
    required this.user,
    required this.businessId,
    required this.userService,
    required this.onPermissionsUpdated,
  });

  @override
  State<_PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<_PermissionsDialog> {
  late Map<String, dynamic> _currentPermissions;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _currentPermissions = _mergePermissions(widget.user.permissions);
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
        'return': 'برگشت ${t.checks}',
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
        'view': '${t.view} ${t.reports ?? 'گزارش‌ها'}',
        'export': '${t.export} ${t.reports ?? 'گزارش‌ها'}',
      },
      'fiscal_years': {
        'view': '${t.view} ${t.fiscalYears ?? 'سال‌های مالی'}',
        'edit': 'ویرایش سال مالی جاری',
        'close': 'بستن سال مالی',
        'rollback': 'برگشت از سال مالی جاری (عملیات خطرناک)',
      },
      'warranty': {
        'read': '${t.view ?? 'مشاهده'} ${t.warranty ?? 'گارانتی'}',
        'write': '${t.add ?? 'افزودن'} ${t.warranty ?? 'گارانتی'}',
        'delete': '${t.delete ?? 'حذف'} ${t.warranty ?? 'گارانتی'}',
        'manage': '${t.manage ?? 'مدیریت'} ${t.warranty ?? 'گارانتی'}',
      },
      'customer_club': {
        'view': '${t.view} ${t.customerClubTitle}',
        'manage': t.customerClubPermissionManageSettings(t.customerClubTitle),
        'adjust': t.customerClubPermissionAdjustManual(t.customerClubTitle),
        'redeem': t.customerClubPermissionRedeemInvoice(t.customerClubTitle),
      },
      'crm': {
        'view': '${t.view ?? 'مشاهده'} CRM',
        'write': '${t.edit ?? 'ویرایش'} / ${t.add ?? 'افزودن'} CRM',
        'reports': '${t.view ?? 'مشاهده'} گزارشات CRM',
        'reports_team': 'گزارش عملکرد کارمندان (همه تیم)',
      },
      'distribution': {
        'view': '${t.view} ${t.distributionMenu}',
        'manage': t.distributionPermissionManage,
        'operate': t.distributionPermissionOperate,
        'reports_team': t.distributionPermissionReportsTeam,
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
        if (dbPermissions.containsKey(section) &&
            dbPermissions[section] is Map<String, dynamic> &&
            (dbPermissions[section] as Map<String, dynamic>).containsKey(action)) {
          sectionPermissions[action] = dbPermissions[section][action] == true;
        } else {
          sectionPermissions[action] = false;
        }
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

  /// به‌روزرسانی دسترسی‌ها
  Future<void> _updatePermissions() async {
    if (_isUpdating) return;
    
    setState(() {
      _isUpdating = true;
    });

    try {
      final request = UpdatePermissionsRequest(
        businessId: int.parse(widget.businessId),
        userId: widget.user.userId,
        permissions: _currentPermissions,
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
        _showErrorSnackBar('خطا در به‌روزرسانی دسترسی‌ها: $e');
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

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                  children: _buildAllPermissionSections(t, theme, colorScheme),
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
        'title': 'بانکداری',
        'icon': Icons.account_balance,
        'sections': ['bank_accounts', 'cash', 'petty_cash', 'checks', 'wallet', 'transfers'],
      },
      {
        'title': 'فاکتورها و هزینه‌ها',
        'icon': Icons.receipt,
        'sections': ['invoices', 'expenses_income'],
      },
      {
        'title': 'حسابداری',
        'icon': Icons.calculate,
        'sections': ['accounting_documents', 'chart_of_accounts', 'opening_balance', 'currency_revaluation'],
      },
      {
        'title': 'انبارداری',
        'icon': Icons.warehouse,
        'sections': ['warehouses', 'warehouse_transfers'],
      },
      {
        'title': 'گزارش‌ها',
        'icon': Icons.assessment,
        'sections': ['reports'],
      },
      {
        'title': 'CRM',
        'icon': Icons.handshake_outlined,
        'sections': ['crm'],
      },
      {
        'title': 'تنظیمات',
        'icon': Icons.settings,
        'sections': ['settings', 'storage', 'sms', 'marketplace', 'fiscal_years'],
      },
      {
        'title': 'گارانتی',
        'icon': Icons.verified_user,
        'sections': ['warranty'],
      },
      {
        'title': 'باشگاه مشتریان',
        'icon': Icons.card_giftcard,
        'sections': ['customer_club'],
      },
      {
        'title': t.distributionMenu,
        'icon': Icons.local_shipping_outlined,
        'sections': ['distribution'],
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
                _localizeAction(action),
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
          
          sectionWidgets.add(
            _buildPermissionGroup(
              _getSectionTitle(sectionKey),
              permissionItems,
              theme,
              colorScheme,
            ),
          );
        }
      }
      
      sections.add(
        _buildPermissionSection(
          config['title'] as String,
          config['icon'] as IconData,
          sectionWidgets,
          theme,
          colorScheme,
        ),
      );
      
      // اضافه کردن فاصله بین بخش‌ها
      if (i < sectionConfigs.length - 1) {
        sections.add(const SizedBox(height: 20));
      }
    }
    
    return sections;
  }

  // سعی می‌کند کلید بخش فعلی را برای آیتم تعیین کند (تقریبی)
  String _inferCurrentSectionKey(String title, String description) {
    // جستجو بر اساس کلمات کلیدی ساده
    final pairs = <String, List<String>>{
      'people': [(AppLocalizations.of(context).people)],
      'people_transactions': [
        (AppLocalizations.of(context).receiptsAndPayments),
        (AppLocalizations.of(context).receipts),
        (AppLocalizations.of(context).payments),
      ],
      'products': [(AppLocalizations.of(context).products)],
      'price_lists': [(AppLocalizations.of(context).priceLists)],
      'categories': [(AppLocalizations.of(context).categories)],
      'product_attributes': [(AppLocalizations.of(context).productAttributes)],
      'bank_accounts': [(AppLocalizations.of(context).bankAccounts)],
      'cash': [(AppLocalizations.of(context).cash)],
      'petty_cash': [(AppLocalizations.of(context).pettyCash)],
      'checks': [(AppLocalizations.of(context).checks)],
      'wallet': [(AppLocalizations.of(context).wallet)],
      'transfers': [(AppLocalizations.of(context).transfers)],
      'invoices': [(AppLocalizations.of(context).invoices)],
      'expenses_income': [(AppLocalizations.of(context).expensesIncome)],
      'accounting_documents': [(AppLocalizations.of(context).accountingDocuments)],
      'chart_of_accounts': [(AppLocalizations.of(context).chartOfAccounts)],
      'opening_balance': [(AppLocalizations.of(context).openingBalance)],
      'warehouses': [(AppLocalizations.of(context).warehouses)],
      'warehouse_transfers': [(AppLocalizations.of(context).warehouseTransfers)],
      'settings': [(AppLocalizations.of(context).businessSettings)],
      'storage': [(AppLocalizations.of(context).storageSpace)],
      'sms': [(AppLocalizations.of(context).smsPanel)],
      'marketplace': [(AppLocalizations.of(context).marketplace)],
      'reports': ['گزارش', 'گزارش‌ها', 'reports'],
      'fiscal_years': ['سال مالی', 'سال‌های مالی', 'fiscal year', 'fiscal years'],
      'crm': ['crm', 'CRM'],
    };

    final hay = ('$title $description').toLowerCase();
    for (final entry in pairs.entries) {
      for (final token in entry.value) {
        if (hay.contains(token.toLowerCase())) {
          return entry.key;
        }
      }
    }
    return 'people';
  }

  /// دریافت عنوان بخش بر اساس کلید
  String _getSectionTitle(String sectionKey) {
    final t = AppLocalizations.of(context);
    final titles = {
      'people': 'اشخاص',
      'people_receipts': 'دریافت از اشخاص',
      'people_payments': 'پرداخت‌های اشخاص',
      'people_transactions': '${AppLocalizations.of(context).receiptsAndPayments} ${AppLocalizations.of(context).people}',
      'products': 'کالا و خدمات',
      'price_lists': 'لیست‌های قیمت',
      'categories': 'دسته‌بندی‌ها',
      'product_attributes': 'ویژگی‌های کالا و خدمات',
      'bank_accounts': 'حساب‌های بانکی',
      'cash': 'صندوق',
      'petty_cash': 'تنخواه گردان',
      'checks': 'چک',
      'wallet': 'کیف پول',
      'transfers': 'انتقال',
      'invoices': 'فاکتورها',
      'expenses_income': 'هزینه و درآمد',
      'accounting_documents': 'اسناد حسابداری',
      'chart_of_accounts': 'جدول حساب‌ها',
      'currency_revaluation': t.currencyRevaluation,
      'opening_balance': 'تراز افتتاحیه',
      'warehouses': 'مدیریت انبارها',
      'warehouse_transfers': 'صدور حواله',
      'settings': 'تنظیمات',
      'storage': 'فضای ذخیره‌سازی',
      'sms': 'پنل پیامک',
      'marketplace': 'بازار افزونه‌ها',
      'reports': 'گزارش‌ها',
      'fiscal_years': 'سال‌های مالی',
      'warranty': 'گارانتی',
      'customer_club': t.customerClubMenu,
      'distribution': t.distributionMenu,
      'crm': 'CRM',
    };
    
    return titles[sectionKey] ?? sectionKey;
  }

  String _localizeAction(String action) {
    final t = AppLocalizations.of(context);
    switch (action) {
      case 'add':
        return t.add;
      case 'view':
        return t.view;
      case 'edit':
        return t.edit;
      case 'delete':
        return t.delete;
      case 'draft':
        return t.draft;
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
      case 'collect':
        return t.collect;
      case 'transfer':
        return t.transfer;
      case 'charge':
        return t.charge;
      case 'return':
        return 'برگشت';
      case 'export':
        return t.export ?? 'خروجی';
      case 'manage':
        return t.manage ?? 'مدیریت';
      case 'adjust':
        return t.customerClubActionAdjust;
      case 'redeem':
        return t.customerClubActionRedeem;
      case 'operate':
        return t.distributionPermissionOperate;
      case 'reports_team':
        return t.distributionPermissionReportsTeam;
      default:
        return action;
    }
  }

  Widget _buildPermissionSection(
    String title,
    IconData icon,
    List<Widget> permissions,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
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
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
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

  Widget _buildPermissionGroup(
    String groupTitle,
    List<Widget> permissions,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
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
          const SizedBox(height: 12),
          ...permissions,
        ],
      ),
    );
  }

  Widget _buildPermissionItem(
    String title,
    String description,
    bool value,
    ValueChanged<bool> onChanged,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isViewItem = title == 'view' || description.contains('مشاهده') || description.toLowerCase().contains('view');
    final sectionKey = _inferCurrentSectionKey(title, description);
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
