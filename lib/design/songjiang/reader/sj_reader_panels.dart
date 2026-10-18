/// 松江阅 · 阅读页五个上滑面板（微信读书风格）
///
/// 目录 / 笔记 / 进度 / 亮度 / 字体，对应底栏五个工具位。
/// 面板全部是无状态纯展示组件，数据与回调由外部注入：
///  - 设计预览直接用示例数据；
///  - App 内用真实阅读状态（进度、主题、字号）绑定。
library;

import 'package:flutter/material.dart';

import 'sj_reader_controls.dart';
import 'sj_reader_tokens.dart';

// ---------------------------------------------------------------------------
// 目录
// ---------------------------------------------------------------------------

/// 目录里的一行。
@immutable
class SjTocEntry {
  const SjTocEntry({
    required this.title,
    this.pageText = '',
    this.depth = 0,
  });

  /// 章节名。
  final String title;

  /// 右侧页码。
  final String pageText;

  /// 层级（0 为顶层）。
  final int depth;
}

/// 目录面板：搜索 + 目录/书签切换 + 章节列表 + 「去当前」。
class SjTocPanel extends StatelessWidget {
  const SjTocPanel({
    super.key,
    required this.palette,
    required this.bookTitle,
    required this.entries,
    this.currentIndex,
    this.onSelect,
    this.onLocate,
    this.searchController,
    this.searchHint = '搜本书',
    this.onSearchSubmitted,
    this.modeLabel = '目录',
    this.onToggleMode,
  });

  /// 当前阅读调色板。
  final SjReaderPalette palette;

  /// 书名（列表上方的大标题）。
  final String bookTitle;

  /// 章节列表。
  final List<SjTocEntry> entries;

  /// 当前章节下标。
  final int? currentIndex;

  /// 点击章节。
  final ValueChanged<int>? onSelect;

  /// 点「去当前」。
  final VoidCallback? onLocate;

  /// 搜索输入控制器。
  final TextEditingController? searchController;

  /// 搜索框提示。
  final String searchHint;

  /// 提交搜索。
  final ValueChanged<String>? onSearchSubmitted;

  /// 右侧胶囊文案（目录 / 书签）。
  final String modeLabel;

