[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DriverUrl,

    [Parameter(Mandatory = $true)]
    [string]$CudaUrl,

    [string[]]$ToolkitDebUrls = @(),

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

function Get-FileNameFromUrl {
    param([string]$Url)
    $uri = [System.Uri]$Url
    $name = [System.IO.Path]::GetFileName($uri.AbsolutePath)
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw "Unable to infer filename from URL: $Url"
    }
    return $name
}

function Download-ToPath {
    param(
        [string]$Url,
        [string]$Path
    )
    Write-Host "Downloading: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Path
}

if (-not (Test-Path -LiteralPath $Destination)) {
    New-Item -ItemType Directory -Path $Destination | Out-Null
}

$destRoot = (Resolve-Path -LiteralPath $Destination).Path
$toolkitDest = Join-Path $destRoot 'toolkit-debs'

$driverName = Get-FileNameFromUrl -Url $DriverUrl
$cudaName = Get-FileNameFromUrl -Url $CudaUrl

Download-ToPath -Url $DriverUrl -Path (Join-Path $destRoot $driverName)
Download-ToPath -Url $CudaUrl -Path (Join-Path $destRoot $cudaName)

if ($ToolkitDebUrls.Count -gt 0) {
    if (-not (Test-Path -LiteralPath $toolkitDest)) {
        New-Item -ItemType Directory -Path $toolkitDest | Out-Null
    }

    foreach ($url in $ToolkitDebUrls) {
        $debName = Get-FileNameFromUrl -Url $url
        Download-ToPath -Url $url -Path (Join-Path $toolkitDest $debName)
    }
}

Write-Host "Downloaded offline packages to: $destRoot"
