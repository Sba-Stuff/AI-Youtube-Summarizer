@echo off
title YouTube Video Summarizer - AI Powered
color 0A

:: Check if PowerShell script exists
if not exist "ytvs.ps1" (
    echo [ERROR] ytvs.ps1 not found in current directory!
    echo Please make sure the PowerShell script is in the same folder.
    pause
    exit /b 1
)

:menu
cls
echo ============================================================
echo     YouTube Video Summarizer - AI Powered (LM Studio)
echo ============================================================
echo.
echo This tool will:
echo   1. Download a YouTube video and its subtitles
echo   2. Use AI (LM Studio) to find the most important parts
echo   3. Create a short summary video
echo.
echo ============================================================
echo.

:: Ask for YouTube URL
echo Please enter the YouTube URL:
echo (Example: https://www.youtube.com/watch?v=dQw4w9WgXcQ)
echo.
set /p videoUrl="URL: "

if "%videoUrl%"=="" (
    echo [ERROR] No URL entered!
    timeout /t 2 >nul
    goto menu
)

:: Ask for summary settings
cls
echo ============================================================
echo     Summary Settings
echo ============================================================
echo.
echo Video URL: %videoUrl%
echo.
echo [1] Quick summary (30 seconds, 3 segments)
echo [2] Standard summary (60 seconds, 5 segments) - DEFAULT
echo [3] Detailed summary (90 seconds, 7 segments)
echo [4] Custom settings
echo [5] Back to URL entry
echo.
set /p choice="Select option (1-5): "

if "%choice%"=="1" goto quick
if "%choice%"=="2" goto standard
if "%choice%"=="3" goto detailed
if "%choice%"=="4" goto custom
if "%choice%"=="5" goto menu
goto menu

:quick
set duration=30
set segments=3
goto confirm

:standard
set duration=60
set segments=5
goto confirm

:detailed
set duration=90
set segments=7
goto confirm

:custom
cls
echo ============================================================
echo     Custom Settings
echo ============================================================
echo.
set /p duration="Summary duration in seconds (recommended: 30-120): "
if "%duration%"=="" set duration=60
set /p segments="Number of segments (recommended: 3-10): "
if "%segments%"=="" set segments=5
goto confirm

:confirm
cls
echo ============================================================
echo     Confirm Settings
echo ============================================================
echo.
echo YouTube URL: %videoUrl%
echo Summary duration: %duration% seconds
echo Number of segments: %segments%
echo.
echo [1] Start summarization
echo [2] Change settings
echo [3] Exit
echo.
set /p confirm="Select option (1-3): "

if "%confirm%"=="1" goto run
if "%confirm%"=="2" goto menu
if "%confirm%"=="3" exit /b
goto confirm

:run
cls
echo ============================================================
echo     Processing Video Summary
echo ============================================================
echo.
echo URL: %videoUrl%
echo Duration target: %duration% seconds
echo Segments: %segments%
echo.
echo This may take several minutes depending on video length...
echo.
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "ytvs.ps1" -VideoUrl "%videoUrl%" -SummaryDuration %duration% -NumSegments %segments%

echo.
echo ============================================================
echo.
echo Summary video created! Check for summary_output.mp4
echo.
echo Options:
echo   [1] Open output folder
echo   [2] Create another summary
echo   [3] Exit
echo.
set /p finish="Select option (1-3): "

if "%finish%"=="1" (
    start explorer.exe /select,"summary_output.mp4"
    goto exit
)
if "%finish%"=="2" goto menu
if "%finish%"=="3" goto exit
goto exit

:exit
echo.
echo Thank you for using YouTube Video Summarizer!
timeout /t 2 >nul
exit /b