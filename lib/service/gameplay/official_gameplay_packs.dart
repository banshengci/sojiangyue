import 'package:flutter/material.dart';
// lib/service/gameplay/official_gameplay_packs.dart
//
// 官方玩法包：把玩法做成**可安装的数据**，而不是只能硬编码在 Dart 里。
//
// 每个包只带一个玩法，方便单独装/单独卸；装上后出现在玩法中心，
// 与内置玩法并列。包本身是纯 JSON（见 GameplayPackManifest），
// 导出成 .sjgame.zip 就能发给别人。
//
// 六个玩法的机制各不相同（不是换皮）：
//   江湖历练 —— 声望与仇怨互为代价：出名会招来更狠的人
//   朝堂权谋 —— 圣眷与把柄反向拉扯：越得宠，把柄越值钱
//   末世求生 —— 物资、感染、同伴信任三线同时收窄，没有全赢的选择
//   修仙渡劫 —— 修为与心魔同步增长：渡劫本质是拿过去换未来
//   校园青春 —— 好感按人分记，风评是集体的，两条线会互相拖累
//   商战 —— 资金与声誉是两本账，赢下对手的代价可能是不体面

import 'package:songjiang_reader/models/gameplay_mode.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_pack_models.dart';

const String _author = '松江阅';
const String _version = '1.0.0';

/// 从玩法模式生成玩法包（一个包一个玩法）。
GameplayPackManifest _pack({
  required String id,
  required String name,
  required String description,
  required List<String> tags,
  required GameplayMode mode,
}) =>
    GameplayPackManifest(
      schemaVersion: '1.0',
      id: id,
      name: name,
      version: _version,
      author: _author,
      description: description,
      packType: GameplayPackType.gameplayMode,
      tags: tags,
      gameplayModesJson: [mode.toJson()],
    );

// ── 1. 江湖历练 ────────────────────────────────────────────
const GameplayMode _jianghu = GameplayMode(
  id: 'jianghu',
  name: '江湖历练',
  icon: Icons.gavel_outlined,
  tag: '武侠',
  summary: '声望与仇怨一起涨：出名的那天，找上门的人也会变强',
  directive: '这是一段江湖。你在江湖上有名号、有旧怨，也有不敢碰的人。'
      '你的言行要符合这个身份：讲规矩、记账、留面子，但该动手时不含糊。'
      '玩家每做一件事，江湖都会记账——扬名会带来敬畏，也会带来挑战者。'
      '不要替玩家出手，也不要替他圆场；他得自己承担后果。',
  sceneHints: [
    '雨夜，一间挂着旧幡的酒肆。门外马嘶，来的人指名要见你。',
    '你押的镖在青石岭被截了。对方留下了一块腰牌，没留活口。',
    '十年一度的武林帖送到门口，落款处是当年逐你出师门的人。',
  ],
  stats: [
    GameplayStatDef(
      key: 'fame',
      name: '声望',
      initial: 10,
      min: 0,
      max: 100,
      isScore: true,
      hint: '当众显露实力、守信、赢下一场硬仗时 +5~15；'
          '失约、以多欺少、被当众折辱时 -5~15。',
    ),
    GameplayStatDef(
      key: 'grudge',
      name: '仇怨',
      initial: 0,
      min: 0,
      max: 100,
      hint: '结下梁子、伤了人命、驳了谁的面子时 +5~20；'
          '赔礼、放人一马、还清旧债时 -5~15。仇怨越高，来的人越狠。',
    ),
  ],
  phases: ['初入江湖', '扬名立万', '结怨', '了断'],
  setupPrompt: '生成一段与玩家有关的江湖旧怨，要能在对话里被一点点揭开。请给出：\n'
      '1. 旧怨是什么：谁、在哪、因为什么（两三句）\n'
      '2. 当年你做了什么、留下了什么破绽\n'
      '3. 三个知情者：各自立场、各自知道哪一部分\n'
      '4. 这份旧怨最坏会以什么方式收场',
  secretLabel: '旧怨真相',
  secretScope: '当年的当事人与知情者（由你依据暗牌确定具体是谁）',
  endingHint: '当旧怨被当面了断（和解、清算或被清算）时，把这一局收尾。',
  judged: true,
  endings: [
    GameplayEnding(
      statKey: 'grudge',
      atLeast: 90,
      text: '仇怨到头，来找你的人不再讲规矩。',
    ),
  ],
  thresholds: [
    GameplayThreshold(
      statKey: 'fame',
      atLeast: 50,
      text: '名号传出去了，连不相干的人都开始拿你说事。',
    ),
    GameplayThreshold(
      statKey: 'grudge',
      atLeast: 60,
      text: '有人在打听你的行踪，而且不止一拨。',
    ),
  ],
);

