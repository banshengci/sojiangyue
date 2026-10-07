// lib/service/character/knowledge_prompt.dart
//
// 「原著知识」抽取提示词。
//
// 与人物蒸馏的区别：蒸馏关心「谁是谁、谁跟谁什么关系」，原著知识关心
// 「这本书里有什么可查的事实」——设定、掌故、器物、规则、伏笔等，
// 目标是让读者能按主题检索回原著，而不是复述人物性格。

import 'package:songjiang_reader/config/runtime_config.dart';

/// 抽取知识条目的 system prompt。
///
/// 运行时可热更：远端配置中心下发 `knowledge.systemPrompt` 即覆盖默认
/// （与人物蒸馏的 `distill.systemPrompt` 互不干扰）。
String buildKnowledgeSystemPrompt() {
  final override = RuntimeConfig.instance.getString('knowledge.systemPrompt');
  if (override != null && override.trim().isNotEmpty) return override;

  return '''
你是一位严谨的中文小说校勘者。阅读用户提供的章节文本，抽取其中**可被查阅的事实性知识**。

# 抽取原则
1. 只依据给定文本，不臆造、不外推。
2. 每条知识聚焦一个主题（topic），用 4-15 字概括，便于日后检索。
3. summary 用一到三句话讲清这条知识，写具体信息（人名、地名、名物、数目、规矩），
   不要空泛评价（避免"描写生动""语言优美"这类话）。
4. 优先抽取：设定规则（如某门派的规矩）、名物器物（如某种兵器的来历）、
   典章制度、地理风物、掌故伏笔、关键事件的前因后果。
5. 每条尽量标注 chapter —— 用你看到的那段文本所属的章节标题。
6. 如果这一章确实只有情节推进而无可查阅的事实，返回 {"items":[]}。

# 输出
仅输出一个 JSON 对象（可被 json.loads 解析），不要 Markdown 代码围栏，不要解释：
{
  "items": [ { "topic": "...", "summary": "...", "chapter": "..." } ]
}
'''.trim();
}

/// 用户消息：把切片标题与正文交给模型。
String buildKnowledgeUserPrompt(String chapterTitle, String text) =>
    '章节：$chapterTitle\n\n正文：\n$text';
