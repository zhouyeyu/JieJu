[CmdletBinding()]
param(
    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z.-]*$')][string]$Version = '0.1.0-alpha',
    [string]$ArchivePath,
    [switch]$KeepTemporary
)

$ErrorActionPreference = 'Stop'
function Remove-DirectoryWithRetry([string]$Path) {
    for ($attempt = 1; $attempt -le 40; $attempt++) {
        try {
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
            return
        }
        catch {
            if ($attempt -eq 40) { throw }
            Start-Sleep -Milliseconds 250
        }
    }
}

$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $ArchivePath) {
    $ArchivePath = Join-Path $projectRoot "artifacts/packages/JieJu-Windows-x64-$Version.zip"
}
$archive = [System.IO.Path]::GetFullPath($ArchivePath)
$checksum = "$archive.sha256"
$verificationRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'artifacts/package-verification'))
$expectedParent = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'artifacts'))
if ((Split-Path $verificationRoot -Parent) -ne $expectedParent -or (Split-Path $verificationRoot -Leaf) -ne 'package-verification') {
    throw "Unsafe verification directory: $verificationRoot"
}
if (-not (Test-Path -LiteralPath $archive)) { throw "Package archive is missing: $archive" }
if (-not (Test-Path -LiteralPath $checksum)) { throw "Package checksum is missing: $checksum" }

$expectedHash = ((Get-Content -LiteralPath $checksum -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
$actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash) { throw "SHA-256 mismatch: expected $expectedHash, got $actualHash" }

Remove-DirectoryWithRetry $verificationRoot
New-Item -ItemType Directory -Path $verificationRoot -Force | Out-Null

try {
    $extractRoot = Join-Path $verificationRoot 'extracted'
    Expand-Archive -LiteralPath $archive -DestinationPath $extractRoot -Force
    $packageRoot = Join-Path $extractRoot 'JieJu'
    $requiredPaths = @(
        'JieJu.Windows.exe',
        'ReaderHost/index.html',
        'install.ps1',
        'uninstall.ps1',
        'PACKAGE-README.txt',
        'LICENSE.txt',
        'NOTICE.txt',
        'THIRD-PARTY-NOTICES.txt'
    )
    foreach ($relativePath in $requiredPaths) {
        $requiredPath = Join-Path $packageRoot $relativePath
        if (-not (Test-Path -LiteralPath $requiredPath)) { throw "Package entry is missing: $relativePath" }
    }
    if (Get-ChildItem -LiteralPath $packageRoot -Filter '*.WebView2' -Directory -ErrorAction SilentlyContinue) {
        throw 'Package contains WebView2 user data.'
    }

    $installRoot = Join-Path $verificationRoot 'install-root'
    & (Join-Path $packageRoot 'install.ps1') -InstallRoot $installRoot -NoShortcut
    $installedRoot = Join-Path $installRoot 'JieJu'
    $installedExecutable = Join-Path $installedRoot 'JieJu.Windows.exe'
    if (-not (Test-Path -LiteralPath $installedExecutable)) { throw 'Installed executable is missing.' }

    $smokeResult = Join-Path $verificationRoot 'installed-smoke.json'
    $smokeDataDirectory = Join-Path $verificationRoot 'smoke-data'
    $smokeArguments = @('--data-directory', ('"{0}"' -f $smokeDataDirectory), '--smoke-result', ('"{0}"' -f $smokeResult))
    $process = Start-Process -FilePath $installedExecutable -ArgumentList $smokeArguments -WorkingDirectory $installedRoot -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(30000)) {
        $process.Kill()
        throw 'Installed application smoke test timed out.'
    }
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $smokeResult)) {
        throw "Installed application smoke test failed with exit code $($process.ExitCode)."
    }
    $smokeStatus = Get-Content -LiteralPath $smokeResult -Raw | ConvertFrom-Json
    if (-not $smokeStatus.ready) { throw "Installed application did not become ready: $($smokeStatus.detail)" }

    $dataDirectory = Join-Path $verificationRoot 'preserved-data/JieJu'
    New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dataDirectory 'marker.txt') -Value 'keep' -Encoding ASCII
    & (Join-Path $installedRoot 'uninstall.ps1') -InstallRoot $installRoot -DataDirectory $dataDirectory -NoShortcut
    if (Test-Path -LiteralPath $installedRoot) { throw 'Uninstall did not remove the installed application.' }
    if (-not (Test-Path -LiteralPath (Join-Path $dataDirectory 'marker.txt'))) { throw 'Uninstall removed user data without permission.' }

    & (Join-Path $packageRoot 'install.ps1') -InstallRoot $installRoot -NoShortcut
    & (Join-Path $installedRoot 'uninstall.ps1') -InstallRoot $installRoot -DataDirectory $dataDirectory -RemoveUserData -NoShortcut
    if (Test-Path -LiteralPath $installedRoot) { throw 'Second uninstall did not remove the installed application.' }
    if (Test-Path -LiteralPath $dataDirectory) { throw 'Requested user-data removal did not complete.' }

    Write-Host 'Windows package verification passed: checksum, contents, install, launch, uninstall, and data policy.'
}
finally {
    if (-not $KeepTemporary -and (Test-Path -LiteralPath $verificationRoot)) {
        Set-Location $projectRoot
        Remove-DirectoryWithRetry $verificationRoot
    }
}
