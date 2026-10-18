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
  }) : assert(items.length <= 5, '阅读底栏最多 5 项');

  final List<SjReaderToolItem> items;

  /// -1 表示无选中。
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.divider)),
      ),
      padding: EdgeInsets.only(
        top: SjSpace.xxs,
        bottom: SjSpace.xxs + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: _SjToolTab(
                item: items[i],
                selected: i == selectedIndex,
                colors: c,
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
    required this.colors,
    required this.onTap,
  });

  final SjReaderToolItem item;
  final bool selected;
  final SjColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? colors.pine : colors.inkSoft;
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
