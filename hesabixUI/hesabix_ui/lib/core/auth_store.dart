import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class AuthStore with ChangeNotifier {
  static const _kApiKey = 'auth_api_key';
  static const _kDeviceId = 'device_id';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  String? _apiKey;
  String? _deviceId;

  String? get apiKey => _apiKey;
  String get deviceId => _deviceId ?? '';

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
    notifyListeners();
  }

  Future<void> saveApiKey(String? key) async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = key;
    if (key == null) {
      await _secure.delete(key: _kApiKey);
      await prefs.remove(_kApiKey);
    } else {
      if (kIsWeb) {
        await prefs.setString(_kApiKey, key);
      } else {
        await _secure.write(key: _kApiKey, value: key);
        await prefs.setString(_kApiKey, key);
      }
    }
    notifyListeners();
  }
}


