# HUONG DAN CAI DAT SERVER — HUE HERITAGE MUSIC

Hướng dẫn này dành cho người tải dự án từ GitHub về máy mới (máy không có sẵn môi trường phát triển).

## Yêu cầu hệ thống

- Python 3.12 (đã test trên macOS; Windows tương tự)
- Redis (chỉ bắt buộc khi `USE_RQ=true` — mặc định `false`)
- Git

## Bước 1 — Clone dự án

```bash
git clone https://github.com/ghitatruongle/HUE-HERITAGE-MUSIC.git
cd HUE-HERITAGE-MUSIC
```

## Bước 2 — Tạo môi trường Python

```bash
cd server
python3.12 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

Lưu ý: `librosa` và `basic-pitch` yêu cầu `numpy<2` — file requirements đã khóa đúng phiên bản.

## Bước 3 — Cấu hình

File `server/.env.example` là mẫu. Tạo file thật từ mẫu:

```bash
cp .env.example .env
```

Chỉnh `SECRET_KEY` thành chuỗi ngẫu nhiên dài (không dùng giá trị mặc định khi triển khai thật):

```bash
python -c "import secrets; print(secrets.token_hex(32))"
```

Các giá trị mặc định đã hợp lệ cho chạy local:

| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| `APP_NAME` | Hue Heritage Music API | Tên app |
| `SECRET_KEY` | change-me | Khóa mã hóa — **phải đổi** |
| `AUTH_REQUIRED` | false | bật auth khi triển khai thật |
| `ALLOWED_ORIGINS` | `*` | CORS |
| `REDIS_URL` | redis://127.0.0.1:6379/0 | Dùng khi `USE_RQ=true` |
| `USE_RQ` | false | queue bất đồng bộ (cần Redis) |
| `ACESTEP_API_URL` | http://127.0.0.1:8001 | model AI sinh nhạc (tùy chọn) |

## Bước 4 — Khởi động

```bash
python run_server.py
```

Server chạy tại `http://127.0.0.1:8000` — mở `http://127.0.0.1:8000/docs` để xem OpenAPI/Swagger.

Database tự tạo tại `<repo>/hue_heritage.db` (SQLite) ở lần chạy đầu tiên.

## Kiểm tra

```bash
curl http://127.0.0.1:8000/health
# => {"status":"ok","app":"Hue Heritage Music API",...}

curl http://127.0.0.1:8000/api/heritage
# => []  (danh sách di sản, rỗng ban đầu)

curl http://127.0.0.1:8000/api/music/models
# => {"base":"ACE-Step 1.5","base_ready":false,...}
```

## (Tùy chọn) Worker nặng — cần Redis

Nếu đặt `USE_RQ=true`, cần Redis chạy:

```bash
redis-server --daemonize yes
python -m app.workers.worker
```

## (Tùy chọn) Nối model AI sinh nhạc (ACE-Step)

Tính năng sinh nhạc/ca/cover cần máy chủ ACE-Step riêng (ngoài repo này). Khi có, đặt URL vào `ACESTEP_API_URL` trong `.env`.

## Chạy test

```bash
cd server
pytest -q
# 26 tests pass
```

## Khắc phục sự cố

| Lỗi | Nguyên nhân | Xử lý |
|---|---|---|
| `ModuleNotFoundError: No module named 'librosa'` | thiếu dependency | `pip install -r requirements.txt` |
| cổng 8000 bận | server khác chiếm | đổi `port=8000` trong `run_server.py` |
| transcribe báo lỗi | thiếu ffmpeg | cài ffmpeg (macOS: `brew install ffmpeg`) |