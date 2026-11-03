# CHANGELOG — HUE HERITAGE MUSIC

## 0.0.2-preview (2026-11-03)

### Riêng tư dữ liệu — file test/thử mẫu không còn lộ cho người dùng
- Thêm chế độ hiển thị từng bản ghi: `Công khai` / `Chỉ admin` (cột `visibility` + `owner_user_id` tự migrate vào DB khi khởi động, bản cũ giữ nguyên công khai)
- **Upload của admin trưởng tự động ở chế độ "Chỉ admin"** — file test/thử mẫu không xuất hiện với người dùng thường ở mọi đường đọc: thư viện, chi tiết, audio, audio-url, play-url, heritage-tunes, bài học, cover/sing-original/sing-new-lyrics, luyện tập
- **Công tắc "Chỉ admin" ngay trong tab Kho lưu trữ** (Admin → Storage) — đổi chế độ tức thì, không cần tải lại trang
- **Vá lỗ signed-URL**: chữ ký gắn kèm chế độ hiện tại của bản ghi (`vis:...`) — chuyển bản ghi sang "Chỉ admin" làm vô hiệu ngay mọi URL ký cũ, không phải chờ TTL 6h; URL mới cấp cho admin vẫn phát bình thường
- Người dùng thường dò trộm bản ghi ẩn qua bất kỳ endpoint nào đều nhận 404 (không lộ sự tồn tại)

### Giao diện bảo mật — tab "Bảo mật" mới trong Quản trị
- Bảng sự kiện bảo mật đọc trực tiếp từ security.log của server: đăng nhập thành công/sai mật khẩu, flood IP, admin-unlock, đổi visibility, xóa bản ghi, tạo/xóa tài khoản, mã mời…
- Thống kê 24 giờ dạng chip + thời điểm đăng nhập admin gần nhất; lọc theo loại sự kiện, tìm theo username/IP; phân trang "Tải thêm"
- Server bổ sung 2 endpoint: `GET /api/admin/security/events` + `GET /api/admin/security/summary` (chỉ admin), log thêm sự kiện `heavy_rate_limited`

### Chống giật lag
- **Diệt "refetch storm"**: danh sách Người dùng / Mã mời trước đây gọi API lại mỗi lần rebuild giao diện — giờ fetch một lần khi mở tab, hành động (xóa/khóa/tạo) cập nhật cục bộ không tải lại cả danh sách
- **Keep-alive cả 5 tab Quản trị**: chuyển qua lại tab không còn gọi lại API, giữ nguyên trạng thái cuộn
- Phân trang "Tải thêm" cho: Kho lưu trữ, Người dùng, Mã mời, Thư viện di sản (hết cảnh cắt lặng im ở mốc 200 bản ghi)
- Server: vá N+1 query ở `GET /api/admin/storage` (1 query gộp thay vì query từng bản ghi), cache thống kê Dashboard TTL 30s (riêng dung lượng generated TTL 60s, `?refresh=1` bỏ qua)

### Dọn dẹp tự động
- Tự xóa task đã hoàn tất quá `TASK_RETENTION_DAYS` (mặc định 30 ngày) khi khởi động server — bảng tasks trước đây phình vô hạn
- Nút "Dọn dẹp dữ liệu thừa" trong tab Kho lưu trữ: xóa bản thu AI đã tạo / practice MIDI / cache bài học quá hạn (`GENERATED_RETENTION_DAYS`, `PRACTICE_MIDI_RETENTION_DAYS`, `LESSON_CACHE_RETENTION_DAYS`), báo dung lượng thu hồi + số task đã xóa, ghi sự kiện bảo mật

### Hardening
- `AUTH_REQUIRED` mặc định **true** ngay trong code — server quên cấu hình không còn mở cửa hoàn toàn
- `.env.example` bổ sung 4 biến retention + `ENABLE_DOCS` (khớp tên biến thật trong code)

### Khác
- Version app `0.0.2+1`, server stage `0.0.2-preview`
- Kiểm định: pytest 137/137 (13 test hồi quy mới), flutter analyze 0, flutter test 29/29, red-team visibility-IDOR sạch, sweep bảo mật liên tục toàn xanh

## 0.0.1 (chính thức) (2026-10-28)

