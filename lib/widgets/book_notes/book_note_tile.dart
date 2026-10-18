import 'package:songjiang_reader/constants/note_annotations.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/book_note.dart';
import 'package:songjiang_reader/utils/time_to_human.dart';
import 'package:songjiang_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';

/// 笔记类型 → 中文标签。
///
/// 真实类型只有两种（见 `constants/note_annotations.dart` 的 `notesType`）：
/// 划线 / 下划线。「有批注」不是类型，而是 `readerNote` 是否非空，单独用徽标表示。
String noteTypeLabel(String type) => switch (type) {
      'highlight' => '划线',
      'underline' => '下划线',
      _ => '笔记',
    };

class BookNoteTile extends StatelessWidget {
  const BookNoteTile({
    super.key,
    required this.note,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.backgroundColor,
    this.margin = const EdgeInsets.only(bottom: 8),
  });

  final BookNote note;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final Color? backgroundColor;
  final EdgeInsetsGeometry margin;

  IconData _typeIcon() {
    final match = notesType.where((option) => option.type == note.type);
    return match.isNotEmpty ? match.first.icon : Icons.bookmark;
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);

    // 类型色：划线用品牌松绿，下划线用江青文字版（都满足 AA）。
    final typeColor =
        note.type == 'underline' ? c.riverText : c.pine;
    final hasAnnotation =
        note.readerNote != null && note.readerNote!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: FilledContainer(
        color: backgroundColor,
        padding: const EdgeInsets.all(SjSpace.s),
        margin: margin,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 类型标识：色点 + 图标 + 文字（三重编码，不靠颜色单独区分）──
                  Row(
                    children: [
                      _HighlightSwatch(colorHex: note.color, fallback: c.inkSoft),
                      const SizedBox(width: SjSpace.xs),
                      Icon(_typeIcon(), size: 14, color: typeColor),
                      const SizedBox(width: SjSpace.xxs),
                      Text(
                        noteTypeLabel(note.type),
                        style: SjText.caption(typeColor).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hasAnnotation) ...[
                        const SizedBox(width: SjSpace.xs),
                        _AnnotationBadge(color: c.clayText),
                      ],
                    ],
                  ),
                  const SizedBox(height: SjSpace.xxs),
                  Text(
                    note.content,
                    style: SjText.body(c.ink),
                  ),
                  if (hasAnnotation)
                    Padding(
                      padding: const EdgeInsets.only(top: SjSpace.xxs),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            VerticalDivider(
                              thickness: 3,
                              color: c.clay.withAlpha(160),
                            ),
                            const SizedBox(width: SjSpace.xs),
                            Expanded(
                              child: Text(
                                note.readerNote!,
                                style: SjText.meta(c.inkSoft),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: SjSpace.xs),
                  Divider(height: 1, color: c.divider),
                  const SizedBox(height: SjSpace.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          note.chapter,
                          style: SjText.caption(c.inkSoft),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        timeToHuman(note.createTime),
                        style: SjText.caption(c.inkSoft),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// 「有批注」徽标。
class _AnnotationBadge extends StatelessWidget {  const _AnnotationBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(SjSizes.radiusPill),
      ),
      child: Text(
        '批注',
        style: SjText.caption(color).copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 高亮色点：保留用户为该条笔记选的颜色。
///
/// 颜色本身**不再单独承载语义**（类型靠图标+文字），只作为「这是我选的黄/蓝」的辅助记忆。
class _HighlightSwatch extends StatelessWidget {
  const _HighlightSwatch({required this.colorHex, required this.fallback});

  final String colorHex;
  final Color fallback;

  Color get _color {
    final v = int.tryParse(colorHex, radix: 16);
    if (v == null) return fallback;
    return Color(0xFF000000 | v);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: _color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
      ),
    );
  }
}