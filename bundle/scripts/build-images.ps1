[CmdletBinding()]
param(
    [ValidateSet('all', 'openwebui', 'proxy', 'ragflow', 'deps', 'vllm', 'tei')]
    [string[]]$Component = @('all'),

    [ValidateSet('auto', 'source', 'pull')]
    [string]$OpenWebUIBuildMode = 'auto',

    [ValidateSet('auto', 'source', 'pull')]
    [string]$VLLMBuildMode = 'auto',

    [switch]$AllowPullFallback,

    [string]$ReleaseTag = (Get-Date -Format 'yyyyMMdd-HHmmss')
)

$ErrorActionPreference = 'Stop'

$bundleRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$imagesDir = Join-Path $bundleRoot 'images'
$reposDir = Resolve-Path (Join-Path $bundleRoot '..\repos')
$infraDir = Resolve-Path (Join-Path $bundleRoot '..\infra')

$indexPath = Join-Path $imagesDir 'index.tsv'

$openwebuiRepo = Join-Path $reposDir 'openwebui'
$proxyDir = Join-Path $infraDir 'ragflow-openai-proxy'
$vllmRepo = Join-Path $reposDir 'vllm'

$ragflowEnvPath = Join-Path $bundleRoot 'compose\ragflow\.env'
$openwebuiEnvPath = Join-Path $bundleRoot 'compose\openwebui\.env'

$OPENWEBUI_UPSTREAM_IMAGE = 'ghcr.io/open-webui/open-webui:v0.7.2'
$OPENWEBUI_STABLE_IMAGE = 'forstar/openwebui:offline'
$OPENWEBUI_RELEASE_IMAGE = "forstar/openwebui:$ReleaseTag"
$OPENWEBUI_GATEWAY_IMAGE = 'nginx:1.27-alpine'

$PROXY_STABLE_IMAGE = 'forstar/ragflow-openai-proxy:offline'
$PROXY_RELEASE_IMAGE = "forstar/ragflow-openai-proxy:$ReleaseTag"

$VLLM_UPSTREAM_IMAGE = 'vllm/vllm-openai:latest'
$VLLM_STABLE_IMAGE = 'forstar/vllm-openai:offline'
$VLLM_RELEASE_IMAGE = "forstar/vllm-openai:$ReleaseTag"

$VLLM_DOCKERFILE = if ($env:VLLM_DOCKERFILE) { $env:VLLM_DOCKERFILE } else { 'docker/Dockerfile' }
$VLLM_BUILD_CONTEXT = if ($env:VLLM_BUILD_CONTEXT) { $env:VLLM_BUILD_CONTEXT } else { $vllmRepo }
$VLLM_CUDA_VERSION = if ($env:VLLM_CUDA_VERSION) { $env:VLLM_CUDA_VERSION } else { '' }
$VLLM_PYTHON_VERSION = if ($env:VLLM_PYTHON_VERSION) { $env:VLLM_PYTHON_VERSION } else { '' }

function Get-DotEnvValue {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Default
    )

    if (-not (Test-Path $Path)) {
        return $Default
    }

    $line = Get-Content $Path | Where-Object { $_ -match "^$Name=" } | Select-Object -First 1
    if (-not $line) {
        return $Default
    }

    $value = ($line -split '=', 2)[1]
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }

    return $value.Trim()
}

$RAGFLOW_IMAGE = Get-DotEnvValue -Path $ragflowEnvPath -Name 'RAGFLOW_IMAGE' -Default 'infiniflow/ragflow:v0.23.1'
$TEI_IMAGE_CPU = Get-DotEnvValue -Path $ragflowEnvPath -Name 'TEI_IMAGE_CPU' -Default 'infiniflow/text-embeddings-inference:cpu-1.8'
$TEI_IMAGE_GPU = Get-DotEnvValue -Path $ragflowEnvPath -Name 'TEI_IMAGE_GPU' -Default 'infiniflow/text-embeddings-inference:1.8'
$OPENWEBUI_BASE_PATH = Get-DotEnvValue -Path $openwebuiEnvPath -Name 'OPENWEBUI_BASE_PATH' -Default ''