### Sửa lỗi — tải lại trang không còn bị đăng xuất
- **Nguyên nhân gốc**: server gắn header `Clear-Site-Data` trên response trả web app → trình duyệt xóa sạch token đăng nhập mỗi lần F5. Đã bỏ header (giữ no-cache để vẫn nhận bản build mới qua service worker).
- **Sliding session**: `/api/auth/me` cấp lại token mới mỗi lần mở app + xác thực phiên lúc khởi động — hết hạn thì đăng xuất êm có thông báo, mất mạng giữ nguyên phiên
- TTL mặc định khuyến nghị 72h (`.env.example`)

### Quản trị hệ thống (admin xịn xò)
- **Màn hình Quản trị 4 tab** (chỉ admin trưởng thấy): Tổng quan (số liệu user/invite/kho/task + trạng thái engine AI), Người dùng, Mã mời, Kho lưu trữ
- **Tạo tài khoản trực tiếp** không cần mã mời — mật khẩu tạm tự sinh, buộc đổi ở lần đăng nhập đầu (`must_change_password`)
- Reset mật khẩu hộ cũng gắn cờ buộc đổi; app tự hiện hộp thoại nhắc đổi
- **Quản lý kho lưu trữ**: xem dung lượng từng bản ghi (gốc + MIDI/MusicXML/phục dựng), xóa cascade cả file lẫn cache bài học
- **Vá lỗ hổng**: hủy task sinh nhạc (`/music/task/{id}/cancel`) trước đây ai cũng gọi được — giờ bắt buộc đăng nhập + đúng chủ task

### Nền móng app di động
- Tải MIDI/MusicXML trên Android/iOS mở **hộp lưu/chia sẻ của hệ điều hành** (share_plus) thay vì ghi im lặng vào thư mục tạm
- **Splash screen** có thương hiệu (Android 12+/iOS/Web)
- Pin minSdk 23 / targetSdk 35; cấu hình ký release Android qua `key.properties` (mẫu `key.properties.example`, fallback debug signing để CI luôn build được)
- **CI build APK**: mỗi tag có thêm `hue-heritage-music-android.apk` trong Release

### Bảo mật
- Validate email chuẩn (regex) thay cho luật "@gmail.com duy nhất" — cả server lẫn form đăng ký
- `.env.example`: bỏ mã mời mặc định `QHH2026`; mặc định `AUTH_REQUIRED=true`
- Test hồi quy cho magic-bytes upload + các endpoint admin mới

### Quốc tế hóa & polish
- ~150 chuỗi tiếng Việt hardcode trong 18 file UI chuyển vào `AppStrings` (108 key mới, vi + en)
- Phân tích bản thu: lỗi nhận diện nhạc cụ hiện thông báo riêng thay vì im lặng

### Giả lập tấn công 3 mức độ (nhẹ / trung bình / nâng cao)
- Chiến dịch 44 kịch bản tự viết: `server/tools/attack/atk_tiered_campaign.py` (dò quét không xác thực → lạm dụng có xác thực → giả mạo token/giả danh admin/race) + chạy lại bộ 20 script tấn công chuyên sâu
- **Vá 1 lỗ hổng mức trung vừa tìm ra**: tài khoản mang mật khẩu tạm (`must_change_password`) trước đây vẫn gọi được toàn bộ API ghi (upload, sinh nhạc, xóa...) — giờ bị 403 trên mọi request ghi, chỉ mở `change-password`/`revoke-all` cho tới khi đổi mật khẩu
- Kết quả sau vá: 44/44 bị chặn, admin-takeover CLEAN (42 lần thử), privilege-escalation CLEAN, invite-race với mã one-time thật CLEAN (atomic DB lock giữ vững); pentest 37/37; pytest 115/115

### Giả lập tải 1 → 1000 người dùng cùng lúc
- Tool ramp test mới `server/tools/load_ramp.py`: đỉnh **~718 req/s @25 VU**, phục vụ ổn 150–340 req/s tới 1000 VU, **không crash / không 500** ở bất kỳ mức nào
- **Vá blackout cạn DB pool khi stress cực hạn** (1000 VU treo 60s): `deploy_lan.sh` thêm `--limit-concurrency 512` → xả tải lịch sự bằng 503, hồi phục tức thì
- Ghi khuyến nghị: KHÔNG dùng `--workers > 1` với SQLite (đo thật: 2 workers chậm hơn) — chi tiết trong SETUP.md mục "Sức chịu tải"

