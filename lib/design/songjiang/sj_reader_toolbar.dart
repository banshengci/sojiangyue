import 'package:flutter/material.dart';

import 'sj_tokens.dart';

/// 阅读页底栏的一项。
@immutable
class SjReaderToolItem {
  const SjReaderToolItem({
    required this.icon,
    required this.label,
    this.badgeCount,
  });

  final IconData icon;
  final String label;

  /// 可选角标（如笔记条数）。
  final int? badgeCount;
}

/// 阅读页底栏（5 项）。
///
/// 设计约束（来自评审）：
///  - **最多 5 项**。v2 原型放了 6 项，超过 iOS（≤5）与 M3（3–5）上限。
///  - 选中态同时用「颜色 + 字重」两种线索，不只靠颜色。
///  - 每项热区 ≥44×44（本组件给到 52 高）。
///
/// 用法：
/// ```dart
/// SjReaderToolbar(
///   items: const [
///     SjReaderToolItem(icon: Icons.toc, label: '目录'),
///     SjReaderToolItem(icon: Icons.edit_note, label: '笔记'),
///     SjReaderToolItem(icon: Icons.headphones, label: '听'),
///     SjReaderToolItem(icon: Icons.auto_awesome, label: '问'),
///     SjReaderToolItem(icon: Icons.text_fields, label: '排版'),
///   ],
///   selectedIndex: 0,
///   onTap: (i) {},
/// )
/// ```
class SjReaderToolbar extends StatelessWidget {
  const SjReaderToolbar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    this.background,
    this.borderColor,
    this.foreground,
    this.accent,
    this.showSafeArea = true,
  }) : assert(items.length <= 5, '阅读底栏最多 5 项');

  final List<SjReaderToolItem> items;

  /// -1 表示无选中。
  final int selectedIndex;
  final ValueChanged<int> onTap;

  /// 以下四个可选：阅读页有自己的阅读配色（用户可换主题/背景图），
  /// 传进来后底栏会跟随阅读配色，而不是用全局 SjColors。
  final Color? background;
  final Color? borderColor;
  final Color? foreground;
  final Color? accent;

  /// 是否自己处理底部安全区（默认 true）。
  final bool showSafeArea;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final bg = background ?? c.card;
    final line = borderColor ?? c.divider;
    final fg = foreground ?? c.inkSoft;
    final on = accent ?? c.pine;
    final bottomInset = showSafeArea ? MediaQuery.of(context).padding.bottom : 0.0;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: line)),
      ),
      padding: EdgeInsets.only(
        top: SjSpace.xxs,
        bottom: SjSpace.xxs + bottomInset,
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: _SjToolTab(
                item: items[i],
                selected: i == selectedIndex,
                foreground: fg,
                accent: on,
                onTap: () => onTap(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _SjToolTab extends StatelessWidget {
  const _SjToolTab({
    required this.item,
    required this.selected,
    required this.foreground,
    required this.accent,
    required this.onTap,
  });

  final SjReaderToolItem item;
  final bool selected;
  final Color foreground;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? accent : foreground;
    return Semantics(
      label: item.label,
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: SjSizes.minTouchTarget + 8,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, size: 20, color: fg),
              const SizedBox(height: 2),
              Text(
                item.label,
                style: SjText.caption(fg).copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
