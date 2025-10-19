import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Almacenamiento seguro de tokens (Keystore/Keychain).
class TokenStorage {
  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(
      // Usa EncryptedSharedPreferences bajo el capó (Android 6+)
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      // Acceso tras el primer desbloqueo del dispositivo
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  /// Migra tokens antiguos desde SharedPreferences → SecureStorage (se ejecuta una sola vez).
  static Future<void> migrateFromPrefsIfNeeded() async {
    try {
      final alreadySecure = await Future.wait([
        _secure.containsKey(key: _kAccess),
        _secure.containsKey(key: _kRefresh),
      ]);
      if (alreadySecure[0] && alreadySecure[1]) return;

      final prefs = await SharedPreferences.getInstance();
      final a = prefs.getString(_kAccess);
      final r = prefs.getString(_kRefresh);

      if ((a?.isNotEmpty ?? false) || (r?.isNotEmpty ?? false)) {
        if (a != null) await _secure.write(key: _kAccess, value: a);
        if (r != null) await _secure.write(key: _kRefresh, value: r);

        // Limpia los viejos (opcional pero recomendado)
        await prefs.remove(_kAccess);
        await prefs.remove(_kRefresh);
      }
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Token migration failed: $e\n$st');
      }
    }
  }

  // Lectura
  static Future<String?> readAccess() => _secure.read(key: _kAccess);
  static Future<String?> readRefresh() => _secure.read(key: _kRefresh);

  // Escritura
  static Future<void> writeTokens({
    required String access,
    required String refresh,
  }) async {
    await _secure.write(key: _kAccess, value: access);
    await _secure.write(key: _kRefresh, value: refresh);
  }

  static Future<void> writeAccess(String access) =>
      _secure.write(key: _kAccess, value: access);

  static Future<void> writeRefresh(String refresh) =>
      _secure.write(key: _kRefresh, value: refresh);

  // Limpieza
  static Future<void> clear() async {
    await _secure.delete(key: _kAccess);
    await _secure.delete(key: _kRefresh);
  }
}
