from fastapi import APIRouter

from . import heritage, tasks, sing_learning, transcription, restoration, instruments, music_gen

api_router = APIRouter()
api_router.include_router(heritage.router)
api_router.include_router(tasks.router)
api_router.include_router(sing_learning.router)
api_router.include_router(transcription.router)
api_router.include_router(restoration.router)
api_router.include_router(instruments.router)
api_router.include_router(music_gen.router)
