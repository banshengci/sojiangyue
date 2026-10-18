# 松江阅插件开发指南

> 面向想给松江阅加能力的开发者。读完之后你应该能写出一个能装、能跑、能分享的插件。
>
> 本文只描述**松江阅自己的实现**。文末有一节与造梦（Zaomeng）插件规范的对照，
> 说明两者取向不同以及我们还缺什么——那一节是刻意保留的，不要当成广告。

---

## 0. 一句话模型

松江阅的插件 = **一组元数据 + 若干「工具配方」+ 可选事件钩子**。

工具配方最终变成 AI agent 可调用的工具；钩子决定这些工具在什么时候被触发。
插件里**不能写代码**：没有 Python、没有 JAR、没有 Dart。你只能拼模板、调模型、
读当前阅读上下文。

这与造梦的根本差别在第 7 节，先看你需要知道的东西。

---

## 1. 五分钟写第一个插件

新建目录 `my-polish/`，放一个 `plugin.json`：

```json
{
  "schemaVersion": "1.0",
  "id": "com.example.note-polish",
  "name": "笔记润色",
  "version": "0.1.0",
  "description": "把随手记的零散笔记整理成通顺的段落。",
  "author": "your-name",
  "permissions": ["ai.query"],
  "hooks": [
    { "event": "onSelectText", "tool": "polish_note" }
  ],
  "tools": [
    {
      "id": "polish_note",
      "displayName": "润色笔记",
      "description": "把一段零散笔记整理成通顺段落，保留原意与关键细节。",
      "inputSchema": {
        "type": "object",
        "properties": {
          "text": { "type": "string", "description": "原始笔记" }
        },
        "required": ["text"]
      },
      "behavior": "aiPrompt",
      "prompt": "把下面这段笔记整理成通顺的段落，保留原意与关键细节，不要扩写：\n{{text}}"
    }
  ]
}
```

三步装进去：

1. 打开 **设置 → AI → 插件工坊**，把上面这份 JSON 的字段填进表单
   （工坊就是为了「不手写 JSON」而做的：填元信息 → 勾权限 → 加工具）。
2. 点「安装试用」，插件会立刻注册；第三方插件默认**关闭**，需要手动启用。
3. 阅读时选中一段文字，`onSelectText` 会触发 `polish_note`。

> **关于分发**：现在有三条路。
> ① **本地文件**：设置 → AI → 插件 → 「从文件安装」，直接选 `.plugin.zip` 或 `plugin.json`；
> ② **插件市场**：目录 JSON + SHA256 + Ed25519 签名；
> ③ **随包预置**（`assets` 里的示例插件）。
>
> 本地安装会校验包体（≤10 MB、≤500 文件、解压 ≤100 MB、拒绝路径穿越），
> 并在安装前把权限逐条摆给你确认；装完默认关闭。

## 2. plugin.json 字段

| 字段 | 必填 | 说明 |
|---|---|---|
| `schemaVersion` | 否 | 缺省 `1.0` |
| `id` | **是** | 全局唯一，工具 id 会变成 `<id>.<toolId>` |
| `name` | **是** | 列表里显示的名字 |
| `version` | **是** | 插件版本 |
| `description` | 否 | 一句话说明用途 |
| `author` | 否 | 作者 |
| `permissions` | 按能力 | 见第 4 节。**没声明的能力用不了** |
| `hooks` | 否 | 见第 3 节 |
| `tools` | **是** | 至少一个工具配方 |
| `minAppVersion` | 否 | 低于该版本时拒绝加载 |

---

## 3. 工具配方与事件钩子

### 3.1 三种 behavior

| behavior | 用途 | 需要写 | 执行方式 |
|---|---|---|---|
| `aiPrompt` | 一次模板 → 一次模型调用 | `prompt` | 渲染模板后调模型，结果作为工具返回值 |
| `llmChain` | 多步链，后步引用前步输出 | `steps` | 逐步渲染 → 调模型 → 输出存入变量 |
| `builtin` | 引用已注册的原生工具 | 无需模板 | 直接复用内置能力（第三方插件通常用不到） |

写法上 `ai_prompt` / `llm_chain`（蛇形）与 `aiPrompt` / `llmChain`（驼峰）都认。

### 3.2 模板变量

模板里用 `{{变量名}}`，变量来自**工具入参**（即 `inputSchema.properties` 的键）。

```json
"prompt": "书名：{{book_title}}\n原文：{{text}}\n\n请给出三条候选。"
```

