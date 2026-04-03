@echo off
title YouTube Text Summarizer - AI Powered
color 0A

:: Check if PowerShell script exists
if not exist "ytts.ps1" (
    echo [ERROR] ytts.ps1 not found in current directory!
    pause
    exit /b 1
)

:menu
cls
echo ============================================================
echo     YouTube Text Summarizer - AI Powered (LM Studio)
echo ============================================================
echo.
echo This tool will:
echo   1. Download subtitles from a YouTube video
echo   2. Use AI (LM Studio) to summarize the content
echo   3. Create a text file with the summary
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

:: Ask for language
cls
echo ============================================================
echo     Subtitle Language
echo ============================================================
echo.
echo [1] English (en) - DEFAULT
echo [2] Spanish (es)
echo [3] French (fr)
echo [4] German (de)
echo [5] Japanese (ja)
echo [6] Korean (ko)
echo [7] Chinese (zh)
echo [8] Other (specify)
echo.
set /p langChoice="Select language (1-8): "

if "%langChoice%"=="1" set language=en
if "%langChoice%"=="2" set language=es
if "%langChoice%"=="3" set language=fr
if "%langChoice%"=="4" set language=de
if "%langChoice%"=="5" set language=ja
if "%langChoice%"=="6" set language=ko
if "%langChoice%"=="7" set language=zh
if "%langChoice%"=="8" (
    set /p language="Enter language code (e.g., hi, ru, ar): "
)
if "%language%"=="" set language=en

cls
echo ============================================================
echo     Processing Video Summary
echo ============================================================
echo.
echo URL: %videoUrl%
echo Language: %language%
echo.
echo This may take 30-60 seconds...
echo.
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "ytts.ps1" -VideoUrl "%videoUrl%" -Language "%language%"

echo.
echo ============================================================
echo.
echo Summary text file created in the current directory!
echo.
echo Options:
echo   [1] Open output folder
echo   [2] Summarize another video
echo   [3] Exit
echo.
set /p finish="Select option (1-3): "

if "%finish%"=="1" (
    start explorer.exe .
    goto exit
)
if "%finish%"=="2" goto menu
if "%finish%"=="3" goto exit
goto exit

:exit
echo.
echo Thank you for using YouTube Text Summarizer!
timeout /t 2 >nul
exit /b