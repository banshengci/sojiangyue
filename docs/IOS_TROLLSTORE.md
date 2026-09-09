# iOS 侧载（TrollStore / 无付费开发者账号）

适用于：**自己用**、不上架 App Store、没有（或不想买）Apple Developer Program 的情况。

你的情况：**iPhone 14 · iOS 16.1 · 已装 TrollStore（巨魔）** —— 兼容。

## 推荐：GitHub Actions 出未签名 IPA

仓库 `ci.yml` 在 main / PR 上会跑 **Build iOS (unsigned IPA / TrollStore)**：

1. 打开仓库 **Actions** → 选最近一次成功运行
2. 左侧选择 **Build iOS (unsigned IPA / TrollStore)**
3. 页面底部 **Artifacts** 下载  
   `songjiang_reader-ios-unsigned-ipa`
4. 解压得到 `SongJiang-Reader-ios-unsigned.ipa`

该 IPA 为 `flutter build ios --release --no-codesign` 产物，**没有** Apple 证书签名；TrollStore 会在设备上用自身机制安装/重签。

## 装到 iPhone 14（iOS 16.1）

任选一种把 `.ipa` 送到手机：

1. **AirDrop** 到 iPhone → 用「文件」打开  
2. 或电脑上用爱思/Filza 等拷到设备  
3. 或起个本地 HTTP，Safari 下载

在手机上：

1. 用 **TrollStore** 打开该 `.ipa`（或分享到 TrollStore）
2. 确认安装
3. 首次可能需在 **设置 → 通用 → VPN与设备管理** 里信任（TrollStore 机型通常已处理）

若 TrollStore 提示签名/权限问题，见下方「补充签名」。

## 本地有 Mac 时打包（可选）

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter build ios --release --no-codesign

# 打包 IPA
cd build/ios/iphoneos   # 若无此目录则试 Release-iphoneos
mkdir -p Payload
cp -R Runner.app Payload/
zip -qry SongJiang-Reader-ios-unsigned.ipa Payload
```

## 补充签名（ldid，可选）

部分 TrollStore 版本更喜欢带 `get-task-allow` 等 entitlements 的包。在 Mac 上可对 `Runner.app` 执行：

```bash
# 安装 ldid（brew install ldid）后：
ldid -S entitlements.plist Payload/Runner.app
```

`entitlements.plist` 最小示例：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>get-task-allow</key>
  <true/>
  <key>platform-application</key>
  <true/>
  <key>com.apple.private.security.no-container</key>
  <true/>
  <key>com.apple.developer.kernel.increase-memory-limit</key>
  <true/>
</dict>
</plist>
```

然后重新 `zip` 为 `.ipa` 再导入 TrollStore。

## 常见问题

| 现象 | 处理 |
|------|------|
| 安装后闪退 | 确认 TrollStore 版本支持 iOS 16.1；重装 IPA；重启设备 |
| 提示无效应用 | 用 ldid 补 entitlements 后再装 |
| 找不到 WebView | 需要 iOS 14+ 自带 WebView；系统设置里勿禁用 |
| 内购 | 无开发者账号/不上架则内购不可用；App 内购由 `EnvVar.enableInAppPurchase` 门控，默认商店构建才开 |

## 与 App Store 版关系

- 本路径产物供 **个人侧载**，不经过公证/审核。
- 若要以后上架，改用带证书的 `build-ios.yaml` / App Store 流程，与此无关。