$MYSQL_IMAGE = 'mysql:8.0.39'
$MINIO_IMAGE = 'quay.io/minio/minio:RELEASE.2025-06-13T11-33-47Z'
$VALKEY_IMAGE = 'valkey/valkey:8'
$ELASTIC_IMAGE = 'elasticsearch:8.11.3'

$allComponents = @('openwebui', 'proxy', 'ragflow', 'deps', 'vllm', 'tei')
$requested = if ($Component -contains 'all') {
    $allComponents
} else {
    $Component | Select-Object -Unique
}

function Invoke-Docker {
    param([string[]]$DockerArgs)

    & docker @DockerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Docker command failed: docker $($DockerArgs -join ' ')"
    }
}

function Resolve-BuildMode {
    param(
        [string]$Mode,
        [bool]$SourceAvailable
    )

    if ($Mode -eq 'source' -and -not $SourceAvailable) {
        throw 'Build mode set to source, but local source path is missing.'
    }

    if ($Mode -eq 'auto') {
        if ($SourceAvailable) {
            return 'source'
        }
        return 'pull'
    }

    return $Mode
}

function Save-ImageTar {
    param(
        [string]$ComponentName,
        [string]$StableImage,
        [string]$ReleaseImage
    )

    $safeStable = ($StableImage -replace '[/:]', '_')
    $fileName = "${ComponentName}__${safeStable}__${ReleaseTag}.tar"
    $tarPath = Join-Path $imagesDir $fileName

    $saveArgs = @('save', '-o', $tarPath, $StableImage)
    if ($ReleaseImage -and $ReleaseImage -ne $StableImage) {
        $saveArgs += $ReleaseImage
    }

    Write-Host "Saving $StableImage -> $tarPath"
    Invoke-Docker -DockerArgs $saveArgs

    return $fileName
}

function Upsert-IndexRows {
    param(
        [array]$Rows,
        [array]$Updates
    )

    $map = @{}

    foreach ($row in $Rows) {
        $key = "$($row.component)|$($row.stable_image)"
        $map[$key] = $row
    }

    foreach ($row in $Updates) {
        $key = "$($row.component)|$($row.stable_image)"
        $map[$key] = $row
    }

    return $map.Values | Sort-Object component, stable_image
}

function Read-IndexRows {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return @()
    }

    $rows = @()
    $lines = Get-Content $Path
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('component')) {
            continue
        }

        $parts = $line -split "`t", 6
        if ($parts.Count -lt 6) {
            continue
        }

        $rows += [pscustomobject]@{
            component = $parts[0]
            tar_file = $parts[1]
            stable_image = $parts[2]
            release_image = $parts[3]
            release_tag = $parts[4]
            updated_at = $parts[5]
        }
    }

    return $rows
}

function Write-IndexRows {
    param(
        [string]$Path,
        [array]$Rows
    )

    $header = 'component' + "`t" + 'tar_file' + "`t" + 'stable_image' + "`t" + 'release_image' + "`t" + 'release_tag' + "`t" + 'updated_at'
    $lines = @($header)

    foreach ($row in $Rows) {
        $line = @(
            $row.component,
            $row.tar_file,
            $row.stable_image,
            $row.release_image,
            $row.release_tag,
            $row.updated_at
        ) -join "`t"
        $lines += $line
    }

    Set-Content -Path $Path -Value $lines
}

if (-not (Test-Path $imagesDir)) {
    New-Item -ItemType Directory -Path $imagesDir | Out-Null
}

$existingRows = Read-IndexRows -Path $indexPath

$indexUpdates = @()
$timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')

