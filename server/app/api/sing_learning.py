from typing import Optional
import asyncio

from fastapi import APIRouter, UploadFile, File, Form, Depends, HTTPException, Request
from ..rate_limit import RATE_LIMIT_DETAIL, RATE_LIMIT_HEADERS

from ..audio_access import sha_viewable
from ..database import crud
from ..database.session import SessionLocal
from ..services import pitch_service, compare_service, user_inflight
from ..storage import manager
from .auth import require_user, resolve_bearer_user

router = APIRouter(tags=["sing"])
MAX_BYTES = manager.MAX_ANALYSIS_BYTES


@router.post("/music/analyze-pitch")
async def analyze_pitch(request: Request, file: UploadFile = File(...), user_id: Optional[str] = Depends(require_user)):
    if manager.content_length_exceeds(request, MAX_BYTES):
        raise HTTPException(status_code=413, detail="file too large")
    data = await manager.read_upload_limited(file, MAX_BYTES)
    if not user_inflight.try_acquire(user_inflight.user_key("pitch", user_id)):
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
    try:
        max_seconds = compare_service.MAX_COMPARE_SECONDS
        duration_full = _wav_header_duration(data)
        try:
            samples, sr = await user_inflight.run_dsp(pitch_service.read_mono_wav, data, max_seconds=max_seconds)
        except ValueError:
            raise HTTPException(status_code=400, detail="wav decode failed")
        times, f0s = await user_inflight.run_dsp(pitch_service.estimate_f0, samples, sr)
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
    s_data = await manager.read_upload_limited(sample, MAX_BYTES)
    u_data = await manager.read_upload_limited(user, MAX_BYTES)
    if not user_inflight.try_acquire(user_inflight.user_key("compare", user_id)):
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
    try:
        try:
            return await user_inflight.run_dsp(compare_service.compare, s_data, u_data)
        except compare_service.CompareEmptyError as e:
            raise HTTPException(status_code=422, detail={"code": e.code, "message": e.message})
        except ValueError as e:
            msg = str(e)
            if "empty contour" in msg:
                raise HTTPException(status_code=400, detail="empty pitch contour (silence or unvoiced audio)")
            raise HTTPException(status_code=400, detail="wav decode failed")
    finally:
        user_inflight.release(user_inflight.user_key("compare", user_id))


def _resolve_stored_audio(db, request: Request, item_id: str, sha: str, viewer):
    if item_id:
        item = crud.get_item(db, item_id)
        if not item or not crud.can_view_item(item, viewer):
            raise HTTPException(status_code=404, detail="not found")
        if not manager.safe_original_name(item.filename):
            raise HTTPException(status_code=400, detail="bad filename")
        path = manager.original_dir() / item.filename
        if not path.exists():
            raise HTTPException(status_code=404, detail="file missing")
        return path, f"heritage:{item.sha256 or item.id}"
    if sha:
        if not manager.is_sha256(sha) or not sha_viewable(db, request, sha):
            raise HTTPException(status_code=404, detail="not found")
        path = manager.restored_dir() / (sha + "_restored.wav")
        if not path.exists():
            raise HTTPException(status_code=404, detail="file missing")
        return path, f"restored:{sha}"
    return None, None


@router.post("/music/compare-items")
async def compare_items(
    request: Request,
    sample_item_id: str = Form(""),
    user_item_id: str = Form(""),
    sample_sha: str = Form(""),
    user_sha: str = Form(""),
    sample: Optional[UploadFile] = File(None),
    user: Optional[UploadFile] = File(None),
    user_id: Optional[str] = Depends(require_user),
):
    s_bytes = None
    u_bytes = None
    if sample is not None:
        s_bytes = await manager.read_upload_limited(sample, MAX_BYTES)
    if user is not None:
        u_bytes = await manager.read_upload_limited(user, MAX_BYTES)

    def _resolve_sources():
        db = SessionLocal()
        try:
            viewer = crud.get_user_by_id(db, user_id) if user_id else resolve_bearer_user(request, db)
            sp, sk = (None, None) if s_bytes is not None else _resolve_stored_audio(db, request, sample_item_id.strip(), sample_sha.strip(), viewer)
            up, _ = (None, None) if u_bytes is not None else _resolve_stored_audio(db, request, user_item_id.strip(), user_sha.strip(), viewer)
            return sp, sk, up
        finally:
            db.close()

    s_path, s_key, u_path = await asyncio.to_thread(_resolve_sources)

    if (s_bytes is None and s_path is None) or (u_bytes is None and u_path is None):
        raise HTTPException(status_code=400, detail="missing comparison source")
    if not user_inflight.try_acquire(user_inflight.user_key("compare", user_id)):
        raise HTTPException(status_code=429, detail=RATE_LIMIT_DETAIL, headers=RATE_LIMIT_HEADERS)
    try:
        def _run():
            try:
                raw_s = s_bytes if s_bytes is not None else s_path.read_bytes()
                raw_u = u_bytes if u_bytes is not None else u_path.read_bytes()
            except OSError:
                return None
            return compare_service.compare(raw_s, raw_u, sample_key=s_key)

        try:
            res = await user_inflight.run_dsp(_run)
        except compare_service.CompareEmptyError as e:
            raise HTTPException(status_code=422, detail={"code": e.code, "message": e.message})
        except ValueError as e:
            msg = str(e)
            if "empty contour" in msg:
                raise HTTPException(status_code=400, detail="empty pitch contour (silence or unvoiced audio)")
            raise HTTPException(status_code=400, detail="wav decode failed")
        if res is None:
            raise HTTPException(status_code=404, detail="file missing")
        return res
    finally:
        user_inflight.release(user_inflight.user_key("compare", user_id))
