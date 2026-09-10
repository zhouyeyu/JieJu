[CmdletBinding()]
param(
    [string]$DotNetPath = 'dotnet',
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [switch]$Smoke,
    [switch]$OllamaSmoke,
    [switch]$VocabularySmoke,
    [switch]$DeepSmoke,
    [switch]$PopupSmoke,
    [switch]$FuriganaSmoke
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$windowsRoot = Join-Path $projectRoot 'Apps/Windows'

function New-SmokeEpub([string]$Path, [bool]$Japanese = $false) {
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew)
    try {
        $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            $files = [ordered]@{
                'META-INF/container.xml' = '<container><rootfiles><rootfile full-path="OPS/package.opf"/></rootfiles></container>'
                'OPS/package.opf' = if ($Japanese) { '<package><metadata><title>Windows EPUB Smoke</title><language>ja</language></metadata><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="one"/></spine></package>' } else { '<package><metadata><title>Windows EPUB Smoke</title><language>zh-CN</language></metadata><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="one"/></spine></package>' }
                'OPS/one.xhtml' = if ($Japanese) { '<html xmlns="http://www.w3.org/1999/xhtml" lang="ja"><head><title>第一章</title></head><body><h1>第一章</h1><p>彼女は学校で本を読んでいます。</p></body></html>' } else { '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章</title></head><body><h1>第一章</h1><p>她正在<ruby>读书<rt>どくしょ</rt></ruby>。</p></body></html>' }
            }
            foreach ($pair in $files.GetEnumerator()) {
                $writer = [System.IO.StreamWriter]::new($archive.CreateEntry($pair.Key).Open(), [System.Text.UTF8Encoding]::new($false))
                try { $writer.Write($pair.Value) } finally { $writer.Dispose() }
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Invoke-AppSmoke([string]$Exe, [string]$Result, [string[]]$ExtraArguments, [string]$Label) {
    $arguments = @($ExtraArguments) + @('--smoke-result', ('"{0}"' -f $Result))
    $process = Start-Process -FilePath $Exe -ArgumentList $arguments -PassThru -WindowStyle Hidden
    try {
        if (-not $process.WaitForExit(45000)) { throw "$Label timed out after 45 seconds." }
        if ($process.ExitCode -ne 0) { throw "$Label exited with code $($process.ExitCode)." }
        if (-not (Test-Path $Result)) { throw "$Label did not report WebView2 readiness." }
        $status = Get-Content -Raw $Result | ConvertFrom-Json
        if (-not $status.ready) { throw "$Label failed: $($status.detail)" }
        Write-Host "$Label ready. WebView2 $($status.detail)"
    }
    finally {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id }
        if (Test-Path $Result) { Remove-Item -LiteralPath $Result }
    }
}
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
        Invoke-AppSmoke $exe $result @() 'WinUI + shared Reader Bridge'
        $epub = Join-Path ([System.IO.Path]::GetTempPath()) ("jieju-epub-smoke-{0}.epub" -f [guid]::NewGuid())
        try {
            New-SmokeEpub $epub $FuriganaSmoke
            $epubResult = Join-Path ([System.IO.Path]::GetTempPath()) ("jieju-epub-smoke-{0}.json" -f [guid]::NewGuid())
            $epubArguments = @('--open', ('"{0}"' -f $epub), '--smoke-selection')
            if ($PopupSmoke) { $epubArguments += '--smoke-popup' }
            if ($FuriganaSmoke) { $epubArguments += '--smoke-furigana' }
            if ($VocabularySmoke) { $epubArguments += '--smoke-word' }
            elseif ($DeepSmoke) { $epubArguments += @('--smoke-inference', '--smoke-deep') }
            elseif ($OllamaSmoke) { $epubArguments += '--smoke-inference' }
            $label = $FuriganaSmoke ? 'EPUB local Japanese furigana' : ($VocabularySmoke ? 'EPUB selection and local Ollama vocabulary inference' : ($DeepSmoke ? 'EPUB selection and local Ollama deep analysis' : ($OllamaSmoke ? 'EPUB selection and local Ollama inference' : ($PopupSmoke ? 'EPUB selection and popup explanation panel' : 'EPUB selection and explanation panel'))))
            Invoke-AppSmoke $exe $epubResult $epubArguments $label
        }
        finally { if (Test-Path $epub) { Remove-Item -LiteralPath $epub } }
    }
}
finally { Pop-Location }
