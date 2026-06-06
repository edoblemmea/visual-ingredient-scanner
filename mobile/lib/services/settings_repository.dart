import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

/// Persists [AppSettings] as a single JSON blob in `shared_preferences`. The
/// whole object (model ids, threshold, density overrides, toggles, API key) is
/// small, so one key is simpler than scattering fields. A corrupt/absent value
/// falls back to defaults rather than throwing.
class SettingsRepository {
  SettingsRepository(this._prefs);

  static const String _key = 'app_settings_v1';

  final SharedPreferences _prefs;

  static Future<SettingsRepository> create() async =>
      SettingsRepository(await SharedPreferences.getInstance());

  AppSettings load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return AppSettings.defaults;
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AppSettings.defaults;
    }
  }

  Future<void> save(AppSettings settings) =>
      _prefs.setString(_key, jsonEncode(settings.toJson()));
}