### Giả lập 1000 người dùng + hacker tấn công đồng thời
- Tool `server/tools/load_under_attack.py`: 100 user thật duyệt web + 5 luồng tấn công (brute force, token giả, POST flood, upload độc, dò admin) chạy song song ở các mức 25/100/400/1000 VU
- Kết quả: server giữ vững toàn bộ, user thật 0 lỗi ở tải ≤100 VU, hacker bị chặn hàng nghìn phát (429/401/403/404), không rò dữ liệu — chi tiết biên bản mục 2d

### Chống tấn công thời gian khi so khớp mật khẩu
- Login với user **không tồn tại** giờ vẫn chạy đủ PBKDF2 trên hash giả (trước đây nhanh hơn hẳn → dò được user tồn tại qua thời gian phản hồi)
- **Jitter ngẫu nhiên 2–6ms** (nguồn ngẫu nhiên mật mã) vào mọi lần so khớp mật khẩu (login, đổi mật khẩu, admin-unlock) — che nốt sai khác microseconds của so sánh
- Test hồi quy đo thời gian: 2 đường đăng nhập sai trả cùng thông điệp và cùng tầng giá

### Bảo mật tài khoản admin
- **Mật khẩu admin bắt buộc ≥12 ký tự, có chữ + số**; mật khẩu tạm reset cho admin dài ≥12 ký tự
- **Token admin chỉ sống 8 giờ** (`ADMIN_TOKEN_TTL_HOURS`) — user thường giữ 24–72h
- **Xác thực lại mật khẩu admin** trước mọi hành động phá hủy (tạo user, khóa/mở, xóa user, reset mật khẩu hộ, xóa bản ghi kho) — hiệu lực 10 phút, app tự hiện hộp thoại
- Sự kiện `admin_login` ghi riêng vào nhật ký bảo mật

### Kiểm định
- 121/121 pytest, 29/29 flutter test, analyze 0, build web release OK, pentest 37/37, tấn công 44/44, hack chuyên sâu đa người dùng VERDICT SẠCH, smoke E2E 23/23 — biên bản đầy đủ: `docs/bien-ban-kiem-dinh-0.0.1.md`
- **Nâng cấp chịu tải ghi**: SQLite WAL mode + write-slot semaphore cho endpoint ghi nặng + pool 100 + threadpool 192 — vá treo server khi ~100 upload đồng thời (400 VU: 400/400 timeout → 11/1773)
- **Vá CPU-flood đăng nhập/đăng ký**: PBKDF2 giờ chạy trên mọi lần thử (chống timing) khiến xoay username flood được CPU — thêm trần **120 login/phút/IP** + **200 đăng ký/phút/IP** (`AUTH_FLOOD_IP_LIMIT`, `REGISTER_IP_RATE_LIMIT`)
- **`/api/music/models` yêu cầu đăng nhập** (trước đây lộ engine + adapter AI cho ẩn danh)
- Phiên offline mở app không còn treo 5s (xác thực phiên chạy nền sau khi UI hiện); chuỗi "Gmail" cũ đổi hết thành "Email"; ghi chú quên mật khẩu sửa theo tính năng reset của admin
- **Vá lộ riêng tư bản thu luyện tập (red-team cao cấp)**: tên file practice MIDI đoán được theo timestamp → dò được bản thu hát của người khác; đổi sang tên random 24 ký tự mật mã, enumeration 4000 lần → 0 hit; ma trận phân quyền 31 route × 3 vai trò toàn sạch (`tools/attack/redteam_v3.py` 45/45)
- **Vá body DoS (red-team nâng cao)**: JSON API trần 2MB qua `BodyLimitMiddleware` (trước đây nuốt body 20MB+ vào RAM); upload đọc stream có trần 50MB + middleware ngắt giữa stream khi chunked vượt trần (trước đây chunked không content-length nuốt vô hạn) — red-team v2 31/31 (`tools/attack/redteam_v2.py`)

## 0.0.1-beta (2026-10-26)

