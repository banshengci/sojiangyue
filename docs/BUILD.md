# 松江阅 构建指南

## 1. 环境要求

| 组件 | 版本 | 说明 |
|---|---|---|
| Flutter SDK | **3.35.3 stable**（Dart 3.9.2） | 不要用 3.47.x —— build_runner 在其上会卡死 |
| JDK | 17+（本机 21） | Android Gradle Plugin 8.9 要求 |
| Android SDK | platforms **android-36**、build-tools 35+ | compileSdk / targetSdk = 36 |
| Android NDK | 27.0.12077973 | sqlite3_flutter_libs 等插件编译 native |
| Android CMake | 3.22.1+ | 同上；本机用 VS BuildTools 自带的 3.31.6 |
| Ninja | 任意 | CMake 的构建后端 |
| Visual Studio | 2022 BuildTools + **ATL** | Windows 构建（flutter_tts 需要 `<atlstr.h>`） |

本机 Flutter 命令一律走 `D:\xinxiangmu\flutterw3353.sh`（绕开 flutter.bat 的 bootstrap 卡死）。
详见 `.workbuddy/memory/` 下的日志。

---

## 2. 常用命令

```bash
# 依赖
bash /d/xinxiangmu/flutterw3353.sh pub get
bash /d/xinxiangmu/flutterw3353.sh pub run build_runner build --delete-conflicting-outputs

# 质量
bash /d/xinxiangmu/flutterw3353.sh analyze
bash /d/xinxiangmu/flutterw3353.sh test --no-pub

# Windows
bash /d/xinxiangmu/flutterw3353.sh build windows --debug
bash /d/xinxiangmu/flutterw3353.sh build windows --release

# Android（等价脚本 scripts/build-android.sh）
bash /d/xinxiangmu/flutterw3353.sh build apk --debug
bash /d/xinxiangmu/flutterw3353.sh build apk --release      # 单包
bash /d/xinxiangmu/flutterw3353.sh build appbundle --release # AAB（上架用）

# 发布构建记得带上自有服务配置，例如：
bash /d/xinxiangmu/flutterw3353.sh build apk --release \
  --dart-define=PROJECT_REPO=yourname/songjiang_reader \
  --dart-define=PRIVACY_URL=https://example.com/privacy \
  --dart-define=TERMS_URL=https://example.com/terms
```

---

## 3. Android 签名配置

### Debug
默认使用 Android SDK 的 `~/.android/debug.keystore`。
**受限环境**（沙箱 / 部分 CI）无法写入 `~/.android` 时，AGP 创建 keystore 会失败
（`AccessDeniedException: debug.keystore.lock`）。

此时在 `android/app/` 放一个 `debug.keystore` 即可自动生效（已内置于 `build.gradle`）：

```bash
keytool -genkeypair -v -keystore android/app/debug.keystore \
  -storepass android -alias androiddebugkey -keypass android \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Android Debug,O=Android,C=US"
```

### Release
1. 生成 keystore（**务必自行更换密码并妥善保管**）：

```bash
keytool -genkeypair -v -keystore android/app/release.jks -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10000 -alias songjiang \
  -storepass <你的密码> -keypass <你的密码> \
  -dname "CN=SongJiang Reader, OU=SongJiang, O=com.songjiang, L=Shanghai, ST=Shanghai, C=CN"
```

2. 创建 `android/key.properties`（**不要提交**）：

```properties
storeFile=release.jks
storePassword=<你的密码>
keyAlias=songjiang
keyPassword=<你的密码>
```

`key.properties`、`*.jks`、`*.keystore` 都已在 `android/.gitignore` 中忽略。

3. 构建：`flutter build apk --release` 或 `flutter build appbundle --release`

> ⚠️ 仓库里的 `key.properties` / `release.jks` 仅是**占位示例**（密码 `songjiang2026`），
> 正式发布前必须替换为自己的密钥，且**不要**提交到任何公开仓库。

---

## 4. 已知环境坑（Windows）

### 4.1 pub git 依赖丢文件 —— Windows 长路径
`flutter pub get` 克隆 git 依赖（如 `flutter_inappwebview`）时，路径超过 Windows 260 字符限制的
源文件会**静默不被创建**，编译期表现为大批「找不到符号」（如 `headless_in_app_webview` 整个目录为空）。

```bash
# 修复（对每个受影响的包执行一次）
cd "$LOCALAPPDATA/Pub/Cache/git/<包名>-<hash>"
git config core.longpaths true
git checkout -- .
```

CI 已包含 `git config --system core.longpaths true` 预防。

### 4.2 项目缺 Gradle wrapper
`android/.gitignore` 忽略了 `gradlew` / `gradlew.bat` / `gradle-wrapper.jar`，
所以 checkout 后项目里没有 wrapper，首次 `flutter build apk` 容易卡住。补齐命令：

```bash
SDK="$(dirname "$(dirname "$(command -v flutter)")")"
cp "$SDK/bin/cache/artifacts/gradle_wrapper/gradlew" android/gradlew
cp "$SDK/bin/cache/artifacts/gradle_wrapper/gradlew.bat" android/gradlew.bat
mkdir -p android/gradle/wrapper
cp "$SDK/bin/cache/artifacts/gradle_wrapper/gradle/wrapper/gradle-wrapper.jar" android/gradle/wrapper/
```

### 4.3 Android SDK 缺 CMake / Ninja
`sqlite3_flutter_libs` 需要 CMake 编译 native：
- 方案 A：`sdkmanager --install "cmake;3.22.1"`
- 方案 B：复用 VS BuildTools 自带的 CMake，`android/local.properties` 里加
  `cmake.dir=C:/BuildTools/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake`
  （**必须用正斜杠**，properties 里 `\` 是转义符），并把
  `.../CMake/Ninja/ninja.exe` 复制到 `.../CMake/CMake/bin/`

### 4.4 Flutter SDK 的 iOS USB artifact 检查
受限环境下 Flutter 工具启动会尝试重写 `bin/cache/*.stamp` 并失败。
根治方法是让 `IosUsbArtifacts` 判定为 up-to-date —— 在
`bin/cache/artifacts/libimobiledevice/` 放空的 `idevicescreenshot`、`idevicesyslog`，
在 `bin/cache/artifacts/libusbmuxd/` 放空的 `iproxy`（本机不做 iOS 开发，用不到真实二进制）。

### 4.5 Gradle 增量构建需要删除文件
沙箱/受限环境下 Gradle 删除 “stale output file” 会被拒绝（`Unable to delete file ...`）。
逐个文件修是无穷的；**构建前把 `build/`、`android/build` 整个 mv 重命名让位**，
让 Gradle 全量新建即可（没有旧文件可删）。

---

## 5. 自有服务配置

所有远程端点通过 `--dart-define` 注入，详见 [DEPLOY.md](DEPLOY.md)。

最简：设置 `PROJECT_REPO=owner/repo` 即启用 GitHub Releases 作为更新源，无需自建后端。