  /// 切换目录 / 书签。
  final VoidCallback? onToggleMode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: _SearchPill(
              palette: palette,
              controller: searchController,
              hint: searchHint,
              onSubmitted: onSearchSubmitted,
            )),
            const SizedBox(width: 10),
            SjPillButton(
              palette: palette,
              label: modeLabel,
              height: 38,
              outlined: true,
              onTap: onToggleMode,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4, left: 4),
          child: Text(
            bookTitle,
            style: SjReaderText.chapterTitle(palette.foreground)
                .copyWith(fontSize: 20),
          ),
        ),
        Expanded(
          child: Stack(
            children: <Widget>[
              ListView.builder(
                padding: const EdgeInsets.only(bottom: 64),
                itemCount: entries.length,
                itemBuilder: (BuildContext context, int index) {
                  final entry = entries[index];
                  final selected = index == currentIndex;
                  return _TocRow(
                    palette: palette,
                    entry: entry,
                    selected: selected,
                    onTap: () => onSelect?.call(index),
                  );
                },
              ),
              if (onLocate != null)
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _LocateButton(palette: palette, onTap: onLocate!),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({
    required this.palette,
    required this.hint,
    this.controller,
    this.onSubmitted,
  });

  final SjReaderPalette palette;
  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.chip,
        borderRadius: BorderRadius.circular(SjReaderSize.pillRadius),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search_rounded, size: 17, color: palette.faint),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: onSubmitted,
              cursorColor: palette.accent,
              style: TextStyle(fontSize: 13, color: palette.foreground),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(fontSize: 13, color: palette.faint),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TocRow extends StatelessWidget {
  const _TocRow({
    required this.palette,
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final SjReaderPalette palette;
  final SjTocEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      fontFamily: SjReaderText.serif,
      fontSize: 15,
      height: 1.3,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      color: selected ? palette.accent : palette.foreground,
    );

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(
          left: 4 + entry.depth * 18,
          right: 2,
          top: 13,
          bottom: 13,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.divider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(entry.title, style: titleStyle),
                  if (selected) ...<Widget>[
                    const SizedBox(height: 5),
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.menu_book_rounded,
                          size: 12,
                          color: palette.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '当前读到',
                          style: TextStyle(fontSize: 11, color: palette.accent),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '添加书签',
                          style: TextStyle(fontSize: 11, color: palette.faint),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              entry.pageText,
              style: TextStyle(fontSize: 12, color: palette.faint),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocateButton extends StatelessWidget {
  const _LocateButton({required this.palette, required this.onTap});

  final SjReaderPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.surfaceRaised,
      borderRadius: BorderRadius.circular(SjReaderSize.pillRadius),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: InkWell(
        borderRadius: BorderRadius.circular(SjReaderSize.pillRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.menu_book_outlined, size: 15, color: palette.foreground),
              const SizedBox(width: 5),
              Text(
                '去当前',
                style: TextStyle(fontSize: 13, color: palette.foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 笔记
// ---------------------------------------------------------------------------

/// 笔记面板：书籍摘要卡 + 四个入口 + 笔记内容。
///
/// [child] 为空时展示微信读书同款空状态。
class SjNotesPanel extends StatelessWidget {
  const SjNotesPanel({
    super.key,
    required this.palette,
    required this.bookTitle,
    this.readingTimeText = '时长<1分钟',
    this.cover,
    this.child,
    this.onAddBookmark,
    this.onAllNotes,
    this.onExportNotes,
    this.onBookDetail,
    this.onSeeAllNotes,
  });

  /// 当前阅读调色板。
  final SjReaderPalette palette;

  /// 书名。
  final String bookTitle;

  /// 阅读时长文案。
  final String readingTimeText;

  /// 封面缩略图。
  final Widget? cover;

  /// 笔记列表（为空显示空状态）。
  final Widget? child;

  /// 添加书签。
  final VoidCallback? onAddBookmark;

  /// 全部笔记。
  final VoidCallback? onAllNotes;

  /// 导出笔记。
  final VoidCallback? onExportNotes;

  /// 书籍详情。
  final VoidCallback? onBookDetail;

  /// 查看我的全部笔记（空状态里的链接）。
  final VoidCallback? onSeeAllNotes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: BorderRadius.circular(SjReaderSize.cardRadius),
          ),
          child: Column(
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          bookTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            color: palette.foreground,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.trending_up_rounded,
                              size: 14,
                              color: palette.faint,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              readingTimeText,
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.faint,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (cover != null) ...[
                    const SizedBox(width: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(width: 46, height: 64, child: cover),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Divider(height: 1, thickness: 1, color: palette.divider),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Expanded(
                    child: SjSheetAction(
                      palette: palette,
                      icon: Icons.bookmark_add_outlined,
                      label: '添加书签',
                      onTap: onAddBookmark,
                    ),
                  ),
                  Expanded(
                    child: SjSheetAction(
                      palette: palette,
                      icon: Icons.sticky_note_2_outlined,
                      label: '全部笔记',
                      onTap: onAllNotes,
                    ),
                  ),
                  Expanded(
                    child: SjSheetAction(
                      palette: palette,
                      icon: Icons.ios_share_rounded,
                      label: '导出笔记',
                      onTap: onExportNotes,
                    ),
                  ),
                  Expanded(
                    child: SjSheetAction(
                      palette: palette,
                      icon: Icons.info_outline_rounded,
                      label: '书籍详情',
                      onTap: onBookDetail,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: child ??
              Container(
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  borderRadius: BorderRadius.circular(SjReaderSize.cardRadius),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '你可以在这里记录本书的',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: palette.subForeground,
                        ),
                      ),
                      Text(
                        '想法、划线、书签',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: palette.subForeground,
                        ),
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: onSeeAllNotes,
                        child: Text(
                          '查看我的全部笔记',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.6,
                            color: palette.accent,
                            decoration: TextDecoration.underline,
                            decorationColor: palette.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 进度
// ---------------------------------------------------------------------------

/// 进度面板：三项统计 + 进度滑块 + 两个动作。
class SjProgressPanel extends StatelessWidget {
  const SjProgressPanel({
    super.key,
    required this.palette,
    required this.percent,
    required this.readingTimeText,
    required this.noteCountText,
    this.onSeek,
    this.onSeekEnd,
    this.primaryLabel = '阅读明细',
    this.onPrimary,
    this.secondaryLabel = '开启自动翻页',
    this.secondaryActive = false,
    this.onSecondary,
  });

  /// 当前阅读调色板。
  final SjReaderPalette palette;

  /// 阅读进度（0–1）。
  final double percent;

  /// 阅读时长文案。
  final String readingTimeText;

  /// 笔记数量文案。
  final String noteCountText;

  /// 拖动进度。
  final ValueChanged<double>? onSeek;

  /// 拖动结束。
  final VoidCallback? onSeekEnd;

  /// 左侧按钮文案（默认「阅读明细」）。
  final String primaryLabel;

  /// 左侧按钮动作。
  final VoidCallback? onPrimary;

  /// 右侧按钮文案（默认「开启自动翻页」）。
  final String secondaryLabel;

  /// 右侧按钮是否处于开启态。
  final bool secondaryActive;

  /// 右侧按钮动作。
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: SjStatBlock(
                palette: palette,
                value: '${(percent * 100).toStringAsFixed(0)}%',
                label: '阅读进度',
              ),
            ),
            Expanded(
              child: SjStatBlock(
                palette: palette,
                value: readingTimeText,
                label: '阅读时长',
              ),
            ),
            Expanded(
              child: SjStatBlock(
                palette: palette,
                value: noteCountText,
                label: '笔记',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: SjKnobSlider(
                palette: palette,
                value: percent.clamp(0.0, 1.0),
                onChanged: onSeek,
                onChangeEnd: onSeekEnd,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: palette.faint,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: SjPillButton(
                palette: palette,
                label: primaryLabel,
                height: 40,
                expand: true,
                onTap: onPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SjPillButton(
                palette: palette,
                label: secondaryLabel,
                height: 40,
                expand: true,
                selected: secondaryActive,
                onTap: onSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 亮度 / 颜色
// ---------------------------------------------------------------------------

/// 背景缩略图。
@immutable
class SjReaderBackground {
  const SjReaderBackground({
    required this.colors,
    this.selected = false,
  });

  /// 渐变两端色（纯色时两点相同）。
  final List<Color> colors;

  /// 是否选中。
  final bool selected;
}

/// 亮度面板：亮度滑块 + 颜色 + 背景。
class SjAppearancePanel extends StatelessWidget {
  const SjAppearancePanel({
    super.key,
    required this.palette,
    required this.brightness,
    required this.papers,
    required this.selectedPaperId,
    this.onBrightness,
    this.onBrightnessEnd,
    this.onPaperSelected,
    this.backgrounds = const <SjReaderBackground>[],
    this.onBackgroundSelected,
    this.onMoreBackgrounds,
  });

  /// 当前阅读调色板。
  final SjReaderPalette palette;

  /// 亮度 0–1。
  final double brightness;

  /// 可选纸张。
  final List<SjReaderPaper> papers;

  /// 当前纸张 id。
  final String selectedPaperId;

  /// 拖动亮度。
  final ValueChanged<double>? onBrightness;

  /// 亮度拖动结束。
  final VoidCallback? onBrightnessEnd;

  /// 选择纸张。
  final ValueChanged<SjReaderPaper>? onPaperSelected;

  /// 背景缩略图。
  final List<SjReaderBackground> backgrounds;

  /// 选择背景。
  final ValueChanged<int>? onBackgroundSelected;

  /// 更多背景（打开背景图选择器）。
  final VoidCallback? onMoreBackgrounds;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SjKnobSlider(
          palette: palette,
          value: brightness.clamp(0.0, 1.0),
          onChanged: onBrightness,
          onChangeEnd: onBrightnessEnd,
          leading: Icon(
            Icons.brightness_low_rounded,
            size: 17,
            color: palette.faint,
          ),
        ),
        const SizedBox(height: 14),
        Text('颜色', style: SjReaderText.sheetLabel(palette.faint)),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            for (final paper in papers)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SjSwatch(
                  palette: palette,
                  color: paper.background,
                  selected: paper.id == selectedPaperId,
                  onTap: () => onPaperSelected?.call(paper),
                  child: paper.isDark
                      ? Icon(
                          Icons.nightlight_round,
                          size: 16,
                          color: paper.foreground,
                        )
                      : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('背景', style: SjReaderText.sheetLabel(palette.faint)),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            for (var i = 0; i < backgrounds.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => onBackgroundSelected?.call(i),
                  child: Container(
                    width: 54,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: backgrounds[i].colors,
                      ),
                      border: Border.all(
                        color: backgrounds[i].selected
                            ? palette.accent
                            : palette.divider,
                        width: backgrounds[i].selected ? 1.6 : 1,
                      ),
                    ),
                  ),
                ),
              ),
            if (onMoreBackgrounds != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: onMoreBackgrounds,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: palette.chip,
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: palette.subForeground,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 字体
// ---------------------------------------------------------------------------

/// 字体面板：字号滑块 + 边距 / 行距分段 + 三个入口。
class SjTypographyPanel extends StatelessWidget {
  const SjTypographyPanel({
    super.key,
    required this.palette,
    required this.fontSize,
    required this.marginIndex,
    required this.lineHeightIndex,
    this.minFontSize = 12,
    this.maxFontSize = 30,
    this.onFontSize,
    this.onFontSizeEnd,
    this.onMargin,
    this.onLineHeight,
    this.onFontFamily,
    this.onIndent,
    this.onPageTurn,
    this.moreLabel = '更多设置',
    this.onMore,
  });

  /// 当前阅读调色板。
  final SjReaderPalette palette;

  /// 当前字号（像素）。
  final double fontSize;

  /// 字号下限。
  final double minFontSize;

  /// 字号上限。
  final double maxFontSize;

  /// 当前边距档位（0 小 / 1 中 / 2 大）。
  final int marginIndex;

  /// 当前行距档位（0 紧 / 1 中 / 2 松）。
  final int lineHeightIndex;

  /// 拖动字号。
  final ValueChanged<double>? onFontSize;

  /// 字号拖动结束。
  final VoidCallback? onFontSizeEnd;

  /// 切换边距。
  final ValueChanged<int>? onMargin;

  /// 切换行距。
  final ValueChanged<int>? onLineHeight;

  /// 字体样式。
  final VoidCallback? onFontFamily;

  /// 首行缩进。
  final VoidCallback? onIndent;

  /// 翻页方式。
  final VoidCallback? onPageTurn;

  /// 额外入口文案（微信读书这里没有，用于进入完整设置）。
  final String moreLabel;

  /// 额外入口。
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final t = ((fontSize - minFontSize) / (maxFontSize - minFontSize))
        .clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              '字体大小',
              style: TextStyle(fontSize: 13, color: palette.foreground),
            ),
            const Spacer(),
            if (onMore != null)
              GestureDetector(
                onTap: onMore,
                child: Row(
                  children: <Widget>[
                    Text(
                      moreLabel,
                      style: TextStyle(fontSize: 11, color: palette.faint),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 15,
                      color: palette.faint,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SjKnobSlider(
          palette: palette,
          value: t,
          onChanged: onFontSize == null
              ? null
              : (double v) =>
                  onFontSize!(minFontSize + v * (maxFontSize - minFontSize)),
          onChangeEnd: onFontSizeEnd,
          leading: Text(
            'A',
            style: TextStyle(fontSize: 13, height: 1, color: palette.faint),
          ),
          trailing: Text(
            'A',
            style: TextStyle(
              fontSize: 19,
              height: 1,
              color: palette.subForeground,
            ),
          ),
          knobLabel: fontSize.round().toString(),
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: SjSegmented(
                palette: palette,
                labels: const <String>['小', '边距', '大'],
                index: marginIndex,
                onChanged: (int i) => onMargin?.call(i),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SjSegmented(
                palette: palette,
                labels: const <String>['紧', '行距', '松'],
                index: lineHeightIndex,
                onChanged: (int i) => onLineHeight?.call(i),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // 窄屏（≤ 340）三个胶囊一行放不下，拆成「两行 + 一行」
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final narrow = constraints.maxWidth < 340;
            final buttons = <Widget>[
              SjPillButton(
                palette: palette,
                label: '字体样式',
                height: 38,
                expand: true,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onFontFamily,
              ),
              SjPillButton(
                palette: palette,
                label: '首行缩进',
                height: 38,
                expand: true,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onIndent,
              ),
              SjPillButton(
                palette: palette,
                label: '仿真翻页',
                height: 38,
                expand: true,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onPageTurn,
              ),
            ];
            if (narrow) {
              return Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(child: buttons[0]),
                      const SizedBox(width: 10),
                      Expanded(child: buttons[1]),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(children: <Widget>[Expanded(child: buttons[2])]),
                ],
              );
            }
            return Row(
              children: <Widget>[
                Expanded(child: buttons[0]),
                const SizedBox(width: 10),
                Expanded(child: buttons[1]),
                const SizedBox(width: 10),
                Expanded(child: buttons[2]),
              ],
            );
          },
        ),
      ],
    );
  }
}
