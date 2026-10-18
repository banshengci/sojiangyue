// lib/service/gameplay/gameplay_catalog.dart
//
// 玩法总目录：内置玩法 + 已安装玩法包。
//
// 为什么要这一层：玩法原先是硬编码在 Dart 里的常量，用户装不了新的。
// 现在玩法包（gameplay_mode 类型）可以携带玩法模式，装完就出现在这里。
//
// 两条规则：
// 1. **内置优先不可被顶掉**：包里的 id 若与内置重复，视为包出错，直接忽略，
//    避免第三方包覆盖掉「剧本杀」这类用户已经熟悉的东西。
// 2. 已安装包之间同 id 时后装的覆盖先装的（升级场景）。

import 'package:songjiang_reader/models/gameplay_mode.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_modes.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_pack_models.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_pack_service.dart';
import 'package:songjiang_reader/utils/log/common.dart';

class GameplayCatalog {
  const GameplayCatalog({
    required this.builtin,
    required this.installed,
  });

  /// 内置玩法。
  final List<GameplayMode> builtin;

  /// 来自已安装玩法包的玩法。
  final List<GameplayMode> installed;

  /// 全部可选玩法（内置在前）。
  List<GameplayMode> get all => [...builtin, ...installed];

  bool get hasInstalled => installed.isNotEmpty;

  /// 是否来自玩法包（界面据此标「已安装」）。
  bool isFromPack(String id) => installed.any((m) => m.id == id);

  /// 读取内置 + 已安装。读取失败时退化为只有内置，不影响开新局。
  static Future<GameplayCatalog> load() async {
    final installed = <GameplayMode>[];
    try {
      final packs = await GameplayPackService.instance.listInstalled();
      final builtinIds = kBuiltinGameplayModes.map((m) => m.id).toSet();
      for (final pack in packs) {
        if (pack.packType != GameplayPackType.gameplayMode) continue;
        for (final mode in pack.gameplayModes) {
          if (builtinIds.contains(mode.id)) {
            SjLog.warning('Gameplay: 玩法包 ${pack.id} 重复声明了内置玩法 ${mode.id}，已忽略');
            continue;
          }
          installed.removeWhere((m) => m.id == mode.id);
          installed.add(mode);
        }
      }
    } catch (e) {
      SjLog.warning('Gameplay: 读取已安装玩法包失败: $e');
    }
    return GameplayCatalog(
      builtin: kBuiltinGameplayModes,
      installed: installed,
    );
  }
}
