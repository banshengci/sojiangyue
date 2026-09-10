# 松江阅 构建指南

## 1. 环境要求

| 组件 | 版本 | 说明 |
|---|---|---|
| Flutter SDK | **3.35.3 stable**（Dart 3.9.2） | 不要用 3.47.x —— build_runner 在其上会卡死 |
| JDK | 17+ | Android Gradle Plugin 8.9 要求 |
| Android SDK | platforms **android-36**、build-tools 35+ | compileSdk / targetSdk = 36 |
| Android NDK | 27.0.12077973 | sqlite3_flutter_libs 等插件编译 native |
| Visual Studio | 2022 BuildTools + **ATL** | Windows 构建（flutter_tts 需要 `<atlstr.h>`） |

将 Flutter 的 `bin` 目录加入 `PATH`，或通过环境变量 `FLUTTER_HOME` / `FLUTTER_BIN` 指向 SDK。

仓库根目录的 `build_apk.bat` / `build_windows.bat` 会按 `FLUTTER_BIN` → `FLUTTER_HOME` → `PATH` 顺序查找 `flutter`。

---

## 2. 常用命令

```bash
# 依赖
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# 质量
flutter analyze
flutter test --no-pub

# Windows
flutter build windows --debug
flutter build windows --release

# Android（等价脚本 scripts/build-android.sh）
flutter build apk --debug
flutter build apk --release      # 单包
flutter build appbundle --release # AAB（上架用）
```

发布构建可按需注入：

```bash
flutter build apk --release \
  --dart-define=PROJECT_REPO=yourname/songjiang_reader \
  --dart-define=PRIVACY_URL=https://example.com/privacy \
  --dart-define=TERMS_URL=https://example.com/terms
```

---

## 3. Android 签名配置

### Debug
默认使用 Android SDK 的 `~/.android/debug.keystore`。

### Release
1. 在**本机**生成 keystore（勿提交到 Git）：

```bash
keytool -genkeypair -v -keystore android/app/release.jks -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10000 -alias songjiang \
  -dname "CN=Your Name, O=Your Org, C=CN"
```

2. 在本机创建 `android/key.properties`（已被 `.gitignore` 忽略）：

```properties
storeFile=release.jks
storePassword=<your-store-password>
keyAlias=songjiang
keyPassword=<your-key-password>
```

3. 确认 `android/.gitignore` 包含 `*.jks` 与 `key.properties`。

CI 使用 GitHub Actions Secrets 注入签名，**不要**把密码写进 workflow 文件。

---

## 4. iOS / macOS

### macOS
```bash
flutter build macos --debug
flutter build macos --release
```

### iOS
```bash
flutter build ios --release --no-codesign   # 无证书 / TrollStore 侧载
```

侧载说明见 `docs/IOS_TROLLSTORE.md`。

---

## 5. 常见问题

### Windows
- 构建前开启 git long paths：
  ```bash
  git config --system core.longpaths true
  ```
- 缺 CMake / Ninja：安装 VS Build Tools（含 ATL）。

### Android
- debug.keystore 被拒写：在 `android/app/` 放本地 `debug.keystore`。
- gradlew 缺失：从 Flutter SDK `bin/cache/artifacts/gradle_wrapper/` 复制到 `android/`。

### CI
- 密钥只放 Actions Secrets；日志中勿 `echo` 密钥。
- Linux 构建需要 WPE WebKit（见 `ci.yml`）。