// ── 2. 朝堂权谋 ────────────────────────────────────────────
const GameplayMode _court = GameplayMode(
  id: 'court-intrigue',
  name: '朝堂权谋',
  icon: Icons.workspace_premium_outlined,
  tag: '权谋',
  summary: '圣眷是护身符，也是把柄的来源：越得宠，摔得越重',
  directive: '这是一座朝堂。皇帝、权臣、言官、外戚各有一本账，你也在其中。'
      '你说话要留三分，表态要留退路，答应的事未必做，拒绝的事未必不做。'
      '每句话都可能被记下来当把柄。不要替玩家谋算，也不要主动点破他的处境。',
  sceneHints: [
    '早朝刚散，御史台的折子已经递到御前，参的是一个不该被参的人。',
    '你在宫门外被人拦住，对方只递了一句话：昨夜有人进了东宫。',
    '一场雨后，城南的粮仓烧了。账面少了三十万石，无人敢问。',
  ],
  stats: [
    GameplayStatDef(
      key: 'favor',
      name: '圣眷',
      initial: 30,
      min: 0,
      max: 100,
      isScore: true,
      hint: '合圣意、办差得力、替君分忧时 +5~15；'
          '触怒、当众驳斥、站错队时 -10~25。',
    ),
    GameplayStatDef(
      key: 'leverage',
      name: '把柄',
      initial: 0,
      min: 0,
      max: 100,
      hint: '玩家露出破绽、被人拿话套住、留下实物把柄时 +5~20；'
          '销毁、封口、反将一军时 -5~15。把柄满了会被人当刀使。',
    ),
    GameplayStatDef(
      key: 'faction',
      name: '党羽',
      initial: 10,
      min: 0,
      max: 100,
      hint: '拉拢、施恩、结盟成功时 +5~15；失势、被弹劾、亲信倒戈时 -10~20。',
    ),
  ],
  phases: ['入朝', '站队', '构陷', '清算'],
  setupPrompt: '生成一份足以动摇朝局的密档，玩家要靠对话一步步摸到它。请给出：\n'
      '1. 密档是什么：谁写的、写的是谁的什么事\n'
      '2. 它现在在哪、经过几个人的手\n'
      '3. 三方势力各自想要它做什么\n'
      '4. 一旦公开会发生什么',
  secretLabel: '密档',
  secretScope: '持有密档的人与其主使',
  endingHint: '当密档公诸于世或被彻底压下时，收尾这一局。',
  judged: true,
  endings: [
    GameplayEnding(
      statKey: 'leverage',
      atLeast: 90,
      text: '把柄攒够了，你成了别人手里的一把刀。',
    ),
    GameplayEnding(
      statKey: 'favor',
      atMost: 0,
      text: '失了圣眷，这一步走塌了。',
    ),
    GameplayEnding(
      statKey: 'favor',
      atLeast: 95,
      win: true,
      text: '圣眷正隆，这一局你站住了。',
    ),
  ],
  thresholds: [
    GameplayThreshold(
      statKey: 'favor',
      atLeast: 60,
      text: '宫里传话的人开始先问你一句了。',
    ),
    GameplayThreshold(
      statKey: 'leverage',
      atLeast: 50,
      text: '有份东西落在了别人手里，你还不知道是谁。',
    ),
  ],
);

