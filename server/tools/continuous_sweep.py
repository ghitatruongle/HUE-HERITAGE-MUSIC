import argparse
import secrets
import shutil
import socket
import subprocess
import sys

import httpx
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PYBIN = ROOT / ".venv-mac312" / "bin"
PYTHON = PYBIN / "python"
UVICORN = PYBIN / "uvicorn"
WORKDIR = ROOT / "server"
LOGDIR = Path("/tmp/hue_sweep")
REPORT = ROOT / "docs" / "bao-cao-quet-lien-tuc.md"


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def wait_health(base, timeout=40):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            r = httpx.get(base + "/health", timeout=5)
            if r.status_code == 200:
                return True
        except Exception:
            pass
        time.sleep(1)
    return False


class Server:
    def __init__(self, envdir, auth_required=True):
        import os

        self.envdir = envdir
        self.port = free_port()
        self.base = f"http://127.0.0.1:{self.port}"
        self.proc = None
        self.auth_required = auth_required
        self._env = {
            **os.environ,
            "DATABASE_URL": f"sqlite:///{self.envdir}/sweep.db",
            "STORAGE_DIR": f"{self.envdir}/storage",
            "MODELS_DIR": f"{self.envdir}/models",
            "HUE_SECURITY_LOG": f"{self.envdir}/security.log",
            "AUTH_REQUIRED": "true" if self.auth_required else "false",
            "SECRET_KEY": secrets.token_hex(32),
            "TOKEN_TTL_HOURS": "72",
            "INVITE_CODES": "CHAOS-CODE",
            "REGISTER_IP_RATE_LIMIT": "5000",
            "AUTH_FLOOD_IP_LIMIT": "5000",
        }

    def env(self):
        return dict(self._env)

    def start(self):
        self.proc = subprocess.Popen(
            [str(UVICORN), "app.main:app", "--host", "127.0.0.1", "--port", str(self.port),
             "--no-proxy-headers", "--limit-concurrency", "512"],
            cwd=WORKDIR, env=self.env(),
            stdout=open(self.envdir / "uvicorn.log", "ab"),
            stderr=subprocess.STDOUT,
        )
        if not wait_health(self.base):
            raise RuntimeError(f"server không lên trên {self.base}")

    def stop(self):
        if self.proc:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
            self.proc = None
        time.sleep(1)

    def restart(self):
        self.stop()
        time.sleep(1)
        self.start()

    def reset_db(self):
        db = self.envdir / "sweep.db"
        for suffix in ("", "-wal", "-shm"):
            f = Path(str(db) + suffix)
            if f.exists():
                f.unlink()


def run_tool(script, args, logname, env, timeout=900):
    log = LOGDIR / logname
    with open(log, "wb") as f:
        proc = subprocess.run(
            [str(PYTHON), "-I", str(ROOT / "server" / "tools" / script)] + args,
            cwd=WORKDIR, env=env, stdout=f, stderr=subprocess.STDOUT, timeout=timeout,
        )
    return proc.returncode


def probe_register(base, username, password):
    c = httpx.Client(base_url=base, timeout=60)
    r = c.post("/api/auth/register", json={
        "username": username, "email": f"{username}@gmail.com",
        "password": password, "invite_code": "CHAOS-CODE",
    })
    c.close()
    return r.status_code


def sweep_v2(envdir):
    server = Server(envdir / "v2")
    server.envdir.mkdir(parents=True, exist_ok=True)
    server.start()
    code1 = run_tool("attack/redteam_v2.py", ["--base", server.base, "--port", str(server.port)], "v2_pass1.log", server.env())
    server.restart()
    code2 = run_tool("attack/redteam_v2.py", ["--base", server.base, "--port", str(server.port)], "v2_pass2.log", server.env())
    server.stop()
    return code2


def sweep_v3(envdir):
    server = Server(envdir / "v3")
    server.envdir.mkdir(parents=True, exist_ok=True)
    server.start()
    code1 = run_tool("attack/redteam_v3.py", ["--base", server.base, "--port", str(server.port)], "v3_pass1.log", server.env())
    server.restart()
    code2 = run_tool("attack/redteam_v3.py", ["--base", server.base, "--port", str(server.port)], "v3_pass2.log", server.env())
    server.stop()
    return code2


def sweep_security_test(envdir):
    server = Server(envdir / "sectest", auth_required=False)
    server.envdir.mkdir(parents=True, exist_ok=True)
    server.start()
    code = run_tool("security_test.py", [server.base], "sectest.log", server.env())
    server.stop()
    return code


def sweep_tiered(envdir):
    server = Server(envdir / "tiered")
    server.envdir.mkdir(parents=True, exist_ok=True)
    server.start()
    admin_pw = "SweepAdmin#2026"
    st = probe_register(server.base, "ghitatruongle", admin_pw)
    server.restart()
    code = run_tool("attack/atk_tiered_campaign.py",
                    ["--base", server.base, "--admin-password", admin_pw], "tiered.log", server.env())
    server.stop()
    return code


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true", help="chỉ sectest + tiered")
    args = ap.parse_args()

    if LOGDIR.exists():
        shutil.rmtree(LOGDIR, ignore_errors=True)
    LOGDIR.mkdir(parents=True, exist_ok=True)
    envdir = LOGDIR / "env"

    stamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    print(f"SWEEP BẢO MẬT {stamp}")
    results = []

    print("== [1/4] security_test.py (37 kịch bản, auth-off) ==")
    results.append(("security_test 37", sweep_security_test(envdir)))

    print("== [2/4] tiered campaign (44 kịch bản) ==")
    results.append(("tiered 44", sweep_tiered(envdir)))

    if not args.quick:
        print("== [3/4] redteam_v2 (31 kịch bản) ==")
        results.append(("redteam_v2 31", sweep_v2(envdir)))

        print("== [4/4] redteam_v3 (45 kịch bản) ==")
        results.append(("redteam_v3 45", sweep_v3(envdir)))

    ok = all(code == 0 for _, code in results)
    line = f"- {datetime.now().strftime('%Y-%m-%d %H:%M')} — " + " | ".join(
        f"{name}: {'SẠCH' if code == 0 else f'LỖI (exit {code})'}" for name, code in results
    )
    print("\n" + line)
    try:
        if not REPORT.exists():
            REPORT.write_text("# NHẬT KÝ QUÉT BẢO MẬT LIÊN TỰC\n\n", encoding="utf-8")
        with open(REPORT, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
