$ErrorActionPreference = 'Stop'
$qtRoot = Join-Path $PSScriptRoot '.tools\Qt\6.10.3\mingw_64'
$env:PATH = "$qtRoot\bin;$PSScriptRoot\.tools\Qt\Tools\mingw1310_64\bin;$env:PATH"
$env:QT_PLUGIN_PATH = "$qtRoot\plugins"
$env:QML_IMPORT_PATH = "$qtRoot\qml"
Start-Process -FilePath "$PSScriptRoot\build\ImageClassifier.exe" -WorkingDirectory $PSScriptRoot -WindowStyle Normal -RedirectStandardOutput "$PSScriptRoot\app.log" -RedirectStandardError "$PSScriptRoot\app-error.log"
