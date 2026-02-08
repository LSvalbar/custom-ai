# Offline Bundle Guide

This bundle supports:
- offline deployment on Ubuntu server
- no-downtime update (`docker compose up -d`, no `down -v`)
- single-component upgrade or full upgrade
- vLLM local-source-first build with pull fallback option
- OpenWebUI local-source-first build with pull fallback option
- OpenWebUI subpath build (`/ai`)

## Directory

- `scripts/build-images.ps1`: build/package images on online machine
- `scripts/load-images.sh`: load image tar on server (component-aware)
- `scripts/upgrade.sh`: no-downtime upgrade (single component or all)
- `scripts/backup.sh`: optional pre-upgrade data backup
- `scripts/deploy-oneclick.sh`: one-click full deployment/upgrade
- `scripts/export-docker-logs.sh`: export/follow container stdout logs to files
- `scripts/cleanup-legacy-python.sh`: cleanup helper for old pip-based openwebui/vllm
- `scripts/check-gpu-stack.sh`: check GPU driver/CUDA compatibility quickly
- `scripts/upgrade-nvidia-cuda-offline.sh`: offline NVIDIA+CUDA upgrade script
- `scripts/stage-nvidia-offline.ps1`: stage NVIDIA/CUDA offline installers into project
- `scripts/download-nvidia-offline.ps1`: download NVIDIA/CUDA installers into project (online machine)
- `offline/nvidia/`: default offline package directory used by upgrade script
- `nginx/host-nginx-ai.conf.example`: host nginx routing example (`/forstar` + `/ai`)

## 1) Build images (online machine)

### Build all components

```powershell
powershell -ExecutionPolicy Bypass -File .\bundle\scripts\build-images.ps1 -Component all
```

### Build only vLLM

```powershell
powershell -ExecutionPolicy Bypass -File .\bundle\scripts\build-images.ps1 -Component vllm
```

### vLLM local-source-first behavior

- Default is `-VLLMBuildMode auto`
- If `repos/vllm` + Dockerfile exists, build from local source
- If local source is missing, pull upstream image

Force mode examples:

```powershell
# Force local source build
powershell -ExecutionPolicy Bypass -File .\bundle\scripts\build-images.ps1 -Component vllm -VLLMBuildMode source

# Force pull
powershell -ExecutionPolicy Bypass -File .\bundle\scripts\build-images.ps1 -Component vllm -VLLMBuildMode pull

# Source build, fallback to pull when build fails
powershell -ExecutionPolicy Bypass -File .\bundle\scripts\build-images.ps1 -Component vllm -VLLMBuildMode source -AllowPullFallback
```

Optional vLLM source build overrides (PowerShell env vars):

```powershell
$env:VLLM_DOCKERFILE = "docker/Dockerfile"   # default already
$env:VLLM_BUILD_CONTEXT = "D:\Project\Codex\LLM\repos\vllm"
$env:VLLM_CUDA_VERSION = "12.2.2"
$env:VLLM_PYTHON_VERSION = "3.12"
```

### Build OpenWebUI for `/ai`

Set this in `compose/openwebui/.env`:

```bash
OPENWEBUI_BASE_PATH=/ai
```

OpenWebUI default build mode is now `auto` (source-first if local repo exists).
Force source build:

```powershell
powershell -ExecutionPolicy Bypass -File .\bundle\scripts\build-images.ps1 -Component openwebui -OpenWebUIBuildMode source
```

Force pull build:

```powershell
powershell -ExecutionPolicy Bypass -File .\bundle\scripts\build-images.ps1 -Component openwebui -OpenWebUIBuildMode pull
```

## 2) Transfer bundle to offline server

```bash
scp -r bundle/ user@server:/opt/ai-platform/
```

## 3) One-click deployment (offline server)

```bash
cd /opt/ai-platform/bundle
export HOST_DATA_ROOT=/home/ubuntu/data/forstar
export HOST_LOG_ROOT=/var/log/forstar
bash scripts/deploy-oneclick.sh
```

