[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DriverRunfile,

    [Parameter(Mandatory = $true)]
    [string]$CudaRunfile,

    [string]$ToolkitDebDir = '',

    [string]$Destination = ''
)

$ErrorActionPreference = 'Stop'

$ScriptBase = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
} else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}

if ([string]::IsNullOrWhiteSpace($Destination)) {
    $Destination = Join-Path (Join-Path $ScriptBase '..') 'offline\nvidia'
}

function Resolve-ExistingFile {
    param([string]$PathValue)
    if (-not (Test-Path -LiteralPath $PathValue -PathType Leaf)) {
        throw "File not found: $PathValue"
    }
    return (Resolve-Path -LiteralPath $PathValue).Path
}

function Copy-And-Hash {
    param(
        [string]$SourceFile,
        [string]$TargetDir
    )

    $targetFile = Join-Path $TargetDir ([System.IO.Path]::GetFileName($SourceFile))
    Copy-Item -LiteralPath $SourceFile -Destination $targetFile -Force

    $hash = Get-FileHash -LiteralPath $targetFile -Algorithm SHA256
    return "{0}  {1}" -f $hash.Hash.ToLowerInvariant(), ([System.IO.Path]::GetFileName($targetFile))
}

$driverPath = Resolve-ExistingFile -PathValue $DriverRunfile
$cudaPath = Resolve-ExistingFile -PathValue $CudaRunfile

if (-not (Test-Path -LiteralPath $Destination)) {
    New-Item -ItemType Directory -Path $Destination | Out-Null
}

$destRoot = (Resolve-Path -LiteralPath $Destination).Path
$toolkitDest = Join-Path $destRoot 'toolkit-debs'

$lines = @()
$lines += Copy-And-Hash -SourceFile $driverPath -TargetDir $destRoot
$lines += Copy-And-Hash -SourceFile $cudaPath -TargetDir $destRoot

if (-not [string]::IsNullOrWhiteSpace($ToolkitDebDir)) {
    if (-not (Test-Path -LiteralPath $ToolkitDebDir -PathType Container)) {
        throw "Toolkit deb directory not found: $ToolkitDebDir"
    }

    if (-not (Test-Path -LiteralPath $toolkitDest)) {
        New-Item -ItemType Directory -Path $toolkitDest | Out-Null
    }

    $debFiles = Get-ChildItem -LiteralPath $ToolkitDebDir -Filter *.deb -File
    if ($debFiles.Count -eq 0) {
        throw "No .deb files found in ToolkitDebDir: $ToolkitDebDir"
    }

    foreach ($deb in $debFiles) {
        $lines += Copy-And-Hash -SourceFile $deb.FullName -TargetDir $toolkitDest
    }
}

$shaPath = Join-Path $destRoot 'SHA256SUMS.txt'
Set-Content -LiteralPath $shaPath -Value $lines -Encoding utf8

Write-Host "Staged offline NVIDIA/CUDA files to: $destRoot"
Write-Host "Checksum manifest: $shaPath"
