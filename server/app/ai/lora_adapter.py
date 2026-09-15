from pathlib import Path

from ..config import settings

ADAPTER_FILE = "adapter_model.safetensors"


def lora_root() -> Path:
    d = settings.models_dir / "lora"
    d.mkdir(parents=True, exist_ok=True)
    return d


def list_adapters():
    out = []
    root = lora_root()
    for sub in sorted(root.iterdir()):
        if not sub.is_dir():
            continue
        w = sub / ADAPTER_FILE
        out.append({"name": sub.name, "ready": w.exists()})
    return out


def resolve(name):
    if not name:
        return None
    if "/" in name or "\\" in name or ".." in name:
        return None
    w = lora_root() / name / ADAPTER_FILE
    if w.exists():
        return str(w)
    return None
