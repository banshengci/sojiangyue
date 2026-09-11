import 'package:flutter/material.dart';

import '../data/sj_view_models.dart';
import '../sj_icon.dart';
import '../sj_list_items.dart';
import '../sj_tokens.dart';

/// 「我的」页视觉（对应画板 07 · 页面三）。
///
/// 真实数据：已读数 / 收藏数 / 笔记数由 [SjProfileData] 传入。
/// 头像与昵称为本地默认值（应用暂无账号体系）。
class SjMinePage extends StatefulWidget {
  const SjMinePage({super.key, required this.profile});

  final SjProfileData profile;

  @override
  State<SjMinePage> createState() => _SjMinePageState();
}

class _SjMinePageState extends State<SjMinePage> {
  bool _darkMode = false;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final profile = widget.profile;

    return ListView(
      padding: const EdgeInsets.fromLTRB(SjSpace.page, 12, SjSpace.page, 120),
      children: [
        // 个人信息
        Row(
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.pine, shape: BoxShape.circle),
              child: Text(
                '墨',
                style: TextStyle(
                  fontFamily: SjText.serif,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: c.onPine,
                ),
              ),
            ),
            const SizedBox(width: SjSpace.l),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '墨客',
                    style: SjText.coverTitle(c.ink).copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(profile.subtitle, style: SjText.meta(c.inkSoft)),
                ],
              ),
            ),
          ],
        ),

        // 数据统计
        const SizedBox(height: SjSpace.xl),
        SjCard(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Row(
            children: [
              Expanded(
                child: SjStatTile(
                  value: '${profile.booksRead}',
                  label: '已读',
                ),
              ),
              _StatDivider(color: c.divider),
              Expanded(
                child: SjStatTile(
                  value: '${profile.favorites}',
                  label: '收藏',
                ),
              ),
              _StatDivider(color: c.divider),
              Expanded(
                child: SjStatTile(value: '${profile.notes}', label: '笔记'),
              ),
            ],
          ),
        ),

        // 功能菜单
        const SizedBox(height: SjSpace.xl),
        SjCard(
          child: Column(
            children: [
              const SjMenuRow(icon: SjIconName.stats, label: '阅读统计'),
              const SjCardDivider(),
              const SjMenuRow(icon: SjIconName.note, label: '我的笔记'),
              const SjCardDivider(),
              const SjMenuRow(icon: SjIconName.sync, label: '离线缓存'),
              const SjCardDivider(),
              SjMenuRow(
                icon: SjIconName.nightMode,
                label: '深色模式',
                trailing: Switch(
                  value: _darkMode,
                  activeThumbColor: c.pine,
                  onChanged: (v) => setState(() => _darkMode = v),
                ),
              ),
              const SjCardDivider(),
              const SjMenuRow(icon: SjIconName.settings, label: '设置'),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 44, color: color);
  }
}
