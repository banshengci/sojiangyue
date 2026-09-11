import 'package:flutter/material.dart';

import 'sj_icon.dart';
import 'sj_tokens.dart';

/// 底部导航项。
///
/// 品牌图标集覆盖「书库 / 收藏」，其余（搜索 / 我的）使用 Material 线性图标。
@immutable
class SjNavItem {
  const SjNavItem({required this.label, this.brand, this.material})
      : assert(brand != null || material != null,
            '每个导航项至少需要一个图标');

  final String label;
  final SjIconName? brand;
  final IconData? material;

  static const SjNavItem library =
      SjNavItem(label: '书库', brand: SjIconName.bookshelf);
  static const SjNavItem search =
      SjNavItem(label: '搜索', material: Icons.search);
  static const SjNavItem favorites =
      SjNavItem(label: '收藏', brand: SjIconName.bookmark);
  static const SjNavItem mine =
      SjNavItem(label: '我的', material: Icons.person_outline);
}

/// 悬浮式底部导航（圆角胶囊 / 卡片底 / 细描边）。
///
/// 激活项为松绿实底胶囊，图标与文字转为纸白。
class SjBottomNav extends StatelessWidget {
  const SjBottomNav({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onTap,
  });

  final List<SjNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(SjSizes.radiusPill),
        border: Border.all(color: c.cardBorder),
        boxShadow: [
          BoxShadow(
            color: c.ink.withAlpha(18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: _SjNavTab(
                item: items[i],
                selected: i == selectedIndex,
                onTap: () => onTap(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _SjNavTab extends StatelessWidget {
  const _SjNavTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final SjNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final Color fg = selected ? c.onPine : c.inkSoft;
    final Widget icon = item.brand != null
        ? SjIcon(item.brand!, size: 20, color: fg)
        : Icon(item.material, size: 20, color: fg);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SjSizes.radiusPill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? c.pine : Colors.transparent,
          borderRadius: BorderRadius.circular(SjSizes.radiusPill),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
