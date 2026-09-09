@echo off
REM SongJiang Reader - APK (Release) build helper
REM Double-click to build, or run: build_apk.bat
REM Flutter is resolved from PATH, or from FLUTTER_HOME / FLUTTER_BIN env vars.
setlocal
cd /d %~dp0

if defined FLUTTER_BIN (
  set "FLUTTER_CMD=%FLUTTER_BIN%"
) else if defined FLUTTER_HOME (
  set "FLUTTER_CMD=%FLUTTER_HOME%\bin\flutter.bat"
) else (
  set "FLUTTER_CMD=flutter"
)

call "%FLUTTER_CMD%" pub get
if errorlevel 1 (
  echo [ERROR] pub get failed
  echo         Install Flutter and add it to PATH, or set FLUTTER_BIN / FLUTTER_HOME.
  pause
  exit /b 1
)
call "%FLUTTER_CMD%" build apk --release
if errorlevel 1 (
  echo [ERROR] build failed
  pause
  exit /b 1
)
echo Build complete: build\app\outputs\flutter-apk\app-release.apk
pause
