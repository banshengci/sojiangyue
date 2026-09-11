import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';

/// 松江阅自有视觉体系
///
/// 取「松江」意象：松之苍绿为主，宣纸之暖白为底，松烟墨为暗色，
/// 松花黄作点缀。与上游 anx-reader 的冷灰 + 蓝色调刻意区分。
class SongJiangColors {
  const SongJiangColors._();

  /// 松绿 —— 品牌主色，同时是动态配色的默认种子色
  /// （对齐设计令牌《松江阅 · 色彩》松绿 #2E6B4F）
  static const Color pine = Color(0xFF2E6B4F);

  /// 松绿（浅）—— 渐变起点 / 亮色强调
  static const Color pineLight = Color(0xFF59A17D);

  /// 松绿（深）—— 渐变终点 / 深色强调
  static const Color pineDeep = Color(0xFF173B2E);

  /// 江青 —— 次强调色（设计令牌 江青 #3D8C7D）
  static const Color bamboo = Color(0xFF3D8C7D);

  /// 江青（浅）—— 清新明亮的青绿，用于品牌头图渐变起点
  static const Color bambooLight = Color(0xFF6BB8A6);

  /// 江青（深）—— 青绿渐变终点，保持竹意同时不过于暗沉
  static const Color bambooDeep = Color(0xFF2A6B5E);

  /// 砂朱 —— 点缀色（徽标、特殊标签）（设计令牌 砂朱 #C4543D）
  static const Color pollen = Color(0xFFC4543D);

  /// 纸白 —— 浅色模式分组背景（设计令牌 纸白 #F7F5ED）
  static const Color paper = Color(0xFFF7F5ED);

  /// 纸白 —— 浅色模式卡片 / 容器表面
  static const Color paperCard = Color(0xFFFFFFFF);

  /// 松墨 —— 深色模式分组背景（设计令牌 松墨 #12261F）
  static const Color ink = Color(0xFF12261F);

  /// 墨绿 —— 深色模式卡片 / 容器表面
  static const Color inkCard = Color(0xFF1B332A);

  /// 深色模式下的次级容器（比 [inkCard] 略亮一档）
  static const Color inkCardHigh = Color(0xFF263A30);

  /// 松霜 —— 弱化色（次要底 / 描边 / 标签底）（设计令牌 松霜 #A8C9BD）
  static const Color frost = Color(0xFFA8C9BD);

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
