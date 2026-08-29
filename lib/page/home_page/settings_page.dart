import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/page/iap_page.dart';
import 'package:songjiang_reader/page/settings_page/more_settings_page.dart';
import 'package:songjiang_reader/page/settings_page/subpage/ai_chat_page.dart';
import 'package:songjiang_reader/providers/iap.dart';
import 'package:songjiang_reader/service/iap/iap_service.dart';
import 'package:songjiang_reader/theme/songjiang_theme.dart';
import 'package:songjiang_reader/utils/env_var.dart';
import 'package:songjiang_reader/widgets/settings/about.dart';
import 'package:songjiang_reader/widgets/settings/theme_mode.dart';
import 'package:songjiang_reader/widgets/settings/webdav_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.controller});

  final ScrollController? controller;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final ScrollController _scrollController =
      widget.controller ?? ScrollController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 80),
          child: Column(
            children: [
              const _BrandHero(),
              const Divider(),
              // AI 已不在底栏占位，改由这里进入对话（另见阅读页侧栏）
              if (EnvVar.enableAIFeature)
                ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: Text(L10n.of(context).aiChat),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const AiChatPage()),
                  ),
                ),
              if (EnvVar.enableAIFeature) const Divider(),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 10, 8),
                child: ChangeThemeMode(),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: webdavSwitch(context, setState, ref),
              ),
              const Divider(),
              const MoreSettings(),
              if (EnvVar.enableInAppPurchase)
                ListTile(
                  title: Text(L10n.of(context).iapPageTitle),
                  leading: const Icon(Icons.star_outline),
                  subtitle: Text(ref.watch(iapProvider).maybeWhen(
                        data: (state) => state.status.title(context),
                        orElse: () => L10n.of(context).iapStatusUnknown,
                      )),
                  onTap: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const IAPPage()));
                  },
                ),
              const About(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 松江阅品牌头图
///
/// 取代上游 Anx 那个巨大的纯文字标题，改成带松绿渐变、水印字与
/// 版本号的品牌卡片；点击打开「关于」。
class _BrandHero extends StatelessWidget {
  const _BrandHero();

  Future<String> _readVersion() async {
    try {
      final pubspecContent = await rootBundle.loadString('pubspec.yaml');
      return Pubspec.parse(pubspecContent).version.toString();
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: BoxDecoration(
                gradient: isDark
                    ? SongJiangColors.pineGradientDark
                    : SongJiangColors.pineGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: (isDark ? Colors.black : SongJiangColors.pineDeep)
                        .withAlpha(isDark ? 90 : 60),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: InkWell(
                onTap: () => openAboutDialog(),
                child: Stack(
                  children: <Widget>[
                    // 水印：淡「阅」字，营造水墨留白感
                    Positioned(
                      right: -18,
                      bottom: -42,
                      child: Text(
                        '阅',
                        style: TextStyle(
                          fontSize: 150,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withAlpha(isDark ? 16 : 28),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 24, 18, 24),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 66,
                            height: 66,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withAlpha(26)
                                  : Colors.white.withAlpha(220),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withAlpha(isDark ? 40 : 0),
                                width: 1,
                              ),
                            ),
                            padding: const EdgeInsets.all(7),
                            child: Image.asset(
                              SongJiangBrand.logoAsset,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Flexible(
                                      child: Text(
                                        SongJiangBrand.name,
                                        style: const TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 3,
                                          color: Colors.white,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    FutureBuilder<String>(
                                      future: _readVersion(),
                                      builder: (context, snapshot) {
                                        final v = snapshot.data ?? '';
                                        if (v.isEmpty) {
                                          return const SizedBox.shrink();
                                        }
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withAlpha(40),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            'v$v',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color:
                                                  Colors.white.withAlpha(220),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  SongJiangBrand.nameEn,
                                  style: TextStyle(
                                    fontSize: 12,
                                    letterSpacing: 1.6,
                                    color: Colors.white.withAlpha(190),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  SongJiangBrand.tagline,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.3,
                                    color: Colors.white.withAlpha(205),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.white.withAlpha(150),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