## 4) Upgrade without downtime

### Full upgrade

```bash
bash scripts/upgrade.sh all
```

### Single-component upgrade

```bash
bash scripts/upgrade.sh vllm
bash scripts/upgrade.sh openwebui proxy
bash scripts/upgrade.sh ragflow
```

### Upgrade with backup

```bash
bash scripts/upgrade.sh ragflow --backup
bash scripts/upgrade.sh all --backup --backup-dir /opt/ai-backups/release-001
```

## 5) Manual image load only

```bash
bash scripts/load-images.sh all
bash scripts/load-images.sh vllm
bash scripts/load-images.sh openwebui proxy
```

## 6) Data persistence rules

Data is kept in host bind directories. Do not run `docker compose down -v`.

Default roots:
- `HOST_DATA_ROOT` (default from scripts): `$HOME/data/forstar`
- `HOST_LOG_ROOT` (default from scripts): `/var/log/forstar`

Main data directories:
- OpenWebUI: `$HOST_DATA_ROOT/openwebui`
- RAGFlow: `$HOST_DATA_ROOT/ragflow/...`
- vLLM: model directory from `compose/vllm/.env` (`MODEL_ROOT`)

Main log directories:
- OpenWebUI app log: `$HOST_LOG_ROOT/openwebui/runtime.log`
- RAGFlow proxy app log: `$HOST_LOG_ROOT/ragflow-proxy/runtime.log`
- RAGFlow app logs: `$HOST_LOG_ROOT/ragflow/`
- Docker stdout/stderr export: `$HOST_LOG_ROOT/<container>/docker.log`

For stdout/stderr logs (docker logs), export to files:

```bash
bash scripts/export-docker-logs.sh --since 24h
```

## 7) Compose image tags

- OpenWebUI: `forstar/openwebui:offline`
- RAGFlow proxy: `forstar/ragflow-openai-proxy:offline`
- vLLM: `forstar/vllm-openai:offline`

These stable tags are updated by your packaged tar + `docker load` + `upgrade.sh`.

## 8) Notes

- `upgrade.sh` does not call `down`; it only runs `up -d` to recreate changed services.
- If you modify OpenWebUI code, use local-source build mode for OpenWebUI:

```powershell
powershell -ExecutionPolicy Bypass -File .\bundle\scripts\build-images.ps1 -Component openwebui -OpenWebUIBuildMode source
```

## 9) GPU Driver/CUDA (offline)

Compatibility check:

```bash
bash scripts/check-gpu-stack.sh 12.2
```

Stage installers into project (Windows online machine):

Option A: auto-download to project:

```powershell
powershell -ExecutionPolicy Bypass -File .\bundle\scripts\download-nvidia-offline.ps1 `
  -DriverUrl "https://..." `
  -CudaUrl "https://..." `
  -ToolkitDebUrls @("https://.../nvidia-container-toolkit_*.deb")
```

Option B: use already downloaded files:

```powershell
powershell -ExecutionPolicy Bypass -File .\bundle\scripts\stage-nvidia-offline.ps1 `
  -DriverRunfile "D:\offline\NVIDIA-Linux-x86_64-535.183.01.run" `
  -CudaRunfile "D:\offline\cuda_12.2.2_535.104.05_linux.run" `
  -ToolkitDebDir "D:\offline\nvidia-container-toolkit-debs"
```

Then transfer `bundle/` to offline server and run:

```bash
cd /opt/ai-platform/bundle
sudo bash scripts/upgrade-nvidia-cuda-offline.sh
```

The script will auto-discover:
- driver runfile: `bundle/offline/nvidia/NVIDIA-Linux-x86_64-*.run`
- cuda runfile: `bundle/offline/nvidia/cuda_*_linux.run`
- toolkit debs: `bundle/offline/nvidia/toolkit-debs/*.deb`
