import asyncio

from fastapi import APIRouter, UploadFile, File, Depends, HTTPException

from ..services import pitch_service, compare_service
from .auth import require_user

router = APIRouter(tags=["sing"])
MAX_BYTES = 15 * 1024 * 1024


@router.post("/music/analyze-pitch")
async def analyze_pitch(file: UploadFile = File(...), user_id: str | None = Depends(require_user)):
    data = await file.read()
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="file too large")
    try:
        samples, sr = pitch_service.read_mono_wav(data)
    except ValueError:
        raise HTTPException(status_code=400, detail="wav decode failed")
    times, f0s = await asyncio.to_thread(pitch_service.estimate_f0, samples, sr)
    voiced = [f for f in f0s if f > 0]
    mean_f0 = round(sum(voiced) / len(voiced), 1) if voiced else 0.0
    return {
        "filename": file.filename,
        "sample_rate": sr,
        "duration": round(len(samples) / sr, 2),
        "frames": len(times),
        "mean_f0": mean_f0,
        "times": times,
        "f0": f0s,
    }


@router.post("/music/compare")
async def compare_sing(sample: UploadFile = File(...), user: UploadFile = File(...), user_id: str | None = Depends(require_user)):
    s_data = await sample.read()
    u_data = await user.read()
    if len(s_data) == 0 or len(u_data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    if len(s_data) > MAX_BYTES or len(u_data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="file too large")
    try:
        return await asyncio.to_thread(compare_service.compare, s_data, u_data)
    except ValueError as e:
        msg = str(e)
        if "empty contour" in msg:
            raise HTTPException(status_code=400, detail="empty pitch contour (silence or unvoiced audio)")
        raise HTTPException(status_code=400, detail="wav decode failed")
