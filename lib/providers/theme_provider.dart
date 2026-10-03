import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 外观主题管理：深色 / 浅色 / 跟随系统。设置仅保存在本机。
class ThemeProvider extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  static const _key = 'theme_mode';

  ThemeMode get mode => _mode;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_key);
    if (v != null && v >= 0 && v < ThemeMode.values.length) {
      _mode = ThemeMode.values[v];
      notifyListeners();
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, mode.index);
  }

  void toggle() {
    setMode(_mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}
