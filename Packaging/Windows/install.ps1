[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs'),
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

$sourceDirectory = [System.IO.Path]::GetFullPath($PSScriptRoot)
$resolvedRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$installDirectory = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot 'JieJu'))
if ((Split-Path $installDirectory -Parent) -ne $resolvedRoot -or (Split-Path $installDirectory -Leaf) -ne 'JieJu') {
    throw "Unsafe installation target: $installDirectory"
}
$installPrefix = $installDirectory.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if ($sourceDirectory -eq $installDirectory -or $sourceDirectory.StartsWith($installPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Run install.ps1 from an extracted package outside the installation directory.'
}

$running = Get-Process -Name 'JieJu.Windows' -ErrorAction SilentlyContinue | Where-Object {
    try { $_.Path -and [System.IO.Path]::GetFullPath($_.Path).StartsWith($installPrefix, [System.StringComparison]::OrdinalIgnoreCase) }
    catch { $false }
}
if ($running) { throw 'Close the installed JieJu application before updating it.' }

Remove-DirectoryWithRetry $installDirectory
New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
Get-ChildItem -LiteralPath $sourceDirectory | Where-Object { $_.Name -notlike '*.WebView2' } |
    Copy-Item -Destination $installDirectory -Recurse -Force

if (-not $NoShortcut) {
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'JieJu.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $installDirectory 'JieJu.Windows.exe'
    $shortcut.WorkingDirectory = $installDirectory
    $shortcut.Description = 'JieJu language-learning reader'
    $shortcut.Save()
}

Write-Host "JieJu installed to: $installDirectory"
Write-Host 'Reading data remains under %LOCALAPPDATA%\JieJu when the application is updated or removed.'
