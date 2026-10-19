// lib/design/songjiang/reader/sj_style_panel.dart
//
// 完整排版面板（阅读页「A / 字体」一级页）。
//
// 版式对齐用户给的参考图：顶部一排小按钮（字重 / 字体 / 缩进 / 简繁 / 边距 / 信息），
// 下面四行「− 滑块 + 数值」（字号 / 字距 / 行距 / 段距），再往下是翻页方式与预设底色。
//
// 数据全部落在 BookStyle + ReadingStylePrefs，改一项立即 apply 到 WebView，
// 不经过上层 rebuild——拖动滑块时不会有整页重建的卡顿。

import 'package:flutter/material.dart';

import 'package:songjiang_reader/config/reading_style_prefs.dart';
import 'package:songjiang_reader/config/reading_ui_prefs.dart';
import 'package:songjiang_reader/config/shared_preference_provider.dart';
import 'package:songjiang_reader/design/songjiang/reader/sj_reader_tokens.dart';
import 'package:songjiang_reader/enums/page_turn.dart';
import 'package:songjiang_reader/enums/reading_info.dart';
import 'package:songjiang_reader/models/book_style.dart';
import 'package:songjiang_reader/models/reading_info.dart';
import 'package:songjiang_reader/page/book_player/epub_player.dart';

/// 排版面板。
class SjStylePanel extends StatefulWidget {
  const SjStylePanel({
    super.key,
    required this.palette,
    required this.epubPlayerKey,
    this.onOpenBgImage,
    this.onOpenFonts,
  });

  final SjReaderPalette palette;
  final GlobalKey<EpubPlayerState> epubPlayerKey;
  final VoidCallback? onOpenBgImage;
  final VoidCallback? onOpenFonts;

  @override
  State<SjStylePanel> createState() => _SjStylePanelState();
}

class _SjStylePanelState extends State<SjStylePanel> {
  late final BookStyle _style = ReadingStylePrefs.bookStyle;

  void _apply() {
    widget.epubPlayerKey.currentState?.changeStyle(_style);
    ReadingStylePrefs.saveBookStyle(_style);
    setState(() {});
  }

