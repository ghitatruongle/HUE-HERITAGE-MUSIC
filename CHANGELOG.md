# CHANGELOG — HUE HERITAGE MUSIC

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
