import 'package:flutter/material.dart';
import 'package:songjiang_reader/theme/songjiang_icons.dart';
import 'package:songjiang_reader/theme/songjiang_theme.dart';

/// 统一空态：松绿柔光圆盘 + 图标 + 标题 + 可选副标题/动作。
class EmptyStateHint extends StatelessWidget {
  const EmptyStateHint({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.compact = false,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final pine = SongJiangColors.pine;
    final size = compact ? 72.0 : 112.0;
    final iconSize = compact ? 32.0 : 44.0;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: pine.withAlpha(isDark ? 28 : 18),
                border: Border.all(
                  color: pine.withAlpha(isDark ? 55 : 40),
                  width: 1,
                ),
              ),
              child: Icon(
                icon ?? SongJiangIcons.bookOpen,
                size: iconSize,
                color: pine.withAlpha(isDark ? 190 : 200),
              ),
            ),
            SizedBox(height: compact ? 12 : 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 统一加载态：居中进度 + 可选文案。
class AppLoadingHint extends StatelessWidget {
  const AppLoadingHint({
    super.key,
    this.label,
  });

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          if (label != null) ...[
            const SizedBox(height: 12),
            Text(
              label!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
