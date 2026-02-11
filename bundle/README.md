# Offline Bundle Guide

This bundle keeps only the required workflows:
- build images on Windows (online)
- load/upgrade images on Ubuntu server (offline)
- one-click deploy
- one-click stop and remove containers
- reconcile Python environments and keep one Python 3.12 venv

## Scripts kept

- `scripts/build-images.ps1`
- `scripts/load-images.sh`
- `scripts/retag-images.sh`
- `scripts/prepare-host-layout.sh`
- `scripts/upgrade.sh`
- `scripts/deploy-oneclick.sh`
- `scripts/destroy-oneclick.sh`
- `scripts/python-env-reconcile.sh`

## Build images (Windows)

```powershell
powershell -ExecutionPolicy Bypass -File .\bundle\scripts\build-images.ps1 -Component all -OpenWebUIBuildMode auto -VLLMBuildMode auto
```

Source-first behavior:
- OpenWebUI: local source in `repos/openwebui` first, fallback to pull by mode.
- vLLM: local source in `repos/vllm` first, fallback to pull by mode.

Output:
- image tar files in `bundle/images/`
- index file `bundle/images/index.tsv`

## Deploy on offline Ubuntu server

1) Transfer `bundle/` to server.

2) Deploy:

```bash
cd /opt/ai-platform/bundle
export HOST_DATA_ROOT=/home/ubuntu/data/forstar
export HOST_LOG_ROOT=/var/log/forstar
bash scripts/deploy-oneclick.sh
```

Important:
- `deploy-oneclick.sh` and `upgrade.sh` require `vm.max_map_count >= 262144` for Elasticsearch.
- If blocked, run:

```bash
sudo sysctl -w vm.max_map_count=262144
```

## Upgrade images (no down -v)

Full:

```bash
bash scripts/upgrade.sh all
```

Single component:

```bash
bash scripts/upgrade.sh openwebui proxy
bash scripts/upgrade.sh ragflow
bash scripts/upgrade.sh vllm
```

## Stop and remove all containers

```bash
bash scripts/destroy-oneclick.sh
```

This only removes containers/network from compose stacks. Host bind data under `HOST_DATA_ROOT` is kept.

## Python environment reconcile

Report only:

```bash
bash scripts/python-env-reconcile.sh
```

Cleanup source-installed `/usr/local` Python artifacts (dry-run first):

```bash
bash scripts/python-env-reconcile.sh --cleanup-source
bash scripts/python-env-reconcile.sh --cleanup-source --apply --create-venv --venv-path /opt/venvs/py312 --python-bin /usr/bin/python3.12
```

## Default host ports

- OpenWebUI gateway: `8888` (`/ai`)
- RAGFlow web: `8889`
- RAGFlow https: `8890`
- RAGFlow API: `8891`
- RAGFlow admin: `8892`
- RAGFlow MCP: `8893`
- vLLM OpenAI API: `8894`
- MinIO API: `8895`
- MinIO Console: `8896`
- MySQL: `8897`
- Redis: `8898`
- Elasticsearch: `8899`
- TEI: `8900`
- OpenSearch: `8901`

## Access paths

- OpenWebUI: `http://<SERVER_IP>:8888/ai/`
- RAGFlow: `http://<SERVER_IP>:8889/`
- vLLM: `http://<SERVER_IP>:8894/v1`

