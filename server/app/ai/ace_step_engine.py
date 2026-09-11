from pathlib import Path

from ..config import settings

ENGINE = "ACE-Step 1.5"


class EngineUnavailable(Exception):
    pass


def base_dir() -> Path:
    d = settings.models_dir / "ace_step"
    d.mkdir(parents=True, exist_ok=True)
    return d


def weights_found() -> bool:
    d = base_dir()
    for p in d.iterdir():
        if p.suffix in (".safetensors", ".pt", ".bin", ".ckpt") and p.is_file():
            return True
    return False


def status():
    return {
        "engine": ENGINE,
        "loaded": False,
        "weights_found": weights_found(),
        "weights_dir": str(base_dir()),
    }


def generate(prompt, duration=60, seed=0):
    if not weights_found():
        raise EngineUnavailable("no weights on this machine")
    raise EngineUnavailable("inference wired on Mac only")
