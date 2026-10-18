@echo off
cd /d "%~dp0"
if not exist ".venv\Scripts\pythonw.exe" (
    echo Preview environment missing. See docs\09-ui-preview.md.
    pause
    exit /b 1
)
start "" ".venv\Scripts\pythonw.exe" "%~dp0preview.py"
