from typing import Optional
import asyncio

from fastapi import APIRouter, UploadFile, File, Depends, HTTPException, Request
from ..rate_limit import RATE_LIMIT_DETAIL, RATE_LIMIT_HEADERS

from ..services import pitch_service, compare_service, user_inflight
from ..storage import manager
from .auth import require_user

router = APIRouter(tags=["sing"])
MAX_BYTES = manager.MAX_ANALYSIS_BYTES


@router.post("/music/analyze-pitch")
async def analyze_pitch(request: Request, file: UploadFile = File(...), user_id: Optional[str] = Depends(require_user)):
    if manager.content_length_exceeds(request, MAX_BYTES):
        raise HTTPException(status_code=413, detail="file too large")
    data = await file.read()
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="file too large")
    if not user_inflight.try_acquire(user_inflight.user_key("pitch", user_id)):
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
    try:
        max_seconds = compare_service.MAX_COMPARE_SECONDS
        duration_full = _wav_header_duration(data)
        try:
            samples, sr = await asyncio.to_thread(pitch_service.read_mono_wav, data, max_seconds=max_seconds)
        except ValueError:
            raise HTTPException(status_code=400, detail="wav decode failed")
        times, f0s = await asyncio.to_thread(pitch_service.estimate_f0, samples, sr)
    finally:
        user_inflight.release(user_inflight.user_key("pitch", user_id))
    voiced = [f for f in f0s if f > 0]
    mean_f0 = round(sum(voiced) / len(voiced), 1) if voiced else 0.0
    truncated = duration_full is not None and duration_full > max_seconds + 0.05
    return {
        "filename": file.filename,
        "sample_rate": sr,
        "duration": round(len(samples) / sr, 2),
        "duration_full": round(duration_full, 2) if duration_full is not None else None,
        "truncated": truncated,
        "max_seconds": max_seconds,
        "frames": len(times),
        "mean_f0": mean_f0,
        "times": times,
        "f0": f0s,
    }


def _wav_header_duration(data: bytes) -> Optional[float]:
    import io as _io
    import wave as _wave

    try:
        with _wave.open(_io.BytesIO(data)) as w:
            rate = w.getframerate()
            if rate <= 0:
                return None
            return w.getnframes() / float(rate)
    except Exception:
        return None


@router.post("/music/compare")
async def compare_sing(request: Request, sample: UploadFile = File(...), user: UploadFile = File(...), user_id: Optional[str] = Depends(require_user)):
    if manager.content_length_exceeds(request, manager.COMPARE_BODY_LIMIT):
        raise HTTPException(status_code=413, detail="file too large")
    s_data = await sample.read()
    u_data = await user.read()
    if len(s_data) == 0 or len(u_data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    if len(s_data) > MAX_BYTES or len(u_data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="file too large")
    if not user_inflight.try_acquire(user_inflight.user_key("compare", user_id)):
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
    try:
        try:
            return await asyncio.to_thread(compare_service.compare, s_data, u_data)
        except compare_service.CompareEmptyError as e:
            raise HTTPException(status_code=422, detail={"code": e.code, "message": e.message})
        except ValueError as e:
            msg = str(e)
            if "empty contour" in msg:
                raise HTTPException(status_code=400, detail="empty pitch contour (silence or unvoiced audio)")
            raise HTTPException(status_code=400, detail="wav decode failed")
    finally:
        user_inflight.release(user_inflight.user_key("compare", user_id))
