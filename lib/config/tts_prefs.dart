import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// TTS 配置的领域访问层。
///
/// UI 响应式状态见 `providers/tts_providers.dart`；
/// 服务层（SystemTts / OnlineTts / TtsFactory / 各 backend）用本类同步读写。
/// 须在 `Prefs().initPrefs()` 之后使用（main 启动流程已调用 ensureInitialized）。
class TtsPrefs {
  TtsPrefs._();

  static const String volumeKey = 'ttsVolume';
  static const String pitchKey = 'ttsPitch';
  static const String rateKey = 'ttsRate';
  static const String serviceKey = 'ttsService';
  static const String allowMixKey = 'allowMixWithOtherAudio';
  static const String isSystemLegacyKey = 'isSystemTts';
  static const String onlineServiceLegacyKey = 'onlineTtsService';
  static const String voiceModelKeyPrefix = 'ttsVoiceModel_';
  static const String onlineConfigKeyPrefix = 'onlineTtsConfig_';

  static const double defaultVolume = 1.0;
  static const double defaultPitch = 1.0;
  static const double defaultRate = 0.6;
  static const String defaultService = 'system';

  static SharedPreferences? _sp;

  /// 须在 `Prefs().initPrefs()` 之后调用（main 启动流程）。
  static Future<void> ensureInitialized() async {
    _sp = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _require {
    final sp = _sp;
    if (sp == null) {
      throw StateError(
        'TtsPrefs.ensureInitialized() 未调用（应在 main 中 Prefs 初始化后）',
      );
    }
    return sp;
  }

  // ---- volume / pitch / rate ----

  static double get volume =>
      _require.getDouble(volumeKey) ?? defaultVolume;

  static set volume(double value) {
    _require.setDouble(volumeKey, value);
  }

  static double get pitch => _require.getDouble(pitchKey) ?? defaultPitch;

  static set pitch(double value) {
    _require.setDouble(pitchKey, value);
  }

  static double get rate => _require.getDouble(rateKey) ?? defaultRate;

  static set rate(double value) {
    _require.setDouble(rateKey, value);
  }

  // ---- service id ----

  static String get serviceId {
    final service = _require.getString(serviceKey);
    if (service != null) return service;

    // 迁移/回退：旧版用 isSystemTts + onlineTtsService 两个键
    final isSystem = _require.getBool(isSystemLegacyKey) ?? true;
    if (!isSystem) {
      final online = _require.getString(onlineServiceLegacyKey);
      if (online != null) return online;
    }
    return defaultService;
  }

  static set serviceId(String serviceId) {
    _require.setString(serviceKey, serviceId);
  }

  // ---- allow mix with other audio ----

  static bool get allowMixWithOtherAudio =>
      _require.getBool(allowMixKey) ?? false;

  static set allowMixWithOtherAudio(bool allow) {
    _require.setBool(allowMixKey, allow);
  }

  // ---- per-service voice model ----

  static void setVoiceModel(String serviceId, String shortName) {
    _require.setString('$voiceModelKeyPrefix$serviceId', shortName);
  }

  static void removeVoiceModel(String serviceId) {
    _require.remove('$voiceModelKeyPrefix$serviceId');
  }

  static String getVoiceModel(String serviceId) =>
      _require.getString('$voiceModelKeyPrefix$serviceId') ?? '';

  // ---- online TTS JSON config ----

  static Map<String, dynamic> getOnlineConfig(String serviceId) {
    final json = _require.getString('$onlineConfigKeyPrefix$serviceId');
    if (json == null) return {};
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveOnlineConfig(
    String serviceId,
    Map<String, dynamic> config,
  ) async {
    await _require.setString(
      '$onlineConfigKeyPrefix$serviceId',
      jsonEncode(config),
    );
  }
}
