import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../services/business_user_service.dart';
import '../../models/business_user_model.dart';

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
        _showErrorSnackBar('خطا در بارگذاری کاربران: $e');
      }
    }
  }

  Future<void> _addUser() async {
    if (_emailOrPhoneController.text.trim().isEmpty) {
      _showErrorSnackBar('لطفاً ایمیل یا شماره تلفن را وارد کنید');
      return;
    }

    // Check if trying to add business owner
    if (_isTryingToAddOwner(_emailOrPhoneController.text.trim())) {
      _showOwnerWarning();
      return;
    }

    // Check if user already exists
    if (_isUserAlreadyAdded(_emailOrPhoneController.text.trim())) {
      _showAlreadyAddedWarning();
      return;
    }

    try {
      final request = AddUserRequest(
        businessId: int.parse(widget.businessId),
        emailOrPhone: _emailOrPhoneController.text.trim(),
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
      _showErrorSnackBar('خطا در افزودن کاربر: $e');
    }
  }

  Future<void> _updatePermissions(BusinessUser user, Map<String, dynamic> newPermissions) async {
    try {
      final request = UpdatePermissionsRequest(
        businessId: int.parse(widget.businessId),
        userId: user.userId,
        permissions: newPermissions,
      );

      final response = await _userService.updatePermissions(request);
      
      if (response.success) {
        _showSuccessSnackBar(response.message);
        _loadUsers(); // Refresh the list
      } else {
        _showErrorSnackBar(response.message);
      }
    } catch (e) {
      _showErrorSnackBar('خطا در به‌روزرسانی دسترسی‌ها: $e');
    }
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
      _showErrorSnackBar('خطا در حذف کاربر: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
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
                          'مدیریت کاربران و دسترسی‌های کسب و کار',
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
                      '${_users.length} کاربر',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
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
          Row(
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
          ),
        ],
      ),
    );
  }



  Widget _buildUsersList(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    if (_loading) {
      return Container(
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
      return Container(
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
      return Container(
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
            'مالک',
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

  void _showPermissionsDialog(BusinessUser user) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          Map<String, dynamic> currentPermissions = Map.from(user.permissions);
          
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              width: 800,
              height: 700,
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.security,
                            color: colorScheme.onPrimary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${t.userPermissions} - ${user.userName}',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'مدیریت دسترسی‌های کاربر',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => context.pop(),
                          icon: Icon(
                            Icons.close,
                            color: colorScheme.onPrimaryContainer,
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
                        children: [
                          // اشخاص
                          _buildPermissionSection(
                            'اشخاص',
                            Icons.people,
                            [
                              _buildPermissionGroup(
                                'اشخاص',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن شخص جدید', _getPermission(currentPermissions, 'people', 'add'), (value) => _setPermission(currentPermissions, 'people', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده لیست اشخاص', _getPermission(currentPermissions, 'people', 'view'), (value) => _setPermission(currentPermissions, 'people', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش اطلاعات اشخاص', _getPermission(currentPermissions, 'people', 'edit'), (value) => _setPermission(currentPermissions, 'people', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف اشخاص', _getPermission(currentPermissions, 'people', 'delete'), (value) => _setPermission(currentPermissions, 'people', 'delete', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                              _buildPermissionGroup(
                                'دریافت از اشخاص',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن دریافت جدید', _getPermission(currentPermissions, 'people_receipts', 'add'), (value) => _setPermission(currentPermissions, 'people_receipts', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده دریافت‌ها', _getPermission(currentPermissions, 'people_receipts', 'view'), (value) => _setPermission(currentPermissions, 'people_receipts', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش دریافت‌ها', _getPermission(currentPermissions, 'people_receipts', 'edit'), (value) => _setPermission(currentPermissions, 'people_receipts', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف دریافت‌ها', _getPermission(currentPermissions, 'people_receipts', 'delete'), (value) => _setPermission(currentPermissions, 'people_receipts', 'delete', value), theme, colorScheme),
                                  _buildPermissionItem('مدیریت پیش‌نویس‌ها', 'مدیریت پیش‌نویس‌های دریافت', _getPermission(currentPermissions, 'people_receipts', 'draft'), (value) => _setPermission(currentPermissions, 'people_receipts', 'draft', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                              _buildPermissionGroup(
                                'پرداخت به اشخاص',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن پرداخت جدید', _getPermission(currentPermissions, 'people_payments', 'add'), (value) => _setPermission(currentPermissions, 'people_payments', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده پرداخت‌ها', _getPermission(currentPermissions, 'people_payments', 'view'), (value) => _setPermission(currentPermissions, 'people_payments', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش پرداخت‌ها', _getPermission(currentPermissions, 'people_payments', 'edit'), (value) => _setPermission(currentPermissions, 'people_payments', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف پرداخت‌ها', _getPermission(currentPermissions, 'people_payments', 'delete'), (value) => _setPermission(currentPermissions, 'people_payments', 'delete', value), theme, colorScheme),
                                  _buildPermissionItem('مدیریت پیش‌نویس‌ها', 'مدیریت پیش‌نویس‌های پرداخت', _getPermission(currentPermissions, 'people_payments', 'draft'), (value) => _setPermission(currentPermissions, 'people_payments', 'draft', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                            ],
                            theme,
                            colorScheme,
                          ),

                          const SizedBox(height: 20),

                          // کالا و خدمات
                          _buildPermissionSection(
                            'کالا و خدمات',
                            Icons.inventory,
                            [
                              _buildPermissionGroup(
                                'کالا‌ها و خدمات',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن کالا یا خدمت', _getPermission(currentPermissions, 'products', 'add'), (value) => _setPermission(currentPermissions, 'products', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده کالاها و خدمات', _getPermission(currentPermissions, 'products', 'view'), (value) => _setPermission(currentPermissions, 'products', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش کالاها و خدمات', _getPermission(currentPermissions, 'products', 'edit'), (value) => _setPermission(currentPermissions, 'products', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف کالاها و خدمات', _getPermission(currentPermissions, 'products', 'delete'), (value) => _setPermission(currentPermissions, 'products', 'delete', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                              _buildPermissionGroup(
                                'لیست‌های قیمت',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن لیست قیمت', _getPermission(currentPermissions, 'price_lists', 'add'), (value) => _setPermission(currentPermissions, 'price_lists', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده لیست‌های قیمت', _getPermission(currentPermissions, 'price_lists', 'view'), (value) => _setPermission(currentPermissions, 'price_lists', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش لیست‌های قیمت', _getPermission(currentPermissions, 'price_lists', 'edit'), (value) => _setPermission(currentPermissions, 'price_lists', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف لیست‌های قیمت', _getPermission(currentPermissions, 'price_lists', 'delete'), (value) => _setPermission(currentPermissions, 'price_lists', 'delete', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                              _buildPermissionGroup(
                                'دسته‌بندی‌ها',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن دسته‌بندی', _getPermission(currentPermissions, 'categories', 'add'), (value) => _setPermission(currentPermissions, 'categories', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده دسته‌بندی‌ها', _getPermission(currentPermissions, 'categories', 'view'), (value) => _setPermission(currentPermissions, 'categories', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش دسته‌بندی‌ها', _getPermission(currentPermissions, 'categories', 'edit'), (value) => _setPermission(currentPermissions, 'categories', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف دسته‌بندی‌ها', _getPermission(currentPermissions, 'categories', 'delete'), (value) => _setPermission(currentPermissions, 'categories', 'delete', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                              _buildPermissionGroup(
                                'ویژگی‌های کالا و خدمات',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن ویژگی', _getPermission(currentPermissions, 'product_attributes', 'add'), (value) => _setPermission(currentPermissions, 'product_attributes', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده ویژگی‌ها', _getPermission(currentPermissions, 'product_attributes', 'view'), (value) => _setPermission(currentPermissions, 'product_attributes', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش ویژگی‌ها', _getPermission(currentPermissions, 'product_attributes', 'edit'), (value) => _setPermission(currentPermissions, 'product_attributes', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف ویژگی‌ها', _getPermission(currentPermissions, 'product_attributes', 'delete'), (value) => _setPermission(currentPermissions, 'product_attributes', 'delete', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                            ],
                            theme,
                            colorScheme,
                          ),

                          const SizedBox(height: 20),

                          // بانکداری
                          _buildPermissionSection(
                            'بانکداری',
                            Icons.account_balance,
                            [
                              _buildPermissionGroup(
                                'حساب‌های بانکی',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن حساب بانکی', _getPermission(currentPermissions, 'bank_accounts', 'add'), (value) => _setPermission(currentPermissions, 'bank_accounts', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده حساب‌های بانکی', _getPermission(currentPermissions, 'bank_accounts', 'view'), (value) => _setPermission(currentPermissions, 'bank_accounts', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش حساب‌های بانکی', _getPermission(currentPermissions, 'bank_accounts', 'edit'), (value) => _setPermission(currentPermissions, 'bank_accounts', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف حساب‌های بانکی', _getPermission(currentPermissions, 'bank_accounts', 'delete'), (value) => _setPermission(currentPermissions, 'bank_accounts', 'delete', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                              _buildPermissionGroup(
                                'صندوق',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن صندوق', _getPermission(currentPermissions, 'cash', 'add'), (value) => _setPermission(currentPermissions, 'cash', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده صندوق‌ها', _getPermission(currentPermissions, 'cash', 'view'), (value) => _setPermission(currentPermissions, 'cash', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش صندوق‌ها', _getPermission(currentPermissions, 'cash', 'edit'), (value) => _setPermission(currentPermissions, 'cash', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف صندوق‌ها', _getPermission(currentPermissions, 'cash', 'delete'), (value) => _setPermission(currentPermissions, 'cash', 'delete', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                              _buildPermissionGroup(
                                'تنخواه گردان',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن تنخواه', _getPermission(currentPermissions, 'petty_cash', 'add'), (value) => _setPermission(currentPermissions, 'petty_cash', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده تنخواه‌ها', _getPermission(currentPermissions, 'petty_cash', 'view'), (value) => _setPermission(currentPermissions, 'petty_cash', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش تنخواه‌ها', _getPermission(currentPermissions, 'petty_cash', 'edit'), (value) => _setPermission(currentPermissions, 'petty_cash', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف تنخواه‌ها', _getPermission(currentPermissions, 'petty_cash', 'delete'), (value) => _setPermission(currentPermissions, 'petty_cash', 'delete', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                              _buildPermissionGroup(
                                'چک',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن چک', _getPermission(currentPermissions, 'checks', 'add'), (value) => _setPermission(currentPermissions, 'checks', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده چک‌ها', _getPermission(currentPermissions, 'checks', 'view'), (value) => _setPermission(currentPermissions, 'checks', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش چک‌ها', _getPermission(currentPermissions, 'checks', 'edit'), (value) => _setPermission(currentPermissions, 'checks', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف چک‌ها', _getPermission(currentPermissions, 'checks', 'delete'), (value) => _setPermission(currentPermissions, 'checks', 'delete', value), theme, colorScheme),
                                  _buildPermissionItem('وصول', 'وصول چک‌ها', _getPermission(currentPermissions, 'checks', 'collect'), (value) => _setPermission(currentPermissions, 'checks', 'collect', value), theme, colorScheme),
                                  _buildPermissionItem('انتقال', 'انتقال چک‌ها', _getPermission(currentPermissions, 'checks', 'transfer'), (value) => _setPermission(currentPermissions, 'checks', 'transfer', value), theme, colorScheme),
                                  _buildPermissionItem('برگشت', 'برگشت چک‌ها', _getPermission(currentPermissions, 'checks', 'return'), (value) => _setPermission(currentPermissions, 'checks', 'return', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                              _buildPermissionGroup(
                                'کیف پول',
                                [
                                  _buildPermissionItem('مشاهده', 'مشاهده کیف پول', _getPermission(currentPermissions, 'wallet', 'view'), (value) => _setPermission(currentPermissions, 'wallet', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('شارژ', 'شارژ کیف پول', _getPermission(currentPermissions, 'wallet', 'charge'), (value) => _setPermission(currentPermissions, 'wallet', 'charge', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                              _buildPermissionGroup(
                                'انتقال',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن انتقال', _getPermission(currentPermissions, 'transfers', 'add'), (value) => _setPermission(currentPermissions, 'transfers', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده انتقال‌ها', _getPermission(currentPermissions, 'transfers', 'view'), (value) => _setPermission(currentPermissions, 'transfers', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش انتقال‌ها', _getPermission(currentPermissions, 'transfers', 'edit'), (value) => _setPermission(currentPermissions, 'transfers', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف انتقال‌ها', _getPermission(currentPermissions, 'transfers', 'delete'), (value) => _setPermission(currentPermissions, 'transfers', 'delete', value), theme, colorScheme),
                                  _buildPermissionItem('مدیریت پیش‌نویس‌ها', 'مدیریت پیش‌نویس‌های انتقال', _getPermission(currentPermissions, 'transfers', 'draft'), (value) => _setPermission(currentPermissions, 'transfers', 'draft', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                            ],
                            theme,
                            colorScheme,
                          ),

                          const SizedBox(height: 20),

                          // فاکتورها و هزینه‌ها
                          _buildPermissionSection(
                            'فاکتورها و هزینه‌ها',
                            Icons.receipt,
                            [
                              _buildPermissionGroup(
                                'فاکتورها',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن فاکتور', _getPermission(currentPermissions, 'invoices', 'add'), (value) => _setPermission(currentPermissions, 'invoices', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده فاکتورها', _getPermission(currentPermissions, 'invoices', 'view'), (value) => _setPermission(currentPermissions, 'invoices', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش فاکتورها', _getPermission(currentPermissions, 'invoices', 'edit'), (value) => _setPermission(currentPermissions, 'invoices', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف فاکتورها', _getPermission(currentPermissions, 'invoices', 'delete'), (value) => _setPermission(currentPermissions, 'invoices', 'delete', value), theme, colorScheme),
                                  _buildPermissionItem('مدیریت پیش‌نویس‌ها', 'مدیریت پیش‌نویس‌های فاکتور', _getPermission(currentPermissions, 'invoices', 'draft'), (value) => _setPermission(currentPermissions, 'invoices', 'draft', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                              _buildPermissionGroup(
                                'هزینه و درآمد',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن هزینه یا درآمد', _getPermission(currentPermissions, 'expenses_income', 'add'), (value) => _setPermission(currentPermissions, 'expenses_income', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده هزینه‌ها و درآمدها', _getPermission(currentPermissions, 'expenses_income', 'view'), (value) => _setPermission(currentPermissions, 'expenses_income', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش هزینه‌ها و درآمدها', _getPermission(currentPermissions, 'expenses_income', 'edit'), (value) => _setPermission(currentPermissions, 'expenses_income', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف هزینه‌ها و درآمدها', _getPermission(currentPermissions, 'expenses_income', 'delete'), (value) => _setPermission(currentPermissions, 'expenses_income', 'delete', value), theme, colorScheme),
                                  _buildPermissionItem('مدیریت پیش‌نویس‌ها', 'مدیریت پیش‌نویس‌های هزینه و درآمد', _getPermission(currentPermissions, 'expenses_income', 'draft'), (value) => _setPermission(currentPermissions, 'expenses_income', 'draft', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                            ],
                            theme,
                            colorScheme,
                          ),

                          const SizedBox(height: 20),

                          // حسابداری
                          _buildPermissionSection(
                            'حسابداری',
                            Icons.calculate,
                            [
                              _buildPermissionGroup(
                                'اسناد حسابداری',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن سند حسابداری', _getPermission(currentPermissions, 'accounting_documents', 'add'), (value) => _setPermission(currentPermissions, 'accounting_documents', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده اسناد حسابداری', _getPermission(currentPermissions, 'accounting_documents', 'view'), (value) => _setPermission(currentPermissions, 'accounting_documents', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش اسناد حسابداری', _getPermission(currentPermissions, 'accounting_documents', 'edit'), (value) => _setPermission(currentPermissions, 'accounting_documents', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف اسناد حسابداری', _getPermission(currentPermissions, 'accounting_documents', 'delete'), (value) => _setPermission(currentPermissions, 'accounting_documents', 'delete', value), theme, colorScheme),
                                  _buildPermissionItem('مدیریت پیش‌نویس‌ها', 'مدیریت پیش‌نویس‌های اسناد', _getPermission(currentPermissions, 'accounting_documents', 'draft'), (value) => _setPermission(currentPermissions, 'accounting_documents', 'draft', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                              _buildPermissionGroup(
                                'جدول حساب‌ها',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن حساب', _getPermission(currentPermissions, 'chart_of_accounts', 'add'), (value) => _setPermission(currentPermissions, 'chart_of_accounts', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده جدول حساب‌ها', _getPermission(currentPermissions, 'chart_of_accounts', 'view'), (value) => _setPermission(currentPermissions, 'chart_of_accounts', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش جدول حساب‌ها', _getPermission(currentPermissions, 'chart_of_accounts', 'edit'), (value) => _setPermission(currentPermissions, 'chart_of_accounts', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف حساب‌ها', _getPermission(currentPermissions, 'chart_of_accounts', 'delete'), (value) => _setPermission(currentPermissions, 'chart_of_accounts', 'delete', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                              _buildPermissionGroup(
                                'تراز افتتاحیه',
                                [
                                  _buildPermissionItem('مشاهده', 'مشاهده تراز افتتاحیه', _getPermission(currentPermissions, 'opening_balance', 'view'), (value) => _setPermission(currentPermissions, 'opening_balance', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش تراز افتتاحیه', _getPermission(currentPermissions, 'opening_balance', 'edit'), (value) => _setPermission(currentPermissions, 'opening_balance', 'edit', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                            ],
                            theme,
                            colorScheme,
                          ),

                          const SizedBox(height: 20),

                          // انبارداری
                          _buildPermissionSection(
                            'انبارداری',
                            Icons.warehouse,
                            [
                              _buildPermissionGroup(
                                'مدیریت انبارها',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن انبار', _getPermission(currentPermissions, 'warehouses', 'add'), (value) => _setPermission(currentPermissions, 'warehouses', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده انبارها', _getPermission(currentPermissions, 'warehouses', 'view'), (value) => _setPermission(currentPermissions, 'warehouses', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش انبارها', _getPermission(currentPermissions, 'warehouses', 'edit'), (value) => _setPermission(currentPermissions, 'warehouses', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف انبارها', _getPermission(currentPermissions, 'warehouses', 'delete'), (value) => _setPermission(currentPermissions, 'warehouses', 'delete', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                              _buildPermissionGroup(
                                'صدور حواله',
                                [
                                  _buildPermissionItem('افزودن', 'افزودن حواله', _getPermission(currentPermissions, 'warehouse_transfers', 'add'), (value) => _setPermission(currentPermissions, 'warehouse_transfers', 'add', value), theme, colorScheme),
                                  _buildPermissionItem('مشاهده', 'مشاهده حواله‌ها', _getPermission(currentPermissions, 'warehouse_transfers', 'view'), (value) => _setPermission(currentPermissions, 'warehouse_transfers', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('ویرایش', 'ویرایش حواله‌ها', _getPermission(currentPermissions, 'warehouse_transfers', 'edit'), (value) => _setPermission(currentPermissions, 'warehouse_transfers', 'edit', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف حواله‌ها', _getPermission(currentPermissions, 'warehouse_transfers', 'delete'), (value) => _setPermission(currentPermissions, 'warehouse_transfers', 'delete', value), theme, colorScheme),
                                  _buildPermissionItem('مدیریت پیش‌نویس‌ها', 'مدیریت پیش‌نویس‌های حواله', _getPermission(currentPermissions, 'warehouse_transfers', 'draft'), (value) => _setPermission(currentPermissions, 'warehouse_transfers', 'draft', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                            ],
                            theme,
                            colorScheme,
                          ),

                          const SizedBox(height: 20),

                          // تنظیمات
                          _buildPermissionSection(
                            'تنظیمات',
                            Icons.settings,
                            [
                              _buildPermissionGroup(
                                'تنظیمات',
                                [
                                  _buildPermissionItem('تنظیمات کسب و کار', 'مدیریت تنظیمات کسب و کار', _getPermission(currentPermissions, 'settings', 'business'), (value) => _setPermission(currentPermissions, 'settings', 'business', value), theme, colorScheme),
                                  _buildPermissionItem('تنظیمات چاپ اسناد', 'مدیریت تنظیمات چاپ', _getPermission(currentPermissions, 'settings', 'print'), (value) => _setPermission(currentPermissions, 'settings', 'print', value), theme, colorScheme),
                                  _buildPermissionItem('تاریخچه رویدادها', 'مشاهده تاریخچه رویدادها', _getPermission(currentPermissions, 'settings', 'history'), (value) => _setPermission(currentPermissions, 'settings', 'history', value), theme, colorScheme),
                                  _buildPermissionItem('کاربران و دسترسی‌ها', 'مدیریت کاربران و دسترسی‌ها', _getPermission(currentPermissions, 'settings', 'users'), (value) => _setPermission(currentPermissions, 'settings', 'users', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                              _buildPermissionGroup(
                                'فضای ذخیره‌سازی',
                                [
                                  _buildPermissionItem('مشاهده', 'مشاهده فضای ذخیره‌سازی', _getPermission(currentPermissions, 'storage', 'view'), (value) => _setPermission(currentPermissions, 'storage', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('حذف', 'حذف فایل‌ها', _getPermission(currentPermissions, 'storage', 'delete'), (value) => _setPermission(currentPermissions, 'storage', 'delete', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                              _buildPermissionGroup(
                                'پنل پیامک',
                                [
                                  _buildPermissionItem('مشاهده تاریخچه', 'مشاهده تاریخچه پیامک‌ها', _getPermission(currentPermissions, 'sms', 'history'), (value) => _setPermission(currentPermissions, 'sms', 'history', value), theme, colorScheme),
                                  _buildPermissionItem('مدیریت قالب‌ها', 'مدیریت قالب‌های پیامک', _getPermission(currentPermissions, 'sms', 'templates'), (value) => _setPermission(currentPermissions, 'sms', 'templates', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                              _buildPermissionGroup(
                                'بازار افزونه‌ها',
                                [
                                  _buildPermissionItem('مشاهده', 'مشاهده افزونه‌ها', _getPermission(currentPermissions, 'marketplace', 'view'), (value) => _setPermission(currentPermissions, 'marketplace', 'view', value), theme, colorScheme),
                                  _buildPermissionItem('خرید', 'خرید افزونه‌ها', _getPermission(currentPermissions, 'marketplace', 'buy'), (value) => _setPermission(currentPermissions, 'marketplace', 'buy', value), theme, colorScheme),
                                  _buildPermissionItem('صورت حساب‌ها', 'مشاهده صورت حساب‌ها', _getPermission(currentPermissions, 'marketplace', 'invoices'), (value) => _setPermission(currentPermissions, 'marketplace', 'invoices', value), theme, colorScheme),
                                ],
                                theme,
                                colorScheme,
                              ),
                            ],
                            theme,
                            colorScheme,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Actions
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => context.pop(),
                          child: Text(t.cancel),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            _updatePermissions(user, currentPermissions);
                            context.pop();
                          },
                          icon: const Icon(Icons.save, size: 18),
                          label: Text(t.savePermissions),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: colorScheme.primary,
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


  bool _getPermission(Map<String, dynamic> permissions, String section, String action) {
    if (!permissions.containsKey(section)) return false;
    final sectionPerms = permissions[section] as Map<String, dynamic>?;
    if (sectionPerms == null) return false;
    return sectionPerms[action] == true;
  }

  void _setPermission(Map<String, dynamic> permissions, String section, String action, bool value) {
    if (!permissions.containsKey(section)) {
      permissions[section] = {};
    }
    permissions[section][action] = value;
  }

}