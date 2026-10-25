# HUONG DAN CAI DAT SERVER — HUE HERITAGE MUSIC

Hướng dẫn này dành cho người tải dự án từ GitHub về máy mới (máy không có sẵn môi trường phát triển).

## Yêu cầu hệ thống

- Python 3.12 (đã test trên macOS và Windows; Linux tương tự). **Không dùng Python 3.13+** — `basic-pitch` yêu cầu `numpy<2`
- Redis (chỉ bắt buộc khi `USE_RQ=true` — mặc định `false`)
- Git
- ffmpeg (tùy chọn, chỉ cần khi xử lý định dạng ngoài WAV)

### Ghi chú theo hệ điều hành

| Hệ điều hành | Venv | Ghi chú |
|---|---|---|
| macOS (Apple Silicon) | `python3.12 -m venv .venv-mac312` | chạy tốt toàn bộ tính năng, kể cả basic-pitch |
| Windows | `py -3.12 -m venv .venv` | kích hoạt: `.venv\Scripts\activate`; theo lộ trình phần cứng, Windows dùng cho dev/demo và suy luận turbo INT8 |
| Linux | `python3.12 -m venv .venv` | cần thêm `libsndfile1` (cho soundfile) và `ffmpeg`; app desktop cần `libsecret` + keyring để lưu token đăng nhập |

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

Server có các endpoint auth:

- `POST /api/auth/register` — tạo tài khoản, bắt buộc `invite_code` hợp lệ; tài khoản mới luôn mang vai trò `user`
- `POST /api/auth/login` — nhận `identifier` (tên tài khoản hoặc email) + mật khẩu, trả về Bearer token kèm `role`
- `GET /api/auth/me` — xem thông tin user từ token (gồm `role`)
- `GET /api/auth/users` — liệt kê toàn bộ tài khoản + vai trò; **chỉ admin trưởng dùng được**

Vai trò (role): chỉ có `admin` và `user`. **Admin trưởng duy nhất là tài khoản `ghitatruongle`** — server tự động gán khi khởi động (biến `ADMIN_TRUONG_USERNAME` trong `.env` nếu cần đổi) và tự hạ mọi tài khoản khác về `user`, nên không thể có admin thứ hai xuất hiện. Mọi tài khoản đăng ký qua mã mời/web đều là `user`.

Mã mời được nạp theo thứ tự ưu tiên:

1. Mã dùng một lần trong CSDL (bảng `invite_codes`) — tạo bằng `python tools/create_invite_code.py <MÃ> --note "ghi chú"`; mỗi mã chỉ đăng ký được 1 tài khoản
2. `server/INVITATION_CODES.json` (gitignored) dạng `{"valid_codes": ["MÃ_1", "MÃ_2"]}` (dùng nhiều lần)
3. biến `INVITE_CODES` trong `.env` (phân tách bằng dấu phẩy, dùng nhiều lần)

Nếu cả 3 nguồn đều rỗng thì đăng ký bị đóng (không còn mã mặc định cứng).

Lưu ý bảo mật:

- `AUTH_REQUIRED=false` tắt toàn bộ kiểm tra token trên các tác vụ ghi (upload, sinh nhạc, chuyển văn...) — chỉ dùng khi test local.
- Khi `AUTH_REQUIRED=true`, server từ chối khởi động nếu `SECRET_KEY` là một trong các giá trị cứng đã biết hoặc ngắn hơn 32 ký tự.
- Khi bật auth, các route tải audio yêu cầu token Bearer hoặc liên kết có chữ ký (signed URL) do server phát.
- Mọi sự kiện đăng nhập/đăng ký (thành công, thất bại, bị chặn 429) được ghi vào `logs/security.log`.
- Token hết hạn sau `TOKEN_TTL_HOURS` giờ (mặc định 72); đăng xuất chỉ xóa token phía client.
- Triển khai qua LAN thật sự nên đặt HTTPS ở tầng reverse proxy (caddy/nginx) và thu hẹp `ALLOWED_ORIGINS`.

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
```

Từ gốc repo (macOS venv chuẩn): `./.venv-mac312/bin/python -m pytest server/tests -q`.

## Khắc phục sự cố

| Lỗi | Nguyên nhân | Xử lý |
|---|---|---|
| `ModuleNotFoundError: No module named 'librosa'` | thiếu dependency | `pip install -r requirements.txt` |
| cổng 8000 bận | server khác chiếm | đổi `port=8000` trong `run_server.py` |
| transcribe báo lỗi | thiếu ffmpeg | cài ffmpeg (macOS: `brew install ffmpeg`) |