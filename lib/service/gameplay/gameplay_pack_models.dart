// lib/service/gameplay/gameplay_pack_models.dart
//
// 玩法包数据模型（3.3 玩法包 / 盲盒 / 名场面生态）。
//
// 设计要点（对齐 zaomeng_review_for_songjiang.md §3.3）：
// - 玩法包本质 = 「声明式插件（脚本工具）+ 场景卡 + 挑战规则」的组合，
//   因此直接复用 2.3 插件契约（PluginToolSpec / PluginManifest）与
//   2.4 增强包的 x_songjiang_* 扩展键约定，避免平行造契约。
// - 三类玩法包：reading_script（阅读剧本/闯关）、reading_challenge（读书挑战）、
//   scene_card（名句/名场面分享卡）。
// - scriptTools 以原文 Map 存储，导出/导入零信息损耗，并可在激活时编译为
//   PluginManifest 注入 PluginRegistry（与 2.3 插件系统打通）。
// - fromJson 严格校验 packType 与必需字段，缺字段 / 非法类型立即抛错，
//   配套契约测试（test/contract/gameplay_pack_contract_test.dart）卡门。

import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';

/// 玩法包类型常量。
class GameplayPackType {
  const GameplayPackType._();

  /// 阅读剧本 / 闯关：scriptTools 声明多步提示链，按需触发。
  static const String readingScript = 'reading_script';

  /// 读书挑战：每日目标 + 成就激励。
  static const String readingChallenge = 'reading_challenge';

  /// 名句 / 名场面分享卡。
  static const String sceneCard = 'scene_card';

  /// 全部合法类型（契约边界）。
  static const List<String> values = [
    readingScript,
    readingChallenge,
    sceneCard,
  ];
}

/// 名句 / 名场面分享卡（对应造梦「名场面卡」）。
class SceneCard {
  const SceneCard({
    required this.id,
    required this.bookTitle,
    required this.quote,
    this.chapter,
    this.context,
    this.tags = const [],
    this.theme = 'ink',
    this.createdAt,
  });

  final String id;
  final String bookTitle;
  final String quote;
  final String? chapter;
  final String? context;
  final List<String> tags;

  /// 分享卡配色主题键（如 ink 水墨 / daiblue 黛蓝 / cinnabar 朱砂）。
  final String? theme;
  final String? createdAt;