> **注意**：没有内置变量，也没有设置项注入。模型漏传某个参数时，
> 模板里会原样留下 `{{xxx}}`。所以**把必需参数都写进 `required`**。

### 3.3 多步链示例

```json
{
  "id": "two_step_summary",
  "displayName": "两步摘要",
  "description": "先提取要点，再写成段落。",
  "inputSchema": {
    "type": "object",
    "properties": { "content": { "type": "string" } },
    "required": ["content"]
  },
  "behavior": "llmChain",
  "steps": [
    { "prompt": "从下面正文里提取不超过 8 个要点，每行一个：\n{{content}}", "as": "points" },
    { "prompt": "把这些要点写成一段 200 字以内的通顺文字：\n{{points}}", "as": "final" }
  ]
}
```

后一步可以引用前一步的 `as` 名字。

### 3.4 可用事件

| event | 触发时机 |
|---|---|
| `onBookOpen` | 打开一本书 |
| `onBookImport` | 导入一本书（内置的「人物蒸馏」用这个） |
| `onChapterEnter` | 进入某一章 |
| `onSelectText` | 选中文字 |
| `onPageTurn` | 翻页 |
| `onAiQuery` | 发起一次 AI 查询 |

钩子的字段是 `tool`（不是 `toolId`）：

```json
{ "event": "onChapterEnter", "tool": "recap_chapter" }
```

---

## 4. 权限

| 权限 | 含义 |
|---|---|
| `read.book.text` | 读取当前阅读上下文 / 正文 |
| `network.https` | 允许 https 出网（禁明文、禁私有网段） |
| `ai.query` | 调用用户已配置的模型 |
| `write.notes` | 写入笔记 / 批注 |

**未声明即不可用。** 不要为"以后可能用到"多申请——
用户在安装时必须看到并确认这些权限。

---

## 5. 安全模型

| 约束 | 实现 |
|---|---|
| 不执行任意代码 | 只有模板与模型调用，没有脚本入口 |
| 网络受控 | 仅 `https`；拒绝 `localhost`、`0.0.0.0`、回环、RFC1918 私有网段、链路本地（含 IPv6） |
| 分发验签 | 市场安装时校验 **SHA256** 与 **Ed25519 发布者签名**，任一不符即拒绝 |
| 来源校验 | 下载地址非公网 https（或白名单镜像）一律拒绝 |
| 默认关闭 | 第三方插件安装后**保持禁用**，须用户显式启用 |
| 可随时停用 | 在 设置 → AI 里逐个开关、卸载 |

> 已具备：本地安装会校验包体大小（≤10 MB）、条目数（≤500）、
> 解压总量（≤100 MB），并拒绝绝对路径与 `..` 穿越。
> 符号链接检查依赖 ZIP 格式本身不携带该信息，属已知限制。

---

## 6. 打包、安装与调试

- **开发调试**：插件工坊（`设置 → AI → 插件工坊`）可以直接编辑配方、安装试用。
- **导出分享**：工坊里「导出 ZIP」会生成 `<id>.plugin.zip`，内含 `plugin.json`。
- **查看状态**：设置 → AI 的插件列表会显示启用状态与工具数量。

内置插件（`lib/plugin/builtin/`）是**最好的参考**：
摘句卡 / 章节回顾 / 共读提问三个插件都走同一条声明式路径，
结构与第三方插件一模一样，可以直接对照着改。

---

## 6.5 设置、存储与增强器

### 设置（settings）

在 `plugin.json` 里声明，宿主负责渲染与保存，模板用 `{{config.<key>}}` 读取：

```json
"settings": [
  { "key": "tone", "title": "语气", "type": "enum",
    "default": "克制", "options": ["克制", "温柔", "直白"] },
  { "key": "max_points", "title": "要点数量", "type": "integer", "default": 3 },
  { "key": "strict", "title": "严格模式", "type": "boolean", "default": false }
]
```

类型：`boolean` / `integer` / `enum` / `text`（`text` 是造梦没有的，
用来填一个词或一句提示）。

约束：**只能写已声明的键**。插件不能给自己加配置项，
也不能改自己的启用状态——那是用户的决定。

### 私有存储（storage）

按插件隔离的小容量文本区，用来"记住一点东西"。
模板用 `{{storage.<key>}}` 读取（需声明 `storage.read` 权限）。

| 上限 | 值 |
|---|---|
| 单值 | 8 KB |
| 键数量 | 32 |
| 合计 | 64 KB |

键名只能是 `[A-Za-z0-9_.-]`。插件不是数据库——需要存大块内容说明设计错了。

### 生成增强器（enhancers）

