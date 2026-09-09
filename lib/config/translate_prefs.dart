import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/enums/lang_list.dart';
import 'package:songjiang_reader/service/translate/index.dart';
import 'package:songjiang_reader/utils/get_current_language_code.dart';

/// 翻译服务与语言的领域访问层。
class TranslatePrefs {
  TranslatePrefs._();

  static const String serviceKey = 'translateService';
  static const String fromKey = 'translateFrom';
  static const String toKey = 'translateTo';
  static const String fullServiceKey = 'fullTextTranslateService';
  static const String fullFromKey = 'fullTextTranslateFrom';
  static const String fullToKey = 'fullTextTranslateTo';
  static const String translationModeKey = 'translationMode';

  static SharedPreferences? _sp;

  static Future<void> ensureInitialized() async {
    _sp = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _require {
    final sp = _sp;
    if (sp == null) {
      throw StateError(
        'TranslatePrefs.ensureInitialized() 未调用（应在 main 中 Prefs 初始化后）',
      );
    }
    return sp;
  }

  static TranslateService get service =>
      getTranslateService(_require.getString(serviceKey) ?? 'bingWeb');

  static set service(TranslateService value) {
    _require.setString(serviceKey, value.name);
  }

  static LangListEnum get from =>
      getLang(_require.getString(fromKey) ?? 'auto');

  static set from(LangListEnum value) {
    _require.setString(fromKey, value.code);
  }

  static LangListEnum get to =>
      getLang(_require.getString(toKey) ?? getCurrentLanguageCode());

  static set to(LangListEnum value) {
    _require.setString(toKey, value.code);
  }

  static TranslateService get fullTextService {
    final name = _require.getString(fullServiceKey) ?? 'microsoftApi';
    if (name == 'microsoft') {
      _require.setString(fullServiceKey, 'microsoftApi');
      return TranslateService.microsoftApi;
    }
    return getTranslateService(name);
  }

  static set fullTextService(TranslateService value) {
    _require.setString(fullServiceKey, value.name);
  }

  static LangListEnum get fullTextFrom =>
      getLang(_require.getString(fullFromKey) ?? 'auto');

  static set fullTextFrom(LangListEnum value) {
    _require.setString(fullFromKey, value.code);
  }

  static LangListEnum get fullTextTo =>
      getLang(_require.getString(fullToKey) ?? getCurrentLanguageCode());

  static set fullTextTo(LangListEnum value) {
    _require.setString(fullToKey, value.code);
  }
}
