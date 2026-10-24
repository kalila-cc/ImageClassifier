param([string]$Root = '', [string]$AttemptId = ([guid]::NewGuid().ToString()), [switch]$KeepExportTools)
$ErrorActionPreference = 'Stop'
if (!$Root) {
    $Root = if ($env:IMAGECLASSIFIER_AI_HOME) { $env:IMAGECLASSIFIER_AI_HOME } else { Join-Path $PSScriptRoot '.tools\smart-crop' }
}
$aiRoot = [IO.Path]::GetFullPath($Root)
[IO.Directory]::CreateDirectory($aiRoot) | Out-Null
# Only an explicit user action starts this task; the lock survives app restarts.
try { $installLock = [IO.File]::Open((Join-Path $aiRoot 'install.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
catch { Write-Output 'Another model installation is already running.'; exit 73 }
$stateFile = Join-Path $aiRoot 'install-state.json'
$processCreated = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToFileTimeUtc().ToString()
function Write-InstallState([string]$State, [string]$Stage, [string]$Detail = '') {
    $json = @{ schema=1; state=$State; stage=$Stage; detail=$Detail; attempt=$AttemptId; pid=$PID; processCreated=$processCreated; updated=[DateTime]::UtcNow.ToString('o') } | ConvertTo-Json -Compress
    $tempState = "$stateFile.$PID.tmp"
    [IO.File]::WriteAllText($tempState, $json, [Text.UTF8Encoding]::new($false))
    if ([IO.File]::Exists($stateFile)) { [IO.File]::Replace($tempState, $stateFile, [NullString]::Value) }
    else { [IO.File]::Move($tempState, $stateFile) }
}
$transcribing = $false
$resultCode = 0
try {
    Write-InstallState 'installing' 'preparing'
    Start-Transcript -Path (Join-Path $aiRoot 'install.log') -Append | Out-Null
    $transcribing = $true
    $env:PYTHONUTF8 = '1'
    $env:PYTHONUNBUFFERED = '1'
    $basePython = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
    $runtimePython = Join-Path $aiRoot 'runtime\Scripts\python.exe'
    if (!(Test-Path -LiteralPath $basePython)) { throw 'Project Python environment is missing. Follow README build setup first.' }
    $manifest = Join-Path $aiRoot 'models\manifest.json'
    if (Test-Path -LiteralPath $manifest) { Remove-Item -LiteralPath $manifest -Force }
    Write-InstallState 'installing' 'runtime'
    if (!(Test-Path -LiteralPath $runtimePython)) {
        & $basePython -m venv (Join-Path $aiRoot 'runtime')
        if ($LASTEXITCODE) { throw 'Cannot create AI runtime' }
    }
    & $runtimePython -m pip install --disable-pip-version-check --no-cache-dir -r (Join-Path $PSScriptRoot 'requirements-ai.txt')
    if ($LASTEXITCODE) { throw 'Cannot install runtime dependencies. Check the network connection and install.log.' }
    Write-InstallState 'installing' 'person-pose'
    & $runtimePython (Join-Path $PSScriptRoot 'tools\ai\setup_models.py') --root $aiRoot
    if ($LASTEXITCODE) { throw 'Cannot download or verify person/pose models. Check the network connection and install.log.' }
    Write-InstallState 'installing' 'features'
    $features = Join-Path $aiRoot 'models\features.onnx'
    if (Test-Path -LiteralPath $features) {
        & $runtimePython (Join-Path $PSScriptRoot 'tools\ai\setup_models.py') --root $aiRoot --check-features
        if ($LASTEXITCODE) { Remove-Item -LiteralPath $features -Force }
    }
    if (!(Test-Path -LiteralPath $features)) {
        $exportPython = Join-Path $aiRoot 'export-env\Scripts\python.exe'
        if (!(Test-Path -LiteralPath $exportPython)) {
            & $basePython -m venv (Join-Path $aiRoot 'export-env')
            if ($LASTEXITCODE) { throw 'Cannot create model export environment' }
        }
        & $exportPython -m pip install --disable-pip-version-check --no-cache-dir torch==2.5.1 --index-url https://download.pytorch.org/whl/cpu
        if ($LASTEXITCODE) { throw 'Cannot install model export tool' }
        & $exportPython -m pip install --disable-pip-version-check --no-cache-dir transformers==4.46.3 onnx==1.17.0 numpy==2.1.3
        if ($LASTEXITCODE) { throw 'Cannot install model export dependencies' }
        & $exportPython (Join-Path $PSScriptRoot 'tools\ai\export_features.py') --root $aiRoot
        if ($LASTEXITCODE) { throw 'Cannot export image feature model' }
    }
    Write-InstallState 'installing' 'verifying'
    & $runtimePython (Join-Path $PSScriptRoot 'tools\ai\setup_models.py') --root $aiRoot --verify
    if ($LASTEXITCODE) { throw 'AI model verification failed' }
    Write-InstallState 'installing' 'cleanup'
    if (!$KeepExportTools) {
        $resolvedAiRoot = (Resolve-Path -LiteralPath $aiRoot).Path
        foreach ($folder in @('export-env', 'export-cache')) {
            $exportFolder = Join-Path $resolvedAiRoot $folder
            if (Test-Path -LiteralPath $exportFolder) {
                $resolvedExport = (Resolve-Path -LiteralPath $exportFolder).Path
                $exportInfo = Get-Item -LiteralPath $resolvedExport
                if (!$resolvedExport.StartsWith($resolvedAiRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
                    ($exportInfo.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                    throw 'Refusing to clean an export directory outside the AI workspace'
                }
                Remove-Item -LiteralPath $resolvedExport -Recurse -Force
            }
        }
    }
    Write-InstallState 'installed' 'complete'
    Write-Output 'Local smart crop models are ready.'
} catch {
    $resultCode = 1
    Write-InstallState 'failed' 'failed' $_.Exception.Message
    Write-Output $_.Exception.Message
} finally {
    if ($transcribing) { Stop-Transcript | Out-Null }
    $installLock.Dispose()
}
exit $resultCode
