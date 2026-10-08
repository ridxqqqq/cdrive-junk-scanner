@echo off
rem ============================================================
rem  C-Drive Junk Scan launcher (READ-ONLY scan, deletes nothing)
rem  Double-click: elevates if needed, then runs the .ps1 in
rem  the same folder. ASCII-only on purpose - any codepage safe.
rem ============================================================
setlocal
cd /d "%~dp0"
fltmc >nul 2>&1
if not errorlevel 1 goto run
echo Requesting administrator privileges, please click Yes on the UAC prompt...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
:run
set "BASE=%~n0"
set "PS1=%~dp0%BASE%.ps1"
if exist "%PS1%" goto go
for %%f in ("%~dp0*.ps1") do set "PS1=%%~ff"
:go
if exist "%PS1%" goto exec
echo [ERROR] No .ps1 script found next to this launcher.
pause
exit /b 1
:exec
echo Running: "%PS1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
echo.
echo Scan finished. Reports are on the Desktop.
pause
