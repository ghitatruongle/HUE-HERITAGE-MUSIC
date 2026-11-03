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

Bảo mật tài khoản admin trưởng (mặc định bật, chỉnh qua `.env`):

- **Mật khẩu admin** phải tối thiểu 12 ký tự, có cả chữ và số (áp khi admin đổi mật khẩu của mình).
- **Token admin chỉ sống 8 giờ** (`ADMIN_TOKEN_TTL_HOURS`) trong khi user thường 24–72h; sliding session vẫn gia hạn khi đang dùng.
- **Xác thực lại trước hành động phá hủy**: tạo user, khóa/mở, xóa user, reset mật khẩu, xóa bản ghi lưu trữ đều yêu cầu nhập lại mật khẩu admin (`POST /api/auth/admin-unlock`, hiệu lực 10 phút — `ADMIN_UNLOCK_WINDOW_SECONDS`). App tự hiện hộp thoại khi cần.
- Mọi đăng nhập của admin được ghi sự kiện riêng `admin_login` vào nhật ký bảo mật.
- So khớp mật khẩu chống tấn công thời gian: user không tồn tại vẫn chạy đủ PBKDF2 (hash giả) + jitter ngẫu nhiên 2–6ms sau mỗi lần so khớp — thời gian phản hồi không tiết lộ username hay số ký tự đúng.

Mã mời được nạp theo thứ tự ưu tiên:

1. Mã dùng một lần trong CSDL (bảng `invite_codes`) — tạo trong app (tab **Quản trị → Mã mời**) hoặc gọi `POST /api/auth/invites` bằng token admin; mỗi mã chỉ đăng ký được 1 tài khoản. Admin còn có thể tạo tài khoản trực tiếp (tab **Quản trị → Người dùng** hoặc `POST /api/auth/users`) không cần mã mời
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

## Sức chịu tải (đo thật trên Mac M4, 2026-10-28)

Ramp test 1 → 1000 người dùng đồng thời bằng `tools/load_ramp.py` (đọc/xem, think-time 10–50ms):

- Đỉnh thông lượng **~700 req/s ở 25 VU**; nghẽn bắt đầu từ ~50 VU; 1 worker phục vụ ổn **~150–340 req/s** ở mức 100–1000 VU.
- Ở 700–1000 VU (stress khắc nghiệt) server **không sập, không lỗi 500** — phần vượt ngưỡng bị **xả lịch sự bằng 503** nhờ `--limit-concurrency 512`, health hồi phục ngay sau bão.
- Đăng nhập song song: ~105 lần/s (PBKDF2 600k chiếm CPU); đăng ký: ~20–25 lần/s.
- **Không dùng `--workers N > 1` với SQLite**: 2 workers làm throughput GIẢM (659 vs 718 rps) do tranh lock SQLite chéo process.
- Kịch bản thật (người dùng đọc/xem có nghỉ 2–5s giữa các thao tác) ≈ chỉ 200–500 request đồng thời ở 1000 người online → chạy thoải mái trong cấu hình trên.

Khuyến nghị vận hành LAN: 1 worker + `--limit-concurrency 512` (đã cấu hình sẵn trong `tools/deploy_lan.sh`).

Tối ưu ghi đa người dùng (2026-10-28): SQLite chạy **WAL mode** + `busy_timeout` 30s; các endpoint ghi nặng (upload, đăng ký, tạo user, xóa bản ghi) đi qua **write-slot semaphore 8** — writer xếp hàng trong app thay vì cầm kết nối pool chờ khóa; pool 100 kết nối; threadpool 192. Bộ test chuyên sâu: `tools/attack/deep_multiuser_campaign.py`.

## Khắc phục sự cố

| Lỗi | Nguyên nhân | Xử lý |
|---|---|---|
| `ModuleNotFoundError: No module named 'librosa'` | thiếu dependency | `pip install -r requirements.txt` |
| cổng 8000 bận | server khác chiếm | đổi `port=8000` trong `run_server.py` |
| transcribe báo lỗi | thiếu ffmpeg | cài ffmpeg (macOS: `brew install ffmpeg`) |