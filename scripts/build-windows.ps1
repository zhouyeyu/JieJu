[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Release',
    [ValidateSet('win-x64')][string]$Runtime = 'win-x64',
    [string]$OutputDirectory,
    [string]$DotNetPath = 'dotnet',
    [string]$Version,
    [switch]$NoRestore
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$windowsRoot = Join-Path $projectRoot 'Apps/Windows'
$project = Join-Path $windowsRoot 'JieJu.Windows/JieJu.Windows.csproj'
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot "artifacts/windows/$Runtime/JieJu" }
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$artifactsRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'artifacts'))
$isManagedOutput = $OutputDirectory.StartsWith($artifactsRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
if ($isManagedOutput -and (Test-Path -LiteralPath $OutputDirectory)) {
    Remove-Item -LiteralPath $OutputDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

if (-not (Get-Command $DotNetPath -ErrorAction SilentlyContinue)) {
    $localSdk = Join-Path $env:LOCALAPPDATA 'JieJuBuild/dotnet/dotnet.exe'
    if ($DotNetPath -eq 'dotnet' -and (Test-Path -LiteralPath $localSdk)) { $DotNetPath = $localSdk }
    else { throw 'Install the .NET SDK specified in Apps/Windows/global.json or pass -DotNetPath.' }
}

Push-Location $windowsRoot
try {
    if (-not $NoRestore) {
        & $DotNetPath restore 'JieJu.Windows.sln' --locked-mode
        if ($LASTEXITCODE -ne 0) { throw 'Windows dependency restore failed.' }
    }

    $publishArguments = @(
        'publish', $project,
        '-c', $Configuration,
        '-r', $Runtime,
        '-p:Platform=x64',
        '--self-contained', 'true',
        '--no-restore',
        '-o', $OutputDirectory,
        '-p:DebugType=None',
        '-p:DebugSymbols=false'
    )
    if ($Version) { $publishArguments += "-p:Version=$Version" }
    & $DotNetPath @publishArguments
    if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }
}
finally { Pop-Location }

$executable = Join-Path $OutputDirectory 'JieJu.Windows.exe'
$reader = Join-Path $OutputDirectory 'ReaderHost/index.html'
if (-not (Test-Path -LiteralPath $executable) -or -not (Test-Path -LiteralPath $reader)) {
    throw 'Publish completed without the executable or ReaderHost assets.'
}

Write-Host "Windows build ready: $executable"
