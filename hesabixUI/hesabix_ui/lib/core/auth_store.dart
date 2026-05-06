import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'api_client.dart';
import 'business_panel_ui_store.dart';
import '../models/business_dashboard_models.dart';

class AuthStore with ChangeNotifier {
  static const _kApiKey = 'auth_api_key';
  static const _kDeviceId = 'device_id';
  static const _kAppPermissions = 'app_permissions';
  static const _kIsSuperAdmin = 'is_superadmin';
  static const _kLastUrl = 'last_url';
  static const _kUserName = 'user_name';
  static const _kUserMobile = 'user_mobile';
  static const _kCurrentBusiness = 'current_business';
  static const _kSelectedCurrencyCode = 'selected_currency_code';
  static const _kSelectedCurrencyId = 'selected_currency_id';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  String? _apiKey;
  String? _deviceId;
  Map<String, dynamic>? _appPermissions;
  bool _isSuperAdmin = false;
  BusinessWithPermission? _currentBusiness;
  Map<String, dynamic>? _businessPermissions;
  String? _selectedCurrencyCode; // مثل USD/EUR/IRR
  int? _selectedCurrencyId; // شناسه ارز در دیتابیس
  String? _currentUserName;
  String? _currentUserMobile;

  String? get apiKey => _apiKey;
  String get deviceId => _deviceId ?? '';
  Map<String, dynamic>? get appPermissions => _appPermissions;
  bool get isSuperAdmin => _isSuperAdmin;
  int? _currentUserId;
  int? get currentUserId => _currentUserId;
  String? get currentUserName => _currentUserName;
  String? get currentUserMobile => _currentUserMobile;
  BusinessWithPermission? get currentBusiness => _currentBusiness;
  Map<String, dynamic>? get businessPermissions => _businessPermissions;
  String? get selectedCurrencyCode => _selectedCurrencyCode;
  int? get selectedCurrencyId => _selectedCurrencyId;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_kDeviceId);
    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = const Uuid().v4();
      await prefs.setString(_kDeviceId, _deviceId!);
    }

    if (kIsWeb) {
      _apiKey = prefs.getString(_kApiKey);
    } else {
      _apiKey = await _secure.read(key: _kApiKey);
      _apiKey ??= prefs.getString(_kApiKey);
    }

    // بارگذاری دسترسی‌های اپلیکیشن
    await _loadAppPermissions();
    // بارگذاری ارز انتخاب‌شده (در سطح اپ/کسب‌وکار)
    await _loadSelectedCurrency();
    
    // اگر API key موجود است اما دسترسی‌ها نیست، از سرور دریافت کن
    if (_apiKey != null && _apiKey!.isNotEmpty && (_appPermissions == null || _appPermissions!.isEmpty)) {
      await _fetchPermissionsFromServer();
    }
    
    notifyListeners();
  }

  Future<void> _loadAppPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (kIsWeb) {
      final permissionsJson = prefs.getString(_kAppPermissions);
      if (permissionsJson != null) {
        try {
          _appPermissions = Map<String, dynamic>.from(
            const JsonDecoder().convert(permissionsJson),
          );
        } catch (e) {
          _appPermissions = null;
        }
      } else {
        _appPermissions = null;
      }
      _isSuperAdmin = prefs.getBool(_kIsSuperAdmin) ?? false;
      _currentUserName = prefs.getString(_kUserName);
      _currentUserMobile = prefs.getString(_kUserMobile);
    } else {
      try {
        final permissionsJson = await _secure.read(key: _kAppPermissions);
        if (permissionsJson != null) {
          _appPermissions = Map<String, dynamic>.from(
            const JsonDecoder().convert(permissionsJson),
          );
        } else {
          _appPermissions = null;
        }
        final superAdminStr = await _secure.read(key: _kIsSuperAdmin);
        _isSuperAdmin = superAdminStr == 'true';
        _currentUserName = await _secure.read(key: _kUserName);
        _currentUserMobile = await _secure.read(key: _kUserMobile);
      } catch (e) {
        _appPermissions = null;
        _isSuperAdmin = false;
        _currentUserName = null;
        _currentUserMobile = null;
      }
    }
  }

  Future<void> saveApiKey(String? key) async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = key;
    if (key == null) {
      if (kIsWeb) {
        await prefs.remove(_kApiKey);
      } else {
        try {
          await _secure.delete(key: _kApiKey);
        } catch (_) {}
        await prefs.remove(_kApiKey);
      }
      // پاک کردن دسترسی‌ها و آخرین URL هنگام خروج
      await _clearAppPermissions();
      await clearLastUrl();
      BusinessPanelUiStore.instance.reset();
    } else {
      if (kIsWeb) {
        await prefs.setString(_kApiKey, key);
      } else {
        try {
          await _secure.write(key: _kApiKey, value: key);
        } catch (_) {}
        await prefs.setString(_kApiKey, key);
      }
    }
    notifyListeners();
  }

  Future<void> saveAppPermissions(
    Map<String, dynamic>? permissions,
    bool isSuperAdmin, {
    int? userId,
    String? userName,
    String? userMobile,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _appPermissions = permissions;
    _isSuperAdmin = isSuperAdmin;
    if (userId != null) {
      _currentUserId = userId;
    }
    _currentUserName = userName;
    _currentUserMobile = userMobile;

    if (permissions == null) {
      await _clearAppPermissions();
    } else {
      final permissionsJson = const JsonEncoder().convert(permissions);

      if (kIsWeb) {
        await prefs.setString(_kAppPermissions, permissionsJson);
        await prefs.setBool(_kIsSuperAdmin, isSuperAdmin);
        if (userName != null) {
          await prefs.setString(_kUserName, userName);
        } else {
          await prefs.remove(_kUserName);
        }
        if (userMobile != null) {
          await prefs.setString(_kUserMobile, userMobile);
        } else {
          await prefs.remove(_kUserMobile);
        }
      } else {
        try {
          await _secure.write(key: _kAppPermissions, value: permissionsJson);
          await _secure.write(key: _kIsSuperAdmin, value: isSuperAdmin.toString());
          if (userName != null) {
            await _secure.write(key: _kUserName, value: userName);
          } else {
            await _secure.delete(key: _kUserName);
          }
          if (userMobile != null) {
            await _secure.write(key: _kUserMobile, value: userMobile);
          } else {
            await _secure.delete(key: _kUserMobile);
          }
        } catch (_) {
          // Fallback to SharedPreferences
          await prefs.setString(_kAppPermissions, permissionsJson);
          await prefs.setBool(_kIsSuperAdmin, isSuperAdmin);
          if (userName != null) {
            await prefs.setString(_kUserName, userName);
          } else {
            await prefs.remove(_kUserName);
          }
          if (userMobile != null) {
            await prefs.setString(_kUserMobile, userMobile);
          } else {
            await prefs.remove(_kUserMobile);
          }
        }
      }
    }
    notifyListeners();
  }

  Future<void> _clearAppPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    _appPermissions = null;
    _isSuperAdmin = false;
    _currentUserName = null;
    _currentUserMobile = null;

    if (kIsWeb) {
      await prefs.remove(_kAppPermissions);
      await prefs.remove(_kIsSuperAdmin);
      await prefs.remove(_kUserName);
      await prefs.remove(_kUserMobile);
    } else {
      try {
        await _secure.delete(key: _kAppPermissions);
        await _secure.delete(key: _kIsSuperAdmin);
        await _secure.delete(key: _kUserName);
        await _secure.delete(key: _kUserMobile);
      } catch (_) {}
      await prefs.remove(_kAppPermissions);
      await prefs.remove(_kIsSuperAdmin);
      await prefs.remove(_kUserName);
      await prefs.remove(_kUserMobile);
    }
  }

  Future<void> _fetchPermissionsFromServer() async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      return;
    }

    try {
      final apiClient = ApiClient();
      final response = await apiClient.get('/api/v1/auth/me');
      
      if (response.statusCode == 200) {
        final root = response.data;
        if (root is Map<String, dynamic>) {
          // پاسخ API در فیلد data قرار دارد
          final payload = (root['data'] is Map<String, dynamic>)
              ? root['data'] as Map<String, dynamic>
              : root;
          final user = payload['user'] as Map<String, dynamic>?;
          final permsObj = payload['permissions'] as Map<String, dynamic>?;
          Map<String, dynamic>? appPermissions;
          bool isSuperAdmin = false;
          int? userId;
          String? userName;
          String? userMobile;

          if (user != null) {
            appPermissions = user['app_permissions'] as Map<String, dynamic>?;
            userId = user['id'] as int?;
            // استخراج نام کاربر (اولویت با full_name، سپس first_name + last_name، سپس email)
            final fullName = user['full_name']?.toString().trim();
            final firstName = user['first_name']?.toString().trim();
            final lastName = user['last_name']?.toString().trim();
            if (fullName != null && fullName.isNotEmpty) {
              userName = fullName;
            } else {
              final buffer = <String>[];
              if (firstName != null && firstName.isNotEmpty) buffer.add(firstName);
              if (lastName != null && lastName.isNotEmpty) buffer.add(lastName);
              if (buffer.isNotEmpty) {
                userName = buffer.join(' ');
              } else {
                final email = user['email']?.toString().trim();
                if (email != null && email.isNotEmpty) {
                  userName = email;
                }
              }
            }
            final mobile = user['mobile']?.toString().trim();
            if (mobile != null && mobile.isNotEmpty) {
              userMobile = mobile;
            }
          }
          // fallback: اگر در permissions هم مقدار باشد از آن بخوان
          if (!isSuperAdmin && permsObj != null) {
            final pIs = permsObj['is_superadmin'];
            if (pIs is bool) {
              isSuperAdmin = pIs;
            }
          }
          if (!isSuperAdmin && appPermissions != null) {
            isSuperAdmin = appPermissions['superadmin'] == true;
          }

          // ذخیره در استور و لوکال
          await saveAppPermissions(
            appPermissions,
            isSuperAdmin,
            userId: userId,
            userName: userName,
            userMobile: userMobile,
          );
        }
      }
    } catch (e) {
      // Silent fail - permissions will be loaded from storage
    }
  }

  bool hasAppPermission(String permission) {
    if (_isSuperAdmin) {
      return true;
    }
    
    return _appPermissions?[permission] == true;
  }

  bool get canAccessSupportOperator => hasAppPermission('support_operator');

  // ذخیره آخرین URL برای بازیابی بعد از refresh
  Future<void> saveLastUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastUrl, url);
    } catch (_) {}
  }

  // بازیابی آخرین URL
  Future<String?> getLastUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kLastUrl);
    } catch (_) {
      return null;
    }
  }

  // پاک کردن آخرین URL
  Future<void> clearLastUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLastUrl);
    } catch (_) {}
  }

  // مدیریت کسب و کار فعلی
  Future<void> setCurrentBusiness(BusinessWithPermission business) async {
    
    _currentBusiness = business;
    _businessPermissions = business.permissions;
    
    
    notifyListeners();
    
    // ذخیره در حافظه محلی
    await _saveCurrentBusiness();

    // اگر ارز انتخاب نشده یا ارز انتخابی با کسب‌وکار ناسازگار است، ارز پیشفرض کسب‌وکار را ست کن
    await _ensureCurrencyForBusiness();
    
  }

  Future<void> clearCurrentBusiness() async {
    _currentBusiness = null;
    _businessPermissions = null;
    notifyListeners();
    
    // پاک کردن از حافظه محلی
    await _clearCurrentBusiness();
  }

  Future<void> _saveCurrentBusiness() async {
    if (_currentBusiness == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final businessJson = const JsonEncoder().convert({
        'id': _currentBusiness!.id,
        'name': _currentBusiness!.name,
        'business_type': _currentBusiness!.businessType,
        'business_field': _currentBusiness!.businessField,
        'owner_id': _currentBusiness!.ownerId,
        'address': _currentBusiness!.address,
        'phone': _currentBusiness!.phone,
        'mobile': _currentBusiness!.mobile,
        'created_at': _currentBusiness!.createdAt,
        'is_owner': _currentBusiness!.isOwner,
        'role': _currentBusiness!.role,
        'permissions': _currentBusiness!.permissions,
        'default_currency': _currentBusiness!.defaultCurrency != null
            ? {
                'id': _currentBusiness!.defaultCurrency!.id,
                'code': _currentBusiness!.defaultCurrency!.code,
                'title': _currentBusiness!.defaultCurrency!.title,
                'symbol': _currentBusiness!.defaultCurrency!.symbol,
              }
            : null,
        'currencies': _currentBusiness!.currencies
            .map((c) => {
                  'id': c.id,
                  'code': c.code,
                  'title': c.title,
                  'symbol': c.symbol,
                })
            .toList(),
      });
      
      if (kIsWeb) {
        await prefs.setString(_kCurrentBusiness, businessJson);
      } else {
        try {
          await _secure.write(key: _kCurrentBusiness, value: businessJson);
        } catch (_) {
          await prefs.setString(_kCurrentBusiness, businessJson);
        }
      }
    } catch (e) {
      // Silent fail
    }
  }

  Future<void> _clearCurrentBusiness() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (kIsWeb) {
        await prefs.remove(_kCurrentBusiness);
      } else {
        try {
          await _secure.delete(key: _kCurrentBusiness);
        } catch (_) {}
        await prefs.remove(_kCurrentBusiness);
      }
    } catch (e) {
      // Silent fail
    }
  }

  bool _directBusinessPermission(String section, String action) {
    final sectionPerms = _businessPermissions![section] as Map<String, dynamic>?;
    if (sectionPerms == null) {
      return false;
    }
    if (sectionPerms.isEmpty) {
      return action == 'read' || action == 'view';
    }
    if (sectionPerms[action] == true) {
      return true;
    }
    if (action == 'view' && sectionPerms['read'] == true) return true;
    if (action == 'read' && sectionPerms['view'] == true) return true;
    return false;
  }

  /// همان نقش مجوزهای `warehouse_transfers` در UI برای `inventory.*` در کد قدیمی.
  bool _inventoryViaWarehouseTransfers(String action) {
    switch (action) {
      case 'read':
      case 'view':
        return _directBusinessPermission('warehouse_transfers', 'view') ||
            _directBusinessPermission('warehouse_transfers', 'read');
      case 'write':
        return _directBusinessPermission('warehouse_transfers', 'add') ||
            _directBusinessPermission('warehouse_transfers', 'edit') ||
            _directBusinessPermission('warehouse_transfers', 'draft');
      case 'delete':
        return _directBusinessPermission('warehouse_transfers', 'delete');
      default:
        return false;
    }
  }

  // بررسی دسترسی‌های کسب و کار
  bool hasBusinessPermission(String section, String action) {
    
    if (_currentBusiness?.isOwner == true) {
      return true;
    }
    
    if (_businessPermissions == null) {
      return false;
    }

    if (section == 'inventory') {
      if (_directBusinessPermission(section, action)) return true;
      return _inventoryViaWarehouseTransfers(action);
    }

    return _directBusinessPermission(section, action);
  }

  // دسترسی‌های کلی
  bool canReadSection(String section) {
    // خواندن فقط زمانی مجاز است که به‌صراحت در سکشن اجازه داده شده باشد
    return hasBusinessPermission(section, 'view');
  }

  bool canWriteSection(String section) {
    return hasBusinessPermission(section, 'add') || 
           hasBusinessPermission(section, 'edit');
  }

  bool canDeleteSection(String section) {
    return hasBusinessPermission(section, 'delete');
  }

  /// ثبت یا ویرایش سند حسابداری (شامل اسناد خودکار از چک، دریافت‌وپرداخت و …).
  /// هم‌ارز بررسیٔ `accounting.write` در سرور.
  bool canCreateOrEditAccountingDocuments() {
    if (_currentBusiness?.isOwner == true) {
      return true;
    }
    return hasBusinessPermission('accounting_documents', 'add') ||
        hasBusinessPermission('accounting_documents', 'edit') ||
        hasBusinessPermission('accounting_documents', 'draft');
  }

  // دسترسی‌های خاص
  bool canManageDrafts(String section) {
    return hasBusinessPermission(section, 'draft');
  }

  bool canCollectChecks() {
    return hasBusinessPermission('checks', 'collect');
  }

  bool canTransferChecks() {
    return hasBusinessPermission('checks', 'transfer');
  }

  bool canReturnChecks() {
    return hasBusinessPermission('checks', 'return');
  }

  bool canChargeWallet() {
    return hasBusinessPermission('wallet', 'charge');
  }

  bool canManageUsers() {
    return hasBusinessPermission('settings', 'users');
  }

  bool canManageFtpBackup() {
    return hasBusinessPermission('settings', 'manage_ftp');
  }

  // بررسی دسترسی به کسب و کار
  bool canAccessBusiness(int businessId) {
    if (_currentBusiness == null) return false;
    return _currentBusiness!.id == businessId;
  }

  /// چت وب CRM: مشاهده (جدید) + سازگاری با crm.view
  bool canViewCrmWebChat() {
    if (_currentBusiness?.isOwner == true) return true;
    return hasBusinessPermission('crm_web_chat', 'view') ||
        hasBusinessPermission('crm', 'view');
  }

  /// ارسال پیام/تایپ/فایل + legacy crm.write
  bool canReplyCrmWebChat() {
    if (_currentBusiness?.isOwner == true) return true;
    return hasBusinessPermission('crm_web_chat', 'reply') ||
        hasBusinessPermission('crm', 'write');
  }

  /// ساخت/ویرایش ویجت + legacy crm.write
  bool canManageCrmWebChatWidgets() {
    if (_currentBusiness?.isOwner == true) return true;
    return hasBusinessPermission('crm_web_chat', 'manage_widgets') ||
        hasBusinessPermission('crm', 'write');
  }

  /// ویرایش مکالمه (وضعیت، ارجاع، لید) + legacy crm.write
  bool canEditCrmWebChatConversations() {
    if (_currentBusiness?.isOwner == true) return true;
    return hasBusinessPermission('crm_web_chat', 'edit_conversations') ||
        hasBusinessPermission('crm', 'write');
  }

  /// حذف پیام + legacy crm.write
  bool canDeleteCrmWebChatMessages() {
    if (_currentBusiness?.isOwner == true) return true;
    return hasBusinessPermission('crm_web_chat', 'delete_messages') ||
        hasBusinessPermission('crm', 'write');
  }

  // دریافت دسترسی‌های موجود برای یک بخش
  List<String> getAvailableActions(String section) {
    if (_currentBusiness?.isOwner == true) {
      return ['add', 'view', 'edit', 'delete', 'draft', 'collect', 'transfer', 'return', 'charge'];
    }
    
    if (_businessPermissions == null) return ['view'];
    
    final sectionPerms = _businessPermissions![section] as Map<String, dynamic>?;
    if (sectionPerms == null) return ['view'];
    
    return sectionPerms.keys.where((key) => sectionPerms[key] == true).toList();
  }

  // مدیریت ارز انتخاب‌شده
  Future<void> _loadSelectedCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kSelectedCurrencyCode);
    final id = prefs.getInt(_kSelectedCurrencyId);
    _selectedCurrencyCode = code;
    _selectedCurrencyId = id;
  }

  Future<void> setSelectedCurrency({required String code, int? id}) async {
    final prefs = await SharedPreferences.getInstance();
    _selectedCurrencyCode = code;
    _selectedCurrencyId = id;
    await prefs.setString(_kSelectedCurrencyCode, code);
    if (id != null) {
      await prefs.setInt(_kSelectedCurrencyId, id);
    } else {
      await prefs.remove(_kSelectedCurrencyId);
    }
    notifyListeners();
  }

  Future<void> clearSelectedCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedCurrencyCode = null;
    _selectedCurrencyId = null;
    await prefs.remove(_kSelectedCurrencyCode);
    await prefs.remove(_kSelectedCurrencyId);
    notifyListeners();
  }

  Future<void> _ensureCurrencyForBusiness() async {
    final business = _currentBusiness;
    if (business == null) return;
    
    // اگر ارزی انتخاب نشده، یا کد/شناسه فعلی جزو ارزهای کسب‌وکار نیست
    final allowedCodes = business.currencies.map((c) => c.code).toSet();
    final allowedIds = business.currencies.map((c) => c.id).toSet();

    final hasValidCode = _selectedCurrencyCode != null && allowedCodes.contains(_selectedCurrencyCode);
    final hasValidId = _selectedCurrencyId != null && allowedIds.contains(_selectedCurrencyId);

    if (hasValidCode || hasValidId) {
      return; // همان را نگه داریم
    }

    // در غیر اینصورت ارز پیشفرض کسب‌وکار را ست کن اگر موجود است
    if (business.defaultCurrency != null) {
      await setSelectedCurrency(code: business.defaultCurrency!.code, id: business.defaultCurrency!.id);
      return;
    }

    // یا اگر لیست ارزها خالی نیست، اولین ارز را ست کن
    if (business.currencies.isNotEmpty) {
      final c = business.currencies.first;
      await setSelectedCurrency(code: c.code, id: c.id);
    }
  }
}



