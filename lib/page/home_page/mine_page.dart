import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:songjiang_reader/design/songjiang/data/sj_data_providers.dart';
import 'package:songjiang_reader/design/songjiang/data/sj_view_models.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_achievements_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_favorites_page.dart';
import 'package:songjiang_reader/design/songjiang/sj_tap_target.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/page/home_page/statistics_page.dart';
import 'package:songjiang_reader/page/iap_page.dart';
import 'package:songjiang_reader/page/settings_page/more_settings_page.dart';
import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/models/book.dart';
import 'package:songjiang_reader/page/character/character_list_page.dart';
import 'package:songjiang_reader/page/settings_page/subpage/ai_chat_page.dart';
import 'package:songjiang_reader/providers/iap.dart';
import 'package:songjiang_reader/service/iap/iap_service.dart';
import 'package:songjiang_reader/utils/env_var.dart';
import 'package:songjiang_reader/widgets/settings/about.dart';
import 'package:songjiang_reader/widgets/settings/theme_mode.dart';
import 'package:songjiang_reader/widgets/settings/webdav_switch.dart';

/// 「我的」——底栏第四个（也是最后一个）目的地。
///
/// 设计变更（v3）：
///  - 原来「统计」与「设置」各占一个底栏位；现在统计升为本页首屏摘要卡、
///    设置降为右上角齿轮，底栏从 5 项收敛到 4 项。
///  - 高频项（主题）内联在本页，0 跳可改；低频项（外观/朗读/翻译/存储/高级）
///    仍走「设置」。
///  - 所有可点行 ≥52 高，右上角齿轮用 [SjTapTarget] 撑到 44×44。
class MinePage extends ConsumerStatefulWidget {
  const MinePage({super.key, this.controller});

  final ScrollController? controller;

  @override
  ConsumerState<MinePage> createState() => _MinePageState();
}

class _MinePageState extends ConsumerState<MinePage> {
  late final ScrollController _scrollController =
      widget.controller ?? ScrollController();

