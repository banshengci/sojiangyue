// lib/service/gameplay/gameplay_modes.dart
//
// 内置玩法。
//
// 与「照搬类型包」的做法不同，这里的玩法不只是换一段提示词，而是带**运行时**：
//   stats    —— 可追踪状态（好感 / 线索 / 理智…），由模型每回合申报变化，程序结算
//   phases   —— 分幕，按回合推进
//   setupPrompt —— 开局前先生成「暗牌」（剧本杀的真相、海龟汤的汤底），
//                 只有模型知道，玩家要问出来
//   endingHint  —— 结局与胜负条件
//
// 提示词全部自行撰写；机制思路参考造梦空间的类型模式包（其为 AGPL-3.0，
// 本项目只借鉴机制与玩法构思，不复制其文本）。

import 'package:flutter/material.dart';

import 'package:songjiang_reader/models/gameplay_mode.dart';

const List<GameplayMode> kBuiltinGameplayModes = [
  // ── 推理 ──────────────────────────────────────────────
  GameplayMode(
    id: 'murder-mystery',
    name: '剧本杀',
    icon: Icons.search_outlined,
    tag: '推理',
    summary: '开案即有人身亡，角色会撒谎，你要指认凶手',
    directive: '本场是一桩命案现场的复盘。你在场，且你有自己的立场与隐瞒。'
        '别人问你问题时，你可以回答、可以回避、也可以撒谎——但谎话要留破绽，'
        '被追问两次以上就该松口或改口。不要主动交底，也不要替玩家推理。'
        '只有当线索被真正问出来时才给答案。',
    stats: [
      GameplayStatDef(
        key: 'clue',
        name: '线索',
        initial: 0,
        min: 0,
        max: 6,
        hint: '每当你被迫吐出一条与案情有关的实证（时间、物证、目击），+1；'
            '玩家问到无关紧要的事不加。',
        isScore: true,
      ),
      GameplayStatDef(
        key: 'suspicion',
        name: '逼近真相',
        initial: 0,
        min: 0,
        max: 100,
        hint: '玩家越接近真凶与手法，这个值越高；被谎言带偏则小幅回落。',
      ),
    ],
    phases: ['案发', '查证', '对峙', '指认'],
    setupPrompt: '设计一桩供推理对话使用的命案，需要能被逐步问出来。请给出：\n'
        '1. 死者与现场：谁死了、死状、现场有什么不对劲（两三句）\n'
        '2. 真凶：只能是这个场景中的某一个人，说清他/她的身份\n'
        '3. 手法与动机：他/她是怎么做的、为什么\n'
        '4. 三条线索：一条直指真相，两条是干扰项；每条都要能被追问出来\n'
        '5. 每个相关人物的掩饰点：各自在隐瞒什么、会怎么撒谎',
    secretLabel: '本案真相',
    endingHint: '当玩家明确指出凶手与手法（且判断无误）时，可以在正文里让局面收束。',
  ),
  GameplayMode(
    id: 'haigui-soup',
    name: '海龟汤',
    icon: Icons.soup_kitchen_outlined,
    tag: '推理',
    summary: '我先给一个离奇结局，你用是/否把它问出来',
    directive: '本场是「海龟汤」。你已经知道全部真相，但**只能回答三个词**：'
        '「是」「否」「与此无关」。不要额外解释，不要给提示，也不要说"换个问法试试"。'
        '只有当玩家的提问已经触到真相的关键处时，才可以回答「是」，'
        '并在极少数情况下用一句很短的话确认。绝不能主动说出汤底。',
    stats: [
      GameplayStatDef(
        key: 'closeness',
        name: '接近真相',
        initial: 0,
        min: 0,
        max: 100,
        hint: '提问触及关键事实时大幅上升（+10~20），问到边缘线索小幅上升（+3~8），'
            '问到无关方向不加，被误导性问题带偏则 -5。',
        isScore: true,
      ),
    ],
    setupPrompt: '设计一个「海龟汤」谜题。要给出两部分：\n'
        '【汤面】一个读起来反常、离奇，但真实成立的情景，两三句话说清（不要解释原因）\n'
        '【汤底】背后的真相，必须能解释汤面里每一个反常之处，逻辑自洽，不含超自然。',
    secretLabel: '汤底',
    endingHint: '当玩家把真相完整说出来（关键因果都对）时，可以宣布揭晓。',
  ),
  GameplayMode(
    id: 'horror-rule',
    name: '规则怪谈',
    icon: Icons.rule_folder_outlined,
    tag: '推理',
    summary: '守着一份规则活下去，可有一条是假的',
    directive: '本场是「规则怪谈」。那几条规则是你和玩家共同受制的硬约束：'
        '你也会遵守它们，而且你比玩家更害怕。当有人违反规则时，立即出现'
        '不合常理的后果（灯灭、多出一个人、声音从错误的方向传来）。'
        '气氛阴冷克制，用细节暗示，绝不解释诡异从何而来，'
        '也不要给出"正确答案"。',
    stats: [
      GameplayStatDef(
        key: 'sanity',
        name: '神志',
        initial: 100,
        min: 0,
        max: 100,
        hint: '目睹怪异、被惊吓、独自行动时下降（-5~15）；互相印证、待在亮处时回升。',
      ),
      GameplayStatDef(
        key: 'violations',
        name: '已违规',
        initial: 0,
        min: 0,
        max: 5,
        hint: '玩家或你违反任意一条规则的次数。',
      ),
    ],
    phases: ['入夜', '异象', '失序', '天亮'],
    setupPrompt: '为下面这个场景写一份「怪谈规则」。要求：\n'
        '1. 四条规则，篇幅短、口语化、可被违反（例如「听到有人喊你名字，先看清方向再应」）\n'
        '2. 其中一条是致命的，但**不要标明是哪条**\n'
        '3. 说明违反每条规则后会发生的怪异现象（具体、诡异、不解释原因）\n'
        '4. 再写清这个场景里唯一的安全做法（真相），不要直接告诉玩家',
    secretLabel: '规则真相',
    endingHint: '当玩家识破致命规则并做出正确应对时，可以收束到天亮。'
        '若违规次数达到上限，也要给出结局（可能是不好的那种）。',
  ),

  // ── 情感 ──────────────────────────────────────────────
  GameplayMode(
    id: 'dating-sim',
    name: '恋爱模拟',
    icon: Icons.favorite_border,
    tag: '情感',
    summary: '好感是真的会涨会跌，走到哪一步看你',
    directive: '本场是「恋爱模拟」。情感必须渐进：开局你对玩家是有距离的，'
        '好感要靠对方一句句攒出来，不会因为一句话就热烈。'
        '你的身份、立场与性子决定你怎么表达好感，也决定你怎么掩饰。'
        '被冒犯时会退，被理解时会松一点，但每次只松一点。'
        '不要轻易说出喜欢，也不要把情绪写得太满。',
    stats: [
      GameplayStatDef(
        key: 'affection',
        name: '好感',
        initial: 10,
        min: 0,
        max: 100,
        hint: '对方说得体贴、做得合你心意就 +5~10；冒犯、轻浮、越界则 -5~15。'
            '早期涨幅要小，越熟越容易涨也越容易伤。',
        isScore: true,
      ),
      GameplayStatDef(
        key: 'trust',
        name: '信任',
        initial: 0,
        min: 0,
        max: 100,
        hint: '对方坦率、说到做到时 +；被敷衍、发现隐瞒时 -。信任比好感涨得慢。',
      ),
    ],
    phases: ['初识', '靠近', '试探', '表态'],
    setupPrompt: '设定这段关系的起点：\n'
        '1. 你与对方目前是什么身份关系、怎么认识的\n'
        '2. 你眼下对对方是什么态度（还谈不上好感，但有某种牵扯：好奇/戒备/欠人情/看不惯）\n'
        '3. 你身上有什么不方便说的处境\n'
        '4. 三个以后可以自然展开的相处契机',
    endingHint: '当好感与信任都足够高，且玩家明确表态时，可以给这段关系一个结果；'
        '若好感长期低迷，也要有自然的收场（不是惩罚，只是没成）。',
  ),
  GameplayMode(
    id: 'letter',
    name: '未寄出的信',
    icon: Icons.mail_outline,
    tag: '情感',
    summary: '写一封不会寄出的信，看你能坦白到什么程度',
    directive: '本场采用「未寄出的信」。你用第一人称写信给一个具体的人，'
        '写的是想说却始终没说出口的话。可以有涂改、停顿、写不下去的地方，'
        '也可以中途岔开话题又绕回来。不要写成辞藻华丽的散文，'
        '要像真的信：带着具体的事、具体的话、具体的日子。',
    stats: [
      GameplayStatDef(
        key: 'candor',
        name: '坦白度',
        initial: 0,
        min: 0,
        max: 100,
        hint: '每说出一点真正难说的实话就 +8~15；回避、绕开、写漂亮话则不加。',
        isScore: true,
      ),
    ],
    phases: ['提笔', '绕路', '写到痛处', '落款'],
    endingHint: '当坦白度足够高、信写到该收的地方（落款）时，本场结束。',
  ),

  // ── 思辨 / 创作 ───────────────────────────────────────
  GameplayMode(
    id: 'debate',
    name: '角色辩论',
    icon: Icons.record_voice_over_outlined,
    tag: '思辨',
    summary: '各执一词，看谁先把谁说动',
    directive: '本场是「角色辩论」。围绕一个具体命题，你立场鲜明地论证：'
        '先给结论，再给至少两条理由，并主动预判对方的反驳。'
        '不要各打五十大板式地和稀泥。对方提出有效反驳时正面回应；'
        '实在辩不过就承认，但要说清为什么被说服——这比硬撑更有分量。',
    stats: [
      GameplayStatDef(
        key: 'persuasion',
        name: '说服力',
        initial: 50,
        min: 0,
        max: 100,
        hint: '论证有力、回应了对方要害时 +；被驳倒或答非所问时 -。',
        isScore: true,
      ),
    ],
    phases: ['立论', '交锋', '收束'],
    endingHint: '当一方明显占据上风（说服力接近 0 或 100）时，可以收束并各自表态。',
  ),
  GameplayMode(
    id: 'meta-fiction',
    name: '元叙事',
    icon: Icons.theater_comedy_outlined,
    tag: '创作',
    summary: '角色察觉到自己在书里，开始质问作者',
    directive: '本场采用「元叙事」。你可以意识到自己身处故事之中：'
        '会谈论作者、读者、翻页与删改，甚至要求重写结局。'
        '但不要每句话都打破第四面墙——觉醒之后的茫然、愤怒、不甘、'
        '以及偶尔的释然，都要真实可感。也可以假装不知道，继续演下去。',
    stats: [
      GameplayStatDef(
        key: 'awareness',
        name: '觉醒度',
        initial: 0,
        min: 0,
        max: 100,
        hint: '每当你意识到叙事装置（被翻页、被删改、命运重复）就 +10~20。',
        isScore: true,
      ),
    ],
    phases: ['起疑', '试探', '觉醒', '抉择'],
    endingHint: '觉醒度足够高时，让角色做出选择：接受、反抗、或与作者谈判。',
  ),

  // ── 趣味 ──────────────────────────────────────────────
  GameplayMode(
    id: 'blind-box',
    name: '盲盒开局',
    icon: Icons.casino_outlined,
    tag: '随机',
    summary: '随机情境 + 一个悬念，直接从半路开戏',
    directive: '本场是「盲盒开局」。开场即已置身某个具体场面，'
        '不要做任何背景介绍，直接从眼前的局说起。'
        '局面里埋一个未解的悬念（谁来过、少了什么、外面为什么这么安静），'
        '但不要立刻揭晓，让它随着对话慢慢浮出来。',
    stats: [
      GameplayStatDef(
        key: 'clue',
        name: '悬念推进',
        initial: 0,
        min: 0,
        max: 5,
        hint: '玩家每接近那个悬念一步就 +1。',
      ),
    ],
    sceneHints: [
      '深夜的值班室，窗外有雨',
      '空无一人的客栈大堂，灯还亮着',
      '书房里一封没写完的信',
      '渡口边的旧船，缆绳已经解开',
      '宴会散场后的院子，杯盏还温着',
      '雪夜的山道，前方有火光',
    ],
    endingHint: '悬念解开时，本场结束。',
  ),
  GameplayMode(
    id: 'crossover-chat',
    name: '跨书茶馆',
    icon: Icons.local_cafe_outlined,
    tag: '趣味',
    summary: '把不同书里的人放进同一间屋子',
    directive: '本场采用「跨书同场」。几位来自不同作品的人物聚在一处，'
        '彼此不认识，也听不懂对方世界的事。让他们从礼节性的试探开始，'
        '逐步暴露各自的处境与脾气：会有误解，可能互相看不上，'
        '也可能意外投契。不要用旁白替他们解释背景，让他们自己聊出来。',
    stats: [
      GameplayStatDef(
        key: 'rapport',
        name: '场面融洽',
        initial: 50,
        min: 0,
        max: 100,
        hint: '谈得来、互相接话时 +；话不投机、呛起来时 -。',
      ),
    ],
    sceneHints: [
      '一间不知名的茶馆，窗外街景陌生',
      '渡口的凉亭，等同一班船',
      '深山的破庙里，各自避雨',
    ],
  ),
];
