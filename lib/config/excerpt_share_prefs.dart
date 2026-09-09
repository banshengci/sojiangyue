import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/enums/excerpt_share_template.dart';
import 'package:songjiang_reader/models/font_model.dart';

/// 摘录分享卡片配置的领域访问层。
class ExcerptSharePrefs {
  ExcerptSharePrefs._();

  static const String templateKey = 'excerptShareTemplate';
  static const String fontKey = 'excerptShareFont';
  static const String colorIndexKey = 'excerptShareColorIndex';
  static const String bgimgIndexKey = 'excerptShareBgimgIndex';

  static SharedPreferences? _sp;

  static Future<void> ensureInitialized() async {
    _sp = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _require {
    final sp = _sp;
    if (sp == null) {
      throw StateError(
        'ExcerptSharePrefs.ensureInitialized() 未调用（应在 main 中 Prefs 初始化后）',
      );
    }
    return sp;
  }

  static ExcerptShareTemplateEnum get template {
    return ExcerptShareTemplateEnum.values.firstWhere(
      (e) => e.name == _require.getString(templateKey),
      orElse: () => ExcerptShareTemplateEnum.defaultTemplate,
    );
  }

  static set template(ExcerptShareTemplateEnum value) {
    _require.setString(templateKey, value.name);
  }

  /// 系统默认字体（与旧 Prefs 行为一致；label 依赖 L10n，由调用方在 UI 层处理）。
  static FontModel get font {
    final json = _require.getString(fontKey);
    if (json == null) {
      return FontModel(
        label: 'System',
        name: 'customFont0',
        path: 'SourceHanSerifSC-Regular.otf',
      );
    }
    return FontModel.fromJson(json);
  }

  static set font(FontModel value) {
    _require.setString(fontKey, value.toJson());
  }

  static int get colorIndex => _require.getInt(colorIndexKey) ?? 0;

  static set colorIndex(int index) {
    _require.setInt(colorIndexKey, index);
  }

  static int get bgimgIndex => _require.getInt(bgimgIndexKey) ?? 1;

  static set bgimgIndex(int index) {
    _require.setInt(bgimgIndexKey, index);
  }
}
