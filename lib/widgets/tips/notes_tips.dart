import 'package:songjiang_reader/design/songjiang/sj_icon.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:flutter/material.dart';

/// 笔记空态：品牌插画 + 标题 + 副标题。
class NotesTips extends StatelessWidget {
  const NotesTips({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SjIllustrationView(SjIllustration.noNotes, width: 200),
          const SizedBox(height: 28),
          Text(
            L10n.of(context).notesTips_1,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            L10n.of(context).notesTips_2,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}