if ($requested -contains 'openwebui') {
    $sourceAvailable = Test-Path (Join-Path $openwebuiRepo 'Dockerfile')
    $mode = Resolve-BuildMode -Mode $OpenWebUIBuildMode -SourceAvailable $sourceAvailable

    if ($mode -eq 'source') {
        try {
            Write-Host "Building OpenWebUI from local source: $openwebuiRepo"
            Invoke-Docker -DockerArgs @(
                'build',
                '--build-arg',
                "WEBUI_BASE_PATH=$OPENWEBUI_BASE_PATH",
                '-t',
                $OPENWEBUI_RELEASE_IMAGE,
                $openwebuiRepo
            )
        } catch {
            if (-not $AllowPullFallback) {
                throw
            }
            Write-Warning "OpenWebUI source build failed. Falling back to pull: $OPENWEBUI_UPSTREAM_IMAGE"
            Invoke-Docker -DockerArgs @('pull', $OPENWEBUI_UPSTREAM_IMAGE)
            Invoke-Docker -DockerArgs @('tag', $OPENWEBUI_UPSTREAM_IMAGE, $OPENWEBUI_RELEASE_IMAGE)
        }
    } else {
        Write-Host "Pulling OpenWebUI image: $OPENWEBUI_UPSTREAM_IMAGE"
        Invoke-Docker -DockerArgs @('pull', $OPENWEBUI_UPSTREAM_IMAGE)
        Invoke-Docker -DockerArgs @('tag', $OPENWEBUI_UPSTREAM_IMAGE, $OPENWEBUI_RELEASE_IMAGE)
    }

    Invoke-Docker -DockerArgs @('tag', $OPENWEBUI_RELEASE_IMAGE, $OPENWEBUI_STABLE_IMAGE)
    $tar = Save-ImageTar -ComponentName 'openwebui' -StableImage $OPENWEBUI_STABLE_IMAGE -ReleaseImage $OPENWEBUI_RELEASE_IMAGE

    $indexUpdates += [pscustomobject]@{
        component = 'openwebui'
        tar_file = $tar
        stable_image = $OPENWEBUI_STABLE_IMAGE
        release_image = $OPENWEBUI_RELEASE_IMAGE
        release_tag = $ReleaseTag
        updated_at = $timestamp
    }

    Write-Host "Pulling OpenWebUI gateway image: $OPENWEBUI_GATEWAY_IMAGE"
    Invoke-Docker -DockerArgs @('pull', $OPENWEBUI_GATEWAY_IMAGE)
    $gatewayTar = Save-ImageTar -ComponentName 'openwebui' -StableImage $OPENWEBUI_GATEWAY_IMAGE -ReleaseImage $OPENWEBUI_GATEWAY_IMAGE

    $indexUpdates += [pscustomobject]@{
        component = 'openwebui'
        tar_file = $gatewayTar
        stable_image = $OPENWEBUI_GATEWAY_IMAGE
        release_image = $OPENWEBUI_GATEWAY_IMAGE
        release_tag = $ReleaseTag
        updated_at = $timestamp
    }
}

if ($requested -contains 'proxy') {
    Write-Host "Building RAGFlow proxy from local source: $proxyDir"
    Invoke-Docker -DockerArgs @('build', '-t', $PROXY_RELEASE_IMAGE, $proxyDir)
    Invoke-Docker -DockerArgs @('tag', $PROXY_RELEASE_IMAGE, $PROXY_STABLE_IMAGE)

    $tar = Save-ImageTar -ComponentName 'proxy' -StableImage $PROXY_STABLE_IMAGE -ReleaseImage $PROXY_RELEASE_IMAGE

    $indexUpdates += [pscustomobject]@{
        component = 'proxy'
        tar_file = $tar
        stable_image = $PROXY_STABLE_IMAGE
        release_image = $PROXY_RELEASE_IMAGE
        release_tag = $ReleaseTag
        updated_at = $timestamp
    }
}