### Bảo mật
- Xóa sạch mã mời mặc định `QHH2026` (config default rỗng; mã one-time quản lý qua UI admin)
- Token TTL 72h → **24h**; cơ chế **token_epoch** thu hồi phiên: đổi mật khẩu / "đăng xuất mọi thiết bị" / admin vô hiệu hóa tài khoản → mọi token cũ chết ngay
- Tài khoản có cờ `active`: admin khóa mở được; đăng nhập bị chặn khi bị khóa
- Nhật ký bảo mật xoay vòng 5MB × 3 bản

### Tài khoản
- **User tự đổi mật khẩu** (xác nhận mật khẩu cũ, tự đăng xuất thiết bị khác)
- **Admin trưởng**: danh sách tài khoản kèm vai trò/trạng thái, vô hiệu hóa/kích hoạt (không thể tự khóa mình), **đặt lại mật khẩu hộ** (mật khẩu tạm tự sinh, tự copy clipboard)

### Bảo mật (kiểm định xâm nhập)
- **Vá bypass rate limit** qua giả mạo X-Forwarded-For (uvicorn tin XFF từ localhost) — `--no-proxy-headers` trên mọi đường khởi động
- **Tắt Swagger/OpenAPI công khai** (trần thông tin API) — bật qua env `HUE_ENABLE_DOCS=1`
- Bộ pentest 48 kịch bản tự động: `server/tools/security_test.py` (auth bypass, SQLi, path traversal, upload độc, IDOR, headers)

### Hiệu năng
- **F0 tracking vector hóa numpy batch-FFT**: so sánh hát 2×10s **475ms → 163ms**; trần 4000 frames bỏ → contour phủ **cả bài dài** (30s audio = 27–42ms)
- Oracle test đối chiếu kết quả F0 cũ/mới trên nhiều tần số

### Học hát
- **Nghe lại bản thu của mình** ngay trong thẻ kết quả (web + desktop)
- **Metronome đếm nhập** 4 nhịp theo BPM bài học (tiếng tick sinh trực tiếp, bật/tắt được)
- **Xuất MIDI bản luyện** (nốt người dùng hát → file .mid tải về cho coach)
- **Tiến độ chi tiết**: trung bình 5 lượt gần nhất + danh sách từng buổi kèm điểm

### Giao diện & kỹ thuật
- Tách màn khổng lồ thành widget riêng: `TaskResultCard`, `InviteManagerSection`, `AccountManagerSection`, `ScalePracticeCard` — không đổi hành vi
- i18n: các màn Học hát / Luyện tập / Ký âm / player chuyển hết qua vi/en
- Icon launcher sinh cho Android/iOS/Windows/macOS từ logo chính thức
- **Service worker web bật lại** (Flutter quản version) — mở lần 2 không tải lại ~4MB
- CI: khi đánh tag → tự build web + macOS và đính vào GitHub Release
- `/health` chế độ mở rộng (env `HUE_HEALTH_EXTENDED=1`): engine online, task chạy/đợi, dung lượng đĩa
- `server/tools/deploy_lan.sh` — deploy LAN một lệnh; launchd plist cho tự khởi động sau reboot

## 0.0.1-alpha (2026-10-25) — commit `9b6ff8a`

- W1–W9: sửa poll/hủy task, cache engine, retry GET-only, bảo mật nền (secret guard, rehash PBKDF2, security headers, gzip audio, cache immutable), App ID `com.ghita.hueheritagemusic` 6 nền tảng, version đọc từ build, keyring cảnh báo Linux, save-as desktop, user_id task, rate limit 429, semaphore sinh nhạc, signed URLs, **Học hát Pha 1** (luyện theo câu + overlay cao độ + điểm), mã mời one-time, SSE progress, CI, luyện thang ngũ cung
- Vá debug: SSE spinner/fallback, recorder guard, double-sign, race role, pool DB + threadpool (50 tải đồng thời), warmup nền bài học (5.7s → 0.03s), fix copy clipboard trên HTTP

## 0.0.0 (2026-10-12) — `aa179d6`

- Bản phát hành đầu tiên: 10 màn hình Flutter, FastAPI server, AMT ký âm, DSP phục chế, so sánh hát, sinh nhạc ACE-Step, phân quyền cơ bản, invite code
