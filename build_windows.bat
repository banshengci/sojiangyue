@echo off
REM SongJiang Reader - Windows (Release) build helper
REM Double-click to build, or run: build_windows.bat
setlocal
set FLUTTER_BIN=D:\flutter_windows_3.35.3-stable\flutter\bin\flutter.bat
cd /d D:\xinxiangmu\songjiang_reader
call "%FLUTTER_BIN%" pub get
if errorlevel 1 (
  echo [ERROR] pub get failed
  pause
  exit /b 1
)
call "%FLUTTER_BIN%" build windows --release
if errorlevel 1 (
  echo [ERROR] build failed
  pause
  exit /b 1
)
echo Build complete: build\windows\x64\runner\Release\songjiang_reader.exe
pause