```json
"enhancers": [
  { "id": "short-lines", "title": "短句模式",
    "rule": "每名角色每次最多说两句，保留自然停顿。" }
]
```

启用后，这条规则会追加到 AI 对话 system prompt 的末尾。
与钩子的区别：**钩子是"事件 → 跑工具"，增强器是"规则长期生效"**。

用户在「设置 → AI → 插件 → 设置」里逐条开关；禁用插件会立刻失效。
### 规则（rules）

增强器是"一直生效"，规则是**满足条件才发生**：

```json
"rules": [
  {
    "id": "merchant",
    "title": "神秘商人登场",
    "event": "before_generation",
    "match": { "everyTurns": 5, "chancePercent": 30 },
    "actions": [{ "type": "add_instruction", "instruction": "让一名神秘商人自然进入场景。" }]
  },
  {
    "id": "remember-refusal",
    "title": "记录拒绝",
    "event": "after_turn",
    "match": { "keywords": ["拒绝", "不买"] },
    "actions": [{ "type": "increment_state", "key": "refusals", "amount": 1 }]
  }
]
```

* `event`：`before_generation`（可注入指令）/ `after_turn`（可累计状态）
* `match`：`everyTurns` / `chancePercent` / `keywords`，**多个条件取交集**
* `actions`：`add_instruction` / `increment_state`

状态按「插件 × 会话」隔离；**同一回合重试不会重复累计**，
但指令每次都会重新注入（重新生成时仍然需要它）。

规则**默认关闭**，用户要在插件设置页逐条开启。

> 也可以把 `rules` 放在 `execution.rules` 里（与造梦写法一致），两种都认。

---

## 7. 与造梦插件规范的对照

造梦的公开规范（Declarative Plugin API 2）与本项目取向不同，不是简单的新旧关系：

| 维度 | 造梦 | 松江阅 |
|---|---|---|
| 插件进入用户视野的方式 | **聊天输入区的动作菜单**（用户点击触发） | **AI agent 的工具**（模型决定何时调用）+ 事件钩子 |
| 贡献点 | `chatActions` / `generationEnhancers` / `temporaryNpcGenerators` | `tools`（三种 behavior）+ `hooks`（六种事件）+ `enhancers` |
| 操作集 | 9 种（suggest / variants / storage_get / http_get / reply_as_character / mute_character …） | 由 `behavior` + 模板表达；没有具名操作表 |
| 权限 | 10 项，粒度细（如 `chat.cast.write`、`generation.enhance`） | 6 项（读取正文 / https / 调模型 / 写笔记 / 存储读写） |
| 插件设置 | `settings[]`，宿主渲染 boolean / integer / enum | 同有（另有 `text` 型） |
| 插件私有数据区 | `storage.read/write` + `{{storage.x}}` | 同有（单值 8 KB / 32 键 / 合计 64 KB） |
| 注入主对话规则 | `generationEnhancers` + `execution.rules`（按回合/概率/关键词） | 同有：增强器 + 规则引擎 |
| 临时角色生成 | `temporaryNpcGenerators` | **无** |
| API 版本协商 | `apiVersion`，宿主兼容 1/2 | 有 `schemaVersion` / `minAppVersion`，但没有版本分支策略 |
| 包体限制 | ≤10 MiB、≤500 文件、解压 ≤100 MiB、禁路径穿越与符号链接 | 同有（本地安装校验） |
| 分发验签 | 同有 | SHA256 + Ed25519 |

### 结论

- **能力取向不同**：造梦把插件当作"给用户加按钮 + 改对话生成"；
  我们把插件当作"给 agent 加工具"。两者都能扩展，但第三方写的插件**不能直接互换**。
- **已经补上的**：插件设置、私有存储、生成增强器、本地 `.plugin.zip` 安装。
  到此为止，第三方插件可以配置、可以记忆、也可以影响对话的说话方式。
- **仍然缺的**：临时角色生成（`temporaryNpcGenerators`），
  以及"按会话切换增强器"（我们的增强器是全局开关，不是每个会话各一份）。

---

## 8. 发布前检查表

1. `id` 唯一且稳定；升级只改 `version`。
2. `permissions` 与配方实际用到的能力**逐个对齐**，不多申请。
3. `inputSchema.required` 覆盖模板里用到的每个变量。
4. 每个 `hooks[].tool` 都能在 `tools[].id` 里找到。
5. 至少在一台真机上完成：导入 → 启用 → 触发 → 停用 → 卸载。
6. 失败路径可读：模型不可用时工具应返回明确提示，而不是空字符串。
