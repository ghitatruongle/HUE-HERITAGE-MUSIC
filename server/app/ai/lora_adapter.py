from __future__ import annotations

from pathlib import Path
from typing import Optional
import re

from ..config import settings

WEIGHT_FILES = ("lokr_weights.safetensors", "adapter_model.safetensors")


def lora_root() -> Path:
    d = settings.models_dir / "lora"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _find_weight(directory: Path) -> Optional[Path]:
    if not directory.exists():
        return None
    if directory.is_file() and directory.name in WEIGHT_FILES:
        return directory
    for wf in WEIGHT_FILES:
        cand = directory / wf
        if cand.is_file():
            return cand
    for sub in ("final", "winner"):
        for wf in WEIGHT_FILES:
            cand = directory / sub / wf
            if cand.is_file():
                return cand
    epoch_dirs = []
    try:
        for child in directory.iterdir():
            if child.is_dir() and child.name.startswith("epoch"):
                m = re.search(r"epoch(\d+)", child.name)
                num = int(m.group(1)) if m else 0
                epoch_dirs.append((num, child))
    except OSError:
        pass
    for _, ed in sorted(epoch_dirs, key=lambda x: x[0], reverse=True):
        for wf in WEIGHT_FILES:
            cand = ed / wf
            if cand.is_file():
                return cand
    for cand in sorted(directory.glob("**/*.safetensors")):
        if cand.is_file():
            return cand
    return None


def list_adapters():
    out = []
    root = lora_root()
    if not root.exists():
        return out
    for sub in sorted(root.iterdir()):
        if not sub.is_dir():
            continue
        w = _find_weight(sub)
        out.append({"name": sub.name, "ready": w is not None})
    return out


def resolve(name: str):
    if not name:
        return None
    cleaned = name.strip()
    if not cleaned or "\0" in cleaned or ".." in cleaned:
        return None
    root = lora_root().resolve()
    try:
        target = (root / cleaned).resolve()
        if not target.is_relative_to(root):
            return None
    except (ValueError, OSError):
        return None
    if target.is_file() and target.suffix == ".safetensors" and target.exists():
        return str(target)
    if target.is_dir():
        w = _find_weight(target)
        if w and w.is_file():
            return str(w)
    return None
