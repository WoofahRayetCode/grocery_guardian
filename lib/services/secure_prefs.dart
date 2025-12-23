import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SecurePrefs wraps FlutterSecureStorage and migrates selected keys
/// from SharedPreferences on first access. Values are stored as JSON strings.
class SecurePrefs {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // Cached SharedPreferences instance for performance
  static SharedPreferences? _prefsCache;
  
  /// Get cached SharedPreferences instance (avoids repeated async getInstance calls)
  static Future<SharedPreferences> get _prefs async {
    return _prefsCache ??= await SharedPreferences.getInstance();
  }

  // App-specific keys we consider sensitive
    static String _allergyListKeyForProfile(String profile) =>
      'sec::user_allergy_items::${Uri.encodeComponent(profile)}';
    static String _allergyPromptedKeyForProfile(String profile, String normalized) =>
      'sec::allergy_prompted::${Uri.encodeComponent(profile)}::$normalized';

  // Migration helpers
  static Future<void> _migrateIfNeeded({required String fromKey, required String toKey}) async {
    final prefs = await _prefs;

    final legacy = prefs.getStringList(fromKey);
    final legacyStr = prefs.getString(fromKey);
    // If secure already has a value, skip
    final existing = await _storage.read(key: toKey);
    if (existing != null) return;

    if (legacy != null) {
      await _storage.write(key: toKey, value: jsonEncode(legacy));
      await prefs.remove(fromKey);
    } else if (legacyStr != null) {
      // Migrate single string flags as JSON string
      await _storage.write(key: toKey, value: jsonEncode(legacyStr));
      await prefs.remove(fromKey);
    }
  }

  // Allergy list
  static Future<List<String>> getAllergyList(String profile) async {
    final legacyKey = 'user_allergy_items::${Uri.encodeComponent(profile)}';
    final secKey = _allergyListKeyForProfile(profile);
    await _migrateIfNeeded(fromKey: legacyKey, toKey: secKey);
    final raw = await _storage.read(key: secKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return const [];
  }

  static Future<void> setAllergyList(String profile, List<String> values) async {
    final secKey = _allergyListKeyForProfile(profile);
    await _storage.write(key: secKey, value: jsonEncode(values));
  }

  static Future<bool> getAllergyPrompted(String profile, String normalizedKey) async {
    final legacyKey = 'allergy_prompted::${Uri.encodeComponent(profile)}::$normalizedKey';
    final secKey = _allergyPromptedKeyForProfile(profile, normalizedKey);
    await _migrateIfNeeded(fromKey: legacyKey, toKey: secKey);
    final raw = await _storage.read(key: secKey);
    if (raw == null) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is String) {
        return decoded == 'true';
      } else if (decoded is bool) {
        return decoded;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> setAllergyPrompted(String profile, String normalizedKey, bool prompted) async {
    final secKey = _allergyPromptedKeyForProfile(profile, normalizedKey);
    await _storage.write(key: secKey, value: jsonEncode(prompted));
  }
}
