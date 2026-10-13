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

### 数据库：日期列可用索引

`tb_reading_time.date` 与 `tb_notes.create_time` 存的是 **`'YYYY-MM-DD'` 字符串**
（写入处一律 `toIso8601String().substring(0, 10)`）。ISO 日期的字典序与时间序一致，
所以**不要**把列包进 `DATE()` 再比较：

```sql
-- ✗ 索引失效：EXPLAIN 显示 SCAN，每行都要算一次 DATE()
WHERE DATE(date) BETWEEN DATE(?) AND DATE(?)
-- ✓ 命中 idx_reading_time_date，且结果与上一行逐行一致
WHERE date BETWEEN ? AND ?
```

热力图 / 周月年趋势 / 连续天数 / 每日目标这些都是高频查询，`tb_reading_time`
与 `tb_notes` 原先完全没有索引。索引由 `dao/database.dart` 的
`_ensureReadStatsIndexes()` 在每次打开数据库时幂等补齐——**刻意不放进迁移 case**，
因为迁移只跑一次，而这样已安装的用户也能拿到索引。

回归测试见 `test/dao/reading_time_index_test.dart`：它既比对新旧写法结果一致，
也用 `EXPLAIN QUERY PLAN` 断言确实走索引（否则改回 `DATE(date)` 仍会「测试通过」，
性能退化无人察觉）。

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
| `dart analyze lib test` | **No issues found**（0 error / 0 warning / 0 info） |
| `flutter test` | 全部通过（当前 233 用例） |
| PR CI | `.github/workflows/pr-check.yml` + `ci.yml` 的 `analyze-and-test` job，用 `--fatal-warnings --fatal-infos` 强制上述标准 |

门禁已收紧到零问题：CI 里任何级别的分析问题都会让 PR 失败。
若要临时放宽，只放宽到 `--no-fatal-infos`，并在 PR 说明原因。

历史上这批 info 里有不少是**真问题而非风格噪音**，值得引以为戒、不要看到 info 就忽略：

- `use_build_context_synchronously`×31：async gap 后使用 `BuildContext`。其中
  `service/book.dart` 与 `utils/check_update.dart` 是 await 之后
  `Navigator.pop()`，页面若已被销毁会**关掉用户当前所在的路由**；
  `context_menu.dart` 则可能把 OverlayEntry 插到已卸载的 element 上。
- `unrelated_type_equality_checks`×1：`graph.nodeCount == 0`，而 graphview 的
  `nodeCount` 是方法（`int nodeCount()`），条件恒为 false，导致关系图为空时
  不显示空态、只看到空白图。

新增 lint 规则前先跑全量 analyze，避免一次引入数百条噪音。

> 本机如何在 agent / 无 cmd.exe 环境下跑构建与测试，见 `.workbuddy/memory/MEMORY.md`：
> 用 `flutter_tools.snapshot` 直调，加 `--no-pub` 绕开 pub 解析。

## 本仓库踩过的坑（改代码前先看）

### 一、异步读-改-写必须串行化

「读共享状态 → 改 → 写回」如果跨越 `await`，并发进入时各自都会基于同一份
旧状态计算，后写的把先写的整体覆盖。工具在 `lib/utils/async_mutex.dart`：

```dart
await mutex.run(() async { /* 读-改-写整体 */ });
```

已踩过：`AiCache.setAiCache` 读整个缓存文件、加一条、写回整个文件，
未串行化时实测**并发写 5 条只剩 1 条**，缓存等于失效。

**但不要一律加锁。** `service/ai/index.dart` 的 `_throttleIfNeeded`
「判断配额 → 追加时间戳」之间**没有 await**，同步段在单线程事件循环下
不会被打断，本来就是竞态安全的。曾误判并给它加锁＋改成「按预期发出时刻记账」，
结果过期条目推迟 60 秒才清理、列表不断增长、请求被误限流。
判断依据是**判断与写入之间有没有 await**，而不是「是不是读-改-写」。

### 二、日期列不要包进 `DATE()`

见下方「数据库：日期列可用索引」。`WHERE DATE(date) BETWEEN ...` 会让索引失效。

### 三、测试的正当性依赖「形状是否忠于被测代码」

这一条比看起来重要。写「修复前会失败、修复后通过」的对照用例时，
如果模拟的形状与被测代码不一致，会得到**两个方向的错误结论**：

- 本仓库实测：模拟 RPM 限流时，第一版把整个临界区放进锁内 await，
  形状错了 → 反向对照「不丢」，差点得出「这里没有竞态」的错误结论；
  第二版把「占配额」放在等待之后 → 正确实现的形状被改坏，反而「通过」了错误版本。

写这类用例前，先把被测函数的 await 位置逐个标出来，照着抄。
另外两条具体忌讳：

- **不要用自增 id 做新旧实现的比对快照**：两组数据分别重灌后 id 必然不同，
  断言会失败在无意义的地方（本仓库连续踩了两次）。
- **探针里不要在循环之间 `clearCache()` 之后又复用同一目录**，
  否则会把「覆盖」误读成「全丢」（曾得出「并发 2 条落盘 0 条」的假数字）。

跑动态分析类探针时也要注意：`dart run` 不能加载 Flutter 库
（`sqflite_common_ffi` 这类纯 Dart 依赖可以，引到 `dao/*` 就会连带 Flutter 而失败）。

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