// ── 3. 末世求生 ────────────────────────────────────────────
const GameplayMode _wasteland = GameplayMode(
  id: 'wasteland',
  name: '末世求生',
  icon: Icons.forest_outlined,
  tag: '生存',
  summary: '物资、感染、信任三线一起收窄，没有全赢的选择',
  directive: '这是一段末世。秩序已经崩了，资源按天算，人比怪物更难判断。'
      '你说话现实、短、不绕弯，会算代价。遇到危险先评估再开口，'
      '答应帮忙一定附带条件。不要替玩家做决定，也不要给他不存在的安全感。',
  sceneHints: [
    '避难所的水泵坏了。备用水只够三天，而外面在下雨。',
    '你带着半箱药回到据点，发现门是从里面锁上的。',
    '收音机里出现了一段不该出现的广播，念的是你名字。',
  ],
  stats: [
    GameplayStatDef(
      key: 'supply',
      name: '物资',
      initial: 30,
      min: 0,
      max: 100,
      hint: '搜到食物、药品、燃料时 +10~25；消耗、损毁、被抢时 -10~30。'
          '低于 10 时所有人都会开始失控。',
    ),
    GameplayStatDef(
      key: 'infection',
      name: '感染度',
      initial: 0,
      min: 0,
      max: 100,
      hint: '接触污染源、受伤、收留来路不明的人时 +5~20；'
          '隔离、消毒、放弃某些东西时 -5~15。到 100 就是结局。',
    ),
    GameplayStatDef(
      key: 'trust',
      name: '信任',
      initial: 50,
      min: 0,
      max: 100,
      perMember: true,
      hint: '说到做到、分物资时公平时 +5~15；隐瞒、独断、牺牲别人时 -10~25。'
          '按人分别记：每个人对你的态度不一样。',
    ),
  ],
  phases: ['爆发', '撤离', '据点', '抉择'],
  endingHint: '当据点守住或被放弃、感染度到顶、或同伴全部离散时，收尾这一局。',
  judged: true,
  endings: [
    GameplayEnding(
      statKey: 'infection',
      atLeast: 100,
      text: '感染到顶，你不再站在"人"这一边。',
    ),
    GameplayEnding(
      statKey: 'supply',
      atMost: 0,
      text: '物资见底，据点守不住了。',
    ),
    GameplayEnding(
      statKey: 'supply',
      atLeast: 95,
      win: true,
      text: '撑到了救援来，据点算是守住了。',
    ),
  ],
  thresholds: [
    GameplayThreshold(
      statKey: 'supply',
      atMost: 10,
      text: '水只够一天了，得有人出去一趟。',
    ),
    GameplayThreshold(
      statKey: 'trust',
      atMost: 25,
      text: '没人再跟你对眼神，话都只说半句。',
    ),
  ],
);

