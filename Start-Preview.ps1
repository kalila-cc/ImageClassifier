$ErrorActionPreference = 'Stop'
$previewPython = Join-Path $PSScriptRoot '.venv\Scripts\pythonw.exe'
if (-not (Test-Path -LiteralPath $previewPython)) {
    throw 'Preview environment missing. Run: python -m venv .venv; .\.venv\Scripts\python.exe -m pip install -r requirements-preview.txt'
}
Start-Process -FilePath $previewPython -ArgumentList ('"' + (Join-Path $PSScriptRoot 'preview.py') + '"') -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
