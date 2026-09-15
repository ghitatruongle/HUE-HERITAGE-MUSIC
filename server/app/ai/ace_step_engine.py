import json
import time

import httpx

from ..config import settings

ENGINE = "ACE-Step 1.5"
POLL_INTERVAL = 3.0
POLL_TIMEOUT = 900.0


class EngineUnavailable(Exception):
    pass


def _api_url() -> str:
    return settings.acestep_api_url.rstrip("/")


def api_available() -> bool:
    url = _api_url()
    if not url:
        return False
    try:
        r = httpx.get(url + "/health", timeout=2.0)
        return r.status_code == 200
    except Exception:
        return False


def base_dir():
    from ..storage import manager
    return manager.generated_dir()


def weights_found() -> bool:
    return api_available()


def status():
    return {
        "engine": ENGINE,
        "loaded": api_available(),
        "weights_found": api_available(),
        "api_url": _api_url(),
        "mode": "remote-api",
    }


def models_list():
    url = _api_url()
    if not api_available():
        raise EngineUnavailable("engine offline")
    r = httpx.get(url + "/list_models", timeout=10.0)
    r.raise_for_status()
    return r.json()


def _release(prompt: str, duration: int, seed: int, lora: str = "", strength: float = 0.8) -> str:
    payload = {
        "prompt": prompt,
        "audio_duration": duration,
        "instrumental": True,
    }
    if seed > 0:
        payload["use_random_seed"] = False
        payload["seed"] = seed
    if lora:
        from . import lora_adapter
        payload["lora_path"] = lora_adapter.resolve(lora) or ""
        payload["lora_weight"] = strength
    r = httpx.post(_api_url() + "/release_task", json=payload, timeout=30.0)
    r.raise_for_status()
    body = r.json()
    task_id = (body.get("data") or {}).get("task_id")
    if not task_id:
        raise EngineUnavailable("release_task failed: " + json.dumps(body)[:200])
    return task_id


def _query(task_id: str):
    r = httpx.post(
        _api_url() + "/query_result",
        json={"task_id_list": [task_id]},
        timeout=30.0,
    )
    r.raise_for_status()
    data = r.json().get("data") or []
    return data[0] if data else None


def _download(url_path: str) -> bytes:
    r = httpx.get(_api_url() + url_path, timeout=120.0)
    r.raise_for_status()
    return r.content


def generate(prompt, duration=60, seed=0, lora="", strength=0.8):
    if not api_available():
        raise EngineUnavailable("engine offline (acestep-api not reachable)")
    duration = max(10, min(int(duration), 300))
    task_id = _release(prompt, duration, seed, lora=lora, strength=strength)
    deadline = time.time() + POLL_TIMEOUT
    while time.time() < deadline:
        time.sleep(POLL_INTERVAL)
        entry = _query(task_id)
        if not entry:
            continue
        if entry.get("status") == 2:
            raise EngineUnavailable("generation failed")
        if entry.get("status") == 1:
            results = json.loads(entry.get("result") or "[]")
            files = [x["file"] for x in results if x.get("file")]
            if not files:
                raise EngineUnavailable("no audio returned")
            audio = _download(files[0])
            return {
                "remote_task_id": task_id,
                "audio": audio,
                "info": results[0].get("generation_info", ""),
                "dit_model": results[0].get("dit_model", ENGINE),
                "lm_model": results[0].get("lm_model", ""),
            }
    raise EngineUnavailable("generation timed out")
