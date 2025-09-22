import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  static const String _modeKey = 'theme_mode';
  static const String _seedKey = 'theme_seed';

  ThemeMode _mode = ThemeMode.system;
  // Classic Blue (formal corporate): #0F4C81
  Color _seed = const Color(0xFF0F4C81);

  ThemeMode get mode => _mode;
  Color get seedColor => _seed;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final modeIndex = p.getInt(_modeKey);
    if (modeIndex != null && modeIndex >= 0 && modeIndex < ThemeMode.values.length) {
      _mode = ThemeMode.values[modeIndex];
    }
    final seed = p.getInt(_seedKey);
    if (seed != null) _seed = Color(seed);
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_modeKey, m.index);
  }

  Future<void> setSeedColor(Color c) async {
    if (_seed == c) return;
    _seed = c;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_seedKey, c.toARGB32());
  }
}