  factory SceneCard.fromMap(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    if (id == null || id.isEmpty) throw FormatException('名场面卡缺少 id');
    final bookTitle = j['bookTitle'] as String?;
    if (bookTitle == null || bookTitle.isEmpty) {
      throw FormatException('名场面卡缺少 bookTitle');
    }
    final quote = j['quote'] as String?;
    if (quote == null || quote.isEmpty) throw FormatException('名场面卡缺少 quote');
    return SceneCard(
      id: id,
      bookTitle: bookTitle,
      quote: quote,
      chapter: j['chapter'] as String?,
      context: j['context'] as String?,
      tags: (j['tags'] as List? ?? []).map((e) => e as String).toList(),
      theme: j['theme'] as String? ?? 'ink',
      createdAt: j['createdAt'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'bookTitle': bookTitle,
        'quote': quote,
        if (chapter != null) 'chapter': chapter,
        if (context != null) 'context': context,
        'tags': tags,
        if (theme != null) 'theme': theme,
        if (createdAt != null) 'createdAt': createdAt,
      };
}

/// 读书挑战规则（对应造梦「挑战包」）。
class ReadingChallenge {
  const ReadingChallenge({
    required this.id,
    required this.title,
    required this.metric,
    required this.target,
    this.periodDays = 7,
    this.rewardAchievement,
  });

  final String id;
  final String title;

  /// 度量维度：daily_minutes / daily_pages / weekly_books。
  final String metric;

  /// 目标值（按 metric 解释：分钟 / 页 / 本）。
  final int target;

  /// 周期天数（默认 7 天）。
  final int periodDays;

  /// 关联成就 id（挑战达成后解锁，可对接松江阅已有成就体系）。
  final String? rewardAchievement;

  static const List<String> validMetrics = [
    'daily_minutes',
    'daily_pages',
    'weekly_books',
  ];

  factory ReadingChallenge.fromMap(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    if (id == null || id.isEmpty) throw FormatException('挑战缺少 id');
    final title = j['title'] as String?;
    if (title == null || title.isEmpty) throw FormatException('挑战缺少 title');
    final metric = j['metric'] as String?;
    if (metric == null || !validMetrics.contains(metric)) {
      throw FormatException('挑战 metric 非法：$metric');
    }
    final target = j['target'] as int?;
    if (target == null || target <= 0) throw FormatException('挑战 target 非法');
    return ReadingChallenge(
      id: id,
      title: title,
      metric: metric,
      target: target,
      periodDays: j['periodDays'] as int? ?? 7,
      rewardAchievement: j['rewardAchievement'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'metric': metric,
        'target': target,
        'periodDays': periodDays,
        if (rewardAchievement != null) 'rewardAchievement': rewardAchievement,
      };
}

/// 玩法包清单（package_manifest.json 解析 / 生成）。
class GameplayPackManifest {
  const GameplayPackManifest({
    required this.schemaVersion,
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    required this.description,
    required this.packType,
    this.bookScope,
    this.tags = const [],
    this.sceneCards = const [],
    this.challenges = const [],
    this.scriptToolsJson = const [],
    this.minAppVersion,
    this.createdAt,
  });

  final String schemaVersion;
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;

  /// 玩法包类型（必须是 GameplayPackType.values 之一）。
  final String packType;

  /// 适用范围（书名 / 题材），可选。
  final String? bookScope;
  final List<String> tags;
  final List<SceneCard> sceneCards;
  final List<ReadingChallenge> challenges;

  /// 阅读剧本的声明式脚本工具（原文 Map，复用 2.3 PluginToolSpec）。
  final List<Map<String, dynamic>> scriptToolsJson;
  final String? minAppVersion;
  final String? createdAt;

  /// 把 scriptToolsJson 编译为 PluginToolSpec 列表（供 UI / 激活校验）。
  List<PluginToolSpec> get scriptTools =>
      scriptToolsJson.map((e) => PluginToolSpec.fromJson(e)).toList();

  factory GameplayPackManifest.fromJson(Map<String, dynamic> j) {
    final packType = j['packType'] as String?;
    if (packType == null || !GameplayPackType.values.contains(packType)) {
      throw FormatException('不支持的玩法包类型：$packType');
    }
    final id = j['id'] as String?;
    if (id == null || id.isEmpty) throw FormatException('玩法包缺少 id');
    final version = j['version'] as String?;
    if (version == null || version.isEmpty) {
      throw FormatException('玩法包缺少 version');
    }
    return GameplayPackManifest(
      schemaVersion: j['schemaVersion'] as String? ?? '1.0',
      id: id,
      name: j['name'] as String? ?? id,
      version: version,
      author: j['author'] as String? ?? '',
      description: j['description'] as String? ?? '',
      packType: packType,
      bookScope: j['bookScope'] as String?,
      tags: (j['tags'] as List? ?? []).map((e) => e as String).toList(),
      sceneCards: (j['sceneCards'] as List? ?? [])
          .map((e) => SceneCard.fromMap(e as Map<String, dynamic>))
          .toList(),
      challenges: (j['challenges'] as List? ?? [])
          .map((e) => ReadingChallenge.fromMap(e as Map<String, dynamic>))
          .toList(),
      scriptToolsJson: (j['scriptTools'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      minAppVersion: j['x_songjiang_minApp'] as String?,
      createdAt: j['createdAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'packType': packType,
        'id': id,
        'name': name,
        'version': version,
        'author': author,
        'description': description,
        if (bookScope != null) 'bookScope': bookScope,
        'tags': tags,
        'sceneCards': sceneCards.map((e) => e.toMap()).toList(),
        'challenges': challenges.map((e) => e.toMap()).toList(),
        'scriptTools': scriptToolsJson,
        if (minAppVersion != null) 'x_songjiang_minApp': minAppVersion,
        if (createdAt != null) 'createdAt': createdAt,
      };

  /// 把玩法包编译为 PluginManifest，注入 PluginRegistry 即可获得 AI 工具能力
  /// （与 2.3 插件系统打通：阅读剧本的脚本工具 = 一组声明式 llmChain 工具）。
  ///
  /// 脚本工具复用 read.book.text + ai.query 权限（按需可被权限白名单收紧）。
  PluginManifest toPluginManifest() {
    final map = <String, dynamic>{
      'schemaVersion': '1.0',
      'id': id,
      'name': name,
      'version': version,
      'description': description,
      'author': author,
      'permissions': ['read.book.text', 'ai.query'],
      'hooks': <Map<String, dynamic>>[],
      'tools': scriptToolsJson,
    };
    return PluginManifest.fromJson(map);
  }
}
