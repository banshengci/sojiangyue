@echo off
chcp 65001 >nul 2>&1
set GIT="C:\Users\Administrator\.workbuddy\binaries\PortableGit\versions\1.2.0\cmd\git.exe"
echo === SongJiang Reader - Push to GitHub ===
echo.
echo Pushing to origin/main...
%GIT% push origin main
if %ERRORLEVEL% EQU 0 (
    echo.
    echo === SUCCESS! Code pushed to GitHub ===
    echo CI will start automatically at:
    echo https://github.com/2113024546/sojiangyue/actions
) else (
    echo.
    echo === PUSH FAILED ===
    echo Try running push_force.bat if this is the first push.
)
echo.
pause
