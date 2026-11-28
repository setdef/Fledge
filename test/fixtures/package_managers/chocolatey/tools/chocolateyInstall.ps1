$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

Install-ChocolateyZipPackage -PackageName 'hello' -UnzipLocation $toolsDir `
  -Url64bit 'https://github.com/example/hello/releases/download/v1.0.0/Hello-x64-mingw-ucrt.zip' `
  -Checksum64 'HASH FROM Hello-x64-mingw-ucrt.zip.sha256' -ChecksumType64 'sha256'

Get-ChildItem -LiteralPath $toolsDir -Recurse -Filter '*.exe' |
  Where-Object { $_.Name -ne 'Hello.exe' } |
  ForEach-Object { New-Item -ItemType File -Force -Path "$($_.FullName).ignore" | Out-Null }
