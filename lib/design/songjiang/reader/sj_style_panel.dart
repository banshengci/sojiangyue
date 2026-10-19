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
import 'package:songjiang_reader/design/songjiang/reader/sj_reader_controls.dart';
import 'package:songjiang_reader/design/songjiang/reader/sj_reader_tokens.dart';
import 'package:songjiang_reader/models/book_style.dart';
import 'package:songjiang_reader/page/book_player/epub_player.dart';
import 'package:songjiang_reader/enums/page_turn.dart';

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
            const SizedBox(width: 12),
            Expanded(
              child: SjSegmented(
                palette: palette,
                labels: PageTurn.values
                    .map((e) => e.getLabel(context))
                    .toList(growable: false),
                index: PageTurn.values.indexOf(ReadingStylePrefs.pageTurnStyle),
                onChanged: (int index) {
                  ReadingStylePrefs.pageTurnStyle = PageTurn.values[index];
                  // 引擎侧要重载分页方式才会换动画
                  widget.epubPlayerKey.currentState?.changeStyle(_style);
                  setState(() {});
                },
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
