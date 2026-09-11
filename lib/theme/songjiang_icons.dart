import 'package:flutter/material.dart';
import 'package:songjiang_reader/design/songjiang/sj_icon.dart';

/// 松江阅统一图标与形态 token。
///
/// Material 图标用于 BottomNavigationBar / NavigationRail 等只接受
/// [IconData] 的场景；品牌 SVG 图标通过 [SjBrandIcon] 在其他位置使用。
class SongJiangIcons {
  const SongJiangIcons._();

  // ---- 底部导航 / 侧栏 ----
  static const IconData bookshelf = Icons.menu_book_outlined;
  static const IconData bookshelfSelected = Icons.menu_book_rounded;
  static const IconData statistics = Icons.insights_outlined;
  static const IconData statisticsSelected = Icons.insights_rounded;
  static const IconData notes = Icons.sticky_note_2_outlined;
  static const IconData notesSelected = Icons.sticky_note_2_rounded;
  static const IconData settings = Icons.tune_outlined;
  static const IconData settingsSelected = Icons.tune_rounded;

  // ---- 书架动作 ----
  static const IconData import = Icons.add_circle_outline_rounded;
  static const IconData importSelected = Icons.add_circle_rounded;
  static const IconData sort = Icons.swap_vert_rounded;
  static const IconData tags = Icons.sell_outlined;
  static const IconData search = Icons.search_rounded;
  static const IconData multiSelect = Icons.checklist_rounded;
  static const IconData multiSelectCancel = Icons.close_rounded;
  static const IconData check = Icons.check_circle_rounded;

  // ---- AI 深读 ----
  static const IconData aiPreview = Icons.lightbulb_outline_rounded;
  static const IconData aiQuiz = Icons.quiz_outlined;
  static const IconData aiRecap = Icons.summarize_outlined;
  static const IconData aiChapter = Icons.article_outlined;
  static const IconData aiBook = Icons.auto_stories_outlined;
  static const IconData aiMindmap = Icons.account_tree_outlined;
  static const IconData sparkle = Icons.auto_awesome_rounded;

  // ---- 阅读页 ----
  static const IconData bookmark = Icons.bookmark_border_rounded;
  static const IconData bookmarkOn = Icons.bookmark_rounded;
  static const IconData toc = Icons.toc_rounded;
  static const IconData more = Icons.more_horiz_rounded;
  static const IconData translate = Icons.translate_rounded;
  static const IconData vocabulary = Icons.bookmark_add_outlined;
  static const IconData tts = Icons.headphones_outlined;
  static const IconData palette = Icons.palette_outlined;
  static const IconData edit = Icons.edit_outlined;

  // ---- 通用 ----
  static const IconData chevronRight = Icons.chevron_right_rounded;
  static const IconData chevronLeft = Icons.chevron_left_rounded;
  static const IconData back = Icons.arrow_back_rounded;
  static const IconData download = Icons.download_rounded;
  static const IconData cloud = Icons.cloud_outlined;
  static const IconData storage = Icons.sd_storage_outlined;
  static const IconData dictionary = Icons.menu_book_outlined;
  static const IconData series = Icons.collections_bookmark_outlined;
  static const IconData batchTag = Icons.label_outline_rounded;
  static const IconData batchCover = Icons.image_outlined;
  static const IconData share = Icons.share_outlined;
  static const IconData refresh = Icons.refresh_rounded;
  static const IconData cloudUpload = Icons.cloud_upload_outlined;
  static const IconData trash = Icons.delete_outline_rounded;
  static const IconData checkCircle = Icons.check_circle_rounded;
  static const IconData checkCircleOutline = Icons.check_circle_outline_rounded;
  static const IconData close = Icons.close_rounded;
  static const IconData closeCircle = Icons.cancel_rounded;
  static const IconData moreVertical = Icons.more_vert_rounded;
  static const IconData copy = Icons.copy_outlined;
  static const IconData globe = Icons.language_rounded;
  static const IconData message = Icons.chat_bubble_outline_rounded;
  static const IconData filter = Icons.filter_list_rounded;
  static const IconData filterOn = Icons.filter_alt_rounded;
  static const IconData arrowUp = Icons.arrow_upward_rounded;
  static const IconData arrowDown = Icons.arrow_downward_rounded;
  static const IconData play = Icons.play_circle_outline_rounded;
  static const IconData pause = Icons.pause_circle_outline_rounded;
  static const IconData stop = Icons.stop_circle_outlined;
  static const IconData clock = Icons.schedule_outlined;
  static const IconData activity = Icons.show_chart_rounded;
  static const IconData book = Icons.book_outlined;
  static const IconData bookOpen = Icons.menu_book_outlined;
}

/// 底部导航选中胶囊指示器（松绿半透明）。
class SongJiangNavIndicator extends StatelessWidget {
  const SongJiangNavIndicator({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 55 : 32),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

/// 品牌 SVG 图标包装：在非 BottomNavigationBar 场景下使用品牌图标集。
///
/// 用法与 Material `Icon` 一致，但渲染的是 24px 品牌线性图标。
/// 颜色默认跟随主题 onSurface，可用 [color] 覆盖。
class SjBrandIcon extends StatelessWidget {
  const SjBrandIcon(this.name, {super.key, this.size = 24, this.color});

  final SjIconName name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SjIcon(name, size: size, color: color);
  }
}

/// 品牌图标名称映射：Material 图标常量 → 品牌 SVG 名称。
///
/// 底部导航仍用 Material（接受 IconData），
/// 其他位置可用此映射切换到品牌 SVG。
class SongJiangBrandIcons {
  const SongJiangBrandIcons._();

  static const SjIconName bookshelf = SjIconName.bookshelf;
  static const SjIconName read = SjIconName.read;
  static const SjIconName toc = SjIconName.toc;
  static const SjIconName bookmark = SjIconName.bookmark;
  static const SjIconName typography = SjIconName.typography;
  static const SjIconName readingTime = SjIconName.readingTime;
  static const SjIconName aiDeepRead = SjIconName.aiDeepRead;
  static const SjIconName translate = SjIconName.translate;
  static const SjIconName mindmap = SjIconName.mindmap;
  static const SjIconName quiz = SjIconName.quiz;
  static const SjIconName reviewCard = SjIconName.reviewCard;
  static const SjIconName listen = SjIconName.listen;
  static const SjIconName note = SjIconName.note;
  static const SjIconName highlight = SjIconName.highlight;
  static const SjIconName markColor = SjIconName.markColor;
  static const SjIconName shareCard = SjIconName.shareCard;
  static const SjIconName stats = SjIconName.stats;
  static const SjIconName heatmap = SjIconName.heatmap;
  static const SjIconName achievement = SjIconName.achievement;
  static const SjIconName opds = SjIconName.opds;
  static const SjIconName importIcon = SjIconName.import;
  static const SjIconName sync = SjIconName.sync;
  static const SjIconName nightMode = SjIconName.nightMode;
  static const SjIconName settings = SjIconName.settings;
}
