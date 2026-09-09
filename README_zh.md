[English](README.md) | **简体中文** | [Türkçe](README_tr.md)

<p align="center">
  <img src="./assets/icon/songjiang-logo.png" alt="SongJiang Reader logo" width="100" />
</p>
<h1 align="center">松江阅 · SongJiang Reader - 让阅读更专注</h1>
<p align="center"><em>基于 <a href="https://github.com/Anxcye/anx-reader">Anxcye/anx-reader</a> 二次开发</em></p>


松江阅，一款为热爱阅读的你精心打造的电子书阅读器。集成多种 AI 能力，支持丰富的电子书格式，让阅读更智能、更专注。现代化界面设计，只为提供纯粹的阅读体验。


![](./docs/images/main.jpg)


| 功能模块 | 详细说明 | 状态 |
| --- | --- | --- |
| 多种格式 | EPUB/MOBI/AZW3/FB2/TXT/PDF 已支持 | ✅ |
| 全平台数据同步 | Android/iOS/macOS/Windows 多端覆盖<br>书籍文件、笔记、阅读进度一站式同步 | ✅ |
| AI 助理 | 按阅读进度与风格整理书架<br>生成思维导图辅助理解<br>AI 词典与即时翻译<br>提供观点分析与内容总结 | ✅ |
| AI 深读 | 读前导读 → 读中词典/翻译 → 读后本章自测与回顾卡<br>思维导图与全文翻译 | ✅ |
| 自定义阅读体验 | 调整字间距、段间距、行间距与边距<br>自定义字体大小、样式与字重<br>配置阅读配色、背景图片<br>设置对齐方式与自定义样式 | ✅ |
| 记录笔记 | 多配色与样式选择<br>按时间、章节排序并可按颜色筛选<br>导出 TXT/Markdown/CSV 等多种格式<br>一键生成美观卡片便于分享 | ✅ |
| 阅读统计 | 记录阅读时长<br>按年/月/周/日维度查看<br>阅读热力图呈现习惯变化 | ✅ |
| 其他 | 听书功能：支持多模型、语速、音色与定时<br>书籍全文翻译：原文、译文对照阅读<br>节省空间：云端上传节省本地存储，随用随下<br>简繁转换：中文简繁体一键转换 | ✅ |
| OPDS 书源 | 支持 OPDS 书源，支持自定义添加 Calibre 等在线书库并下载导入 | ✅ |

## 获取方式
松江阅从源码构建，请参考下方[构建](#构建)章节为你的平台编译。

### 我遇到了问题，怎么办？
查看[故障排除](./docs/troubleshooting.md#简体中文)

### 截图
| ![](./docs/images/zh/wide1.png) | ![](./docs/images/zh/wide2.png) |
| :--------------------------: | :--------------------------: |
| ![](./docs/images/zh/wide3.png) | ![](./docs/images/zh/wide4.png) |
| ![](./docs/images/zh/wide5.png) | ![](./docs/images/zh/wide6.png) |
| ![](./docs/images/zh/wide7.png) | ![](./docs/images/zh/wide8.png) |


| ![](./docs/images/zh/mobile1.png) | ![](./docs/images/zh/mobile2.png) | ![](./docs/images/zh/mobile3.png) |
| :----------------------------: | :----------------------------: | :----------------------------: |
| ![](./docs/images/zh/mobile4.png) | ![](./docs/images/zh/mobile5.png) | ![](./docs/images/zh/mobile6.png) |
| ![](./docs/images/zh/mobile7.png) | ![](./docs/images/zh/mobile8.png) | ![](./docs/images/zh/mobile9.png) |

## 构建
希望从源码构建松江阅？请参考以下步骤：
- 安装 [Flutter](https://flutter.dev)。
- 克隆并进入项目目录。
- 运行 `flutter pub get` 。
- 运行 `flutter gen-l10n` 生成多语言文件。
- 运行 `dart run build_runner build --delete-conflicting-outputs` 生成 Riverpod 代码。
- 运行 `flutter run` 启动应用。

您可能遇到 Flutter 版本不兼容的问题，请参考 [Flutter 文档](https://flutter.dev/docs/get-started/install)。
