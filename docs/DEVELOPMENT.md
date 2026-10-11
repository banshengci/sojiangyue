# 松江阅二开约定

本项目基于 [Anxcye/anx-reader](https://github.com/Anxcye/anx-reader) 二次开发。  
本文约定命名、分层、依赖与生成物，供后续贡献者与自动化代理遵守。

## 品牌与命名

| 类别 | 约定 | 示例 |
|------|------|------|
| 类型 / 静态 API 前缀 | `Sj`（SongJiang） | `SjLog`、`SjPlatform`、`SjButton`、`SjHttpProxyOverrides` |
| 路径 helper | `getSj*` | `getSjTempDir`、`getSjDocumentsPath` |
| 组件文件名 | `sj_*.dart` | `sj_button.dart`、`sj_headless_webview.dart` |
| 上游品牌 | 注释中可写 `anx-reader`，不要写 `Anx` 类型名 | `与上游 anx-reader 的冷灰…` |
| SharedPreferences 键 | **保持与上游一致**（备份兼容），不要改键名 | `themeColor`、`ttsVolume` |

不要引入新的 `Anx*` 标识符。JS 桥协议标记为 `SjUA`（与 `assets/foliate-js` 两侧同步）。

## 分层规则

```
page / widgets  →  providers / service  →  dao
                ↘  config/*_prefs.dart（SharedPreferences 领域层）
```

- **widgets 不直接 import dao**；需要数据时走 `providers/` 或 `service/`。
- **models 不依赖 service**；保持纯数据 / freezed 模型。
- **service 不调 Toast / SmartDialog** 等 UI；错误上抛或回调到 UI 层。
- 配置读写优先走 **领域 Prefs**（`lib/config/*_prefs.dart`），不要新增 `Prefs().xxx` 业务字段。

### 领域 Prefs 模式

新配置请仿照已有实现：

1. 在 `lib/config/` 建 `xxx_prefs.dart`，提供同步 getter/setter（及必要异步方法）。
2. 在 `main()` 的 `Prefs().initPrefs()` **之前**调用 `XxxPrefs.ensureInitialized()`。
3. UI / service 读写领域类，不再往 `Prefs` 单例塞字段。
4. SharedPreferences **键名保持不变**，保证 WebDAV 备份兼容。

已迁出领域：`http_proxy` / `tts` / `theme` / `bgimg` / `developer` / `excerpt_share` / `iap` / `reading_style` / `sync` / `ai` / `bookshelf` / `notes` / `reading_ui` / `translate` / `app_misc`。

`Prefs` 单例现仅保留：初始化、备份/恢复、以及少量遗留（`readingInfo`、按书翻译模式、`statisticsDashboardTiles` 等）。

## 依赖升级

- **禁止**无评估地 `flutter pub upgrade`。
- git 依赖必须在 `pubspec.yaml` 注明「为何保留 fork」，并钉死 `ref`。
- 官方已可用且 API 兼容时，优先迁回 hosted（参考 `flutter_inappwebview`、`contentsize_tabbarview`）。
- 改依赖后必须：`flutter pub get` → `flutter analyze` → `flutter test`，并检查 `pubspec.lock` diff。

## 生成物与命令

删除后可重新生成的文件（已被 `.gitignore`）：

- `*.g.dart`、`*.freezed.dart`、`lib/gen/`、`lib/l10n/generated/`

标准流程：

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

Windows 构建（本机脚本已去硬编码路径）：

```powershell
$env:FLUTTER_HOME = "D:\flutter_windows_3.35.3-stable\flutter"
.\build_windows.bat
```

## 质量门禁

| 检查 | 标准 |
|------|------|
| `flutter analyze` | **0 error / 0 warning**（允许既有 ~60 条 info） |
| `flutter test` | 全部通过 |
| **分层依赖门禁** | **无新增违规**；环内文件数不得回退（见下节） |
| PR CI | `.github/workflows/pr-check.yml` + `ci.yml` 的 `analyze-and-test` job |

新增 lint 规则前先跑全量 analyze，避免一次引入数百条噪音。

## 分层依赖门禁（layer gate）

上面「分层规则」的 4 条 + 3 条反向依赖规则，由 `tool/layer_gate.py` 强制检查。
它**零依赖**：纯 Python 3 stdlib，不读 `pubspec.yaml`、不跑 `pub get`、不需要 Dart SDK，
因此在本仓库的 git 依赖解析失败时（例如离线环境）仍然可用。

```bash
# 日常（与 CI 一致）。有新增违规 → 退出码 1
python3 tool/layer_gate.py --repo . --baseline tool/layer_gate_baseline.json

# 只看不改：列出全部违规 + SCC 明细
python3 tool/layer_gate.py --repo . --list-all --scc-detail

# 非阻塞（提出建议期用）
python3 tool/layer_gate.py --repo . --baseline tool/layer_gate_baseline.json --warn-only

# 清理完存量违规后收紧基线
python3 tool/layer_gate.py --repo . --baseline tool/layer_gate_baseline.json --update-baseline
```

**棘轮（ratchet）语义**：基线里冻结了存量违规与基线当时的文件清单。

- **违规**：允许存量、**禁止新增**。
- **循环依赖**：判据是「**既有**文件中是否有新的进入环」——
  * 某个**基线时已存在**的文件新进入环 → **回退，失败**；
  * 某个**本次新建**的文件进入环（例如为拆环而新增的接线文件）→ **不算回退**，但会在报告里单独列出供审阅。
  这样既拦住了"把既有代码拖进环"，又不会误杀"新增一个接线文件以打破 2-环"这类合法重构。

规则清单与选型理由见 `tool/layer_gate.py` 文件头。当前基线快照可从
`tool/layer_gate_baseline.json` 的 `scc` 字段读到。

### CI 里的阻塞开关

`.github/workflows/layer-gate.yml` 由**仓库变量** `LAYER_GATE_BLOCKING` 控制，不用改代码：

| 事件 | 行为 |
|---|---|
| `push` 到 `main` | **始终阻塞** |
| `pull_request` | `LAYER_GATE_BLOCKING == 'true'` → 阻塞；否则 **warn-only** |
| 手动 `workflow_dispatch` | 用运行时的 `mode` 选择，**完全自由**（方便单次验证阻塞效果） |

**默认不阻塞是有意的**：存量 38 处违规、315 个环内文件，PR 一上来就阻塞只会逼出"没人敢改代码"
或"往基线塞例外"。观察期建议 2–4 周，或直到"新增违规 = 0"连续若干次成立，
再把 `LAYER_GATE_BLOCKING` 置为 `true`。

### 撞到门禁怎么办

| 情况 | 正确做法 | 不要做 |
|---|---|---|
| 新功能确实需要跨层调用 | 先问"是不是类型放错文件"，把枚举/常量下沉到 `enums/`、`constants/` | 直接往基线里加例外 |
| 要复用 UI 里的类型 | 下沉到 `enums/` 或该类型所属的叶子文件，原文件加 `export` 保持兼容 | 让 `config/` / `models/` 反向 import `widgets/` |
| 想拆「注册表 <-> 实现」的 2-环 | 把注册表**接口/上下文类型**抽到独立文件，实现只依赖该文件；再 `--update-baseline` | 把 DI/repository 依赖塞进 `base_tool.dart` 这类被插件层引用的叶子文件 |
| 存量违规想清理 | 一次清一类（如某个规则、某个源层），清完 `--update-baseline` | 一次性大重构 |
| 确实要长期豁免某个点 | 该规则加进基线并在 PR 说明里写明原因与到期时间 | 静默跳过 CI |

### 常用辅助脚本

```bash
# SCC 拆解归因与分批路线图（只读分析）
python3 tool/analyze_roadmap.py --repo .

# 各批次/候选改动的统一复算（SCC + 2-环 + 进出环文件）
python3 tool/measure_batches.py --baseline <干净树> --case "标签=<树路径>"
```

### 类型搬家的验证

搬运类型（枚举/常量/类）跨文件时，用 `tool/verify_symbol_move.py` 校验：

```bash
python3 tool/verify_symbol_move.py --repo . --manifest tool/moved_symbols.json
```

它检查**两件事**：

1. **阶段 1**：被搬符号的**全部**引用方都能从新位置解析到它；
2. **阶段 2**：**新家文件自己**引用的全部项目类型都能解析到 —— 这一条拦的是
   「把类搬过去了但忘了把 import 一起搬」这个真实踩过的坑
   （新文件零 import 却引用 `WidgetRef` 与 6 个 Repository，必然编译失败）。

**每次做类型搬家都要往 `tool/moved_symbols.json` 追加一条。** 注意 Dart 的
`export` **不会**把名字引入到执行 export 的那个库自身的作用域——若该文件自己也要用
这个类型，必须同时写 `import`。

> 局限：它是文本级静态检查，不替代编译器。不做类型推断、不检查泛型/重载/条件导入，
> 只对「类型级声明名」做匹配（刻意排除枚举值与局部变量，否则假阳性爆炸）。

## 多语言

- 模板：`app_en.arb`；主语言：`app_zh-CN.arb`。
- 新增 UI 字符串必须同时补 **en + zh-CN**；有精力再补 `zh-TW`。
- 生成后查看 `docs/untranslated_messages.txt` 确认其他语言缺口（可接受，运行时回退英文）。
- `l10n.yaml` 只保留 gen_l10n 标准字段；第三方 IDE 扩展的自定义字段不要写进仓库。

## IAP

内购由 `EnvVar.enableInAppPurchase` 门控，仅商店构建启用。若长期不上架商店，可在确认后整组移除 `in_app_purchase*` / `asn1lib`；当前保留。

## 相关文档

- [构建指南](./BUILD.md)
- [部署](./DEPLOY.md)
- [iOS 侧载 / TrollStore（无开发者账号）](./IOS_TROLLSTORE.md)
- [故障排除](./troubleshooting.md)
