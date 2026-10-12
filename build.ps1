[CmdletBinding()]
param(
    [string]$CompilerPath,
    [string]$BasePath,
    [string]$RuntimeLicensePath
)

$ErrorActionPreference = 'Stop'
$projectDirectory = $PSScriptRoot

function Find-RequiredFile {
    param([string]$ExplicitPath, [string[]]$Candidates, [string]$Description)
    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
            throw "$Description not found: $ExplicitPath"
        }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "$Description not found. Supply its path using the corresponding parameter. See README.md."
}

$installationDirectories = @(
    (Join-Path $env:ProgramFiles 'AutoHotkey'),
    (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey')
)
$compilerCandidates = @()
$baseCandidates = @()
foreach ($directory in $installationDirectories) {
    $compilerCandidates += Join-Path $directory 'Compiler\Ahk2Exe.exe'
    $baseCandidates += Join-Path $directory 'v2\AutoHotkey64.exe'
}
$compiler = Find-RequiredFile $CompilerPath $compilerCandidates 'Ahk2Exe'
$base = Find-RequiredFile $BasePath $baseCandidates 'AutoHotkey v2 x64'
$baseVersion = (Get-Item -LiteralPath $base).VersionInfo.FileVersion
if (-not $baseVersion -or [version]$baseVersion -lt [version]'2.0.19' -or [version]$baseVersion -ge [version]'3.0') {
    throw "The base must be AutoHotkey v2.0.19 or later in the v2 series. Found: $baseVersion"
}
$baseReader = [System.IO.BinaryReader]::new([System.IO.File]::OpenRead($base))
try {
    $baseReader.BaseStream.Position = 0x3c
    $peOffset = $baseReader.ReadInt32()
    $baseReader.BaseStream.Position = $peOffset
    if ($baseReader.ReadUInt32() -ne 0x00004550 -or $baseReader.ReadUInt16() -ne 0x8664) {
        throw 'The base must be an x64 PE executable. Use AutoHotkey64.exe.'
    }
} finally {
    $baseReader.Dispose()
}

# Resolve the selected runtime's license before creating release files.
$runtimeDirectory = Split-Path -Parent $base
$ahkLicenseCandidates = @((Join-Path $runtimeDirectory 'license.txt'),
    (Join-Path (Split-Path -Parent $runtimeDirectory) 'license.txt'))
$runtimeLicense = Find-RequiredFile $RuntimeLicensePath $ahkLicenseCandidates 'AutoHotkey runtime license (-RuntimeLicensePath)'

$outputDirectory = Join-Path $projectDirectory 'dist'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$source = Join-Path $projectDirectory 'Bloodlines.ahk'
$destination = Join-Path $outputDirectory 'MarcoBloodlines.exe'
$icon = Join-Path $projectDirectory 'assets\marco.ico'
$buildStarted = [DateTime]::UtcNow

Push-Location -LiteralPath $projectDirectory
try {
    # Wait for the GUI compiler; the resulting application is not launched.
    # Embedded quotes are necessary for native tools when directory names contain spaces.
    $arguments = @('/in', ('"' + $source + '"'), '/out', ('"' + $destination + '"'),
        '/base', ('"' + $base + '"'), '/icon', ('"' + $icon + '"'), '/cp', '65001', '/compress', '0', '/silent', 'verbose')
    $buildOutput = Join-Path $outputDirectory 'build-output.log'
    $buildErrors = Join-Path $outputDirectory 'build-errors.log'
    $process = Start-Process -FilePath $compiler -ArgumentList $arguments -WorkingDirectory $projectDirectory -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $buildOutput -RedirectStandardError $buildErrors
    if ($process.ExitCode -ne 0) {
        throw "Ahk2Exe exited with code $($process.ExitCode). See $buildErrors and $buildOutput."
    }
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or
        (Get-Item -LiteralPath $destination).LastWriteTimeUtc -lt $buildStarted.AddSeconds(-2)) {
        throw 'The compiler did not produce an updated executable.'
    }

    Copy-Item -LiteralPath (Join-Path $projectDirectory 'README.md'), (Join-Path $projectDirectory 'LICENSE'), (Join-Path $projectDirectory 'THIRD_PARTY.md') -Destination $outputDirectory -Force
    $licenseDirectory = Join-Path $outputDirectory 'licenses'
    New-Item -ItemType Directory -Path $licenseDirectory -Force | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $projectDirectory 'vendor\licenses') -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $licenseDirectory -Force
    }
    Copy-Item -LiteralPath $runtimeLicense -Destination (Join-Path $licenseDirectory 'AutoHotkey-license.txt') -Force
    $runtimeHash = (Get-FileHash -LiteralPath $base -Algorithm SHA256).Hash
    $parsedVersion = [version]$baseVersion
    $runtimeTag = if ($parsedVersion.Revision -gt 0) { 'v' + $parsedVersion.ToString() } else { 'v' + $parsedVersion.ToString(3) }
    $sourceNotice = @"
AutoHotkey runtime
Version: $baseVersion
Architecture: x64
SHA-256: $runtimeHash
Project: https://github.com/AutoHotkey/AutoHotkey
Source: https://github.com/AutoHotkey/AutoHotkey/tree/$runtimeTag
Source archive: https://github.com/AutoHotkey/AutoHotkey/archive/refs/tags/$runtimeTag.zip
License: AutoHotkey-license.txt

Provide the corresponding AutoHotkey source alongside redistributed releases.
For a custom runtime build, provide its actual source and build instructions.
"@
    [System.IO.File]::WriteAllText((Join-Path $licenseDirectory 'AutoHotkey-SOURCE.txt'), $sourceNotice + "`r`n", [System.Text.UTF8Encoding]::new($false))
    Write-Output "Build complete: $destination"
    Write-Output 'Interface resources, icon and WebView2 loader are embedded in the executable.'
} finally {
    Pop-Location
}
