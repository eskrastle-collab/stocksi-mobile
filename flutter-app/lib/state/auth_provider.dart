import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../src/rust/api/simple.dart';
import 'token_storage.dart';

/// Состояние авторизации / onboarding-флоу.
enum AuthStage {
  /// Приложение только запустилось — проверяем сохранённый токен.
  initializing,

  /// Токена нет или невалидный — показываем форму ввода.
  awaitingToken,

  /// Идёт проверка формата + сохранение.
  applying,

  /// Токен принят, показываем экран «успех → переход к ленте».
  success,

  /// Ошибка валидации — показываем текст под полем.
  error,

  /// Всё готово, показываем ленту новостей.
  ready,
}

class AuthState {
  final AuthStage stage;
  final String? errorMessage;
  const AuthState({required this.stage, this.errorMessage});

  AuthState copyWith({AuthStage? stage, String? errorMessage}) =>
      AuthState(stage: stage ?? this.stage, errorMessage: errorMessage);
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState(stage: AuthStage.initializing)) {
    _init();
  }

  Future<void> _init() async {
    // Инициализируем SQLite в platform-specific directory
    final docs = await getApplicationSupportDirectory();
    final dbPath = p.join(docs.path, 'stocksi.db');
    await initCore(dbPath: dbPath);

    // Проверяем существующий токен через secure storage. Если запускаемся
    // первый раз после апгрейда — read() сам мигрирует токен из Rust SQLite.
    final existing = await tokenStorage.read();
    if (existing != null && existing.isNotEmpty) {
      state = const AuthState(stage: AuthStage.ready);
    } else {
      state = const AuthState(stage: AuthStage.awaitingToken);
    }
  }

  Future<void> applyToken(String token) async {
    state = const AuthState(stage: AuthStage.applying);
    final trimmed = token.trim();

    // 1. Локальная проверка формата — мгновенная
    final formatError = checkTokenFormat(token: trimmed);
    if (formatError != null) {
      // Короткая задержка для красивой анимации
      await Future.delayed(const Duration(milliseconds: 300));
      state = AuthState(stage: AuthStage.error, errorMessage: formatError);
      return;
    }

    // 2. Серверная проверка — открываем WS и ждём TokenResultOk / TokenResultInvalid
    final serverError = await validateToken(token: trimmed);
    if (serverError != null) {
      state = AuthState(stage: AuthStage.error, errorMessage: serverError);
      return;
    }

    // 3. Токен валиден — сохраняем в secure storage и показываем «Успех»
    await tokenStorage.write(trimmed);
    state = const AuthState(stage: AuthStage.success);
  }

  void goToNewsList() {
    state = const AuthState(stage: AuthStage.ready);
  }

  void resetError() {
    if (state.stage == AuthStage.error) {
      state = const AuthState(stage: AuthStage.awaitingToken);
    }
  }

  /// Стирает сохранённый токен и возвращает приложение к экрану ввода.
  Future<void> resetToken() async {
    await tokenStorage.delete();
    state = const AuthState(stage: AuthStage.awaitingToken);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
