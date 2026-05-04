import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../src/rust/api/simple.dart' as rust;

/// Hardware-backed хранилище токена авторизации.
///
/// На каждой платформе flutter_secure_storage использует свой механизм:
///   • Android — EncryptedSharedPreferences + Android Keystore
///   • iOS / macOS — Keychain
///   • Windows — DPAPI (Data Protection API)
///   • Linux — libsecret
///
/// До этого токен хранился в plain SQLite через Rust storage. При первом
/// запуске новой версии приложения [read] мигрирует токен из Rust в secure
/// storage и затирает оригинал — потом доступ только через secure store.
class TokenStorage {
  static const _key = 'auth_token';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  /// Возвращает токен либо `null` если не сохранён.
  /// Делает однократную миграцию из legacy Rust SQLite если нужно.
  Future<String?> read() async {
    try {
      final secure = await _storage.read(key: _key);
      if (secure != null && secure.isNotEmpty) return secure;
    } catch (e) {
      debugPrint('[token] secure read failed: $e');
    }
    // Legacy migration: токен из старого приложения (до перехода на
    // secure storage). После миграции затираем — secret больше не
    // повторяется в plain виде.
    try {
      final legacy = await rust.getToken();
      if (legacy != null && legacy.isNotEmpty) {
        debugPrint('[token] migrating from Rust SQLite to secure storage');
        try {
          await _storage.write(key: _key, value: legacy);
          await rust.setToken(token: '');
        } catch (e) {
          debugPrint('[token] migration partial fail: $e');
        }
        return legacy;
      }
    } catch (e) {
      debugPrint('[token] legacy read failed: $e');
    }
    return null;
  }

  Future<void> write(String token) async {
    try {
      await _storage.write(key: _key, value: token);
    } catch (e) {
      debugPrint('[token] write failed: $e');
    }
    // На всякий случай зануляем legacy слот, чтобы не было плагины-копии.
    try {
      await rust.setToken(token: '');
    } catch (_) {}
  }

  Future<void> delete() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
    try {
      await rust.setToken(token: '');
    } catch (_) {}
  }
}

final tokenStorage = TokenStorage();
