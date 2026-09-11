import 'package:flutter/material.dart';

import '../sj_chip.dart';
import '../sj_icon.dart';
import '../sj_list_items.dart';
import '../sj_search_field.dart';
import '../sj_tokens.dart';

/// 「搜索」页视觉（对应画板 07 · 页面一）。
///
/// 结构：标题 + 搜索栏 + 分类筹码 + 最近阅读 + 热门标签。
class SjSearchPage extends StatefulWidget {
  const SjSearchPage({super.key});

  @override
  State<SjSearchPage> createState() => _SjSearchPageState();
}

class _SjSearchPageState extends State<SjSearchPage> {
  int _category = 0;

  static const List<String> _categories = ['全部', '文学', '历史', '诗词'];

  static const List<({String title, String author})> _recents = [
    (title: '长恨歌', author: '白居易'),
    (title: '三体', author: '刘慈欣'),
    (title: '红楼梦', author: '曹雪芹'),
  ];

  static const List<String> _hotTags = ['古典文学', '诗词赏析', '历史传记', '科幻小说'];

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SjSpace.page,
        12,
        SjSpace.page,
        120,
      ),
      children: [
        // 标题 + 更多
        Row(
          children: [
            Expanded(
              child: Text('搜索', style: SjText.pageTitle(c.ink)),
            ),
            Icon(Icons.more_horiz, size: 26, color: c.clay),
          ],
        ),
        const SizedBox(height: SjSpace.l),
        const SjSearchField(),

        // 分类筹码
        const SizedBox(height: SjSpace.l),
        Wrap(
          spacing: SjSpace.m,
          runSpacing: SjSpace.m,
          children: [
            for (var i = 0; i < _categories.length; i++)
              SjChip(
                label: _categories[i],
                selected: i == _category,
                onTap: () => setState(() => _category = i),
              ),
          ],
        ),

        // 最近阅读
        const SizedBox(height: SjSpace.xxl),
        const SjSectionHeader(title: '最近阅读'),
        const SizedBox(height: SjSpace.xs),
        for (final r in _recents) _RecentRow(title: r.title, author: r.author),

        // 热门标签
        const SizedBox(height: SjSpace.xxl),
        const SjSectionHeader(title: '热门标签'),
        const SizedBox(height: SjSpace.m),
        Wrap(
          spacing: SjSpace.m,
          runSpacing: SjSpace.m,
          children: [
            for (final tag in _hotTags) SjTagChip(label: tag),
          ],
        ),
      ],
    );
  }
}

/// 最近阅读行（品牌图标 + 书名 + 作者）。
class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.title, required this.author});

  final String title;
  final String author;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SjIcon(SjIconName.read, size: 18, color: c.inkSoft),
            const SizedBox(width: SjSpace.m),
            Text(title, style: SjText.body(c.ink)),
            const SizedBox(width: SjSpace.s),
            Text('·', style: SjText.meta(c.inkSoft)),
            const SizedBox(width: SjSpace.s),
            Text(author, style: SjText.meta(c.inkSoft)),
          ],
        ),
      ),
    );
  }
}
