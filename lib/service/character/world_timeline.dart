import 'package:songjiang_reader/models/character_card.dart';

/// 世界时间线 → system prompt 的一段。
///
/// 时间线本身早就有了：`tb_timeline_events` 表、[TimelineEvent] 模型、
/// `characterDao.getTimeline()`，以及已经接入人物页的展示页
/// （`WorldTimelinePage`），抽取也由蒸馏链路负责。
///
/// 缺的是**把它送进对话**：在此之前对话完全不看时间线，
/// 角色只能凭最近 24 条消息猜处境，一旦对话跨过窗口就会把先后顺序搞混。
/// 这个文件只补这一段渲染，不另起一套数据。
///
/// 没有事件时返回空串——不往 prompt 里塞一个空标题。
String buildTimelineSection(List<TimelineEvent> events) {
  if (events.isEmpty) return '';
  final buf = StringBuffer();
  buf.writeln('## 世界时间线（按先后顺序，供你把握处境，不要逐条复述）');
  var i = 0;
  for (final e in events) {
    i++;
    final parts = <String>[];
    if (e.chapter != null && e.chapter!.trim().isNotEmpty) {
      parts.add('【${e.chapter!.trim()}】');
    }
    parts.add(e.title.trim());
    if (e.timeNote != null && e.timeNote!.trim().isNotEmpty) {
      parts.add('（${e.timeNote!.trim()}）');
    }
    buf.writeln('$i. ${parts.join()}');
  }
  return buf.toString();
}
