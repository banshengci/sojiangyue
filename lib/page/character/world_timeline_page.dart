// lib/page/character/world_timeline_page.dart
//
// 世界观设定 + 世界时间线展示页。
//
// 背景：蒸馏链路（CharacterDistillService）会把 AI 抽出的「世界设定」与
// 「时间线事件」分别写入 tb_world_settings / tb_timeline_events，但此前
// 全项目没有任何 UI 消费这两张表——数据存了、用户永远看不到，等于白烧 token。
// 本页把这两份数据呈现出来，补齐蒸馏产出物的「最后一公里」。
//
// 数据只来自本地库，不做任何 AI 调用；未蒸馏时给空态引导回蒸馏入口。

import 'package:flutter/material.dart';

import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/widgets/common/empty_state_hint.dart';

import 'characters_page_strings.dart';

/// 世界观 / 时间线双页签视图。
class WorldTimelinePage extends StatefulWidget {
  const WorldTimelinePage({
    super.key,
    required this.bookId,
    this.bookTitle,
    this.onRequestDistill,
  });

  final int bookId;

  /// 书名，用于标题与空态文案。
  final String? bookTitle;

  /// 空态下「去蒸馏」的回调；为空时隐藏该按钮。
  final VoidCallback? onRequestDistill;

  @override
  State<WorldTimelinePage> createState() => _WorldTimelinePageState();
}

class _WorldTimelinePageState extends State<WorldTimelinePage> {
  List<WorldSetting> _settings = const [];
  List<TimelineEvent> _events = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final settings = await characterDao.getWorldSettings(widget.bookId);
      final events = await characterDao.getTimeline(widget.bookId);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _events = events;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final hasData = _settings.isNotEmpty || _events.isNotEmpty;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.bookTitle != null
              ? '${widget.bookTitle} · ${CharactersPageText.worldTimelineTitle}'
              : CharactersPageText.worldTimelineTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: CharactersPageText.tabWorld),
              Tab(text: CharactersPageText.tabTimeline),
            ],
          ),
        ),
        floatingActionButton: hasData
            ? FloatingActionButton(
                tooltip: '刷新',
                onPressed: _reload,
                child: const Icon(Icons.refresh),
              )
            : null,
        body: _loading
            ? const AppLoadingHint()
            : _error != null
                ? _buildError(c)
                : hasData
                    ? TabBarView(
                        children: [
                          _buildWorldTab(c),
                          _buildTimelineTab(c),
                        ],
                      )
                    : _buildEmpty(c),
      ),
    );
  }

  Widget _buildError(SjColors c) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: c.clay, size: 32),
              const SizedBox(height: 12),
              Text(
                '读取世界观数据失败：$_error',
                textAlign: TextAlign.center,
                style: SjText.meta(c.inkSoft),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );

  Widget _buildEmpty(SjColors c) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: EmptyStateHint(
            icon: Icons.public_outlined,
            title: CharactersPageText.worldTimelineTitle,
            subtitle: CharactersPageText.worldEmptyHint,
            action: widget.onRequestDistill == null
                ? null
                : FilledButton.icon(
                    onPressed: widget.onRequestDistill,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text(CharactersPageText.worldEmptyAction),
                  ),
          ),
        ),
      );

  /// 世界观设定：按 category 分组（势力 / 地点 / 组织 / 概念 / 物品 / 功法）。
  Widget _buildWorldTab(SjColors c) {
    if (_settings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(CharactersPageText.noWorld, style: SjText.meta(c.inkSoft)),
        ),
      );
    }

    // DAO 已按 category ASC, name ASC 排序，这里只做分组，保持原顺序。
    final grouped = <String, List<WorldSetting>>{};
    for (final s in _settings) {
      grouped.putIfAbsent(s.category, () => []).add(s);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            CharactersPageText.settingsCount(_settings.length),
            style: SjText.meta(c.inkSoft),
          ),
        ),
        for (final entry in grouped.entries) ...[
          _buildCategoryHeader(c, entry.key, entry.value.length),
          ...entry.value.map((s) => _buildSettingCard(c, s)),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 64),
      ],
    );
  }

  Widget _buildCategoryHeader(SjColors c, String category, int count) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8, bottom: 6),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: c.pine,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(category, style: SjText.sectionTitle(c.ink)),
          const SizedBox(width: 6),
          Text('$count', style: SjText.meta(c.inkSoft)),
        ],
      ),
    );
  }

  Widget _buildSettingCard(SjColors c, WorldSetting s) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.name, style: SjText.cardTitle(c.ink)),
            if (s.description != null && s.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                s.description!,
                style: SjText.meta(c.inkSoft),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 世界时间线：左侧轴线 + 圆点的竖向时间轴。
  Widget _buildTimelineTab(SjColors c) {
    if (_events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child:
              Text(CharactersPageText.noTimeline, style: SjText.meta(c.inkSoft)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            CharactersPageText.eventsCount(_events.length),
            style: SjText.meta(c.inkSoft),
          ),
        ),
        for (var i = 0; i < _events.length; i++)
          _buildTimelineItem(c, _events[i], isLast: i == _events.length - 1),
        const SizedBox(height: 64),
      ],
    );
  }

  Widget _buildTimelineItem(
    SjColors c,
    TimelineEvent e, {
    required bool isLast,
  }) {
    final label = (e.timeNote != null && e.timeNote!.isNotEmpty)
        ? e.timeNote!
        : (e.chapter ?? '');

    return Stack(
      children: [
        // 贯穿的轴线（最后一项不画到卡片底部之外）
        if (!isLast)
          Positioned(
            left: 15,
            top: 14,
            bottom: 0,
            width: 1,
            child: Container(color: c.divider),
          ),
        // 节点
        Positioned(
          left: 11,
          top: 5,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: c.clay,
              shape: BoxShape.circle,
              border: Border.all(color: c.paper, width: 1.5),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 34, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    label,
                    style: SjText.meta(c.river),
                  ),
                ),
              Text(e.title, style: SjText.cardTitle(c.ink)),
              if (e.description != null && e.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(e.description!, style: SjText.meta(c.inkSoft)),
              ],
              if (e.chapter != null &&
                  e.chapter!.isNotEmpty &&
                  label != e.chapter) ...[
                const SizedBox(height: 4),
                Text(
                  e.chapter!,
                  style: SjText.meta(c.inkSoft),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
