[CmdletBinding()]
param(
    [string]$DotNetPath = 'dotnet',
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [switch]$Smoke
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$windowsRoot = Join-Path $projectRoot 'Apps/Windows'
if (-not (Get-Command $DotNetPath -ErrorAction SilentlyContinue)) {
    $localSdk = Join-Path $env:LOCALAPPDATA 'JieJuBuild/dotnet/dotnet.exe'
    if ($DotNetPath -eq 'dotnet' -and (Test-Path $localSdk)) { $DotNetPath = $localSdk }
    else { throw 'Install the .NET SDK specified in Apps/Windows/global.json or pass -DotNetPath.' }
}

Push-Location $windowsRoot
try {
    $nodeTests = @(Get-ChildItem "$projectRoot/Shared/Contracts/Tests/*.test.mjs", "$projectRoot/Shared/ReaderWeb/Tests/*.test.mjs" | ForEach-Object FullName)
    & node --test @nodeTests
    if ($LASTEXITCODE -ne 0) { throw 'Shared contract/Bridge tests failed.' }
    & $DotNetPath restore JieJu.Windows.sln --locked-mode
    if ($LASTEXITCODE -ne 0) { throw 'Windows dependency restore failed.' }
    & $DotNetPath build JieJu.Windows.sln -c $Configuration -p:Platform=x64 --no-restore
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
    & $DotNetPath test JieJu.Windows.Tests/JieJu.Windows.Tests.csproj -c $Configuration --no-restore
    if ($LASTEXITCODE -ne 0) { throw 'Windows tests failed.' }
    if ($Smoke) {
        $exe = Join-Path $windowsRoot "JieJu.Windows/bin/x64/$Configuration/net10.0-windows10.0.19041.0/win-x64/JieJu.Windows.exe"
        $result = Join-Path ([System.IO.Path]::GetTempPath()) ("jieju-smoke-{0}.json" -f [guid]::NewGuid())
        $process = Start-Process -FilePath $exe -ArgumentList @('--smoke-result', ('"{0}"' -f $result)) -PassThru -WindowStyle Hidden
        try {
            if (-not $process.WaitForExit(45000)) { throw 'WebView2 smoke test timed out after 45 seconds.' }
            if ($process.ExitCode -ne 0) { throw "App exited with code $($process.ExitCode)." }
            if (-not (Test-Path $result)) { throw 'App did not report WebView2 readiness.' }
            $status = Get-Content -Raw $result | ConvertFrom-Json
            if (-not $status.ready) { throw "WebView2 startup failed: $($status.detail)" }
            Write-Host "WinUI + shared Reader Bridge ready. WebView2 $($status.detail)"
        }
        finally {
            if (-not $process.HasExited) { Stop-Process -Id $process.Id }
            if (Test-Path $result) { Remove-Item -LiteralPath $result }
        }
    }
}
finally { Pop-Location }
