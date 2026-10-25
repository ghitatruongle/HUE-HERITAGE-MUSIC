import json
import threading
import time

import httpx

from ..config import settings

ENGINE = "ACE-Step 1.5"
POLL_INTERVAL = 3.0
POLL_TIMEOUT = 900.0
AVAILABILITY_TTL = 15.0


class EngineUnavailable(Exception):
    pass


class GenerationCancelled(Exception):
    pass


_avail_lock = threading.Lock()
_avail_cache = {"ts": 0.0, "ok": False}


def _api_url() -> str:
    return settings.acestep_api_url.rstrip("/")


def _check_available() -> bool:
    url = _api_url()
    if not url:
        return False
    try:
        r = httpx.get(url + "/health", timeout=2.0)
        return r.status_code == 200
    except Exception:
        return False


def api_available(force: bool = False) -> bool:
    with _avail_lock:
        if not force and time.time() - _avail_cache["ts"] < AVAILABILITY_TTL:
            return _avail_cache["ok"]
    ok = _check_available()
    with _avail_lock:
        _avail_cache["ts"] = time.time()
        _avail_cache["ok"] = ok
    return ok


def invalidate_availability() -> None:
    with _avail_lock:
        _avail_cache["ts"] = 0.0
        _avail_cache["ok"] = False


def base_dir():
    from ..storage import manager
    return manager.generated_dir()


def weights_found() -> bool:
    return api_available()


def status():
    ok = api_available()
    return {
        "engine": ENGINE,
        "loaded": ok,
        "weights_found": ok,
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


def generate(prompt, duration=60, seed=0, lora="", strength=0.8, should_cancel=None):
    if not api_available():
        raise EngineUnavailable("engine offline (acestep-api not reachable)")
    duration = max(10, min(int(duration), 300))
    task_id = _release(prompt, duration, seed, lora=lora, strength=strength)
    deadline = time.time() + POLL_TIMEOUT
    while time.time() < deadline:
        if should_cancel is not None and should_cancel():
            raise GenerationCancelled("cancelled by user")
        time.sleep(POLL_INTERVAL)
        entry = _query(task_id)
        if not entry:
            continue
        if entry.get("status") == 2:
            raise EngineUnavailable("generation failed")
        if entry.get("status") == 1:
            raw_res = entry.get("result")
            if isinstance(raw_res, str):
                try:
                    results = json.loads(raw_res or "[]")
                except Exception:
                    results = []
            elif isinstance(raw_res, list):
                results = raw_res
            elif isinstance(raw_res, dict):
                results = [raw_res]
            else:
                results = []
            files = [x.get("file") for x in results if isinstance(x, dict) and x.get("file")]
            if not files:
                raise EngineUnavailable("no audio returned")
            audio = _download(files[0])
            first_info = results[0] if results and isinstance(results[0], dict) else {}
            return {
                "remote_task_id": task_id,
                "audio": audio,
                "info": first_info.get("generation_info", ""),
                "dit_model": first_info.get("dit_model", ENGINE),
                "lm_model": first_info.get("lm_model", ""),
            }
    raise EngineUnavailable("generation timed out")
