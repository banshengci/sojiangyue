#!/usr/bin/env bash
# 松江阅 Android 构建脚本。
#
# 直接在 Windows cmd / WSL / Git Bash 中运行：
#   bash scripts/build-android.sh                  # debug APK
#   bash scripts/build-android.sh release          # release AAB
#   bash scripts/build-android.sh debug --analyze  # 仅跑静态分析
#
# 前置条件（与本机 dev 一致）:
#   1. Flutter 3.35.3 stable（flutterw3353.sh 的相同版本）
#   2. JDK 17+（flutter doctor 推荐 JDK 17，JDK 21 也可）
#   3. Android SDK 含 platforms;android-35 与 build-tools;35.0.x
#   4. 已执行 `flutter pub get`（pubspec.lock 已钉版 googleai_dart 3.0.0）
#
# 详细环境说明见 docs/BUILD.md
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 选 flutter 入口
if command -v flutter >/dev/null 2>&1; then
  FLUTTER="flutter"
elif [ -x "/d/flutter_windows_3.35.3-stable/flutter/bin/flutter" ]; then
  FLUTTER="/d/flutter_windows_3.35.3-stable/flutter/bin/flutter"
elif [ -x "$HOME/flutter_windows_3.35.3-stable/flutter/bin/flutter" ]; then
  FLUTTER="$HOME/flutter_windows_3.35.3-stable/flutter/bin/flutter"
else
  echo "ERROR: 未找到 flutter。请安装 Flutter 3.35.3 stable 或加入 PATH。" >&2
  exit 1
fi

MODE="${1:-debug}"
EXTRA="${@:2}"

case "$MODE" in
  --analyze|-a)  $FLUTTER analyze ;;
  debug|release|profile)
    # Windows cmd 下 flutter analyze 已跑过, pub get 必跑
    $FLUTTER pub get
    $FLUTTER build apk --"$MODE" $EXTRA
    echo
    echo "✓ APK 已生成（位置见 build/app/outputs/flutter-apk/）"
    ;;
  install)
    $FLUTTER build apk --debug
    $FLUTTER install
    ;;
  *)
    echo "用法: $0 [debug|release|--analyze|install] [flutter build 选项...]" >&2
    exit 1
    ;;
esac