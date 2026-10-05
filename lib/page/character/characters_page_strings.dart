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
  static const charactersCount = (int n) => '已识别 $n 位人物';
  static const relationsCount = (int n) => '$n 条关系';
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
  static const noRelation = '暂无记录的关系。';
  static const noWorld = '暂无世界观设定。';
  static const relationTo = (String name) => '→ $name';
  static const relationType = (String? t) => t == null || t.isEmpty ? '关联' : t;
}
