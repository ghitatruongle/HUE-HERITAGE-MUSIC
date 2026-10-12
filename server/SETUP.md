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
| `SECRET_KEY` | change-me | Khóa mã hóa — **phải đổi**; server từ chối khởi động nếu `AUTH_REQUIRED=true` mà còn dùng khóa mặc định |
| `AUTH_REQUIRED` | true | đặt `false` nếu chỉ muốn test nhanh local không cần đăng nhập |
| `TOKEN_TTL_HOURS` | 72 | thời hạn sống của token đăng nhập |
| `INVITE_CODES` | QHH2026 | mã mời đăng ký (dự phòng khi không có `INVITATION_CODES.json`) |
| `ALLOWED_ORIGINS` | `*` | CORS |
| `REDIS_URL` | redis://127.0.0.1:6379/0 | Dùng khi `USE_RQ=true` |
| `USE_RQ` | false | queue bất đồng bộ (cần Redis) |
| `ACESTEP_API_URL` | http://127.0.0.1:8001 | model AI sinh nhạc (tùy chọn) |

## Đăng nhập & Mã mời (Auth)

Server có 3 endpoint auth, toàn bộ bị vô hiệu hóa khi `AUTH_REQUIRED=false`:

- `POST /api/auth/register` — tạo tài khoản, bắt buộc `invite_code` hợp lệ
- `POST /api/auth/login` — nhận `identifier` (tên tài khoản hoặc email) + mật khẩu, trả về Bearer token
- `GET /api/auth/me` — xem thông tin user từ token

Mã mời được nạp theo thứ tự ưu tiên:

1. `server/INVITATION_CODES.json` (gitignored) dạng `{"valid_codes": ["MÃ_1", "MÃ_2"]}`
2. biến `INVITE_CODES` trong `.env` (phân tách bằng dấu phẩy)
3. mặc định cứng `QHH2026` (chỉ dùng để chạy thử)

Lưu ý bảo mật:

- `AUTH_REQUIRED=false` tắt toàn bộ kiểm tra token trên các tác vụ ghi (upload, sinh nhạc, chuyển văn...) — chỉ dùng khi test local.
- Khi `AUTH_REQUIRED=true`, server từ chối khởi động nếu `SECRET_KEY` vẫn là giá trị mặc định.
- Các endpoint GET/download (nghe audio gốc, tải midi/musicxml/generated...) vẫn công khai kể cả khi bật auth.
- Token hết hạn sau `TOKEN_TTL_HOURS` giờ (mặc định 72); đăng xuất chỉ xóa token phía client.

## Bước 4 — Nạp dữ liệu di sản mẫu (Khuyến nghị)

Để nạp ngay 13 bài bản di sản kinh điển (Ca Huế & Nhã nhạc/Nhạc cụ) cùng toàn bộ siêu dữ liệu âm nhạc học, cấu trúc thể thơ và lời ca luyến láy vào cơ sở dữ liệu:

```bash
python -m app.database.seed_heritage
```

## Bước 5 — Khởi động Server (Phục vụ cả Web App & API)

```bash
python run_server.py
```

Server chạy tại `http://127.0.0.1:8000`:
- **Web App**: Mở `http://127.0.0.1:8000` trên trình duyệt để sử dụng ngay giao diện ứng dụng web di sản (hỗ trợ nén Gzip, định tuyến SPA fallback).
- **Tài liệu API**: Mở `http://127.0.0.1:8000/docs` để xem OpenAPI/Swagger.
- **Build lại Web App (khi cần)**: `cd ../app && flutter build web --release`.

Database tự tạo tại `<repo>/hue_heritage.db` (SQLite) ở lần chạy đầu tiên.

## Kiểm tra

```bash
curl http://127.0.0.1:8000/health
# => {"status":"ok","app":"Hue Heritage Music API",...}

curl http://127.0.0.1:8000/api/heritage
# => danh sách di sản

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

Adapter LoRA cho màn "Tạo nhạc" được nhận từ thư mục `models/lora/` (mỗi adapter một thư mục con chứa `lokr_weights.safetensors` hoặc `adapter_model.safetensors`; nếu thư mục này tồn tại thì không quét thư mục `models/` khác).

## Chạy test

```bash
cd server
pip install -r requirements-dev.txt
pytest -q
# 48 tests pass
```

## Khắc phục sự cố

| Lỗi | Nguyên nhân | Xử lý |
|---|---|---|
| `ModuleNotFoundError: No module named 'librosa'` | thiếu dependency | `pip install -r requirements.txt` |
| cổng 8000 bận | server khác chiếm | đổi `port=8000` trong `run_server.py` |
| transcribe báo lỗi | thiếu ffmpeg | cài ffmpeg (macOS: `brew install ffmpeg`) |