  void _push(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  /// 选一本书 → 进人物页做蒸馏。
  ///
  /// 蒸馏原先只能从「书籍详情 → 右上角按钮」进，藏得太深；
  /// 这里给一个一步可达的入口，选完书直接落到人物页（蒸馏按钮就在页面上）。
  Future<void> _openDistillPicker() async {
    final books = await bookDao.selectNotDeleteBooks();
    if (!mounted) return;
    if (books.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('书架还是空的，先导入一本书')),
      );
      return;
    }
    final picked = await showModalBottomSheet<Book>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final b in books.take(50))
              ListTile(
                title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: b.author.isEmpty ? null : Text(b.author),
                onTap: () => Navigator.pop(ctx, b),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterListPage(
          bookId: picked.id,
          bookTitle: picked.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final statsAsync = ref.watch(sjStatisticsProvider);
    final profileAsync = ref.watch(sjProfileProvider);

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(
            SjSpace.page,
            0,
            SjSpace.page,
            96,
          ),
          children: [
            _header(c),
            const SizedBox(height: SjSpace.m),
            _profile(c, profileAsync),
            const SizedBox(height: SjSpace.m),
            _statsCard(c, statsAsync, profileAsync),
            const SizedBox(height: SjSpace.s),
            _themeCard(c),
            const SizedBox(height: SjSpace.s),
            _syncCard(c),
            const SizedBox(height: SjSpace.s),
            _entryCard(c),
            if (EnvVar.enableInAppPurchase) ...[
              const SizedBox(height: SjSpace.s),
              _iapCard(c),
            ],
            const SizedBox(height: SjSpace.s),
            const About(),
          ],
        ),
      ),
    );
  }

  // ---------- 顶部：标题 + 设置齿轮 ----------
  Widget _header(SjColors c) {
    return Padding(
      padding: const EdgeInsets.only(top: SjSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Text('我的', style: SjText.pageTitle(c.ink)),
          ),
          SjTapTarget(
            semanticLabel: '设置',
            onTap: () => _push(const SubMoreSettings()),
            child: Icon(Icons.settings_outlined, size: 22, color: c.ink),
          ),
        ],
      ),
    );
  }

  // ---------- 个人资料 ----------
  Widget _profile(SjColors c, AsyncValue<SjProfileData> profileAsync) {
    final profile = profileAsync.maybeWhen(
      data: (d) => d,
      orElse: () => const SjProfileData(booksRead: 0, favorites: 0, notes: 0),
    );
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.pine, shape: BoxShape.circle),
          child: Text(
            '墨',
            style: TextStyle(
              fontFamily: SjText.serif,
              fontSize: SjType.headline,
              fontWeight: FontWeight.w700,
              color: c.onPine,
            ),
          ),
        ),
        const SizedBox(width: SjSpace.s),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('墨客', style: SjText.cardTitle(c.ink)),
            const SizedBox(height: SjSpace.xxs),
            Text(
              '已读 ${profile.booksRead} 本 · 收藏 ${profile.favorites} 本',
              style: SjText.meta(c.inkSoft),
            ),
          ],
        ),
      ],
    );
  }

  // ---------- 统计摘要 ----------
  Widget _statsCard(
    SjColors c,
    AsyncValue<SjStatisticsData> statsAsync,
    AsyncValue<SjProfileData> profileAsync,
  ) {
    final stats = statsAsync.maybeWhen(
      data: (d) => d,
      orElse: () => null,
    );
    final profile = profileAsync.maybeWhen(
      data: (d) => d,
      orElse: () => const SjProfileData(booksRead: 0, favorites: 0, notes: 0),
    );

    return Container(
      padding: const EdgeInsets.all(SjSpace.m),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(SjSizes.radiusCard),
        border: Border.all(color: c.cardBorder),
        boxShadow: SjShadow.card,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _statCell(
                c,
                value: stats?.monthDurationLabel ?? '—',
                label: '本月时长',
                emphasize: true,
              ),
              _divider(c),
              _statCell(
                c,
                value: '${stats?.finishedBooks ?? profile.booksRead}',
                label: '已读',
              ),
              _divider(c),
              _statCell(c, value: '${profile.notes}', label: '标注'),
            ],
          ),
          if (stats != null && stats.weeklySeconds.any((s) => s > 0)) ...[
            const SizedBox(height: SjSpace.m),
            Divider(height: 1, color: c.divider),
            const SizedBox(height: SjSpace.s),
            _weeklyBars(c, stats),
          ],
          const SizedBox(height: SjSpace.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  stats == null ? '暂无阅读记录' : '本周 ${_weekTotalLabel(stats)}',
                  style: SjText.caption(c.inkSoft),
                ),
              ),
              SjTapTarget(
                semanticLabel: '查看完整数据',
                onTap: () => _push(const StatisticPage()),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('完整数据', style: SjText.meta(c.inkSoft)),
                    Icon(Icons.chevron_right, size: 18, color: c.borderStrong),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCell(
    SjColors c, {
    required String value,
    required String label,
    bool emphasize = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: SjText.statNumber(emphasize ? c.pine : c.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: SjSpace.xxs),
          Text(label, style: SjText.caption(c.inkSoft)),
        ],
      ),
    );
  }

  Widget _divider(SjColors c) =>
      Container(width: 1, height: 34, color: c.divider);

  Widget _weeklyBars(SjColors c, SjStatisticsData stats) {
    final values = stats.weeklySeconds;
    final maxV = values.fold<int>(0, (a, b) => a > b ? a : b);
    final peak = values.indexOf(maxV);
    return SizedBox(
      height: 64,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: maxV == 0 ? 0.02 : values[i] / maxV,
                          child: Container(
                            decoration: BoxDecoration(
                              color: i == peak ? c.pine : c.frost,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      SjStatisticsData.weekdays[i],
                      style: SjText.caption(c.inkFaint),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _weekTotalLabel(SjStatisticsData stats) {
    final total = stats.weeklySeconds.fold<int>(0, (a, b) => a + b);
    final minutes = (total / 60).round();
    return '$minutes 分钟';
  }

  // ---------- 主题（高频项内联） ----------
  Widget _themeCard(SjColors c) {
    return _card(
      c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SjSpace.m,
              SjSpace.s,
              SjSpace.m,
              SjSpace.xs,
            ),
            child: Text('主题', style: SjText.meta(c.inkSoft)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SjSpace.s,
              0,
              SjSpace.s,
              SjSpace.s,
            ),
            child: const ChangeThemeMode(),
          ),
        ],
      ),
    );
  }

  // ---------- 同步 ----------
  Widget _syncCard(SjColors c) {
    return _card(
      c,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: webdavSwitch(context, () => setState(() {}), ref),
      ),
    );
  }

  // ---------- 内容入口 ----------
  Widget _entryCard(SjColors c) {
    return _card(
      c,
      child: Column(
        children: [
          _MineRow(
            icon: Icons.workspace_premium_outlined,
            title: '成就徽章',
            onTap: () => _push(const _AchievementsRoute()),
          ),
          _rowDivider(c),
          _MineRow(
            icon: Icons.star_border,
            title: '我的收藏',
            onTap: () => _push(const _FavoritesRoute()),
          ),
          // 原来的「数据面板」入口指向 SjAppGallery —— 那是**设计预览画板**
          // （SjGallery 的注释写明「纯展示」「预览用，非交付页面」，自带一套
          // 底栏 + 我的/收藏/成就/统计），用户点进来会看到"第二套系统"。
          // 统计入口保留在页面顶部的统计卡：「完整数据 ›」直达真正的 StatisticPage。
          // 收藏与成就已在本列表里各有入口，删除此行不丢任何功能。
          if (EnvVar.enableAIFeature) ...[
            _rowDivider(c),
            _MineRow(
              icon: Icons.auto_awesome_outlined,
              title: L10n.of(context).aiChat,
              onTap: () => _push(const AiChatPage()),
            ),
          ],
          _rowDivider(c),
          _MineRow(
            icon: Icons.auto_stories_outlined,
            title: '人物蒸馏',
            subtitle: '选一本书，抽出人物、关系与世界观',
            onTap: _openDistillPicker,
          ),
          _rowDivider(c),
          _MineRow(
            icon: Icons.settings_outlined,
            title: L10n.of(context).settingsMoreSettings,
            onTap: () => _push(const SubMoreSettings()),
          ),
        ],
      ),
    );
  }

  Widget _iapCard(SjColors c) {
    final status = ref.watch(iapProvider).maybeWhen(
          data: (state) => state.status.title(context),
          orElse: () => L10n.of(context).iapStatusUnknown,
        );
    return _card(
      c,
      child: _MineRow(
        icon: Icons.card_giftcard_outlined,
        title: L10n.of(context).iapPageTitle,
        subtitle: status,
        onTap: () => _push(const IAPPage()),
      ),
    );
  }

  Widget _rowDivider(SjColors c) => Divider(height: 1, color: c.divider);

  Widget _card(SjColors c, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(SjSizes.radiusCard),
        border: Border.all(color: c.cardBorder),
        boxShadow: SjShadow.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// 通用行：图标 + 标题（+ 副标题）+ 右箭头。
///
/// 高度不低于 52，满足触控下限。
class _MineRow extends StatelessWidget {
  const _MineRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Semantics(
      button: onTap != null,
      label: title,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SjSpace.m,
              vertical: SjSpace.s,
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: c.inkSoft),
                const SizedBox(width: SjSpace.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(title, style: SjText.body(c.ink)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: SjText.caption(c.inkSoft)),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: c.borderStrong),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 收藏页路由：用真实数据（rating > 0 的书）驱动 [SjFavoritesPage]。
class _FavoritesRoute extends ConsumerWidget {
  const _FavoritesRoute();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: ref.watch(sjFavoritesProvider).maybeWhen(
            data: (books) => SjFavoritesPage(books: books),
            orElse: () => const Center(child: CircularProgressIndicator()),
          ),
    );
  }
}

/// 成就页路由：用真实数据驱动 [SjAchievementsPage]。
class _AchievementsRoute extends ConsumerWidget {
  const _AchievementsRoute();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('成就徽章')),
      body: ref.watch(sjAchievementsProvider).maybeWhen(
            data: (data) => SjAchievementsPage(data: data),
            orElse: () => const Center(child: CircularProgressIndicator()),
          ),
    );
  }
}