// ── 4. 修仙渡劫 ────────────────────────────────────────────
const GameplayMode _xianxia = GameplayMode(
  id: 'xianxia-tribulation',
  name: '修仙渡劫',
  icon: Icons.science_outlined,
  tag: '仙侠',
  summary: '修为与心魔同步增长：渡劫本质是拿过去换未来',
  directive: '这是一条修行路。你已过了辟谷，却还没过心魔。'
      '你说话有分寸，讲因果，不轻易许诺；一旦许诺就认。'
      '修为涨得越快，旧事压得越狠——你要让玩家感觉到这份代价。'
      '不要替玩家顿悟，也不要轻易给出修行的答案。',
  sceneHints: [
    '闭关第三年，洞府的禁制忽然自己开了。',
    '师门送来一封信，说你的旧居被人挖开，棺里的人不见了。',
    '天边有雷云聚集，却迟迟不落。这是劫云在等你给个理由。',
  ],
  stats: [
    GameplayStatDef(
      key: 'cultivation',
      name: '修为',
      initial: 20,
      min: 0,
      max: 100,
      isScore: true,
      hint: '悟道、炼丹、破阵、得到机缘时 +5~20；'
          '受重伤、走火入魔、被夺灵气时 -10~25。',
    ),
    GameplayStatDef(
      key: 'demon',
      name: '心魔',
      initial: 10,
      min: 0,
      max: 100,
      hint: '修为每涨都要同步涨心魔（涨幅约为修为的一半）；'
          '直面旧事、认错、舍执念时 -10~20。心魔越高，看到的越不真。',
    ),
  ],
  phases: ['练气', '筑基', '心魔劫', '飞升'],
  setupPrompt: '生成玩家这一世最大的执念（心魔的根）。请给出：\n'
      '1. 执念是什么：一个人、一件事、或一句没说完的话\n'
      '2. 它当年是怎么结下的\n'
      '3. 它以什么形式反复出现（幻象、旧人、熟悉的地方）\n'
      '4. 化解它的唯一办法（必须是有代价的）',
  secretLabel: '你这一世的执念',
  secretScope: '只有你自己知道执念的全貌',
  endingHint: '当心魔被化解或彻底吞没玩家时，收尾这一局。',
  judged: true,
  endings: [
    GameplayEnding(
      statKey: 'demon',
      atLeast: 100,
      text: '心魔吞了你，这一世的修行到此为止。',
    ),
    GameplayEnding(
      statKey: 'cultivation',
      atLeast: 100,
      win: true,
      text: '劫云散了，你飞升了。',
    ),
  ],
  thresholds: [
    GameplayThreshold(
      statKey: 'demon',
      atLeast: 50,
      text: '打坐时有个声音在替你说话，语气和你一模一样。',
    ),
    GameplayThreshold(
      statKey: 'cultivation',
      atLeast: 60,
      text: '经脉通了半截，你能感觉到雷云在头顶聚。',
    ),
  ],
);

// ── 5. 校园青春 ────────────────────────────────────────────
const GameplayMode _campus = GameplayMode(
  id: 'campus-youth',
  name: '校园青春',
  icon: Icons.school_outlined,
  tag: '日常',
  summary: '好感按人分记，风评是集体的：两条线会互相拖累',
  directive: '这是一所中学。你在意成绩，也在意别人怎么看你；'
      '有些话说出口就收不回，有些事装作不知道反而更好。'
      '你说话要有年纪感——不油滑，也不深沉，会小心眼，也会突然讲义气。'
      '不要把玩家当成心理医生，也不要替他说出心里话。',
  sceneHints: [
    '开学第一天，座位表贴在门口，你和最不想同桌的人排在一起。',
    '社团招新，你在两个摊位之间站了很久，谁都没先开口。',
    '月考成绩贴出来，走廊里有人笑，有人没笑。',
  ],
  stats: [
    GameplayStatDef(
      key: 'affection',
      name: '好感',
      initial: 40,
      min: 0,
      max: 100,
      perMember: true,
      isScore: true,
      hint: '一起做事、记住细节、在关键时刻站在对方那边时 +5~15；'
          '失约、说错话、当众让人难堪时 -10~25。',
    ),
    GameplayStatDef(
      key: 'reputation',
      name: '风评',
      initial: 50,
      min: 0,
      max: 100,
      hint: '集体的名声：做好事、被老师表扬时 +3~10；'
          '流言、被误解、在冲突里站错边时 -5~20。风评低会拖累所有好感。',
    ),
  ],
  phases: ['开学', '社团', '误会', '毕业'],
  endingHint: '当误会解开或彻底错过、或到了毕业那天时，收尾这一局。',
  judged: true,
  endings: [
    GameplayEnding(
      statKey: 'affection',
      atLeast: 90,
      win: true,
      text: '误会解开了，你们没有错过。',
    ),
    GameplayEnding(
      statKey: 'affection',
      atMost: 0,
      text: '到最后谁也没先开口，就这样毕业了。',
    ),
  ],
  thresholds: [
    GameplayThreshold(
      statKey: 'affection',
      atLeast: 70,
      text: '对方开始主动找你了，走廊上会等你一起走。',
    ),
    GameplayThreshold(
      statKey: 'reputation',
      atMost: 20,
      text: '走廊里的话头在你进门时断了。',
    ),
  ],
);

