import 'package:songjiang_reader/config/tts_prefs.dart';
import 'package:songjiang_reader/service/tts/models/tts_voice.dart';
import 'package:songjiang_reader/service/tts/tts_factory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tts_providers.g.dart';

@riverpod
class TtsService extends _$TtsService {
  @override
  String build() {
    return TtsPrefs.serviceId;
  }

  void setService(String serviceId) {
    TtsPrefs.serviceId = serviceId;
    state = serviceId;
  }
}

@riverpod
Future<List<TtsVoice>> ttsVoices(Ref ref) async {
  // Watch service change to trigger refresh
  ref.watch(ttsServiceProvider);

  // The voice list usually depends on what is currently active or selected.
  final tts = TtsFactory().current;
  return await tts.getVoices();
}

@riverpod
class OnlineTtsConfig extends _$OnlineTtsConfig {
  @override
  Map<String, dynamic> build(String serviceId) {
    return TtsPrefs.getOnlineConfig(serviceId);
  }

  void updateConfig(String key, dynamic value) {
    final current = Map<String, dynamic>.from(state);
    current[key] = value;
    TtsPrefs.saveOnlineConfig(serviceId, current);
    state = current;
  }
}
