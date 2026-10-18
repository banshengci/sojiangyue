import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/l10n/generated/L10n_zh.dart';

/// 同步的 L10n delegate —— 让「用了 L10n 的页面」也能写 widget 测试。
///
/// ## 为什么需要它
///
/// 项目 `l10n.yaml` 开了 `use-deferred-loading: true`，`L10n.dart` 用
/// `import 'L10n_zh.dart' deferred as L10n_zh;` 延迟加载。
/// 在 widget 测试里 `L10n.delegate.load()` 会走 `_loadLibrary`，
/// 在 fake_async 下产生一个**永远不会完成**的 Timer：
///
/// ```
/// A Timer is still pending even after the widget tree was disposed.
/// ```
///
/// 结果是 `Localizations` 永远停在加载态，整棵树渲染出 **0 个 Text**，
/// 任何 `L10n.of(context)` 也会因为拿不到实例而空指针。
///
/// 既有 20 个渲染测试全部绕开了 L10n（只测 `design/` 下用硬编码中文的页面），
/// 所以这个坑一直没暴露。
///
/// ## 做法
///
/// 各语言的实现类（如 `L10nZh`）本身**不是** deferred 的，只是被 deferred 导入。
/// 测试里直接普通 import `L10n_zh.dart`，再用 [SynchronousFuture] 返回实例，
/// 就能在首帧同步完成本地化。
///
/// ## 用法
///
/// ```dart
/// await tester.pumpWidget(wrapWithL10n(const MinePage()));
/// ```
class TestL10nDelegate extends LocalizationsDelegate<L10n> {
  const TestL10nDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'zh';

  @override
  Future<L10n> load(Locale locale) =>
      SynchronousFuture<L10n>(L10nZh(locale.languageCode));

  @override
  bool shouldReload(TestL10nDelegate old) => false;
}

/// 测试用的本地化 delegate 列表（同步 L10n + Material/Cupertino/Widgets）。
const List<LocalizationsDelegate<dynamic>> testLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
  TestL10nDelegate(),
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

/// 用同步本地化包一层 MaterialApp，供页面级 widget 测试使用。
Widget wrapWithL10n(
  Widget home, {
  Locale locale = const Locale('zh'),
}) {
  return MaterialApp(
    localizationsDelegates: testLocalizationsDelegates,
    supportedLocales: const <Locale>[Locale('zh')],
    locale: locale,
    home: home,
  );
}
