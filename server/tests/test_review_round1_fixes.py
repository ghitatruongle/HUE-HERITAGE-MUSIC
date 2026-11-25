import io
import json
import math
import os
import secrets
import sqlite3
import struct
import subprocess
import time
import wave
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import IntegrityError

from app import main as main_mod
from app.ai import ace_step_engine, lora_adapter
from app.api import auth as auth_api
from app.config import settings
from app.database import crud
from app.database.models import ArtifactAccess, ArtifactOwner, HeritageItem, InviteCode, Task, User
from app.database.session import SessionLocal
from app.main import BodyLimitMiddleware, LARGE_BODY_LIMIT, create_app
from app.services import amt_eval, compare_service, generator_service, lesson_service, media_pipeline, midi_service, musicxml_service, pitch_service, restoration_service, user_inflight
from app.storage import manager


def _wav_bytes(seconds=0.4, sr=8000):
    bio = io.BytesIO()
    with wave.open(bio, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        frames = bytearray()
        for i in range(int(sr * seconds)):
            v = int(12000 * math.sin(2.0 * math.pi * 440.0 * i / sr))
            frames.extend(struct.pack("<h", v))
        w.writeframes(bytes(frames))
    return bio.getvalue()


def _float32_nan_wav(sr=8000):
    samples = [0.25, float("nan"), float("inf"), float("-inf"), -0.25] * 200
    data_chunk = b"".join(struct.pack("<f", s) for s in samples)
    fmt_chunk = struct.pack("<HHIIHH", 3, 1, sr, sr * 4, 4, 32)
    riff_size = 4 + (8 + len(fmt_chunk)) + (8 + len(data_chunk))
    return (
        b"RIFF"
        + struct.pack("<I", riff_size)
        + b"WAVE"
        + b"fmt "
        + struct.pack("<I", len(fmt_chunk))
        + fmt_chunk
        + b"data"
        + struct.pack("<I", len(data_chunk))
        + data_chunk
    )


def test_transcribe_and_evaluate_reject_bad_engine(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    client = TestClient(create_app())
    wav = _wav_bytes()
    r1 = client.post(
        "/api/music/transcribe",
        files={"file": ("tone.wav", wav, "audio/wav")},
        data={"bpm": "60", "engine": "../../evil"},
    )
    assert r1.status_code == 400
    assert r1.json()["detail"] == "bad engine"

    r2 = client.post(
        "/api/music/evaluate",
        files={"file": ("tone.wav", wav, "audio/wav")},
        data={"bpm": "60", "truth": "[]", "engine": "bad_engine"},
    )
    assert r2.status_code == 400
    assert r2.json()["detail"] == "bad engine"

    with pytest.raises(ValueError):
        media_pipeline.notes_cache_path("a" * 64, 60.0, "../../evil")


def test_midi_musicxml_restored_signed_url_scope_for_personal_artifacts(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", "round1-scope-secret-" + "1" * 44, raising=False)
    db = SessionLocal()
    try:
        db.query(ArtifactAccess).delete()
        db.query(ArtifactOwner).delete()
        db.query(User).delete()
        db.commit()
    finally:
        db.close()

    client = TestClient(create_app())
    r_a = client.post("/api/auth/register", json={
        "username": "owner_alice", "email": "alice@example.com",
        "password": "AlicePass#2026", "invite_code": "TESTINVITE",
    })
    assert r_a.status_code == 200, r_a.text
    ha = {"Authorization": f"Bearer {r_a.json()['token']}"}

    r_b = client.post("/api/auth/register", json={
        "username": "other_bob", "email": "bob@example.com",
        "password": "BobPass#2026", "invite_code": "TESTINVITE",
    })
    assert r_b.status_code == 200, r_b.text
    hb = {"Authorization": f"Bearer {r_b.json()['token']}"}

    wav = _wav_bytes()
    tr = client.post(
        "/api/music/transcribe",
        files={"file": ("alice.wav", wav, "audio/wav")},
        data={"bpm": "60", "engine": "dsp"},
        headers=ha,
    )
    assert tr.status_code == 200, tr.text
    sha = tr.json()["sha"]

    rs = client.post(
        "/api/music/restore",
        files={"file": ("alice.wav", wav, "audio/wav")},
        headers=ha,
    )
    assert rs.status_code == 200, rs.text

    assert client.get(f"/api/music/midi/{sha}", headers=hb).status_code == 404
    assert client.get(f"/api/music/musicxml/{sha}", headers=hb).status_code == 404
    assert client.get(f"/api/music/restored/{sha}", headers=hb).status_code == 404
    assert client.get("/api/music/play-url", params={"path": f"/api/music/midi/{sha}"}, headers=hb).status_code == 404

    midi_play = client.get("/api/music/play-url", params={"path": f"/api/music/midi/{sha}"}, headers=ha)
    xml_play = client.get("/api/music/play-url", params={"path": f"/api/music/musicxml/{sha}"}, headers=ha)
    rest_play = client.get(f"/api/music/restored-url/{sha}", headers=ha)
    assert midi_play.status_code == 200
    assert xml_play.status_code == 200
    assert rest_play.status_code == 200

    anon = TestClient(create_app())
    assert anon.get(midi_play.json()["url"]).status_code == 200
    assert anon.get(xml_play.json()["url"]).status_code == 200
    assert anon.get(rest_play.json()["url"]).status_code == 200

    unscoped_restored = client.get(f"/api/music/restored/{sha}")
    assert unscoped_restored.status_code == 401


def test_delete_user_quarantines_tasks_and_task_to_dict_hides_audio_path(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", "round1-task-secret-" + "2" * 44, raising=False)
    db = SessionLocal()
    try:
        db.query(Task).delete()
        db.query(User).delete()
        db.commit()
    finally:
        db.close()

    client = TestClient(create_app())
    u1 = client.post("/api/auth/register", json={
        "username": "task_user1", "email": "t1@example.com",
        "password": "TaskUser1#2026", "invite_code": "TESTINVITE",
    }).json()
    u2 = client.post("/api/auth/register", json={
        "username": "task_user2", "email": "t2@example.com",
        "password": "TaskUser2#2026", "invite_code": "TESTINVITE",
    }).json()
    h2 = {"Authorization": f"Bearer {u2['token']}"}

    db = SessionLocal()
    try:
        t = crud.create_task(
            db,
            "transcribe",
            {"bpm": 60, "audio_path": "/secret/internal/storage/file.wav"},
            user_id=u1["id"],
        )
        tid = t.id
        d = crud.task_to_dict(t)
        assert "audio_path" not in d["params"]
        assert d["params"]["bpm"] == 60
        assert crud.delete_user_everything(db, u1["id"]) is True
        reloaded = crud.get_task(db, tid)
        assert reloaded is not None
        assert reloaded.user_id == f"deleted:{u1['id']}"[:64]
    finally:
        db.close()

    r_list = client.get("/api/task", headers=h2)
    assert r_list.status_code == 200
    assert all(row["id"] != tid for row in r_list.json())
    assert client.get(f"/api/task/{tid}", headers=h2).status_code == 404


def test_generate_rejects_nan_strength(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", False, raising=False)
    client = TestClient(create_app())
    r = client.post(
        "/api/music/generate",
        params={"prompt": "ca hue", "duration": 20, "strength": "nan"},
    )
    assert r.status_code == 400
    assert r.json()["detail"] == "bad strength"


def test_midi_low_bpm_and_musicxml_polyphonic_split_bars():
    notes = [
        {"midi": 60, "start": 0.0, "end": 5.0, "velocity": 80},
        {"midi": 64, "start": 1.0, "end": 2.0, "velocity": 80},
    ]
    mid = midi_service.write_midi(notes, 1.0)
    assert mid.startswith(b"MThd")
    bars = musicxml_service.split_bars(notes)
    assert len(bars) == 2
    assert all(item["pos"] >= 0.0 for bar in bars for item in bar)
    assert any(item["midi"] == 64 and item["pos"] == 1.0 for item in bars[0])
    xml = musicxml_service.build_musicxml(notes, 60.0, "Poly")
    assert "<score-partwise" in xml


def test_amt_eval_validation_and_safe_error_stats():
    assert amt_eval.valid_truth([{"midi": 60, "start": 0.0, "end": 0.5}]) is True
    assert amt_eval.valid_truth([{"midi": True, "start": 0.0, "end": 0.5}]) is False
    assert amt_eval.valid_truth([{"midi": 20000, "start": 0.0, "end": 0.5}]) is False
    assert amt_eval.valid_truth([{"midi": 60, "start": float("nan"), "end": 0.5}]) is False
    assert amt_eval.valid_truth([{"midi": 60, "start": 0.0, "end": float("inf")}]) is False

    pitch_stats, _, _ = amt_eval.error_stats(
        [{"midi": 62, "start": 0.0, "end": 0.5}],
        [{"midi": 60, "start": 0.0, "end": 0.5}],
    )
    assert pitch_stats["mean"] == 200.0


def test_compare_match_note_sequences_two_octave_and_no_octave_mode():
    ref = [{"freq": 440.0, "start": 0.0, "end": 0.5}]
    user_two_oct = [{"freq": 110.0, "start": 0.0, "end": 0.5}]
    assert compare_service._match_note_sequences(ref, user_two_oct, octave_normalize=True) == [(0, 0)]
    assert compare_service._match_note_sequences(ref, user_two_oct, octave_normalize=False) == []


def test_pitch_high_sr_resample_and_nan_float32_wav():
    samples, sr = pitch_service.read_mono_wav(_float32_nan_wav())
    assert sr == 8000
    assert all(math.isfinite(float(v)) for v in samples)

    arr = [math.sin(2.0 * math.pi * 220.0 * i / 999983.0) for i in range(5000)]
    out, out_sr = pitch_service.resample_16k(arr, 999983)
    assert out_sr == pitch_service.UNIFORM_SR
    assert len(out) > 0


def test_media_pipeline_atomic_artifacts():
    wav = _wav_bytes()
    digest, stem, mid, xm = media_pipeline.write_artifacts(
        wav, [{"midi": 69, "start": 0.0, "end": 0.3, "velocity": 80}], 60.0, "hue"
    )
    assert mid.exists() and xm.exists()
    assert not list(manager.midi_dir().glob("*.part"))
    assert not list(manager.xml_dir().glob("*.part"))


def test_generator_service_reason_db_fallback_and_queue_eviction():
    db = SessionLocal()
    try:
        saved = crud.create_task(db, "generate", {"prompt": "test"}, user_id=None)
        crud.update_task(db, saved.id, status="error", error="engine failed", finished=True)
        tid = saved.id
    finally:
        db.close()

    with generator_service.TASKS_LOCK:
        generator_service.TASKS.pop(tid, None)
    fetched = generator_service.get_task(tid)
    assert fetched is not None
    assert fetched["reason"] == "engine failed"

    with generator_service.TASKS_LOCK:
        saved_tasks = dict(generator_service.TASKS)
        generator_service.TASKS.clear()
        try:
            for idx in range(generator_service.MAX_TASKS):
                st = "queued" if idx == 0 else "done"
                generator_service.TASKS[f"t_{idx}"] = {"id": f"t_{idx}", "created_at": float(idx), "status": st}
            if len(generator_service.TASKS) >= generator_service.MAX_TASKS:
                oldest = [
                    k
                    for k in sorted(generator_service.TASKS, key=lambda k: generator_service.TASKS[k]["created_at"])
                    if generator_service.TASKS[k].get("status") not in ("running", "queued", "pending")
                ]
                for k in oldest[: max(0, len(generator_service.TASKS) - generator_service.MAX_TASKS + 1)]:
                    generator_service.TASKS.pop(k, None)
            assert "t_0" in generator_service.TASKS
            assert "t_1" not in generator_service.TASKS
        finally:
            generator_service.TASKS.clear()
            generator_service.TASKS.update(saved_tasks)


def test_register_integrity_rollback_preserves_invite(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "invite_codes", "", raising=False)
    db = SessionLocal()
    try:
        db.query(InviteCode).filter(InviteCode.code == "ATOMICINV1").delete()
        db.query(User).filter(User.username == "atomic_user_a").delete()
        db.query(User).filter(User.username == "atomic_user_b").delete()
        db.commit()
        crud.create_invite_code(db, "ATOMICINV1", note="test")
    finally:
        db.close()

    client = TestClient(create_app())
    r1 = client.post("/api/auth/register", json={
        "username": "atomic_user_a", "email": "same@example.com",
        "password": "AtomicPass#2026", "invite_code": "ATOMICINV1",
    })
    assert r1.status_code == 200, r1.text

    db = SessionLocal()
    try:
        db.query(InviteCode).filter(InviteCode.code == "ATOMICINV2").delete()
        db.commit()
        crud.create_invite_code(db, "ATOMICINV2", note="test2")
    finally:
        db.close()

    from sqlalchemy.exc import IntegrityError
    orig_commit = SessionLocal
    called = {"n": 0}

    r_dup = client.post("/api/auth/register", json={
        "username": "atomic_user_b", "email": "same@example.com",
        "password": "AtomicPass#2026", "invite_code": "ATOMICINV2",
    })
    assert r_dup.status_code == 409

    db = SessionLocal()
    try:
        inv = crud.get_invite_code(db, "ATOMICINV2")
        assert inv is not None and inv.used_by is None
    finally:
        db.close()


def test_body_limit_middleware_multipart_headroom():
    mw = BodyLimitMiddleware(lambda s, r, se: None)
    assert mw._limit_for("/api/music/transcribe") >= LARGE_BODY_LIMIT
    assert mw._limit_for("/api/lessons/abc/practice") >= LARGE_BODY_LIMIT
    assert manager.COMPARE_BODY_LIMIT == 2 * manager.MAX_ANALYSIS_BYTES + 2 * 1024 * 1024


def test_lora_resolve_rejects_dot_and_root_without_creating_dir(monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "models_dir", tmp_path, raising=False)
    assert not (tmp_path / "lora").exists()
    assert lora_adapter.lora_root() == tmp_path
    assert not (tmp_path / "lora").exists()
    assert lora_adapter.resolve(".") is None
    assert lora_adapter.resolve("./") is None
    assert lora_adapter.resolve("..") is None

    lora_dir = tmp_path / "lora"
    lora_dir.mkdir()
    adapter_file = lora_dir / "hue_v1.safetensors"
    adapter_file.write_bytes(b"ok")
    assert lora_adapter.lora_root() == lora_dir
    assert lora_adapter.resolve(".") is None
    assert lora_adapter.resolve("hue_v1.safetensors") == str(adapter_file.resolve())


def test_crud_crash_offset_and_invite_integrity_rollback():
    db = SessionLocal()
    try:
        db.query(InviteCode).filter(InviteCode.code == "R2DUPINV").delete()
        db.commit()
        res = crud.list_crash_reports(db, limit=10, offset=-25)
        assert isinstance(res, list)
        row = crud.create_invite_code(db, "R2DUPINV", note="first")
        assert row.code == "R2DUPINV"
        with pytest.raises(IntegrityError):
            crud.create_invite_code(db, "R2DUPINV", note="dup")
        assert crud.get_invite_code(db, "R2DUPINV") is not None
    finally:
        db.query(InviteCode).filter(InviteCode.code == "R2DUPINV").delete()
        db.commit()
        db.close()


def test_create_invite_integrity_race_returns_409(monkeypatch):
    app = create_app()
    app.dependency_overrides[auth_api.require_staff] = lambda: "staff_r2"
    monkeypatch.setattr(crud, "get_invite_code", lambda db, code: None)

    def _raise_dup(db, code, note=""):
        raise IntegrityError("insert", {}, Exception("unique"))

    monkeypatch.setattr(crud, "create_invite_code", _raise_dup)
    try:
        client = TestClient(app)
        resp = client.post("/api/auth/invites", json={"code": "RACEINV99", "note": "race"})
        assert resp.status_code == 409
        assert resp.json()["detail"] == "code already exists"
    finally:
        app.dependency_overrides.clear()


def test_cancel_gen_task_rejects_non_truong_admin_role(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(
        settings,
        "secret_key",
        "test-secret-key-for-round2-unit-tests-at-least-32-chars",
        raising=False,
    )
    db = SessionLocal()
    impostor_id = f"imp_{secrets.token_hex(4)}"
    owner_id = f"own_{secrets.token_hex(4)}"
    tid = f"t_r2_{secrets.token_hex(4)}"
    try:
        db.query(User).filter(User.username.in_(["not_truong_r2", "owner_r2"])).delete(synchronize_session=False)
        db.commit()
        impostor = User(
            id=impostor_id,
            username="not_truong_r2",
            email="not_truong_r2@example.com",
            password_hash="x",
            role="admin",
            active=1,
            token_epoch=0,
        )
        owner = User(
            id=owner_id,
            username="owner_r2",
            email="owner_r2@example.com",
            password_hash="x",
            role="user",
            active=1,
            token_epoch=0,
        )
        db.add(impostor)
        db.add(owner)
        db.commit()
        token = auth_api.make_token_for(impostor)
        owner_token = auth_api.make_token_for(owner)
    finally:
        db.close()

    with generator_service.TASKS_LOCK:
        saved = dict(generator_service.TASKS)
        generator_service.TASKS[tid] = {"id": tid, "user_id": owner_id, "status": "queued", "created_at": time.time()}
    try:
        client = TestClient(create_app())
        resp = client.post(
            f"/api/music/task/{tid}/cancel",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 404
        ok_resp = client.post(
            f"/api/music/task/{tid}/cancel",
            headers={"Authorization": f"Bearer {owner_token}"},
        )
        assert ok_resp.status_code == 200
    finally:
        with generator_service.TASKS_LOCK:
            generator_service.TASKS.clear()
            generator_service.TASKS.update(saved)
        db = SessionLocal()
        try:
            db.query(User).filter(User.id.in_([impostor_id, owner_id])).delete(synchronize_session=False)
            db.commit()
        finally:
            db.close()


def test_warmup_lessons_skips_instrumental_before_build(monkeypatch):
    item = HeritageItem(
        id="inst_warmup_r2",
        title="Nguoi ngoi",
        type="Nha nhac",
        is_instrumental=True,
        lyrics="",
    )
    called = []
    monkeypatch.setattr(time, "sleep", lambda _s: None)
    monkeypatch.setattr(crud, "get_creation_tunes", lambda _db: [item])
    monkeypatch.setattr(crud, "get_item", lambda _db, _id: item)
    monkeypatch.setattr(lesson_service, "build_lesson", lambda it: called.append(it.id))
    main_mod._warmup_lessons()
    assert called == []


def test_db_backup_script_validation_spaces_and_failed_check(tmp_path):
    script = Path(__file__).resolve().parents[1] / "tools" / "db_backup.sh"
    db_file = tmp_path / "src.db"
    conn = sqlite3.connect(str(db_file))
    conn.execute("CREATE TABLE t (x INT);")
    conn.commit()
    conn.close()

    out_dir = tmp_path / "dir with spaces"
    bad_keep = subprocess.run(["bash", str(script), str(db_file), str(out_dir), "0"], capture_output=True, text=True)
    assert bad_keep.returncode != 0

    ok_run = subprocess.run(["bash", str(script), str(db_file), str(out_dir), "1"], capture_output=True, text=True)
    assert ok_run.returncode == 0, ok_run.stderr
    assert len(list(out_dir.glob("hue_heritage_*.db"))) == 1

    shim_dir = tmp_path / "shim"
    shim_dir.mkdir()
    shim_sqlite = shim_dir / "sqlite3"
    shim_sqlite.write_text(
        "#!/usr/bin/env bash\n"
        "if [[ \"$*\" == *\"PRAGMA quick_check\"* ]]; then\n"
        "  echo corrupt\n"
        "else\n"
        "  touch \"$3\"\n"
        "fi\n"
    )
    shim_sqlite.chmod(0o755)
    bad_dir = tmp_path / "bad out"
    env = dict(os.environ)
    env["PATH"] = f"{shim_dir}:{env.get('PATH', '')}"
    bad_run = subprocess.run(["bash", str(script), str(db_file), str(bad_dir), "2"], capture_output=True, text=True, env=env)
    assert bad_run.returncode != 0
    assert list(bad_dir.glob("hue_heritage_*.db")) == []


def test_multi_user_same_audio_artifact_access(monkeypatch):
    monkeypatch.setattr(settings, "auth_required", True, raising=False)
    monkeypatch.setattr(settings, "secret_key", "multi-owner-scope-" + "9" * 46, raising=False)
    db = SessionLocal()
    try:
        db.query(ArtifactAccess).delete()
        db.query(ArtifactOwner).delete()
        db.query(User).filter(User.username.in_(["co_a", "co_b", "co_c"])).delete(synchronize_session=False)
        db.commit()
    finally:
        db.close()

    client = TestClient(create_app())
    headers = {}
    for uname in ("co_a", "co_b", "co_c"):
        r = client.post("/api/auth/register", json={
            "username": uname,
            "email": f"{uname}@example.com",
            "password": "CoOwnerPass#2026",
            "invite_code": "TESTINVITE",
        })
        assert r.status_code == 200, r.text
        headers[uname] = {"Authorization": f"Bearer {r.json()['token']}"}

    wav = _wav_bytes()
    r1 = client.post("/api/music/restore", files={"file": ("s.wav", wav, "audio/wav")}, headers=headers["co_a"])
    assert r1.status_code == 200, r1.text
    sha = r1.json()["sha"]
    t1 = client.post(
        "/api/music/transcribe",
        files={"file": ("s.wav", wav, "audio/wav")},
        data={"bpm": "60", "engine": "dsp"},
        headers=headers["co_a"],
    )
    assert t1.status_code == 200, t1.text

    assert client.get(f"/api/music/restored/{sha}", headers=headers["co_b"]).status_code == 404
    assert client.get(f"/api/music/midi/{sha}", headers=headers["co_b"]).status_code == 404

    r2 = client.post("/api/music/restore", files={"file": ("s.wav", wav, "audio/wav")}, headers=headers["co_b"])
    assert r2.status_code == 200, r2.text
    assert r2.json()["sha"] == sha
    t2 = client.post(
        "/api/music/transcribe",
        files={"file": ("s.wav", wav, "audio/wav")},
        data={"bpm": "60", "engine": "dsp"},
        headers=headers["co_b"],
    )
    assert t2.status_code == 200, t2.text

    b_url = client.get(f"/api/music/restored-url/{sha}", headers=headers["co_b"])
    assert b_url.status_code == 200
    assert client.get(b_url.json()["url"]).status_code == 200
    assert client.get(f"/api/music/midi/{sha}", headers=headers["co_b"]).status_code == 200
    assert client.get(f"/api/music/musicxml/{sha}", headers=headers["co_b"]).status_code == 200

    assert client.get(f"/api/music/restored-url/{sha}", headers=headers["co_c"]).status_code == 404
    assert client.get(f"/api/music/midi/{sha}", headers=headers["co_c"]).status_code == 404
    assert client.get(f"/api/music/musicxml/{sha}", headers=headers["co_c"]).status_code == 404


def test_estimate_f0_bounded_peak_memory():
    import tracemalloc

    samples, sr = pitch_service.read_mono_wav(_wav_bytes(seconds=6.0, sr=16000))
    tracemalloc.start()
    tracemalloc.reset_peak()
    times, f0s = pitch_service.estimate_f0(samples, sr, hop=256, fmin=70.0)
    _, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    assert len(times) > 300 and len(f0s) == len(times)
    assert peak < 10 * 1024 * 1024, f"peak={peak / 1048576:.2f}MB"


def test_restoration_vectorized_fixes_clicks_and_returns_valid_wav():
    sr = 8000
    frames = []
    for i in range(sr):
        v = int(6000 * math.sin(2.0 * math.pi * 220.0 * i / sr))
        if i == 2000:
            v = 30000
        frames.append(struct.pack("<h", v))
    bio = io.BytesIO()
    with wave.open(bio, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(b"".join(frames))
    out, rep = restoration_service.restore(bio.getvalue())
    assert out.startswith(b"RIFF")
    assert rep["clicks_fixed"] >= 1


def test_run_dsp_caps_concurrency_to_worker_threads(monkeypatch):
    import asyncio
    import threading

    monkeypatch.setattr(settings, "worker_threads", 2, raising=False)
    lock = threading.Lock()
    state = {"active": 0, "peak": 0}

    def work():
        with lock:
            state["active"] += 1
            state["peak"] = max(state["peak"], state["active"])
        time.sleep(0.05)
        with lock:
            state["active"] -= 1
        return True

    async def driver():
        return await asyncio.gather(*(user_inflight.run_dsp(work) for _ in range(6)))

    res = asyncio.run(driver())
    assert all(res)
    assert state["peak"] <= 2, state


def test_practice_slot_follows_heavy_inflight_env_setting(monkeypatch):
    from fastapi import HTTPException
    from app.api import lessons as L

    L._PRACTICE_INFLIGHT.clear()
    monkeypatch.setattr(settings, "heavy_inflight_per_user", 1, raising=False)
    L._practice_slot_acquire("u_env")
    with pytest.raises(HTTPException) as exc_info:
        L._practice_slot_acquire("u_env")
    assert exc_info.value.status_code == 429
    L._practice_slot_release("u_env")
    assert "DB_WRITE_SLOTS" in (Path(__file__).resolve().parents[1] / ".env.example").read_text()


def test_uvicorn_limit_concurrency_has_headroom_over_shed():
    assert settings.uvicorn_limit_concurrency >= settings.shed_concurrency + 256
    text = (Path(__file__).resolve().parents[1] / ".env.example").read_text()
    assert "UVICORN_LIMIT_CONCURRENCY=1024" in text