if ($requested -contains 'vllm') {
    $dockerfilePath = if ([System.IO.Path]::IsPathRooted($VLLM_DOCKERFILE)) {
        $VLLM_DOCKERFILE
    } else {
        Join-Path $vllmRepo $VLLM_DOCKERFILE
    }

    $sourceAvailable = (Test-Path $vllmRepo) -and (Test-Path $dockerfilePath)
    $mode = Resolve-BuildMode -Mode $VLLMBuildMode -SourceAvailable $sourceAvailable

    if ($mode -eq 'source') {
        try {
            Write-Host "Building vLLM from local source: $VLLM_BUILD_CONTEXT"

            $vllmBuildArgs = @('build', '-t', $VLLM_RELEASE_IMAGE, '-f', $dockerfilePath)
            if (-not [string]::IsNullOrWhiteSpace($VLLM_CUDA_VERSION)) {
                $vllmBuildArgs += @('--build-arg', "CUDA_VERSION=$VLLM_CUDA_VERSION")
            }
            if (-not [string]::IsNullOrWhiteSpace($VLLM_PYTHON_VERSION)) {
                $vllmBuildArgs += @('--build-arg', "PYTHON_VERSION=$VLLM_PYTHON_VERSION")
            }
            $vllmBuildArgs += $VLLM_BUILD_CONTEXT

            Invoke-Docker -DockerArgs $vllmBuildArgs
        } catch {
            if (-not $AllowPullFallback) {
                throw
            }
            Write-Warning "vLLM source build failed. Falling back to pull: $VLLM_UPSTREAM_IMAGE"
            Invoke-Docker -DockerArgs @('pull', $VLLM_UPSTREAM_IMAGE)
            Invoke-Docker -DockerArgs @('tag', $VLLM_UPSTREAM_IMAGE, $VLLM_RELEASE_IMAGE)
        }
    } else {
        Write-Host "Pulling vLLM image: $VLLM_UPSTREAM_IMAGE"
        Invoke-Docker -DockerArgs @('pull', $VLLM_UPSTREAM_IMAGE)
        Invoke-Docker -DockerArgs @('tag', $VLLM_UPSTREAM_IMAGE, $VLLM_RELEASE_IMAGE)
    }

    Invoke-Docker -DockerArgs @('tag', $VLLM_RELEASE_IMAGE, $VLLM_STABLE_IMAGE)
    $tar = Save-ImageTar -ComponentName 'vllm' -StableImage $VLLM_STABLE_IMAGE -ReleaseImage $VLLM_RELEASE_IMAGE

    $indexUpdates += [pscustomobject]@{
        component = 'vllm'
        tar_file = $tar
        stable_image = $VLLM_STABLE_IMAGE
        release_image = $VLLM_RELEASE_IMAGE
        release_tag = $ReleaseTag
        updated_at = $timestamp
    }
}

if ($requested -contains 'ragflow') {
    Write-Host "Pulling RAGFlow image: $RAGFLOW_IMAGE"
    Invoke-Docker -DockerArgs @('pull', $RAGFLOW_IMAGE)

    $tar = Save-ImageTar -ComponentName 'ragflow' -StableImage $RAGFLOW_IMAGE -ReleaseImage $RAGFLOW_IMAGE

    $indexUpdates += [pscustomobject]@{
        component = 'ragflow'
        tar_file = $tar
        stable_image = $RAGFLOW_IMAGE
        release_image = $RAGFLOW_IMAGE
        release_tag = $ReleaseTag
        updated_at = $timestamp
    }
}

if ($requested -contains 'deps') {
    $deps = @($MYSQL_IMAGE, $MINIO_IMAGE, $VALKEY_IMAGE, $ELASTIC_IMAGE)
    foreach ($img in $deps) {
        Write-Host "Pulling dependency image: $img"
        Invoke-Docker -DockerArgs @('pull', $img)

        $tar = Save-ImageTar -ComponentName 'deps' -StableImage $img -ReleaseImage $img

        $indexUpdates += [pscustomobject]@{
            component = 'deps'
            tar_file = $tar
            stable_image = $img
            release_image = $img
            release_tag = $ReleaseTag
            updated_at = $timestamp
        }
    }
}

if ($requested -contains 'tei') {
    $teiImages = @($TEI_IMAGE_CPU, $TEI_IMAGE_GPU)
    foreach ($img in $teiImages) {
        Write-Host "Pulling TEI image: $img"
        Invoke-Docker -DockerArgs @('pull', $img)

        $tar = Save-ImageTar -ComponentName 'tei' -StableImage $img -ReleaseImage $img

        $indexUpdates += [pscustomobject]@{
            component = 'tei'
            tar_file = $tar
            stable_image = $img
            release_image = $img
            release_tag = $ReleaseTag
            updated_at = $timestamp
        }
    }
}

$mergedRows = Upsert-IndexRows -Rows $existingRows -Updates $indexUpdates
Write-IndexRows -Path $indexPath -Rows $mergedRows

Write-Host "Build complete. ReleaseTag=$ReleaseTag"
Write-Host "Image tar index: $indexPath"
