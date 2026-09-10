@echo off
chcp 65001 >nul 2>&1
REM SongJiang Reader - Push to GitHub
REM Requires git on PATH, or set GIT_BIN to full path of git.exe
setlocal
if defined GIT_BIN (
  set "GIT_CMD=%GIT_BIN%"
) else (
  set "GIT_CMD=git"
)

echo === SongJiang Reader - Push to GitHub ===
echo.
echo Pushing to origin/main...
"%GIT_CMD%" push origin main
if %ERRORLEVEL% EQU 0 (
    echo.
    echo === SUCCESS! Code pushed to GitHub ===
    echo Check Actions on the repository page.
) else (
    echo.
    echo === PUSH FAILED ===
    echo Check network / credentials, then try again.
)
echo.
pause
