import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Имена доступных звуков (файлы в assets/sounds/).
const kAvailableSounds = <String>[
  'bubble',
  'bleep',
  'chime',
  'chirp',
  'honk',
  'splash',
];

/// Проигрывает короткий звук уведомления. Использует audioplayers.
///
/// Держит пул из нескольких AudioPlayer'ов и чередует их по кругу — это
/// гарантирует что быстро-прилетающие новости не обрывают предыдущий звук
/// на середине. Каждый новый играет на свободном плеере, текущий доигрывает.
class SoundService {
  static const _poolSize = 3;
  final List<AudioPlayer> _pool = List.generate(
    _poolSize,
    (i) => AudioPlayer(playerId: 'stocksi-alerts-$i'),
  );
  int _nextIdx = 0;

  // Ключи SharedPreferences для персистентности выбора пользователя
  static const _kSoundNameKey = 'sound_name';
  static const _kEnabledKey = 'sound_enabled';
  static const _kVolumeKey = 'sound_volume';

  String _soundName = 'bleep'; // дефолт
  bool _enabled = true;
  double _volume = 1.0;

  // Какой asset сейчас преподгружен в каждом плеере (чтобы не делать
  // повторный stop()+setSource — а только seek(0)+resume()).
  final Map<int, String> _preloaded = {};

  String get currentSound => _soundName;
  bool get enabled => _enabled;
  double get volume => _volume;

  Future<void> init() async {
    // Загружаем сохранённые настройки — иначе каждый перезапуск сбрасывал
    // выбор звука и громкость.
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString(_kSoundNameKey);
      if (savedName != null && kAvailableSounds.contains(savedName)) {
        _soundName = savedName;
      }
      _enabled = prefs.getBool(_kEnabledKey) ?? true;
      _volume = prefs.getDouble(_kVolumeKey)?.clamp(0.0, 1.0) ?? 1.0;
    } catch (e) {
      debugPrint('[sound] load prefs failed: $e');
    }
    // AudioContext: обрабатываем наш звук как короткий sonification/
    // notification. Главное — НЕ запрашивать audio focus. Иначе Android
    // отбирает focus (например при показе system notification) и обрывает
    // воспроизведение на середине.
    // usageType: media — громкое media-volume (не тихое notification-channel)
    // audioFocus: none — не отбираем focus, чтобы system notification
    //   не прерывала наш звук
    // contentType: sonification — короткие сигналы, не music
    //
    // iOS: playback (а НЕ ambient) — потому что:
    //   - ambient молчит когда включён silent switch / Mute в Control Center
    //   - ambient молчит когда экран заблокирован
    //   - мы — приложение для биржевых алертов, пользователь явно ОЖИДАЕТ
    //     слышать звук вне зависимости от mute (как WhatsApp call, Twitter
    //     ping, etc.). Apple это разрешает для приложений с user-initiated
    //     audio notifications.
    // duckOthers — наш короткий bleep автоматом приглушит Apple Music
    //   на время воспроизведения, потом восстановит громкость.
    final ctx = AudioContext(
      android: const AudioContextAndroid(
        isSpeakerphoneOn: false,
        stayAwake: false,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.none,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.duckOthers},
      ),
    );
    // На iOS AudioContext по сути global (одна AVAudioSession на процесс).
    // Лучше выставить через AudioPlayer.global, чтобы все плееры подхватили
    // одинаково и без гонки на старте.
    try {
      await AudioPlayer.global.setAudioContext(ctx);
    } catch (e) {
      debugPrint('[sound] global setAudioContext failed: $e');
    }
    for (var i = 0; i < _pool.length; i++) {
      final p = _pool[i];
      await p.setReleaseMode(ReleaseMode.stop);
      try {
        await p.setAudioContext(ctx);
      } catch (e) {
        debugPrint('[sound] setAudioContext failed: $e');
      }
      await p.setVolume(_volume);
      // Preload дефолтного звука — первая реальная новость не тратит
      // время на диск+инициализацию MediaPlayer. Без этого звук обрезается
      // на первое воспроизведение в release-сборке на Android.
      try {
        await p.setSource(AssetSource('sounds/$_soundName.mp3'));
        _preloaded[i] = _soundName;
      } catch (e) {
        debugPrint('[sound] preload failed on #$i: $e');
      }
    }
  }

  set enabled(bool v) {
    _enabled = v;
    _persistBool(_kEnabledKey, v);
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    for (final p in _pool) {
      try {
        await p.setVolume(_volume);
      } catch (e) {
        debugPrint('[sound] setVolume failed: $e');
      }
    }
    _persistDouble(_kVolumeKey, _volume);
  }

  Future<void> setSoundName(String name) async {
    if (!kAvailableSounds.contains(name)) return;
    _soundName = name;
    _persistString(_kSoundNameKey, name);
    // Preload новый звук во все плееры, чтобы первый playOnce после смены
    // звука не тратил время на загрузку asset.
    for (var i = 0; i < _pool.length; i++) {
      try {
        await _pool[i].stop();
        await _pool[i].setSource(AssetSource('sounds/$name.mp3'));
        _preloaded[i] = name;
      } catch (_) {
        _preloaded.remove(i);
      }
    }
  }

  Future<void> _persistString(String key, String v) async {
    try {
      (await SharedPreferences.getInstance()).setString(key, v);
    } catch (_) {}
  }

  Future<void> _persistBool(String key, bool v) async {
    try {
      (await SharedPreferences.getInstance()).setBool(key, v);
    } catch (_) {}
  }

  Future<void> _persistDouble(String key, double v) async {
    try {
      (await SharedPreferences.getInstance()).setDouble(key, v);
    } catch (_) {}
  }

  /// Проиграть уведомление (если включено).
  Future<void> play() async {
    if (!_enabled) return;
    await playOnce(_soundName);
  }

  /// Однократно проиграть указанный звук (для хэштег-алертов).
  /// Запускает на следующем плеере в пуле — это позволяет перекрывать
  /// звуки если новости идут часто, не обрывая предыдущий.
  Future<void> playOnce(String soundName) async {
    if (!_enabled) return;
    if (!kAvailableSounds.contains(soundName)) return;
    final idx = _nextIdx;
    final player = _pool[idx];
    _nextIdx = (_nextIdx + 1) % _poolSize;
    try {
      if (_preloaded[idx] == soundName) {
        // Source уже готов — дешёвый replay: перемотка + resume.
        // На Android это ≈ мгновенно, без перезагрузки asset с диска.
        await player.seek(Duration.zero);
        await player.resume();
      } else {
        // Звук другой (первый запуск или хэштег-алерт) — полная загрузка
        // и запоминаем что этот asset теперь preloaded.
        await player.stop();
        await player.play(
          AssetSource('sounds/$soundName.mp3'),
          volume: _volume,
        );
        _preloaded[idx] = soundName;
      }
    } catch (e) {
      debugPrint('[sound] play failed: $e');
    }
  }

  Future<void> dispose() async {
    for (final p in _pool) {
      await p.dispose();
    }
  }
}

final soundService = SoundService();
