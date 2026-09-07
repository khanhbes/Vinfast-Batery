@echo off
chcp 65001 >nul
title VinFast Battery Control Center
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
if %ERRORLEVEL% neq 0 pause