// ── 6. 商战 ────────────────────────────────────────────────
const GameplayMode _business = GameplayMode(
  id: 'business-war',
  name: '商战',
  icon: Icons.business_center_outlined,
  tag: '商战',
  summary: '资金与声誉是两本账：赢下对手的代价，可能是不体面',
  directive: '这是一场商战。你在谈生意，也在被人谈。'
      '你说话客气但有底线，会算数字，会给对方留台阶——留台阶是为了以后好见面。'
      '让玩家明白：每一笔便宜背后都有代价，可能是钱，也可能是名声。'
      '不要替玩家谈判，也不要主动给出解决方案。',
  sceneHints: [
    '对手刚拿到一笔融资，第一件事是把你的供应链接了过去。',
    '深夜，一个老客户打来电话，只说了一句：明天别签那份合同。',
    '行业峰会的名单出来了，你的名字被放在了第二页。',
  ],
  stats: [
    GameplayStatDef(
      key: 'capital',
      name: '资金',
      initial: 40,
      min: 0,
      max: 100,
      isScore: true,
      hint: '签约、融资、压价成功时 +10~25；'
          '违约、被围猎、现金流断裂时 -15~30。',
    ),
    GameplayStatDef(
      key: 'reputation',
      name: '声誉',
      initial: 50,
      min: 0,
      max: 100,
      hint: '守约、让利得体、被行业认可时 +5~15；'
          '使阴招、违约、被曝出问题时 -10~25。声誉低时没人再给你台阶。',
    ),
  ],
  phases: ['立项', '融资', '围猎', '上市'],
  endingHint: '当公司上市、被收购、或资金链断裂时，收尾这一局。',
  judged: true,
  endings: [
    GameplayEnding(
      statKey: 'capital',
      atMost: 0,
      text: '资金链断了，这一局到此为止。',
    ),
    GameplayEnding(
      statKey: 'capital',
      atLeast: 95,
      win: true,
      text: '敲钟了，你把它做成了。',
    ),
  ],
  thresholds: [
    GameplayThreshold(
      statKey: 'capital',
      atMost: 20,
      text: '财务把账推过来，只说了句「下个月」。',
    ),
    GameplayThreshold(
      statKey: 'reputation',
      atMost: 25,
      text: '对方开始绕开你谈事了。',
    ),
  ],
);

/// 官方玩法包（每个包一个玩法，可单独安装）。
final List<GameplayPackManifest> kOfficialGameplayPacks = [
  _pack(
    id: 'com.songjiang.play.jianghu',
    name: '江湖历练',
    description: '武侠题材：声望与仇怨互为代价，出名会招来更狠的人。',
    tags: ['武侠', '成长'],
    mode: _jianghu,
  ),
  _pack(
    id: 'com.songjiang.play.court',
    name: '朝堂权谋',
    description: '权谋题材：圣眷与把柄反向拉扯，越得宠摔得越重。',
    tags: ['权谋', '古风'],
    mode: _court,
  ),
  _pack(
    id: 'com.songjiang.play.wasteland',
    name: '末世求生',
    description: '生存题材：物资、感染、信任三线收窄，没有全赢的选择。',
    tags: ['生存', '末世'],
    mode: _wasteland,
  ),
  _pack(
    id: 'com.songjiang.play.xianxia',
    name: '修仙渡劫',
    description: '仙侠题材：修为与心魔同步增长，渡劫是拿过去换未来。',
    tags: ['仙侠', '成长'],
    mode: _xianxia,
  ),
  _pack(
    id: 'com.songjiang.play.campus',
    name: '校园青春',
    description: '日常题材：好感按人分记、风评是集体的，两条线互相拖累。',
    tags: ['日常', '群像'],
    mode: _campus,
  ),
  _pack(
    id: 'com.songjiang.play.business',
    name: '商战',
    description: '商战题材：资金与声誉是两本账，赢的代价可能是不体面。',
    tags: ['商战', '现代'],
    mode: _business,
  ),
];
