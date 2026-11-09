import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local preferences (not synced): appearance.
class AppSettings extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.system;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    themeMode = switch (p.getString('theme_mode')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('theme_mode', switch (m) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }
}
