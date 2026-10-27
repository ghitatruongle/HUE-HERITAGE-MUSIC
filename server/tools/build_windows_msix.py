"""Cài đặt Windows: gói MSIX phát hành nội bộ (không cần chứng chỉ cửa hàng)."""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"


def main():
    print("== 1. Build Windows release ==")
    subprocess.run(["flutter", "build", "windows", "--release"], cwd=APP, check=True)

    print("== 2. Đóng gói MSIX (cài trực tiếp, không qua Store) ==")
    r = subprocess.run(
        ["flutter", "pub", "run", "msix:build",
         "--install-certificate", "false",
         "--signtool-options", "/p"],
        cwd=APP,
    )
    if r.returncode != 0:
        print("msix build thất bại — kiểm tra `flutter pub add --dev msix`")
        sys.exit(1)
    print("== XONG ==")
    print("File .msix nằm trong app/build/ — cài bằng cú đúp chuột (Windows 10+).")


if __name__ == "__main__":
    main()
