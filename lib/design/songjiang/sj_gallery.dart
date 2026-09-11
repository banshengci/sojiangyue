import 'package:flutter/material.dart';

import 'data/sj_view_models.dart';
import 'pages/sj_achievements_page.dart';
import 'pages/sj_empty_state_page.dart';
import 'pages/sj_favorites_page.dart';
import 'pages/sj_mine_page.dart';
import 'pages/sj_search_page.dart';
import 'pages/sj_statistics_page.dart';
import 'sj_bottom_nav.dart';
import 'sj_list_items.dart';
import 'sj_tokens.dart';

/// 松江阅页面视觉预览容器（纯展示）。
///
/// 数据由 [data] 传入：
///  - 真实数据：用 `sj_app_gallery.dart` 的 `SjAppGallery`（接入 DAO / Provider）；
///  - 独立预览与测试：用 `SjGalleryData.sample`（设计稿夹具）。
class SjGallery extends StatefulWidget {
  const SjGallery({
    super.key,
    required this.data,
    this.onImport,
    this.initialIndex = 0,
  });

  final SjGalleryData data;

  /// 导入入口（书架为空时展示）。
  final VoidCallback? onImport;

  /// 初始展示的页签（0 = 设计页索引）。
  final int initialIndex;

  @override
  State<SjGallery> createState() => _SjGalleryState();
}

class _SjGalleryState extends State<SjGallery> {
  static const List<SjNavItem> _items = [
    SjNavItem.library,
    SjNavItem.search,
    SjNavItem.favorites,
    SjNavItem.mine,
  ];

  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final data = widget.data;

    return Scaffold(
      backgroundColor: c.paper,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          children: [
            _SjDesignIndex(
              data: data,
              onImport: widget.onImport,
              onOpenTab: (i) => setState(() => _index = i),
            ),
            const SjSearchPage(),
            SjFavoritesPage(books: data.favorites),
            SjMinePage(profile: data.profile),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(SjSpace.page, 0, SjSpace.page, 12),
        child: SjBottomNav(
          items: _items,
          selectedIndex: _index,
          onTap: (i) => setState(() => _index = i),
        ),
      ),
    );
  }
}

/// 设计页索引（预览用，非交付页面）。
class _SjDesignIndex extends StatelessWidget {
  const _SjDesignIndex({
    required this.data,
    required this.onOpenTab,
    this.onImport,
  });

  final SjGalleryData data;
  final ValueChanged<int> onOpenTab;
  final VoidCallback? onImport;

  void _push(BuildContext context, String name, Widget body) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DesignPageHost(name: name, body: body),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(SjSpace.page, 12, SjSpace.page, 120),
      children: [
        Text('设计页索引', style: SjText.pageTitle(c.ink)),
        const SizedBox(height: 6),
        Text('松江阅 · 画板 07 / 08 页面', style: SjText.meta(c.inkSoft)),

        const SizedBox(height: SjSpace.xl),
        const SjSectionHeader(title: 'P1 · 核心页面'),
        const SizedBox(height: SjSpace.s),
        SjCard(
          child: Column(
            children: [
              _IndexRow(
                label: '搜索',
                trailing: '静态示例',
                onTap: () => onOpenTab(1),
              ),
              const SjCardDivider(),
              _IndexRow(
                label: '收藏',
                trailing: '${data.favorites.length} 本',
                onTap: () => onOpenTab(2),
              ),
              const SjCardDivider(),
              _IndexRow(label: '我的', onTap: () => onOpenTab(3)),
            ],
          ),
        ),

        const SizedBox(height: SjSpace.xl),
        const SjSectionHeader(title: 'P2 · 数据与成就'),
        const SizedBox(height: SjSpace.s),
        SjCard(
          child: Column(
            children: [
              _IndexRow(
                label: '数据统计',
                trailing: data.statistics.monthDurationLabel,
                onTap: () => _push(
                  context,
                  '数据统计',
                  SjStatisticsPage(data: data.statistics),
                ),
              ),
              const SjCardDivider(),
              _IndexRow(
                label: '成就',
                trailing:
                    '${data.achievements.unlockedCount} / ${data.achievements.total}',
                onTap: () => _push(
                  context,
                  '成就',
                  SjAchievementsPage(data: data.achievements),
                ),
              ),
              const SjCardDivider(),
              _IndexRow(
                label: '空状态 · 书架为空',
                trailing: '当前 ${data.bookCount} 本',
                onTap: () => _push(
                  context,
                  '空状态',
                  SjEmptyStatePage(
                    bookCount: data.bookCount,
                    onImport: onImport,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: SjSpace.xl),
        const SjSectionHeader(title: '数据来源'),
        const SizedBox(height: SjSpace.s),
        SjCard(
          padding: const EdgeInsets.all(20),
          child: Text(
            '· 数据统计：tb_reading_time 逐日汇总 + 连续阅读天数\n'
            '· 成就：由读完本数 / 连续天数 / 藏书数 / 笔记数 / 评分数 / 累计时长判定\n'
            '· 收藏：书架中评分 > 0 的书\n'
            '· 空状态：书架藏书数为 0 时触发\n\n'
            '当前为预览夹具；真实数据版见 sj_app_gallery.dart',
            style: SjText.meta(c.inkSoft).copyWith(height: 1.7),
          ),
        ),
      ],
    );
  }
}

/// 索引行（文字 + 可选备注 + 箭头）。
class _IndexRow extends StatelessWidget {
  const _IndexRow({required this.label, required this.onTap, this.trailing});

  final String label;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: SjText.cardTitle(c.ink).copyWith(fontSize: 16),
              ),
            ),
            if (trailing != null) ...[
              Text(trailing!, style: SjText.meta(c.inkSoft)),
              const SizedBox(width: SjSpace.s),
            ],
            Icon(Icons.chevron_right, size: 20, color: c.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// 预览外壳：细返回条 + 页面本体（非设计的一部分）。
class _DesignPageHost extends StatelessWidget {
  const _DesignPageHost({required this.name, required this.body});

  final String name;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, SjSpace.page, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back, color: c.ink),
                    tooltip: '返回',
                  ),
                  Text(name, style: SjText.meta(c.inkSoft)),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
