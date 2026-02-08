from __future__ import annotations

import os
import time
from typing import Iterable

import requests
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, StreamingResponse

app = FastAPI()

RAGFLOW_BASE_URL = os.getenv("RAGFLOW_BASE_URL", "http://ragflow-gpu:9380").rstrip("/")
RAGFLOW_API_KEY = os.getenv("RAGFLOW_API_KEY", "")
RAGFLOW_MODE = os.getenv("RAGFLOW_MODE", "chat").lower()
RAGFLOW_CHAT_ID = os.getenv("RAGFLOW_CHAT_ID", "")
RAGFLOW_AGENT_ID = os.getenv("RAGFLOW_AGENT_ID", "")
MODEL_ID = os.getenv("MODEL_ID", "ragflow-kb")
MODEL_NAME = os.getenv("MODEL_NAME", MODEL_ID)
HTTP_TIMEOUT = float(os.getenv("HTTP_TIMEOUT", "300"))


def _ragflow_endpoint() -> str:
    if RAGFLOW_MODE == "agent":
        if not RAGFLOW_AGENT_ID:
            raise RuntimeError("RAGFLOW_AGENT_ID is required when RAGFLOW_MODE=agent")
        return f"{RAGFLOW_BASE_URL}/api/v1/agents_openai/{RAGFLOW_AGENT_ID}/chat/completions"

    if not RAGFLOW_CHAT_ID:
        raise RuntimeError("RAGFLOW_CHAT_ID is required when RAGFLOW_MODE=chat")
    return f"{RAGFLOW_BASE_URL}/api/v1/chats_openai/{RAGFLOW_CHAT_ID}/chat/completions"


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.get("/v1/models")
async def list_models() -> dict:
    return {
        "object": "list",
        "data": [
            {
                "id": MODEL_ID,
                "object": "model",
                "created": int(time.time()),
                "owned_by": "ragflow",
                "name": MODEL_NAME,
            }
        ],
    }


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    payload = await request.json()

    # Ensure model is set for OpenWebUI
    if "model" not in payload or not payload["model"]:
        payload["model"] = MODEL_ID

    url = _ragflow_endpoint()
    headers = {"Content-Type": "application/json"}
    if RAGFLOW_API_KEY:
        headers["Authorization"] = f"Bearer {RAGFLOW_API_KEY}"

    stream = bool(payload.get("stream", False))

    try:
        resp = requests.post(url, json=payload, headers=headers, stream=stream, timeout=HTTP_TIMEOUT)
    except requests.RequestException as exc:
        raise HTTPException(status_code=502, detail=f"Upstream connection error: {exc}") from exc

    if resp.status_code != 200:
        detail = None
        try:
            detail = resp.json()
        except Exception:
            detail = resp.text
        raise HTTPException(status_code=resp.status_code, detail=detail)

    if not stream:
        return JSONResponse(content=resp.json())

    def iter_sse() -> Iterable[bytes]:
        for line in resp.iter_lines():
            if line:
                yield line + b"\n"

    return StreamingResponse(iter_sse(), media_type="text/event-stream")
