import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'api_client.dart';

class AuthStore with ChangeNotifier {
  static const _kApiKey = 'auth_api_key';
  static const _kDeviceId = 'device_id';
  static const _kAppPermissions = 'app_permissions';
  static const _kIsSuperAdmin = 'is_superadmin';
  static const _kLastUrl = 'last_url';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  String? _apiKey;
  String? _deviceId;
  Map<String, dynamic>? _appPermissions;
  bool _isSuperAdmin = false;

  String? get apiKey => _apiKey;
  String get deviceId => _deviceId ?? '';
  Map<String, dynamic>? get appPermissions => _appPermissions;
  bool get isSuperAdmin => _isSuperAdmin;
  int? _currentUserId;
  int? get currentUserId => _currentUserId;

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
            const JsonDecoder().convert(permissionsJson)
          );
        } catch (e) {
          _appPermissions = null;
        }
      } else {
        _appPermissions = null;
      }
      _isSuperAdmin = prefs.getBool(_kIsSuperAdmin) ?? false;
    } else {
      try {
        final permissionsJson = await _secure.read(key: _kAppPermissions);
        
        if (permissionsJson != null) {
          _appPermissions = Map<String, dynamic>.from(
            const JsonDecoder().convert(permissionsJson)
          );
        } else {
          _appPermissions = null;
        }
        final superAdminStr = await _secure.read(key: _kIsSuperAdmin);
        _isSuperAdmin = superAdminStr == 'true';
      } catch (e) {
        _appPermissions = null;
        _isSuperAdmin = false;
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

  Future<void> saveAppPermissions(Map<String, dynamic>? permissions, bool isSuperAdmin, {int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    _appPermissions = permissions;
    _isSuperAdmin = isSuperAdmin;
    if (userId != null) {
      _currentUserId = userId;
    }

    if (permissions == null) {
      await _clearAppPermissions();
    } else {
      final permissionsJson = const JsonEncoder().convert(permissions);
      
      if (kIsWeb) {
        await prefs.setString(_kAppPermissions, permissionsJson);
        await prefs.setBool(_kIsSuperAdmin, isSuperAdmin);
      } else {
        try {
          await _secure.write(key: _kAppPermissions, value: permissionsJson);
          await _secure.write(key: _kIsSuperAdmin, value: isSuperAdmin.toString());
        } catch (_) {
          // Fallback to SharedPreferences
          await prefs.setString(_kAppPermissions, permissionsJson);
          await prefs.setBool(_kIsSuperAdmin, isSuperAdmin);
        }
      }
    }
    notifyListeners();
  }

  Future<void> _clearAppPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    _appPermissions = null;
    _isSuperAdmin = false;

    if (kIsWeb) {
      await prefs.remove(_kAppPermissions);
      await prefs.remove(_kIsSuperAdmin);
    } else {
      try {
        await _secure.delete(key: _kAppPermissions);
        await _secure.delete(key: _kIsSuperAdmin);
      } catch (_) {}
      await prefs.remove(_kAppPermissions);
      await prefs.remove(_kIsSuperAdmin);
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
        final data = response.data;
        if (data is Map<String, dynamic>) {
          final user = data['user'] as Map<String, dynamic>?;
          if (user != null) {
            final appPermissions = user['app_permissions'] as Map<String, dynamic>?;
            final isSuperAdmin = appPermissions?['superadmin'] == true;
            final userId = user['id'] as int?;
            
            if (appPermissions != null) {
              await saveAppPermissions(appPermissions, isSuperAdmin);
            }
            
            if (userId != null) {
              _currentUserId = userId;
              notifyListeners();
            }
          }
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
}


