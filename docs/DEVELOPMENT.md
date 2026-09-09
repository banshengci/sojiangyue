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
| PR CI | `.github/workflows/pr-check.yml` + `ci.yml` 的 `analyze-and-test` job |

新增 lint 规则前先跑全量 analyze，避免一次引入数百条噪音。

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
- [故障排除](./troubleshooting.md)
