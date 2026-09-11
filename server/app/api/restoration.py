import asyncio

from fastapi import APIRouter, UploadFile, File, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..database.session import get_db
from ..database import crud
from ..services import restoration_service
from ..storage import manager

router = APIRouter(tags=["restoration"])
MAX_BYTES = 15 * 1024 * 1024


def restored_dir():
    return manager.restored_dir()


def run_restore(data, heritage_id, db):
    try:
        out, report = restoration_service.restore(data)
    except ValueError:
        raise HTTPException(status_code=400, detail="wav decode failed")
    digest = manager.sha256_bytes(data)
    dest = restored_dir() / (digest + "_restored.wav")
    if not dest.exists():
        dest.write_bytes(out)
    if heritage_id:
        item = crud.get_item(db, heritage_id)
        if item and not crud.has_audio(db, item.id, "restored", str(dest)):
            crud.create_audio(db, item.id, "restored", str(dest), digest, dest.stat().st_size)
    report["sha"] = digest
    return report


@router.post("/music/restore")
async def restore_upload(file: UploadFile = File(...), db: Session = Depends(get_db)):
    data = await file.read()
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="file too large")
    return await asyncio.to_thread(run_restore, data, "", db)


@router.post("/music/restore-item/{item_id}")
def restore_item(item_id: str, db: Session = Depends(get_db)):
    item = crud.get_item(db, item_id)
    if not item:
        raise HTTPException(status_code=404, detail="not found")
    if not manager.safe_original_name(item.filename):
        raise HTTPException(status_code=400, detail="bad filename")
    path = manager.original_dir() / item.filename
    if not path.exists():
        raise HTTPException(status_code=404, detail="file missing")
    return run_restore(path.read_bytes(), item.id, db)


@router.get("/music/restored/{sha}")
def download_restored(sha: str):
    path = restored_dir() / (sha + "_restored.wav")
    if not manager.is_sha256(sha) or not path.exists():
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(path, media_type="audio/wav")
