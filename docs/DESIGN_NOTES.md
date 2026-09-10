# 松江阅 UI 设计备忘

## 视觉体系（已有，勿另起炉灶）

| Token | 值 | 用途 |
|-------|-----|------|
| pine | #1B6B44 | 主色 / 松绿 |
| paper | #F5F2EA | 浅色底（宣纸） |
| paperCard | #FFFDF7 | 浅色卡片 |
| ink | #121815 | 深色底 |
| inkCard | #1E2621 | 深色卡片 |
| pollen | #C88C2E | 点缀（徽标、评分星） |
| bamboo 渐变 | 竹青系 | 品牌头图 |

## 图标规范

- **只用 Material Icons**（`theme/songjiang_icons.dart`）
- 底部导航：outline + rounded 成对（`SongJiangIcons.bookshelf` / `bookshelfSelected`）
- 工具栏：`*_rounded` 为主，动作类可用 `*_outlined`
- **禁止**再引入 EvaIcons / HeroIcons 到新代码

## 交互

- 书架多选：长按 → 加入多选；勾选 = 松绿描边 + 右上角 check
- AI 快捷 chip 顺序：读前 → 自测 → 回顾 → 章总结 → 导图 → 全书
- 底部导航：浮动胶囊 + 毛玻璃，选中用松绿

## 已完成（本轮）

- [x] 全局替换 EvaIcons → SongJiangIcons / Material（lib 内已清零）
- [x] 更多设置列表图标对齐
- [x] 空态/加载态：`EmptyStateHint` + `AppLoadingHint`（书架、生词、字体页）

## 待做 / 下一轮

- [ ] 阅读工具栏图标风格再统一（圆角粗细）
- [ ] 书架卡片阴影/多选动效
- [ ] 设置页各子页 leading 图标复核
