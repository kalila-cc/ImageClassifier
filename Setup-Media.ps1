$ErrorActionPreference = 'Stop'
$mediaRoot = Join-Path $PSScriptRoot '.tools\media'
$downloadRoot = Join-Path $mediaRoot 'downloads'
New-Item -ItemType Directory -Force $downloadRoot | Out-Null

function Get-VerifiedFile([string]$Url, [string]$Destination, [string]$Sha256) {
    if ((Test-Path -LiteralPath $Destination) -and (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -eq $Sha256) { return }
    New-Item -ItemType Directory -Force (Split-Path -Parent $Destination) | Out-Null
    $temporary = $Destination + '.download'
    Invoke-WebRequest -Uri $Url -OutFile $temporary
    if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $Sha256) { throw "Checksum mismatch: $Url" }
    Move-Item -LiteralPath $temporary -Destination $Destination -Force
}

$exifArchive = Join-Path $downloadRoot 'exiftool-13.59_64.zip'
Get-VerifiedFile 'https://oliverbetz.de/cms/files/Artikel/ExifTool-for-Windows/exiftool-13.59_64.zip' $exifArchive '577257dd22baebe77157d905792d6ed2c5916cd03aa627f40b2175db12110ac6'
Expand-Archive -LiteralPath $exifArchive -DestinationPath (Join-Path $PSScriptRoot '.tools\exiftool') -Force

$heifRoot = Join-Path $mediaRoot 'heif'
$release = 'https://github.com/novomesk/qt-heic-image-plugin/releases/download/v0.7.3'
$libraries = @{
    'heif.dll' = 'feaebd07e3a2d3b7c7fea268bb037eac8b6cf1b37bbda99d24b02b0347613512'
    'libde265.dll' = '825a807ae4fe0b23c0689e04f5d1424adc181ba228680bc7a98bad4889d4581d'
    'openh264-7.dll' = '40ff6c2ddcc25598001850a2dc1f5e184ba3670d0a74cc01e52f9fc4c2d80520'
    'openjp2.dll' = '223daeca0592372e684b90ab70bfdfb4480ee933c32bbcec34af837b538f9114'
}
foreach ($name in $libraries.Keys) { Get-VerifiedFile "$release/$name" (Join-Path $heifRoot $name) $libraries[$name] }
# Compile against the stable 1.19 C interface; the bundled libheif is 1.23.5.
$includeRoot = Join-Path $heifRoot 'include\libheif'
Get-VerifiedFile 'https://raw.githubusercontent.com/strukturag/libheif/v1.19.8/libheif/api/libheif/heif.h' (Join-Path $includeRoot 'heif.h') '404a55c714c44707ec801c7f04f6c9aaa8a2551108667b1a701ce720483b6510'
Set-Content -LiteralPath (Join-Path $includeRoot 'heif_version.h') -Encoding ascii -Value '#define LIBHEIF_NUMERIC_VERSION 0x01130800'

$licenseRoot = Join-Path $mediaRoot 'licenses'
Get-VerifiedFile 'https://raw.githubusercontent.com/strukturag/libheif/v1.23.5/COPYING' (Join-Path $licenseRoot 'libheif-LICENSE.txt') 'fa81ce652315b013359d6e8e4744335f31a50c7c192907176d3632f78a3b4596'
Get-VerifiedFile 'https://raw.githubusercontent.com/strukturag/libde265/v1.1.3/COPYING' (Join-Path $licenseRoot 'libde265-LICENSE.txt') '02cc1585a20677992e0ba578fa692635dc193735f2691dc81de924b51c4e8020'
Get-VerifiedFile 'https://raw.githubusercontent.com/uclouvain/openjpeg/v2.5.4/LICENSE' (Join-Path $licenseRoot 'openjpeg-LICENSE.txt') 'a6af136f3e15038a666b61f376612a07d9a4e48cb7c01adbf3e33b3f14ab49b6'
Get-VerifiedFile 'https://raw.githubusercontent.com/cisco/openh264/v2.6.0/LICENSE' (Join-Path $licenseRoot 'openh264-LICENSE.txt') 'dd5c1c9668512530fa5a96e4c29ac4033d70a7eeb0eed7a42fddb6dd794ebdbb'
Write-Output 'Media components installed. Run Build.ps1 to enable HEIC decoding. ExifTool and libheif remain external, replaceable components.'
