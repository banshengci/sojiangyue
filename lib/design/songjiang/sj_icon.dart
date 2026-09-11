import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'sj_tokens.dart';

/// 品牌功能图标集（icons-24，24px 网格 / 1.75px 描边）。
///
/// 资源位于 `assets/songjiang/icons/`，导出 SVG 为拍平填充路径，
/// 这里用 `BlendMode.srcIn` 重新着色，使其能随主题变化。
enum SjIconName {
  bookshelf('01-bookshelf'),
  read('02-read'),
  toc('03-toc'),
  bookmark('04-bookmark'),
  typography('05-typography'),
  readingTime('06-reading-time'),
  aiDeepRead('07-ai-deepread'),
  translate('08-translate'),
  mindmap('09-mindmap'),
  quiz('10-quiz'),
  reviewCard('11-review-card'),
  listen('12-listen'),
  note('13-note'),
  highlight('14-highlight'),
  markColor('15-mark-color'),
  shareCard('16-share-card'),
  stats('17-stats'),
  heatmap('18-heatmap'),
  achievement('19-achievement'),
  opds('20-opds'),
  import('21-import'),
  sync('22-sync'),
  nightMode('23-night-mode'),
  settings('24-settings');

  const SjIconName(this.slug);

  /// 文件名（不含扩展名）。
  final String slug;

  /// 资源路径。
  String get path => 'assets/songjiang/icons/$slug.svg';
}

/// 渲染一枚品牌线性图标（可按主题着色）。
class SjIcon extends StatelessWidget {
  const SjIcon(
    this.name, {
    super.key,
    this.size = SjSizes.iconGrid,
    this.color,
  });

  final SjIconName name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      name.path,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        color ?? SjColors.of(context).ink,
        BlendMode.srcIn,
      ),
    );
  }
}

/// 品牌情境插画（浅色 / 深色两套）。
enum SjIllustration {
  emptyShelf('empty-shelf'),
  noResults('no-results'),
  offline('offline'),
  noNotes('no-notes'),
  finishedBook('finished-book'),
  aiReading('ai-reading');

  const SjIllustration(this.slug);

  final String slug;

  /// 按亮度选择对应配色。
  String pathFor(Brightness brightness) =>
      'assets/songjiang/illustrations/'
      '${brightness == Brightness.dark ? 'dark' : 'light'}/$slug.svg';
}

/// 渲染一张品牌插画。
class SjIllustrationView extends StatelessWidget {
  const SjIllustrationView(
    this.illustration, {
    super.key,
    this.width = 200,
    this.height,
  });

  final SjIllustration illustration;
  final double width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      illustration.pathFor(Theme.of(context).brightness),
      width: width,
      height: height,
    );
  }
}
