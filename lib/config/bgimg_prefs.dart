import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/enums/bgimg_alignment.dart';
import 'package:songjiang_reader/enums/bgimg_fit.dart';
import 'package:songjiang_reader/enums/bgimg_type.dart';
import 'package:songjiang_reader/models/bgimg.dart';

/// 阅读背景图配置的领域访问层。
///
/// 须在 `Prefs().initPrefs()` 之后使用。
class BgimgPrefs {
  BgimgPrefs._();

  static const String bgimgKey = 'bgimg';
  static const String bgimgFitKey = 'bgimgFit';

  static SharedPreferences? _sp;

  static Future<void> ensureInitialized() async {
    _sp = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _require {
    final sp = _sp;
    if (sp == null) {
      throw StateError(
        'BgimgPrefs.ensureInitialized() 未调用（应在 main 中 Prefs 初始化后）',
      );
    }
    return sp;
  }

  static BgimgModel get bgimg {
    final json = _require.getString(bgimgKey);
    if (json == null) {
      return BgimgModel(
        type: BgimgType.none,
        path: 'none',
        alignment: BgimgAlignment.center,
      );
    }
    return BgimgModel.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  static set bgimg(BgimgModel bgimg) {
    _require.setString(bgimgKey, jsonEncode(bgimg.toJson()));
  }

  static BgimgFitEnum get fit =>
      BgimgFitEnum.fromCode(_require.getString(bgimgFitKey) ?? 'cover');

  static set fit(BgimgFitEnum fit) {
    _require.setString(bgimgFitKey, fit.code);
  }
}
