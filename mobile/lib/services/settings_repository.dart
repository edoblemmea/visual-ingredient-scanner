import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

/// Persists [AppSettings]. Non-secret fields go to a single JSON blob in
/// `shared_preferences`; the Gemini API key is kept out of that blob and stored
/// separately in `flutter_secure_storage` (Keychain / Android Keystore) so no
/// secret is ever written in plaintext.
class SettingsRepository {
  SettingsRepository(this._prefs, this._secure);

  static const String _key = 'app_settings_v1';
  static const String _apiKeyKey = 'gemini_api_key';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  static Future<SettingsRepository> create() async => SettingsRepository(
        await SharedPreferences.getInstance(),
        const FlutterSecureStorage(),
      );

  Future<AppSettings> load() async {
    final apiKey = await _readApiKey();
    final raw = _prefs.getString(_key);
    if (raw == null) return AppSettings.defaults.copyWith(geminiApiKey: apiKey);
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>)
          .copyWith(geminiApiKey: apiKey);
    } catch (_) {
      return AppSettings.defaults.copyWith(geminiApiKey: apiKey);
    }
  }

  Future<void> save(AppSettings settings) async {
    await _prefs.setString(_key, jsonEncode(settings.toJson()));
    if (settings.geminiApiKey.isEmpty) {
      await _secure.delete(key: _apiKeyKey);
    } else {
      await _secure.write(key: _apiKeyKey, value: settings.geminiApiKey);
    }
  }

  Future<String> _readApiKey() async {
    try {
      return await _secure.read(key: _apiKeyKey) ?? '';
    } catch (_) {
      return ''; // secure storage unavailable — treat as no key
    }
  }
}
