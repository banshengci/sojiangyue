import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';

/// 松江阅自有视觉体系
///
/// 取「松江」意象：松之苍绿为主，宣纸之暖白为底，松烟墨为暗色，
/// 松花黄作点缀。与上游 Anx 的冷灰 + 蓝色调刻意区分。
class SongJiangColors {
  const SongJiangColors._();

  /// 松绿 —— 品牌主色，同时是动态配色的默认种子色
  static const Color pine = Color(0xFF1B6B44);

  /// 松绿（浅）—— 渐变起点 / 亮色强调
  static const Color pineLight = Color(0xFF35B575);

  /// 松绿（深）—— 渐变终点 / 深色强调
  static const Color pineDeep = Color(0xFF0C3323);

  /// 竹青 —— 次强调色
  static const Color bamboo = Color(0xFF4F9E75);

  /// 竹青（浅）—— 清新明亮的青绿，用于品牌头图渐变起点
  static const Color bambooLight = Color(0xFF7DD8A8);

  /// 竹青（深）—— 青绿渐变终点，保持竹意同时不过于暗沉
  static const Color bambooDeep = Color(0xFF2A8F70);

  /// 松花黄 —— 点缀色（徽标、特殊标签）
  static const Color pollen = Color(0xFFC88C2E);

  /// 宣纸 —— 浅色模式分组背景（暖调，区别于 iOS 冷灰）
  static const Color paper = Color(0xFFF5F2EA);

  /// 宣纸白 —— 浅色模式卡片 / 容器表面
  static const Color paperCard = Color(0xFFFFFDF7);

  /// 松烟墨 —— 深色模式分组背景（带绿调，区别于纯中性灰）
  static const Color ink = Color(0xFF121815);

  /// 墨绿 —— 深色模式卡片 / 容器表面
  static const Color inkCard = Color(0xFF1E2621);

  /// 深色模式下的次级容器（比 [inkCard] 略亮一档）
  static const Color inkCardHigh = Color(0xFF263029);

  /// 竹青渐变（品牌头图、引导页）—— 比松绿更清新明亮
  static const LinearGradient bambooGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[bambooLight, bamboo, bambooDeep],
  );

  /// 深色模式下的竹青渐变（降低明度，保持可读性）
  static const LinearGradient bambooGradientDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF6BBF9A), Color(0xFF3B8C70), Color(0xFF235A4A)],
  );

  /// 应用向用户提供的主题色候选。
  ///
  /// 以松绿为默认，其余取自水墨 / 江南意象的邻近色，
  /// 不做彩虹式全色轮平铺，保证整体调性统一。
  static const List<Color> themePalette = <Color>[
    pine, // 松绿（默认）
    Color(0xFF3E7A5E), // 苔痕
    Color(0xFF2F6E7A), // 江蓝
    Color(0xFF4A5D8A), // 远山
    Color(0xFF7A4A6B), // 藕荷
    Color(0xFF9A5B3E), // 陶棕
    Color(0xFFA8763A), // 松花黄
    Color(0xFF8A6D4B), // 竹篾
    Color(0xFF6B6257), // 砚灰
    Color(0xFF4F5B52), // 苍黛
    Color(0xFF2F5D3A), // 深松
    Color(0xFF1F3A33), // 松烟
  ];
}

/// 松江阅品牌标识：Logo + 中文名 + 英文名
///
/// 用于设置页顶部头图、关于对话框、导航侧栏等位置。
class SongJiangBrand {
  const SongJiangBrand._();

  /// 应用中文名
  static const String name = '松江阅';

  /// 应用英文名
  static const String nameEn = 'SongJiang Reader';

  /// 品牌标语
  static const String tagline = '松风入怀，书卷在手';

  /// Logo 资源路径
  static const String logoAsset = 'assets/icon/songjiang-logo.png';
}
