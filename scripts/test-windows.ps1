[CmdletBinding()]
param(
    [string]$DotNetPath = 'dotnet',
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [switch]$Smoke,
    [switch]$OllamaSmoke,
    [switch]$VocabularySmoke,
    [switch]$DeepSmoke,
    [switch]$PopupSmoke,
    [switch]$FuriganaSmoke,
    [switch]$JapaneseDeepSmoke,
    [switch]$CloudSettingsSmoke,
    [switch]$SettingsPreviewSmoke,
    [switch]$PaginationSmoke,
    [switch]$ReviewSmoke,
    [switch]$PdfSmoke,
    [switch]$PdfLearningSmoke
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$windowsRoot = Join-Path $projectRoot 'Apps/Windows'

function Remove-DirectoryWithRetry([string]$Path) {
    for ($attempt = 1; $attempt -le 40; $attempt++) {
        try {
            if ([System.IO.Directory]::Exists($Path)) { [System.IO.Directory]::Delete($Path, $true) }
            return
        }
        catch {
            if ($attempt -eq 40) { throw }
            Start-Sleep -Milliseconds 250
        }
    }
}

function New-SmokeEpub([string]$Path, [bool]$Japanese = $false, [bool]$Long = $false) {
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew)
    try {
        $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            $files = [ordered]@{
                'META-INF/container.xml' = '<container><rootfiles><rootfile full-path="OPS/package.opf"/></rootfiles></container>'
                'OPS/package.opf' = if ($Japanese) { '<package><metadata><title>Windows EPUB Smoke</title><language>ja</language></metadata><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="one"/></spine></package>' } else { '<package><metadata><title>Windows EPUB Smoke</title><language>zh-CN</language></metadata><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="one"/></spine></package>' }
                'OPS/one.xhtml' = if ($Long) {
                    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章</title></head><body><h1>第一章</h1>' + ((1..180 | ForEach-Object { "<p>Pagination paragraph $_ keeps enough text on every page for stable reflow verification.</p>" }) -join '') + '</body></html>'
                } elseif ($Japanese) { '<html xmlns="http://www.w3.org/1999/xhtml" lang="ja"><head><title>第一章</title></head><body><h1>第一章</h1><p>彼女は学校で本を読んでいます。</p></body></html>' } else { '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章</title></head><body><h1>第一章</h1><p>她正在<ruby>读书<rt>どくしょ</rt></ruby>。</p></body></html>' }
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

function New-SmokePdf([string]$Path) {
    $encoding = [System.Text.Encoding]::ASCII
    $firstPage = "BT /F1 24 Tf 72 720 Td (JieJu PDF smoke page one) Tj ET"
    $secondPage = "BT /F1 24 Tf 72 720 Td (JieJu PDF learning smoke page two) Tj ET"
    $objects = @(
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 6 0 R >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 7 0 R >>',
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
        ("<< /Length {0} >>`nstream`n{1}`nendstream" -f $firstPage.Length, $firstPage),
        ("<< /Length {0} >>`nstream`n{1}`nendstream" -f $secondPage.Length, $secondPage)
    )
    $pdf = "%PDF-1.4`n"
    $offsets = @()
    for ($index = 0; $index -lt $objects.Count; $index++) {
        $offsets += $encoding.GetByteCount($pdf)
        $pdf += ("{0} 0 obj`n{1}`nendobj`n" -f ($index + 1), $objects[$index])
    }
    $xref = $encoding.GetByteCount($pdf)
    $pdf += "xref`n0 8`n0000000000 65535 f `n"
    foreach ($offset in $offsets) { $pdf += ("{0:D10} 00000 n `n" -f $offset) }
    $pdf += ("trailer`n<< /Size 8 /Root 1 0 R >>`nstartxref`n{0}`n%%EOF`n" -f $xref)
    [System.IO.File]::WriteAllBytes($Path, $encoding.GetBytes($pdf))
}

function Invoke-AppSmoke([string]$Exe, [string]$Result, [string[]]$ExtraArguments, [string]$Label) {
    $automaticDataDirectory = $null
    if ($ExtraArguments -notcontains '--data-directory') {
        $automaticDataDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("jieju-app-smoke-{0}" -f [guid]::NewGuid())
        [System.IO.Directory]::CreateDirectory($automaticDataDirectory) | Out-Null
        $ExtraArguments = @($ExtraArguments) + @('--data-directory', ('"{0}"' -f $automaticDataDirectory))
    }
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
        if ($automaticDataDirectory) {
            $resolvedAutomaticDirectory = [System.IO.Path]::GetFullPath($automaticDataDirectory)
            $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
            if ($resolvedAutomaticDirectory.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and [System.IO.Directory]::Exists($resolvedAutomaticDirectory)) {
                Remove-DirectoryWithRetry $resolvedAutomaticDirectory
            }
        }
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
        $welcomeArguments = $CloudSettingsSmoke ? @('--smoke-cloud-settings') : @()
        Invoke-AppSmoke $exe $result $welcomeArguments ($CloudSettingsSmoke ? 'Cloud provider settings' : 'WinUI + shared Reader Bridge')
        if ($ReviewSmoke) {
            $reviewDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("jieju-review-smoke-{0}" -f [guid]::NewGuid())
            $reviewResult = Join-Path ([System.IO.Path]::GetTempPath()) ("jieju-review-smoke-{0}.json" -f [guid]::NewGuid())
            try {
                [System.IO.Directory]::CreateDirectory($reviewDirectory) | Out-Null
                Invoke-AppSmoke $exe $reviewResult @('--smoke-review', '--data-directory', ('"{0}"' -f $reviewDirectory)) 'Review recognition-card flow'
            }
            finally {
                $resolvedReviewDirectory = [System.IO.Path]::GetFullPath($reviewDirectory)
                $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
                if ($resolvedReviewDirectory.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and [System.IO.Directory]::Exists($resolvedReviewDirectory)) {
                    [System.IO.Directory]::Delete($resolvedReviewDirectory, $true)
                }
            }
        }
        if ($PdfSmoke -or $PdfLearningSmoke) {
            $pdf = Join-Path ([System.IO.Path]::GetTempPath()) ("jieju-pdf-smoke-{0}.pdf" -f [guid]::NewGuid())
            $pdfResult = Join-Path ([System.IO.Path]::GetTempPath()) ("jieju-pdf-smoke-{0}.json" -f [guid]::NewGuid())
            $pdfDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("jieju-pdf-data-{0}" -f [guid]::NewGuid())
            try {
                [System.IO.Directory]::CreateDirectory($pdfDirectory) | Out-Null
                New-SmokePdf $pdf
                $pdfArguments = @('--open', ('"{0}"' -f $pdf), '--smoke-pdf', '--data-directory', ('"{0}"' -f $pdfDirectory))
                if ($PdfLearningSmoke) { $pdfArguments += @('--smoke-pdf-learning', '--smoke-mock-ai', '--smoke-pdf-page', '1') }
                Invoke-AppSmoke $exe $pdfResult $pdfArguments ($PdfLearningSmoke ? 'PDF learning save and source-return flow' : 'Restricted local PDF reader')
            }
            finally {
                if (Test-Path $pdf) { Remove-Item -LiteralPath $pdf }
                $resolvedPdfDirectory = [System.IO.Path]::GetFullPath($pdfDirectory)
                $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
                if ($resolvedPdfDirectory.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and [System.IO.Directory]::Exists($resolvedPdfDirectory)) {
                    [System.IO.Directory]::Delete($resolvedPdfDirectory, $true)
                }
            }
        }
        $epub = Join-Path ([System.IO.Path]::GetTempPath()) ("jieju-epub-smoke-{0}.epub" -f [guid]::NewGuid())
        try {
            New-SmokeEpub $epub ($FuriganaSmoke -or $JapaneseDeepSmoke) $PaginationSmoke
            $epubResult = Join-Path ([System.IO.Path]::GetTempPath()) ("jieju-epub-smoke-{0}.json" -f [guid]::NewGuid())
            $epubArguments = @('--open', ('"{0}"' -f $epub), '--smoke-selection')
            if ($PopupSmoke) { $epubArguments += '--smoke-popup' }
            if ($SettingsPreviewSmoke) { $epubArguments += '--smoke-reading-settings' }
            if ($PaginationSmoke) { $epubArguments += '--smoke-pagination' }
            if ($FuriganaSmoke) { $epubArguments += '--smoke-furigana' }
            if ($JapaneseDeepSmoke) { $epubArguments += @('--smoke-inference', '--smoke-deep') }
            if ($VocabularySmoke) { $epubArguments += '--smoke-word' }
            elseif ($DeepSmoke) { $epubArguments += @('--smoke-inference', '--smoke-deep') }
            elseif ($OllamaSmoke) { $epubArguments += '--smoke-inference' }
            $label = $PaginationSmoke ? 'EPUB horizontal pagination and reflow' : ($SettingsPreviewSmoke ? 'EPUB live reading settings and preview' : ($FuriganaSmoke ? 'EPUB local Japanese furigana' : ($JapaneseDeepSmoke ? 'EPUB local Japanese deep analysis' : ($VocabularySmoke ? 'EPUB selection and local Ollama vocabulary inference' : ($DeepSmoke ? 'EPUB selection and local Ollama deep analysis' : ($OllamaSmoke ? 'EPUB selection and local Ollama inference' : ($PopupSmoke ? 'EPUB selection and popup explanation panel' : 'EPUB selection and explanation panel')))))))
            Invoke-AppSmoke $exe $epubResult $epubArguments $label
        }
        finally { if (Test-Path $epub) { Remove-Item -LiteralPath $epub } }
    }
}
finally { Pop-Location }
