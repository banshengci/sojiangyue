import 'dart:async';

import 'package:songjiang_reader/config/tts_prefs.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/main.dart';
import 'package:songjiang_reader/page/book_player/epub_player.dart';
import 'package:songjiang_reader/page/settings_page/narrate.dart';
import 'package:songjiang_reader/service/tts/base_tts.dart';
import 'package:songjiang_reader/service/tts/tts_handler.dart';
import 'package:songjiang_reader/service/tts/tts_service.dart' as tts_svc;
import 'package:songjiang_reader/theme/songjiang_icons.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/reading_page/more_settings/more_settings.dart';
import 'package:songjiang_reader/widgets/reading_page/widget_title.dart';
import 'package:flutter/material.dart';

class TtsWidget extends StatefulWidget {
  const TtsWidget({super.key, required this.epubPlayerKey});

  final GlobalKey<EpubPlayerState> epubPlayerKey;

  @override
  State<TtsWidget> createState() => _TtsWidgetState();
}

class _TtsWidgetState extends State<TtsWidget> {
  double stopSeconds = 0;
  Timer? stopTimer;

  @override
  void initState() {
    super.initState();
    _startIfNeeded();
  }

  /// 面板一打开就接着播。
  ///
  /// 原来这段直接写在 initState 里，还带着两个隐患：
  /// 一是 `currentState!` 硬断言，阅读内容没就绪时点「听」直接崩；
  /// 二是 `init().then(play)` 不看面板还在不在——用户点开又立刻关掉，
  /// 声音会在面板消失之后突然响起来。
  Future<void> _startIfNeeded() async {
    if (TtsHandler().ttsStateNotifier.value == TtsStateEnum.playing) return;
    final player = widget.epubPlayerKey.currentState;
    if (player == null) {
      SjToast.show('阅读内容还没准备好，稍后再试');
      return;
    }
    try {
      await TtsHandler().init(player.initTts, player.ttsNext, player.ttsPrev);
      if (!mounted) return;
      await audioHandler.play();
    } catch (e) {
      SjLog.warning('TTS: 启动朗读失败: $e');
      if (mounted) SjToast.show('听书启动失败，检查朗读设置里的语音服务');
    }
  }

  /// 定时关闭：按整秒倒数，到点停。
  ///
  /// 原来是每 5 秒减 5 秒，可 slider 是连续值，减着减着就跳变、甚至变负；
  /// 更麻烦的是关掉面板后定时器还在跑——到点把正在播的书停掉，
  /// 用户看到的就是「听书自己断了」。
  void _setStopAfter(double seconds) {
    setState(() => stopSeconds = seconds);
    stopTimer?.cancel();
    if (seconds <= 0) return;
    stopTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        stopSeconds -= 1;
        if (stopSeconds <= 0) {
          stopSeconds = 0;
          timer.cancel();
          TtsHandler().stop();
        }
      });
    });
  }

  @override
  void dispose() {
    // 不取消的话，面板关掉之后它还在后台倒数
    stopTimer?.cancel();
    super.dispose();
  }

  String _getTtsServiceLabel(BuildContext context) {
    final serviceId = TtsPrefs.serviceId;
    if (serviceId == 'system') {
      return L10n.of(context).ttsTypeSystem;
    }
    return tts_svc.getTtsService(serviceId).getLabel(context);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TtsStateEnum>(
      valueListenable: TtsHandler().ttsStateNotifier,
      builder: (context, ttsState, child) {
        Widget volume() {
          return Row(
            children: [
              Text(L10n.of(context).ttsVolume),
              Expanded(
                child: Slider(
                  value: TtsHandler().volume,
                  onChanged: (newVolume) {
                    setState(() {
                      TtsHandler().volume = newVolume;
                    });
                  },
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  label: TtsHandler().volume.toStringAsFixed(1),
                ),
              ),
            ],
          );
        }

        Widget pitch() {
          return Row(
            children: [
              Text(L10n.of(context).ttsPitch),
              Expanded(
                child: Slider(
                  value: TtsHandler().pitch,
                  onChanged: (newPitch) {
                    setState(() {
                      TtsHandler().pitch = newPitch;
                    });
                  },
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  label: TtsHandler().pitch.toStringAsFixed(1),
                ),
              ),
            ],
          );
        }

        Widget rate() {
          return Row(
            children: [
              Text(L10n.of(context).ttsRate),
              Expanded(
                child: Slider(
                  value: TtsHandler().rate,
                  onChanged: (newRate) {
                    setState(() {
                      TtsHandler().rate = newRate;
                    });
                  },
                  min: 0.0,
                  max: 2.0,
                  divisions: 10,
                  label: TtsHandler().rate.toStringAsFixed(1),
                ),
              ),
            ],
          );
        }

        Widget sliders() {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 5, 20, 0),
            child: Column(
              children: [
                volume(),
                pitch(),
                rate(),
                Row(
                  children: [
                    Text(L10n.of(context).ttsType),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          builder: (context) {
                            return FractionallySizedBox(
                              heightFactor: 0.7,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 16.0),
                                child: const NarrateSettings(),
                              ),
                            );
                          },
                        ).then((_) {
                          // Refresh state if needed when sheet closes
                          setState(() {});
                        });
                      },
                      child: Row(
                        children: [
                          Text(
                            _getTtsServiceLabel(context),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        Widget buttons() {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                onPressed: () async {
                  audioHandler.stop();
                  await widget.epubPlayerKey.currentState!.ttsPrevSection();
                  TtsHandler().playPrevious();
                },
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                onPressed: () {
                  TtsHandler().playPrevious();
                },
                icon: const Icon(SongJiangIcons.chevronLeft),
              ),
              IconButton(
                onPressed: () async {
                  ttsState == TtsStateEnum.playing
                      ? audioHandler.pause()
                      : audioHandler.play();
                },
                icon: ttsState == TtsStateEnum.playing
                    ? const Icon(SongJiangIcons.pause)
                    : const Icon(SongJiangIcons.play),
              ),
              IconButton(
                onPressed: () {
                  audioHandler.stop();
                },
                icon: const Icon(SongJiangIcons.stop),
              ),
              IconButton(
                onPressed: () {
                  TtsHandler().playNext();
                },
                icon: const Icon(SongJiangIcons.chevronRight),
              ),
              IconButton(
                onPressed: () async {
                  audioHandler.stop();
                  await widget.epubPlayerKey.currentState!.ttsNextSection();
                  TtsHandler().playNext();
                },
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          );
        }

        Widget stopTimerWidget() {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 5, 20, 0),
            child: Row(
              children: [
                const Icon(SongJiangIcons.clock),
                const SizedBox(width: 10),
                Expanded(
                  child: Slider(
                    value: (stopSeconds / 60).clamp(0, 60),
                    // 一分钟一档：连续值配整秒倒计时会跳数
                    divisions: 60,
                    onChanged: (newValue) => _setStopAfter(newValue * 60),
                    min: 0.0,
                    max: 60.0,
                    label: L10n.of(context)
                        .commonMinutesFull((stopSeconds / 60).round()),
                  ),
                ),
                Text(
                  L10n.of(context).ttsStopAfter((stopSeconds / 60).ceil()),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              widgetTitle(
                L10n.of(context).ttsNarrator,
                ReadingSettings.style,
              ),
              buttons(),
              const Divider(),
              stopTimerWidget(),
              sliders(),
            ],
          ),
        );
      },
    );
  }
}
