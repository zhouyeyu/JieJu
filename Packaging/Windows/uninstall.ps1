[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs'),
    [switch]$RemoveUserData,
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'JieJu'),
    [switch]$NoShortcut
)

$ErrorActionPreference = 'Stop'
function Remove-DirectoryWithRetry([string]$Path) {
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        try {
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
            return
        }
        catch {
            if ($attempt -eq 20) { throw }
            Start-Sleep -Milliseconds 250
        }
    }
}

$resolvedRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$installDirectory = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot 'JieJu'))
if ((Split-Path $installDirectory -Parent) -ne $resolvedRoot -or (Split-Path $installDirectory -Leaf) -ne 'JieJu') {
    throw "Unsafe installation target: $installDirectory"
}
$installPrefix = $installDirectory.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

$running = Get-Process -Name 'JieJu.Windows' -ErrorAction SilentlyContinue | Where-Object {
    try { $_.Path -and [System.IO.Path]::GetFullPath($_.Path).StartsWith($installPrefix, [System.StringComparison]::OrdinalIgnoreCase) }
    catch { $false }
}
if ($running) { throw 'Close JieJu before uninstalling it.' }

if (-not $NoShortcut) {
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'JieJu.lnk'
    if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath -Force }
}
if (Test-Path -LiteralPath $installDirectory) {
    Set-Location ([System.IO.Path]::GetTempPath())
    Remove-DirectoryWithRetry $installDirectory
}

if ($RemoveUserData) {
    $resolvedData = [System.IO.Path]::GetFullPath($DataDirectory)
    if ((Split-Path $resolvedData -Leaf) -ne 'JieJu') { throw "Unsafe data target: $resolvedData" }
    Remove-DirectoryWithRetry $resolvedData
    Write-Host 'JieJu and its local reading data were removed.'
}
else { Write-Host 'JieJu was removed. Local reading data was kept under %LOCALAPPDATA%\JieJu.' }