  /// 一行「− 滑块 + 数值」。
  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    String Function(double)? format,
  }) {
    final text = (format ?? (v) => v.toStringAsFixed(1))(value);
    return Row(
      children: <Widget>[
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: widget.palette.foreground),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: value <= min ? null : () => onChanged((value - 1).clamp(min, max)),
          icon: const Icon(Icons.remove),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: value >= max ? null : () => onChanged((value + 1).clamp(min, max)),
          icon: const Icon(Icons.add),
        ),
        SizedBox(
          width: 34,
          child: Text(
            text,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 12, color: widget.palette.subForeground),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 34),
            side: BorderSide(color: widget.palette.divider),
            foregroundColor: widget.palette.foreground,
          ),
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
      );

  /// 翻页动画的一档。
  Widget _turnChip(PageTurn turn) {
    final selected = ReadingStylePrefs.pageTurnStyle == turn;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ReadingStylePrefs.pageTurnStyle = turn;
          // 引擎侧要重载分页方式才会换动画；覆盖/仿真还要让 Flutter 侧接管过渡
          widget.epubPlayerKey.currentState?.changeStyle(_style);
          setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? widget.palette.foreground : widget.palette.chip,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            turn.getLabel(context),
            style: TextStyle(
              fontSize: 12,
              color: selected
                  ? widget.palette.background
                  : widget.palette.foreground,
            ),
          ),
        ),
      ),
    );
  }

  /// 页眉 / 页脚配置。
  ///
  /// 之所以做成六格而不是两个开关：有人只要页码，有人要章节名 + 进度，
  /// 一个「显示页脚」的开关满足不了。数据直接写进既有的
  /// `ReadingInfoModel`——阅读页一直用它在画这两条，另起一套会画出两条页眉。
  Future<void> _pickInfo({required bool header}) async {
    if (!mounted) return;
    final info = Prefs().readingInfo;
    final section = header ? info.header : info.footer;

    final picked = await showModalBottomSheet<ReadingInfoSectionModel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _InfoEditor(
        title: header ? '页眉' : '页脚',
        initial: section,
        palette: widget.palette,
      ),
    );
    if (picked == null) return;

    Prefs().readingInfo =
        header ? info.copyWith(header: picked) : info.copyWith(footer: picked);
    // 两条信息变了，正文要让出/收回上下边距，所以排版也得重排一次。
    widget.epubPlayerKey.currentState?.changeReadingInfo();
    widget.epubPlayerKey.currentState?.changeStyle(_style);
    setState(() {});
  }

  /// 正文标题：跟书 / 靠左 / 居中 / 隐藏，以及标题字号。
  Future<void> _pickTitle() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('正文标题'),
              ),
            ),
            for (final entry in const <(String, String)>[
              ('跟书排版', 'inherit'),
              ('靠左', 'left'),
              ('居中', 'center'),
              ('隐藏', 'hide'),
            ])
              ListTile(
                title: Text(entry.$1),
                trailing: ReadingStylePrefs.headingAlign == entry.$2
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, entry.$2),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    ReadingStylePrefs.headingAlign = picked;
    widget.epubPlayerKey.currentState?.changeStyle(_style);
    setState(() {});
  }

  Future<void> _pickWeight() async {
    // 字重：正常 400 / 粗体 700 / 细体 300。
    // 引擎侧只认数值，档位在这里映射。
    const options = <(String, double)>[
      ('正常', 400),
      ('粗体', 700),
      ('细体', 300),
    ];
    final picked = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('文章字重切换'),
              ),
            ),
            for (final (label, value) in options)
              ListTile(
                title: Text(label),
                trailing: _style.fontWeight == value
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    _style.fontWeight = picked;
    _apply();
  }

  void _showInfo() {
    final s = _style;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('当前排版'),
        content: Text(
          '字号 ${s.fontSize.toStringAsFixed(0)}\n'
          '字距 ${s.letterSpacing.toStringAsFixed(1)}\n'
          '行距 ${s.lineHeight.toStringAsFixed(1)}\n'
          '段距 ${s.paragraphSpacing.toStringAsFixed(1)}\n'
          '字重 ${s.fontWeight.toStringAsFixed(0)}\n'
          '边距 ${s.sideMargin.toStringAsFixed(0)}\n'
          '缩进 ${s.indent.toStringAsFixed(0)}',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 顶部小按钮组
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              _chip('字重', _pickWeight),
              _chip('字体', widget.onOpenFonts),
              _chip('缩进', () {
                _style.indent = _style.indent == 0 ? 2 : 0;
                _apply();
              }),
              _chip('边距', () {
                // 4 / 12 / 20 三档循环，与设计稿一致
                const steps = <double>[4, 12, 20];
                final i = steps.indexOf(_style.sideMargin);
                _style.sideMargin = steps[(i + 1) % steps.length];
                _apply();
              }),
              _chip('页眉', () => _pickInfo(header: true)),
              _chip('页脚', () => _pickInfo(header: false)),
              _chip('标题', _pickTitle),
              _chip('背景', widget.onOpenBgImage),
              _chip('信息', _showInfo),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _slider(
          label: '字号',
          value: _style.fontSize,
          min: 12,
          max: 34,
          format: (v) => v.toStringAsFixed(0),
          onChanged: (v) {
            _style.fontSize = v;
            _apply();
          },
        ),
        _slider(
          label: '字距',
          value: _style.letterSpacing,
          min: 0,
          max: 3,
          onChanged: (v) {
            _style.letterSpacing = v;
            _apply();
          },
        ),
        _slider(
          label: '行距',
          value: _style.lineHeight,
          min: 0,
          max: 3,
          onChanged: (v) {
            _style.lineHeight = v;
            _apply();
          },
        ),
        _slider(
          label: '段距',
          value: _style.paragraphSpacing,
          min: 0,
          max: 5,
          onChanged: (v) {
            _style.paragraphSpacing = v;
            _apply();
          },
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            Text(
              '翻页动画',
              style: TextStyle(fontSize: 12, color: palette.subForeground),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 32,
                // 五档放一行会挤，改成可以横向滑的胶囊；选中那档填色。
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: <Widget>[
                    for (final turn in PageTurn.values) _turnChip(turn),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '文字颜色和背景',
            style: TextStyle(fontSize: 12, color: palette.subForeground),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              for (final paper in SjReaderPaper.presets)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () {
                      ReadingUiPrefs.readerBrightness =
                          ReadingUiPrefs.readerBrightness;
                      setState(() {});
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: paper.background,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.divider),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 页眉 / 页脚的编辑器：左中右各选一项，另调字号与上下留白。
///
/// 一次只改一条（页眉或页脚）：两边的字号经常不一样——页眉想低调一点，
/// 页脚得看得清页码。
class _InfoEditor extends StatefulWidget {
  const _InfoEditor({
    required this.title,
    required this.initial,
    required this.palette,
  });

  final String title;
  final ReadingInfoSectionModel initial;
  final SjReaderPalette palette;

  @override
  State<_InfoEditor> createState() => _InfoEditorState();
}

class _InfoEditorState extends State<_InfoEditor> {
  late ReadingInfoSectionModel _section = widget.initial;

  Widget _pickRow(
    String label,
    ReadingInfoEnum value,
    ReadingInfoSectionModel Function(ReadingInfoEnum) apply,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: widget.palette.foreground),
            ),
          ),
          Expanded(
            child: DropdownButton<ReadingInfoEnum>(
              isExpanded: true,
              value: value,
              items: <DropdownMenuItem<ReadingInfoEnum>>[
                for (final kind in ReadingInfoEnum.values)
                  DropdownMenuItem<ReadingInfoEnum>(
                    value: kind,
                    child: Text(
                      kind.getL10n(context),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
              onChanged: (ReadingInfoEnum? picked) {
                if (picked == null) return;
                setState(() => _section = apply(picked));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: widget.palette.foreground),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).round(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            value.toStringAsFixed(0),
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 12, color: widget.palette.subForeground),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _section.hasContent;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  widget.title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _section = _section.copyWith(
                      left: ReadingInfoEnum.none,
                      center: ReadingInfoEnum.none,
                      right: ReadingInfoEnum.none,
                    );
                  }),
                  child: const Text('清空'),
                ),
              ],
            ),
            const SizedBox(height: 2),
            _pickRow('左', _section.left,
                (v) => _section.copyWith(left: v)),
            _pickRow('中', _section.center,
                (v) => _section.copyWith(center: v)),
            _pickRow('右', _section.right,
                (v) => _section.copyWith(right: v)),
            const SizedBox(height: 4),
            _numberRow(
              label: '字号',
              value: _section.fontSize,
              min: 8,
              max: 18,
              onChanged: (v) => setState(() => _section =
                  _section.copyWith(fontSize: v)),
            ),
            _numberRow(
              label: '留白',
              value: _section.verticalMargin,
              min: 0,
              max: 24,
              onChanged: (v) => setState(() => _section =
                  _section.copyWith(verticalMargin: v)),
            ),
            if (!visible)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '左中右都选「无」时，这条既不上屏，也不占正文的边距。',
                  style: TextStyle(
                      fontSize: 12, color: widget.palette.subForeground),
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _section),
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
