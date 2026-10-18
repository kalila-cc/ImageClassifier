param([switch]$Test)
$ErrorActionPreference = 'Stop'
$qtRoot = Join-Path $PSScriptRoot '.tools\Qt\6.10.3\mingw_64'
$compilerRoot = Join-Path $PSScriptRoot '.tools\Qt\Tools\mingw1310_64\bin'
$cmakeExe = Join-Path $PSScriptRoot '.venv\Scripts\cmake.exe'
$ninjaExe = Join-Path $PSScriptRoot '.venv\Scripts\ninja.exe'
$env:PATH = "$qtRoot\bin;$compilerRoot;$env:PATH"
$env:QT_FORCE_STDERR_LOGGING = '1'
$localTests = if ($Test) { 'ON' } else { 'OFF' }
if ($Test -and -not (Test-Path -LiteralPath "$PSScriptRoot\tests\CMakeLists.txt")) {
    throw 'Local tests are not included in the repository. Run Build.ps1 without -Test.'
}
& $cmakeExe -S $PSScriptRoot -B "$PSScriptRoot\build" -G Ninja "-DCMAKE_MAKE_PROGRAM=$ninjaExe" "-DCMAKE_CXX_COMPILER=$compilerRoot\g++.exe" "-DCMAKE_PREFIX_PATH=$qtRoot" -DCMAKE_BUILD_TYPE=Release "-DIMAGECLASSIFIER_BUILD_TESTS=$localTests"
if ($LASTEXITCODE) { throw 'Configure failed' }
& $cmakeExe --build "$PSScriptRoot\build" --parallel 6
if ($LASTEXITCODE) { throw 'Build failed' }
if ($Test) {
    & "$PSScriptRoot\.venv\Scripts\ctest.exe" --test-dir "$PSScriptRoot\build" --output-on-failure
    if ($LASTEXITCODE) { throw 'Tests failed' }
}
