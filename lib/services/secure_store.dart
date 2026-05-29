import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Безопасное хранение чувствительных данных.
///
/// Использует:
///   • Android Keystore (через flutter_secure_storage)
///   • iOS Keychain
///
/// Что хранится здесь:
///   • auth_token  — JWT-токен пользователя (никогда в SharedPreferences)
///   • user_id     — ID текущего пользователя
///
/// Также делает миграцию: если в SharedPreferences был старый plaintext-токен,
/// переносим его в secure storage и удаляем оттуда.
class SecureStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      // KeyCipherAlgorithm: AES_GCM_NoPadding (default) — secure
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static const _keyToken = 'auth_token';
  static const _keyUserId = 'user_id';
  static const _keyDisplayName = 'user_display_name';

  static bool _migrationDone = false;

  /// Однократная миграция со старого SharedPreferences на secure storage.
  /// Вызывается лениво при первом обращении.
  static Future<void> _migrateIfNeeded() async {
    if (_migrationDone) return;
    _migrationDone = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Если в secure storage уже есть токен — миграция не нужна
      final existing = await _storage.read(key: _keyToken);
      if (existing != null && existing.isNotEmpty) {
        // На всякий случай чистим старое место
        await prefs.remove(_keyToken);
        return;
      }
      final oldToken = prefs.getString(_keyToken);
      final oldUserId = prefs.getString(_keyUserId);
      final oldName = prefs.getString(_keyDisplayName);

      if (oldToken != null && oldToken.isNotEmpty) {
        await _storage.write(key: _keyToken, value: oldToken);
        await prefs.remove(_keyToken);
      }
      if (oldUserId != null && oldUserId.isNotEmpty) {
        await _storage.write(key: _keyUserId, value: oldUserId);
        await prefs.remove(_keyUserId);
      }
      if (oldName != null && oldName.isNotEmpty) {
        await _storage.write(key: _keyDisplayName, value: oldName);
        await prefs.remove(_keyDisplayName);
      }
    } catch (_) {
      // Если миграция упала — не блокируем приложение
    }
  }

  static Future<String?> getToken() async {
    await _migrateIfNeeded();
    return _storage.read(key: _keyToken);
  }

  static Future<void> setToken(String token) async {
    await _migrateIfNeeded();
    await _storage.write(key: _keyToken, value: token);
  }

  static Future<void> clearToken() async {
    await _migrateIfNeeded();
    await _storage.delete(key: _keyToken);
  }

  static Future<String?> getUserId() async {
    await _migrateIfNeeded();
    return _storage.read(key: _keyUserId);
  }

  static Future<void> setUserId(String id) async {
    await _migrateIfNeeded();
    await _storage.write(key: _keyUserId, value: id);
  }

  static Future<String?> getDisplayName() async {
    await _migrateIfNeeded();
    return _storage.read(key: _keyDisplayName);
  }

  static Future<void> setDisplayName(String name) async {
    await _migrateIfNeeded();
    await _storage.write(key: _keyDisplayName, value: name);
  }

  /// Полная очистка чувствительных данных при logout.
  static Future<void> clearAll() async {
    await _storage.delete(key: _keyToken);
    await _storage.delete(key: _keyUserId);
    await _storage.delete(key: _keyDisplayName);
  }
}
