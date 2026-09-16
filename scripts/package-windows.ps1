[CmdletBinding()]
param(
    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z.-]*$')][string]$Version = '0.1.0-alpha',
    [ValidateSet('win-x64')][string]$Runtime = 'win-x64',
    [string]$DotNetPath = 'dotnet',
    [switch]$NoRestore,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$publishDirectory = Join-Path $projectRoot "artifacts/windows/$Runtime/JieJu"
$packageDirectory = Join-Path $projectRoot 'artifacts/packages'
$archiveName = "JieJu-Windows-x64-$Version.zip"
$archivePath = Join-Path $packageDirectory $archiveName
$checksumPath = "$archivePath.sha256"
$stagingRoot = Join-Path $projectRoot 'artifacts/package-staging'
$stagingDirectory = Join-Path $stagingRoot 'JieJu'

if (-not $SkipBuild) {
    $buildArguments = @{
        Configuration = 'Release'
        Runtime = $Runtime
        OutputDirectory = $publishDirectory
        DotNetPath = $DotNetPath
        Version = $Version
    }
    if ($NoRestore) { $buildArguments.NoRestore = $true }
    & (Join-Path $PSScriptRoot 'build-windows.ps1') @buildArguments
    if ($LASTEXITCODE -ne 0) { throw 'Windows build script failed.' }
}

$executable = Join-Path $publishDirectory 'JieJu.Windows.exe'
if (-not (Test-Path -LiteralPath $executable)) { throw "Build output is missing: $executable" }
New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null
if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
Get-ChildItem -LiteralPath $publishDirectory | Where-Object { $_.Name -notlike '*.WebView2' } |
    Copy-Item -Destination $stagingDirectory -Recurse -Force

Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE') -Destination (Join-Path $stagingDirectory 'LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'NOTICE') -Destination (Join-Path $stagingDirectory 'NOTICE.txt') -Force
$commit = (& git -C $projectRoot rev-parse --short HEAD 2>$null)
if (-not $commit) { $commit = 'unknown' }
@"
JieJu Windows development preview $Version

Run JieJu.Windows.exe. Windows 10 version 1809 or later and Microsoft Edge WebView2 Runtime are required.
Ollama is optional and is only needed for local AI explanations.

This is a portable package. To uninstall it, close JieJu and delete the extracted JieJu folder.
Reading data stored under %LOCALAPPDATA%\JieJu is not removed automatically.

Build commit: $commit
This is an unsigned development preview. See LICENSE.txt and NOTICE.txt for licensing information.
"@ | Set-Content -LiteralPath (Join-Path $stagingDirectory 'PACKAGE-README.txt') -Encoding UTF8

if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
if (Test-Path -LiteralPath $checksumPath) { Remove-Item -LiteralPath $checksumPath -Force }
Compress-Archive -Path $stagingDirectory -DestinationPath $archivePath -CompressionLevel Optimal
$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $archiveName" | Set-Content -LiteralPath $checksumPath -Encoding ASCII
Remove-Item -LiteralPath $stagingRoot -Recurse -Force

Write-Host "Windows package ready: $archivePath"
Write-Host "SHA-256: $hash"
