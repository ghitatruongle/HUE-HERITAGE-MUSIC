from fastapi import APIRouter, HTTPException

from ..services import generator_service

router = APIRouter(tags=["music_gen"])


@router.get("/music/models")
def list_models():
    return generator_service.models_info()


@router.post("/music/generate")
def generate(prompt: str = "", duration: int = 60, lora: str = "", strength: float = 0.8, seed: int = 0):
    if not prompt.strip():
        raise HTTPException(status_code=400, detail="empty prompt")
    if duration < 5 or duration > 300:
        raise HTTPException(status_code=400, detail="bad duration")
    if strength < 0 or strength > 1:
        raise HTTPException(status_code=400, detail="bad strength")
    return generator_service.create_task("generate", prompt.strip(), duration, lora.strip(), strength, seed)


@router.post("/music/cover")
def cover(heritage_id: str = "", style: str = "", duration: int = 60, lora: str = "", strength: float = 0.8):
    if not heritage_id.strip() or not style.strip():
        raise HTTPException(status_code=400, detail="missing params")
    if duration < 5 or duration > 300:
        raise HTTPException(status_code=400, detail="bad duration")
    if strength < 0 or strength > 1:
        raise HTTPException(status_code=400, detail="bad strength")
    prompt = f"cover heritage {heritage_id.strip()}: {style.strip()}"
    return generator_service.create_task("cover", prompt, duration, lora.strip(), strength, 0)


@router.get("/music/task/{task_id}")
def gen_task(task_id: str):
    task = generator_service.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="not found")
    return task
