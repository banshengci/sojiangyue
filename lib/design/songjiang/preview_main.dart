import 'package:flutter/material.dart';

import 'data/sj_view_models.dart';
import 'sj_gallery.dart';
import 'sj_tokens.dart';

/// 松江阅页面视觉 · 设计预览入口。
///
/// 独立于 App 主入口，便于在真机/桌面上单独查看三屏视觉：
///
/// ```bash
/// flutter run -t lib/design/songjiang/preview_main.dart
/// ```
void main() => runApp(const SjPreviewApp());

/// 预览外壳（顶部提供明暗切换）。
class SjPreviewApp extends StatefulWidget {
  const SjPreviewApp({super.key});

  @override
  State<SjPreviewApp> createState() => _SjPreviewAppState();
}

class _SjPreviewAppState extends State<SjPreviewApp> {
  bool _dark = false;

  ThemeData _theme(Brightness brightness) {
    final c = brightness == Brightness.dark ? SjColors.dark : SjColors.light;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: c.pine,
        brightness: brightness,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '松江阅 · 页面预览',
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: Builder(
        builder: (context) {
          final c = SjColors.of(context);
          return Scaffold(
            backgroundColor: c.paper,
            body: Column(
              children: [
                Material(
                  color: c.card,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        SjSpace.page,
                        6,
                        SjSpace.s,
                        6,
                      ),
                      child: Row(
                        children: [
                          Text(
                            '松江阅 · 页面预览',
                            style: SjText.sectionTitle(c.ink),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: _dark ? '切换到浅色' : '切换到深色',
                            onPressed: () => setState(() => _dark = !_dark),
                            icon: Icon(
                              _dark ? Icons.light_mode : Icons.dark_mode,
                              color: c.clay,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Expanded(child: SjGallery(data: SjGalleryData.sample)),
              ],
            ),
          );
        },
      ),
    );
  }
}
