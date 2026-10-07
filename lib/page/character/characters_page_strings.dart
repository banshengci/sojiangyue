/// 人物 / 关系图谱页面本地字符串。
///
/// 切片阶段为避免改动 16 个 l10n/arb 并重新 `flutter gen-l10n`，
/// 这里先用本地中文常量；正式合并时请把这些 key 迁移到
/// `lib/l10n/app_zh.arb`（及对应其他语言文件）并通过 L10n 访问。
class CharactersPageText {
  const CharactersPageText._();

  static const charactersTitle = '人物';
  static const charactersEmptyHint =
      '还没有人物数据。\n点击下方按钮，让 AI 从全书蒸馏人物、关系与世界观。';
  static const distillButton = '生成人物图谱';
  static const redistillButton = '重新蒸馏';
  static const distillModeTitle = '怎么蒸馏这本书？';
  static const distillIncremental = '增量更新（只跑新增内容）';
  static const distillIncrementalHint = '已蒸馏过的内容会跳过，省钱也快';
  static const distillFull = '全量重跑';
  static const distillFullHint = '整本书重新蒸馏一遍，覆盖现有图谱';
  static const distillFullConfirm = '全量重跑会重新消耗全书 token，确定继续？';
  static const distillIncrementalSwitch = '增量更新';
  static const distillIncrementalSwitchHint = '已蒸馏过的内容跳过，省钱也快（推荐）';
  static const distillMajorOnlySwitch = '只看主要人物';
  static const distillMajorOnlyHint = '只收录重要度 ≥ 50 的角色；次要角色与龙套不入库';
  static const distillStart = '开始蒸馏';
  static const distillHowItWorksTitle = '蒸馏到底是怎么做的';
  static const distillHowItWorks = '· 全书按约 1.2 万字切段，多路并发交给 AI 逐段抽取人物、关系、世界观与时间线\n'
      '· 同一个人物在多段出现会按姓名合并，保留重要度更高的那份（不会重复计数）\n'
      '· 每抽完一批就写库，中途停止也能保留已经抽到的内容\n'
      '· 默认收录所有识别到的人物（含次要角色）；开「只看主要人物」则只留重要度 ≥ 50';
  static String distillSkipped(int n) => '已跳过 $n 段未变内容';
  static const distillAlreadyRunning = '这本书的蒸馏已经在跑了，可在任务中心停止';
  static const distillStopped = '已停止蒸馏';
  static const viewGraph = '关系图谱';
  static const generatingTitle = '正在蒸馏全书…';
  static const generatingHint =
      'AI 正在读取并分析章节，请稍候（大书可能耗时数分钟）。';
  static const needAiConfig = '尚未配置 AI 服务，无法蒸馏。请先在「设置 → AI」中配置。';
  static const unsupportedBook =
      '当前仅支持 TXT 书籍蒸馏；EPUB 章节抽取待接入（见 P0 集成说明）。';
  static const distillFailed = '蒸馏失败：';
  static const done = '完成';
  static const background = '后台运行';
  static const close = '关闭';
  static String charactersCount(int n) => '已识别 $n 位人物';
  static String relationsCount(int n) => '$n 条关系';
  static const importance = '重要度';
  static const identity = '身份';
  static const personality = '性格';
  static const motivation = '动机';
  static const backgroundTitle = '背景';
  static const appearance = '外貌';
  static const firstAppearance = '首次出场';
  static const description = '简介';
  static const aliases = '别名';
  static const relationshipTitle = '人物关系';
  static const worldSettingsTitle = '世界观设定';

  // ---- 世界观 / 时间线页 ----
  static const worldTimelineTitle = '世界观';
  static const tabWorld = '设定';
  static const tabTimeline = '时间线';
  static const noWorld = '暂无世界观设定。';
  static const noTimeline = '暂无时间线事件。';
  static const worldEmptyHint =
      '还没有世界观数据。\n对全书做一次人物蒸馏，AI 会同时抽取势力、地点、功法与时间线。';
  static const worldEmptyAction = '生成人物图谱';
  static String settingsCount(int n) => '$n 条设定';
  static String eventsCount(int n) => '$n 个事件';
  static const unknownChapter = '未标注章节';

  // ---- 角色对话 ----
  static const chatTitle = '与书中人对话';
  static const chatSessionsTitle = '对话';
  static const chatNew = '新对话';
  static const chatInputHint = '说点什么…';
  static const chatSend = '发送';
  static const chatGreeting = '正在等 TA 开口…';
  static const chatThinking = '正在回想…';
  static const chatNoSessions = '还没有对话。\n选一位人物，让 TA 亲自回答你的问题。';
  static const chatPickCharacter = '选择要对话的人物';
  static const chatNoCharacterData =
      '这本书还没有人物数据，请先做一次人物蒸馏。';
  static const chatClearConfirm = '清空这段对话的全部消息？';
  static const chatClear = '清空对话';
  static const chatDeleteSelected = '删除所选';
  static const chatDeleted = '已删除';
  static const chatSelectAll = '全选';
  static const chatCancel = '取消';
  static const chatAiNeeded =
      '尚未配置 AI 服务，无法与角色对话。请到「设置 → AI」中配置。';
  static String chatDeletedCount(int n) => '已删除 $n 段对话';
  static const chatNoRelation = '暂无记录的关系。';
  // ---- 卡库 ----
  static const cardLibraryTitle = '卡库';
  static const selfCardEmptyHint =
      '还没有自设卡。\n记下一句设定、一个场面，或你对某个人物的看法。';
  static const openingEmptyHint =
      '还没有开局模板。\n写一个起始情境，与角色对话时一键带入。';
  static const openingApplied = '已把开局情境带入对话';
  // ---- 人物资料校对 / AI 补全 / 头像 ----
  static const editTitle = '校对资料';
  static const avatarSaved = '头像已更新';
  static const avatarReadFailed = '读不到这张图片，请换一张';
  static const enrichNothingMissing = '各字段都有内容，没有需要补的';
  static const enrichNoResult = '现有资料不足以补全，未作改动';
  static String enrichDone(int n) => '已补全 $n 个字段，确认后再保存';

  // ---- 人物整理 ----
  static const cleanupTitle = '整理人物';
  static const cleanupHint = '勾掉不要的角色，删除时连同关系一起清掉';

  static const noRelation = '暂无记录的关系。';
  static String relationTo(String name) => '→ $name';
  static String relationType(String? t) => t == null || t.isEmpty ? '关联' : t;
}
