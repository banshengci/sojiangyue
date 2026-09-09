import 'dart:io';

class EnvVar {
  static const bool isAppStore =
      String.fromEnvironment('isAppStore', defaultValue: 'false') == 'true';

  static const bool isPlayStore =
      String.fromEnvironment('isPlayStore', defaultValue: 'false') == 'true';
  static const bool isFdroid =
      String.fromEnvironment('isFdroid', defaultValue: 'false') == 'true';
  static const bool isOhosStore =
      String.fromEnvironment('isOhosStore', defaultValue: 'false') == 'true';

  static bool get _isChineseMainlandLocale =>
      Platform.localeName == 'zh_Hans_CN';

  static bool get isStoreBuild => isAppStore || isPlayStore;

  static bool get showIapPlaceHolder => isOhosStore;

  static bool get enableCheckUpdate =>
      !isStoreBuild && !isFdroid && !isOhosStore;
  // 松江阅：关于页不展示捐赠入口（个人自用 / 不设捐赠渠道）。
  static bool get enableDonation => false;
  static bool get enableInAppPurchase => isStoreBuild;

  static bool get showBeian =>
      (isAppStore && _isChineseMainlandLocale) || isOhosStore;
  static bool get enableOpenAiConfig => !showBeian;
  static bool get showTelegramLink => !showBeian;

  static bool get enableAIFeature => !isOhosStore;
}
