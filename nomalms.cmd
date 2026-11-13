@echo off
rem nomalms for Windows: runs nomalms.ps1 next to this file.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0nomalms.ps1" %*
exit /b %ERRORLEVEL%
