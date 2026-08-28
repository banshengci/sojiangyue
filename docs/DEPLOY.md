# 自有服务部署指南

松江阅把所有可配置远程端点统一到 `lib/config/remote_config.dart`，通过构建时
`--dart-define=KEY=VALUE` 注入。本指南说明：

- 每个变量对应的服务
- 自建 JSON API / 字体市场的格式要求
- 一组常见的部署示例（Cloudflare Pages / GitHub Pages / 自有 VPS）

---

## 1. 构建变量总览

| Dart-Define          | 用途                                          | 未注入时行为                |
|----------------------|-----------------------------------------------|-----------------------------|
| `PROJECT_REPO`       | GitHub 仓库 `owner/repo`                       | 更新检查和项目链接失效      |
| `UPDATE_API_URL`     | 自定义更新检查 API 完整 URL                    | 回退到 GitHub Releases      |
| `UPDATE_DOWNLOAD_URL`| 「前往下载」按钮目标 URL                       | 回退到 `$PROJECT_REPO/releases/latest` |
| `FONT_BASE_URL`      | 字体市场根 URL（含尾斜杠）                     | 字体下载页禁用              |
| `PRIVACY_URL`        | 自有隐私政策 URL                               | 关于页隐藏该项              |
| `TERMS_URL`          | 自有服务条款 URL                               | 关于页隐藏该项              |
| `DOCS_URL`           | 自有文档站根 URL（含尾斜杠）                   | WebDAV 帮助链接隐藏         |
| `TELEGRAM_URL`       | 自有 Telegram 社群链接                         | 关于页隐藏 Telegram 图标    |
| `DONATE_URL`         | 自有捐赠页 URL                                 | 捐赠弹窗按钮无反应          |

所有变量编译期常量化（`String.fromEnvironment`），未配置时为**空字符串**。
对应功能在 UI 上**自动隐藏**——不会展示出"打开 404"的体验。

---

## 2. 默认行为：GitHub Releases

只要设置：

```
--dart-define=PROJECT_REPO=yourname/songjiang_reader
```

应用就启用 GitHub Releases 作为更新源——无需任何后端服务。发布时只需在 GitHub
上为 tag 创建一个 Release（标题写版本号，正文 Markdown），应用会：
- 解析 `tag_name`（如 `v1.2.3`，自动去 `v`）与 `body`（作为更新说明）
- 「前往下载」按钮打开 `$PROJECT_REPO/releases/latest`

---

## 3. 自有更新检查 API（可选）

如需自定义：

```
--dart-define=UPDATE_API_URL=https://your-host/api/info/latest
--dart-define=UPDATE_DOWNLOAD_URL=https://your-host/download
```

API 响应格式（application/json）：

```json
{
  "version": "v1.2.3",
  "body": "# 1.2.3\n\n- 新增 X\n- 修复 Y"
}
```

字段说明：
- `version`：可省略前缀 `v`（如有会自动去除）。比较时按 `.` 切段、按整数逐段比较
- `body`：Markdown，会渲染为更新说明。可省略

部署示例（Cloudflare Pages / 静态托管）：

```bash
# dist/latest.json
cat > dist/latest.json <<'JSON'
{
  "version": "v1.2.3",
  "body": "# 1.2.3\n\n- 新增 X\n- 修复 Y"
}
JSON
# 上传至 https://your-host/api/info/latest
```

---

## 4. 自有字体市场（可选）

```
--dart-define=FONT_BASE_URL=https://fonts.your-host/
```

需要托管以下结构（参考上游 `fonts-manifest.json`）：

```
https://fonts.your-host/
├── fonts-manifest.json           # 字体清单
├── fonts/<id>/<file>.ttf         # 字体文件
└── <id>/preview.png              # 预览图（可选）
```

`fonts-manifest.json` 是 JSON 数组：

```json
[
  {
    "id": "noto-sans-sc",
    "name": "Noto Sans SC",
    "files": ["fonts/noto-sans-sc/Regular.ttf"],
    "size": 4500000,
    "preview": "noto-sans-sc/preview.png",
    "desc": "思源黑体简体",
    "official": "https://example.com/",
    "license": {
      "name": "OFL",
      "url": "https://example.com/license"
    }
  }
]
```

应用会先请求 `fonts-manifest.json`，列出可用字体，然后从
`${FONT_BASE_URL}${files[i]}` 下载每个文件。

未配置 `FONT_BASE_URL` 时，关于 → 字体下载页会显示"未配置"提示。

---

## 5. 完整发布命令示例

### Windows

```bash
flutter build windows --release \
  --dart-define=PROJECT_REPO=yourname/songjiang_reader \
  --dart-define=FONT_BASE_URL=https://fonts.your-host/ \
  --dart-define=PRIVACY_URL=https://your-host/privacy \
  --dart-define=TERMS_URL=https://your-host/terms \
  --dart-define=DOCS_URL=https://docs.your-host/ \
  --dart-define=DONATE_URL=https://your-host/donate
```

### Android

```bash
flutter build appbundle --release \
  --dart-define=PROJECT_REPO=yourname/songjiang_reader \
  --dart-define=PRIVACY_URL=https://your-host/privacy \
  --dart-define=TERMS_URL=https://your-host/terms
```

### iOS / macOS / Linux / Web：同上相同一组 dart-define。

---

## 6. 国内合规提示

- 如需在国内应用商店上架，请将备案号改为自有的（位于
  `lib/widgets/settings/about.dart` 的 `EnvVar.showBeian` 分支，替换
  `'闽ICP备2025091402号-1A'`）。
- 「检查更新」与「GitHub Releases」在中国大陆可能无法访问——国内发布建议用
  自有 `UPDATE_API_URL`（托管在国内 CDN 上），并禁用 GitHub 项目主页链接（留空
  `PROJECT_REPO`，相应 UI 项会自动隐藏）。