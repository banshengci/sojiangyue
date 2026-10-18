# icons_plus（vendored 说明）

## 为什么要在仓库里放一份

`icons_plus` 上游最新版是 **5.0.0（2023-12-15）**，之后停更。它的实现方式是给每个图标包定义一个
`IconData` 子类：

```dart
class AntDesignIconData extends IconData { ... }
```

从 Flutter 3.44 起，`IconData` 被标记为 `final class`，**不允许在库外继承**，于是这个包直接编译不过：

```
Error: The class 'IconData' can't be extended outside of its library because it's a final class.
```

这会让 `flutter pub get` 之后的任何编译（含 `dart analyze` / `flutter test` / 各平台构建）全部失败。

由于上游不再维护、也没有可用替代版本，选择 vendored 一份等价实现放进仓库，
而不是把 Flutter 永远钉在 3.44 之前（那会连带锁死 Windows 构建：`windows-2019` runner 已被 GitHub 下线）。

## 改了什么

**唯一的改动**：把每个 `XxxIconData(0x...)` 的构造调用**内联成字面量** `const IconData(0x..., fontFamily: ..., fontPackage: 'icons_plus')`，
并删除那些继承 `IconData` 的中间类。

- 图标码点、字体族、字体包名**逐字未改**
- **对外 API 完全不变**：`AntDesign.highlight_outline`、`Bootstrap.arrow_up_short` 等用法照旧
- `assets/` 下的字体原样保留（它们是图标字面量的实际来源）

改动由一次性脚本完成（对上万处构造调用做正则内联），产物抽样校验过码点一致。

## 上游信息

| 项 | 值 |
|---|---|
| 包名 | `icons_plus` |
| 上游版本 | `5.0.0`（2023-12-15） |
| 上游地址 | https://pub.dev/packages/icons_plus |
| 本仓库位置 | `third_party/icons_plus/` |
| 引入方式 | `pubspec.yaml` 里 `icons_plus: { path: third_party/icons_plus }` |

## 什么时候可以删掉这份

若将来满足以下任一条件，应改回 pub.dev 版本并删除本目录：

1. 上游发布了不再继承 `IconData` 的新版本；
2. 项目不再使用 `icons_plus`（可用 Material 图标或 Flutter 内置符号替代，
   目前项目用到约 17 个符号，集中在 Bootstrap 系列）。

## 如果将来需要重新生成

内联脚本的做法（供复现）：

1. 从 pub.dev 下载 `icons_plus 5.0.0` 解包；
2. 对 `lib/src/*.dart` 中每处 `XxxIconData(码点, fontFamily: 'X', fontPackage: 'icons_plus')`，
   替换为 `const IconData(码点, fontFamily: 'X', fontPackage: 'icons_plus')`；
3. 删除 `class XxxIconData extends IconData {...}` 定义；
4. 全量 `dart analyze` 验证 0 error。
