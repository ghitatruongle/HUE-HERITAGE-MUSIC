# CHANGELOG — HUE HERITAGE MUSIC

## 0.0.3 (chính thức) (2026-11-11)

> Bản chính thức của chuỗi 0.0.3: nền beta đã kiểm định trọn vẹn + đợt đại tu ĐỒ HOẠ & GIAO DIỆN — bản sắc "cung đình Huế" bằng font riêng và hoạ tiết vẽ code, hệ chuyển động trọn vẹn, dọn sạch màu cứng và thống nhất bộ widget. Không thêm tính năng mới, không đổi cấu trúc điều hướng.

### Đồ hoạ — bản sắc thị giác
- **Font riêng 2 tầng, hỗ trợ trọn dấu tiếng Việt** (giấy phép OFL, bundle ~1.1MB): Playfair Display cho tiêu đề (chất serif cung đình) + Be Vietnam Pro cho thân bài — hết cảnh mỗi nền tảng một mặt chữ (trước đây khai 'Roboto' nhưng không bundle)
- **Hoạ tiết cung đình vẽ bằng CustomPainter** (không cần file ảnh): lớp sóng nước + hoa văn kim cương phủ mờ trên hero Trang chủ, banner Sáng tạo, card album; **đĩa nhựa VinylDisc** vẽ rãnh vây + máng sáng thay icon `Icons.album` ở màn nghe Kho di sản
- Màn Đăng nhập có header thương hiệu (logo + tên app chữ display)

### Giao diện — sửa lỗi thật
- **3 chỗ chữ gần như tàng hình ở light mode trong màn Sáng tạo** (lời bài hát, hướng dẫn vần, banner giai điệu khoá dùng màu dark-theme viết cứng) — giờ theo theme
- Note "không đặt lại mật khẩu" màn Đăng nhập không còn hộp vàng sáng lùn trong dark mode
- Sidebar và pill trạng thái server dùng đúng token theme (trước đây lặp palette viết cứng ngoài AppTheme)
- TabBar pill ở Học hát/Phục dựng và spinner trong nút so sánh dùng `onPrimary`; card engine offline Quản trị dùng `statusDanger` thay `redAccent`
- Thống nhất widget kit có sẵn: EmptyState (Lịch sử/Sáng tạo/Kho lưu trữ/Mời/Tài khoản), ErrorPanel (Đăng nhập/Sáng tạo/Mời/Tài khoản), `statusColor()` và ChartPalette dùng một nguồn duy nhất

### Chuyển động (motion) — từ số 0 lên hệ trọn vẹn
- Page transitions chuẩn nền tảng (Cupertino trên macOS/iOS, fade-up Android/Windows/Linux)
- **Skeleton loader nhấp nháy thay 10 chỗ spinner trần** (Kho di sản, Sáng tạo, Quản trị ×4 — Tổng quan/Kho/Bài học/Crash — Bảo mật, Phục dựng, danh sách bài học Học hát, player đang nạp)
- Stagger entrance cho lưới Trang chủ (danh sách dài chỉ dùng skeleton — không stagger từng dòng để tránh phát lại animation khi cuộn)
- Chart: tooltip chạm tới tay, trục Hz/giây chuẩn hoá, lưới mảnh — một helper chung cho cả 5 biểu đồ

### Responsive, a11y, i18n
- `AppBreakpoints` hằng số chung thay 3 mốc phân tán 720/860/900
- Nút chạm tối thiểu 44dp (nút Phục dựng trong danh sách, nút hủy tác vụ, switch đếm nhập bỏ scale 0.85, nút VI/theme sidebar thu gọn)
- Semantics + Tooltip cho công tắc luyến láy (trước đây là GestureDetector trần)
- Label dropdown giọng/tông độ/tâm trạng dịch sang tiếng Anh cho user EN — **value gửi máy chủ giữ nguyên chuỗi Việt (API không đổi)**

### Vận hành
- Dọn dẹp định kỳ **giữ lại marker `.gitkeep`** (3 marker storage/heritage bị maintenance xoá mất trước đây — đã khôi phục + test ghim)
- Bump version `0.0.3-beta` → `0.0.3` (FastAPI title, /health extended, app, smoke assert)

### Kiểm định
- pytest **296/296** trên venv có basic-pitch (thêm 1 test `.gitkeep` survives cleanup); parity venv Python 3.9 không còn import được app (code cần ≥3.10 — tình trạng có trước, không thuộc đợt này)
- flutter analyze **0** · flutter test **90/90** (+9: 3 test màu cứng light/dark, 1 render motif + đĩa nhựa, 4 test 360dp cho Sáng tạo/Phục dựng/Học hát/Quản trị, 1 test label i18n)
- Build web release OK

## 0.0.3-beta (2026-11-09)

> Đợt vá nền tảng ổn định: chấm dứt triệt để lỗi "chết im lặng" khi ký âm đồng thời (NK3), trả nợ UI trần lưu trữ đã hứa ở 0.0.2, và siết endpoint tác vụ không còn nhận đường dẫn file từ client.

### Máy chủ — hết treo vô hạn khi ký âm đồng thời (NK3)
- Basic-pitch có trần chờ khoá (mặc định 90s, `BASIC_PITCH_LOCK_WAIT_TIMEOUT`): engine bận trả 503 "engine busy" lịch sự thay vì treo request vô hạn; lối tắt cache model đọc ngoài khoá nên không còn chặn đứng sau trần này
- Trần thời gian chạy 1 lần predict (mặc định 600s, `BASIC_PITCH_RUN_TIMEOUT`): engine kẹt bị cô lập (poisoned) — trả 503 cho mọi request mới cho tới khi thread kẹt kết thúc rồi tự phục hồi với model mới; không còn chết lan toàn bộ
- Worker pool không còn nuốt exception im lặng: mọi lỗi task (kể cả BaseException) đều vào log; worker sống sót qua task lỗi và tiếp tục rút hàng đợi

### Máy chủ — endpoint tác vụ sạch hơn
- `POST /api/task` không còn nhận `audio_path` do client cung cấp — chỉ nhận `heritage_id`; server tự tra file gốc theo item và kiểm quyền xem trước khi dispatch, client gửi kèm audio_path cũng bị bỏ qua

### Ứng dụng
- Màn Cài đặt có khối **"Lưu trữ"**: người dùng thường thấy "đã dùng X / trần Y" kèm thanh tiến độ (đỏ khi chạm trần); admin trưởng thấy "Không giới hạn"; refresh tự động khi mở màn — trả nợ ghi nhận "UI hiển thị sẽ vào bản sau" của 0.0.2

### Kiểm định
- Review chuyên sâu 2 vòng (tự soi từng diff + 2 agent độc lập tuần tự server → client): **12 findings — các lỗi thật đã vá hết**, đáng chú ý nhất: bản rewrite basic-pitch từng làm **mất khối ghi WAV** (file 0 byte → predict luôn fail → fallback DSP âm thầm, test cũ không bắt được vì fake predict không đọc file) — đã khôi phục + thêm test ghim đọc lại file WAV; và race 2 helper predict đồng thời trên cùng model sau một lần stall — đã thêm re-check trong khoá
- pytest **279/279 (0 skip)** trên venv có basic-pitch — test 440Hz chạy thật engine neural (model nạp + predict + bắt đúng MIDI 69); **278 passed + 1 skip** trên venv không có basic-pitch (parity); thêm 9 test NK3: lock-timeout fail-fast · fast-path cache model không chặn khoá predict · ghi WAV hợp lệ (1 kênh/16-bit/đúng số mẫu) · engine stall poisoned + tự phục hồi · 503 cả 2 endpoint transcribe + evaluate · pool sống sót BaseException + log · task theo heritage_id (404 chặn lộ item admin_only · 400 thiếu heritage_id · audio_path client bị bỏ qua)
- flutter analyze **0** · flutter test **76/76** (thêm 6 test card Lưu trữ + nhánh quota=0)
- Build web release OK · Storm ký âm 16 người dùng đồng thời trên server cô lập: **CLEAN** — 16/16 → 200 (wall 4.7s với basic-pitch thật, 0 thread kẹt), wave hồi phục 16/16 → 200 trong 0.1–0.3s, health 0 bad, 0 Traceback; probe đơn chứng minh `engine=basic_pitch`, bắt đúng 440Hz
- Verify orchestrator trên server cô lập 0.0.3-beta (chạy lại sau review-fix): Smoke E2E **39/39** · DSP-storm **SỐNG/SẠCH** (restore 12×200 · analyze 18×200 + 6×429 đúng trần per-user · compare/transcribe 200 hết · **5xx=0** · health max 391ms · RSS đỉnh ~864MB) · Stability restart-giữa-bão **SẠCH** — dữ liệu nguyên vẹn, 0 Traceback

### Hạn chế đã biết (trung thực)
- Helper predict nếu kẹt cứng trong native code (hiếm) sẽ giữ engine ở trạng thái 503 cho tới khi thread đó tự kết thúc hoặc server khởi động lại; trạng thái này lộ ra ở `/health` extended qua `basic_pitch_stalled` để giám sát

### Bảo mật — đợt săn vá 2026-11-10 (bổ sung sau bản beta)
- Vá: F-pwd1 · F-rl1 (rate-limit) · F-race + 3 đường IDOR chặn (B1/B2/B3) · guard mạo danh admin (impersonation-guard) · hardening epoch-equality / early-abort / race-serialized
- Thêm 4 bộ test khóa mới: test_idor_locks · test_nk3_resilience · test_rate_limit_locks · test_upload_surface_locks
- pytest sau đợt này: **295/295 (0 skip)** · flutter test 81/81 · basic 45/45 · Kill-chain 43/43 · Final assault 42.2k hits=0

## 0.0.2 (chính thức) (2026-11-08)

> Bản chính thức của chuỗi 0.0.2: nền beta3 đã kiểm định trọn vẹn + lớp "governance" cho chạy dài ngày tháng — dọn dẹp tự động khi server đang chạy, trần lưu trữ theo người dùng, backup cơ sở dữ liệu, crash-log chỉ admin xem. Không thêm tính năng mới ngoài các mục bền vững này.

### Độ bền lưu trữ (disk governance)
- **Dọn dẹp định kỳ khi server đang chạy** (mỗi 6 giờ, `MAINTENANCE_INTERVAL_HOURS`): toàn bộ retention 7/14/30 ngày không còn chỉ chạy lúc khởi động hay chờ admin bấm nút — server chạy bằng launchd nhiều tháng vẫn tự giữ đĩa sạch
- Thêm 3 cây lưu trữ vào dọn dẹp: `heritage/restored/` (bản phục hồi trước đây ghi đĩa vĩnh viễn), `heritage/musicxml/` (MusicXML ký âm) và `lesson_samples/<sha>` mồ côi khi bản ghi gốc đã bị xóa (`RESTORED_RETENTION_DAYS`, `MUSICXML_RETENTION_DAYS`)
- **Trần lưu trữ theo người dùng** (mặc định 500MB, `USER_STORAGE_QUOTA_MB`): upload vượt trần nhận 413 kèm thông điệp dung lượng đã dùng; admin trưởng không trần; `/api/auth/me` trả `storage_used_bytes` / `storage_quota_bytes`
- Xóa tài khoản giờ xóa sạch `practice_sessions` của họ (trước đây thành mồ côi vĩnh viễn trong DB)

### Độ bền server khi chạy dài
- **Worker pool có trần** (`WORKER_THREADS=8`): transcribe/restore/instruments + sinh nhạc không còn spawn thread mới mỗi task — 100 người dùng đồng thời không còn nhân vô hạn thread
- `ThrottleInterval=15` vào plist launchd — crash-loop không còn spin-restart liên tục dồn ứ log (log launchd trước đây đã tới 30MB)
- `/health` chế độ extended thêm `rss_mb` / `threads` / `db_wal_mb` — giám sát rò rỉ bộ nhớ và WAL khi chạy dài

### Độ bền dữ liệu
- Script backup `server/tools/db_backup.sh`: sqlite online backup không khóa server + integrity check + xoay N bản (mặc định giữ 7) — chạy tay hoặc treo launchd/cron
- Bảng `schema_meta.schema_version` — migration có mốc version chính thức, chuẩn bị cho nâng schema tương lai

### Crash log — chỉ admin trưởng xem
- App gửi crash-log lên server lúc khởi động (nếu còn đăng nhập): `POST /api/crash-reports` (bắt buộc đăng nhập, ≤256KB, rate-limit)
- Chỉ admin trưởng xem được: tab **"Crash"** mới trong màn Quản trị (danh sách, xem chi tiết, xóa tất cả); người dùng thường không thấy crash của ai, kể cả của mình trên server
- Vẫn lưu cục bộ xoay 5×256KB; gửi thành công thì dọn bản chính để không gửi trùng

### Ứng dụng — dọn đĩa khi dùng lâu
- File tạm phát nhạc/beep metronome (`hue_play_*.wav` / `hue_beep_*.wav`) trước đây mọc mới mỗi lần bấm và không bao giờ xóa — giờ tự xóa file cũ ngay và dọn nốt khi đóng; hết cảnh đầy đĩa khi luyện tập dài
- File tải về rồi chia sẻ trên mobile (MIDI/MusicXML ký âm, bản luyện) được **xóa sau khi chia sẻ** — temp dir không còn tích đống

### Hạn chế đã biết (trung thực)
- Màn hình hiển thị "đã dùng X / trần Y" cho người dùng đọc từ `/api/auth/me` — API đã trả đủ, UI hiển thị sẽ vào bản sau
- N6 glít metronome: đã chặn tiếng click chảy vào bản thu + chuỗi hóa thao tác; phần còn lại phụ thuộc nền tảng
- SQLite 1 file: khi mở ra public internet nên đặt sau reverse-proxy và bật backup định kỳ bằng `db_backup.sh`

### Kiểm định
- pytest **263/263** (thêm 14 test hồi quy: dọn dẹp 3 cây + lesson_samples mồ côi · quota 413/admin exempt · cascade practice_sessions · schema_meta · worker pool · backup roundtrip + xoay · crash-report flow admin-only + trần 256KB)
- flutter analyze **0** · flutter test **70/70** (thêm tab Crash 7 tab Quản trị + file tạm tự xóa) · build web release OK
- Smoke E2E **39/39** + verify orchestrator TOÀN XANH trên server cô lập 0.0.2 (DSP-storm SỐNG/SẠCH: restore 12×200 · analyze 18×200+6×429 đúng trần per-user · compare/transcribe 200 hết · **5xx=0**, health max 334ms; stability restart-giữa-bão SẠCH; 0 Traceback)
- Soak dài **1800s (30 phút)** 18 VU: **28/28 SẠCH** — OK=68.495 · 4xx lịch sự=5.719 · **5xx=0 · 0 exception** · p50=158ms · p95=583ms · hồi phục <20s · restart giữa soak không mất dữ liệu
- Battery tấn công trên sân tập chạy code 0.0.2: SQLi / XSS / CSRF / **Kill-chain 6 chuỗi** / **PWD-Hunt 14/14** (driver dựng lại) — toàn bộ **0 breach**; duy nhất 1 phát hiện = artifact test đã biết từ beta3 (422 body-thiếu trả trước 403 khi thiếu xác thực lại — auth vẫn ép khi request đủ)

## 0.0.2-beta3 (2026-11-08, bản beta cuối cùng, trọng tâm ổn định server + client)

> Đợt nâng cấp vá 17 phát hiện ổn định mới (kiểm chứng file:line từng cái) + hoàn tất 9 mục beta2 để lại; trả nợ "DTW 35MB"; mở vùng kiểm định trống duy nhất còn lại: endpoint DSP nặng chưa từng chịu tải thật.

### Máy chủ — hết chặn event loop + RAM đỉnh
- Decode WAV không còn đứng toàn máy chủ: `/api/music/analyze-pitch` chuyển decode sang luồng nền (trước đây 1 file 15MB chặn mọi người dùng khác 1–4 giây)
- Upload heritage không còn chặn event loop khi băm SHA-256 + ghi đĩa
- RAM đỉnh khi chấm điểm giảm hàng chục lần: decode cắt theo thời lượng TRƯỚC khi giải mã + dùng mảng NumPy thay danh sách Python (trước đây ~0.5–1GB/request cho file dài)
- Ký âm mở kết nối DB SAU khi xử lý xong — hết cảnh ghim kết nối suốt nhiều phút DSP; xác thực người dùng mở phiên DB ngắn thay vì giữ suốt request
- File DSP >2MB không còn bị cắt 413 oan: `/api/music/instruments`, `/api/music/restore`, `/api/music/transcribe` nhận đúng trần 15MB như khai báo
- Khi máy quá tải, đăng nhập quản trị không còn bị từ chối 503 theo nhầm (miễn shedding cho login/admin-unlock; vẫn giới hạn theo IP)
- CORS mặc định an toàn hơn: bật xác thực mà khai `ALLOWED_ORIGINS=*` thì trình duyệt chéo nguồn không còn được phép (app desktop/mobile không bị ảnh hưởng); khai danh sách origin rõ ràng để mở lại

### Máy chủ — CPU DSP + chống stampede
- `harmonicity` tính bằng NumPy nhanh ~280 lần (trước đây mỗi request nhạc cụ đốt phút CPU bằng vòng lặp thuần Python)
- STFT/khôi phục dùng FFT NumPy — khôi phục file 8s từ 60–180s CPU xuống ~0.3s
- Cache bài học có khóa theo bài — nhiều request đầu tiên cùng lúc chỉ build 1 lần (hết stampede)
- Mỗi người dùng tối đa 2 tác vụ DSP nặng đồng thời (nhạc cụ / khôi phục / so sánh / ký âm / luyện tập) — vượt trả 429 lịch sự thay vì đốt máy chủ

### Ứng dụng — chống sập, jank và race
- Vào nền khi đang thu: thu âm dừng có kiểm soát qua đúng khóa thu âm (hết giữ khóa mic, hết lệch trạng thái); player nhạc tạm dừng
- Chọn file phân tích lỗi plugin/quyền hiện thông báo lỗi thay vì im lặng kẹt màn hình
- Đổi máy chủ giữa phiên: token KHÔNG còn gắn vào máy chủ lạ người dùng nhập; watcher cũ được thay thế; 401 nhất thời tự thẩm định lại phiên trước khi đăng xuất (mất phiên chỉ khi máy chủ xác nhận token chết)
- Chờ kết quả tạo nhạc: phân biệt rõ "máy chủ khởi động lại, tác vụ mất" với mạng chập chờn
- Khi offline, các tác vụ nặng (phân tích / tạo nhạc / khôi phục) chặn sớm với thông báo ngay — hết chờ timeout vô nghĩa

### Thuật toán chấm điểm
- DTW chỉ cấp phát vùng băng thay vì 2 ma trận full n×m — bộ nhớ đỉnh 34.3MB → 0.63MB (−54×) với đầu ra GIỐNG HỆT (kiểm chứng trên bộ fixture ngẫu nhiên có seed)

### Giữ nguyên theo thiết kế
- URL ký trên bài `admin_only` do admin chủ động mint vẫn cho khách giữ link truy cập (ngữ nghĩa chia sẻ chủ ý được test OC ghim); URL cũ vẫn chết đúng khi đổi visibility (kiểm tra lại bằng 4 test mới)

### Hạn chế đã biết (ghi nhận trung thực)
- N6 glít metronome: đã chặn tiếng click chảy vào bản thu + chuỗi hóa thao tác; còn lại phụ thuộc nền tảng
- N7 crash-log chỉ lưu cục bộ trên máy (không gửi máy chủ) — quyết định riêng tư, xem lại sau bản chính thức
- Quota lưu trữ theo người dùng chưa có; hiện giới hạn số tác vụ đồng thời (2/user) thay thế
- PWD-Hunt driver không còn trong kho kiểm thử — mặt phá dò mật khẩu được phủ bởi các đợt trước (9 hình thức, CLEAN) + ADMIN-MAX lần này
- Kill-Chain C2 "URL sống sau flip admin_only" = hành vi chia sẻ chủ ý theo thiết kế OC (như mục trên), không phải lỗ hổng

## 0.0.2-beta2 (2026-11-07) — "Ổn định toàn diện app + giao diện"

> Bản beta với trọng tâm độ ổn định: 15 track vá theo kết quả nghiên cứu sâu 2 vòng + audit 32 file (37 phát hiện), giữ nguyên trọn vẹn tính năng của beta1.

### Phiên đăng nhập & mạng
- Gõ sai mật khẩu admin-unlock/đổi mật khẩu không còn bị đá khỏi phiên (401 từ /api/auth/* không xóa token)
- Timeout phân lớp: request thường 30s, xử lý DSP/upload 15 phút đặt đúng chỗ, upload có sendTimeout 2 phút — hết cảnh GET nhỏ treo 15 phút
- Retry tự lấy token mới nhất trước khi thử lại; thông báo lỗi che hostname/đường dẫn máy
- Stream sự kiện tác vụ decode UTF-8 an toàn — tiếng Việt cắt giữa ký tự không còn làm chết stream
- Lời bài hát gửi qua JSON body thay vì query string

### Thu âm & luyện tập
- Khóa thu âm 1 luồng duy nhất (mutex + epoch): bấm đúp, tự dừng theo im lặng, auto-stop timer, đổi câu, đổi bài không còn chen nhau ghi rác
- Lỗi micro giữa chừng thoát sạch trạng thái thay vì kẹt nút "Đang thu"
- Rời màn hình khi đang thu: micro được nhả đúng (stop trước dispose) — hết cảnh màn khác không thu được
- 3 nút nghe (vòng lặp / người mẫu / đoạn tham chiếu) có generation guard — bấm nhanh hết lệch đèn play/stop

### Chống treo/kẹt màn hình
- Dialog "Đang xử lý" Phục hồi tự đóng cả khi rời tab giữa lúc upload — hết cảnh treo toàn app phải khởi động lại
- Xem trước giọng, phân tích, chuyển tab tác vụ: đầy đủ mounted guard — hết crash setState-sau-dispose
- Tải thêm ở 4 màn danh sách (Thư viện/Bảo mật/Tài khoản/Mời) có epoch guard — kết quả tìm kiếm cũ không còn trộn vào list mới; lỗi tải thêm hiện thông báo

### Hiệu năng & bộ nhớ
- Giải mã sóng âm chuyển sang isolate riêng (compute) + memoize — hết cảnh quét lại file lớn mỗi tick tiến độ
- Bản thu tạm được xóa sau khi dùng; file tải về trên mobile được dọn sau khi chia sẻ
- ID lịch sử duy nhất tuyệt đối (chống trùng trên web) — cập nhật trạng thái không còn sửa nhầm dòng

### Giao diện
- Sửa tràn màn hình chắc chắn trên điện thoại: hàng BPM+engine Phân tích, nút bottom-sheet Phục hồi
- Thanh điều hướng tự tính slot an toàn theo số tab — hết bom nổ chậm khi giảm số tab
- Vàng kim hiện 2 sắc: sáng nền tối, đậm nền sáng — chart/badge/chip đạt chuẩn tương phản cả 2 theme (test WCAG mở rộng +8 case)
- Thống nhất ErrorPanel cho Học hát/Luyện tập/Phân tích/Phục hồi

### Hạ tầng & nền
- Lưới bắt lỗi toàn cục: lỗi async lọt được ghi log xoay 5 file trong thư mục tài liệu app thay vì crash trắng vô vết
- Không còn nạp phiên đăng nhập 2 lần lúc khởi động; Connectivity dùng 1 instance
- Giới hạn 2 request chấm điểm đồng thời mỗi user (429 khi vượt) — 1 user không nuốt sạch threadpool DSP

## 0.0.2-beta1 (2026-11-06) — "Học hát hoàn thiện + Nâng cấp giao diện"

> Bản beta chốt chất lượng: nghiên cứu B (tách nốt phía bản mẫu làm lại 2 giai đoạn), sửa tận cùng lỗi signed-URL hết hạn, và nâng cấp UI theo hệ design token thống nhất.

### Thuật toán chấm điểm (server)
- Tách nốt phía bản mẫu 2 giai đoạn (B1): đường nốt trung tâm median-nặng riêng cho bản mẫu + ngưỡng delta — nốt mẫu phủ trọn thời gian có giọng kể cả bản nhạc cụ và bản thu cổ
- Merge mảnh vụn phía bản mẫu (B2): nốt quá ngắn hoặc cách đứt quãng nhỏ được ghép lại — hết cảnh phạt oan "thiếu nốt" khi mẫu vỡ vụn
- Bộ đánh giá chuẩn hóa (B5): bộ câu hand-label đo precision/recall onset theo chuẩn MIREX; cờ `REFERENCE_SEGMENTATION=v2` cho phép rollback 1 dòng

### Cứu kết nối phát nhạc (client)
- Signed URL hết hạn 6h không còn "chết" bài luyện: phát lỗi tự re-sign lại 1 lần rồi phát tiếp
- Nút nghe mẫu nghệ nhân báo lỗi rõ + retry thay vì im lặng không phản hồi

### Nâng cấp giao diện
- Hệ design token trong `AppTheme`: border + 4 màu trạng thái chuẩn (thành công/cảnh báo/lỗi/info) + gradient thương hiệu #2A1545 một nguồn duy nhất
- TextTheme + component themes: TabBar, Chip, Dialog, SnackBar (floating), Tooltip, ListTile — hết cảnh mỗi màn tự bày kiểu chữ
- Sửa màn Sáng tạo tối om trong light mode; sửa tương phản nút vàng chữ trắng light mode; widget dùng chung hết dark-only
- Widget kit chung: ErrorPanel có nút thử lại, EmptyState có icon + nút hành động — áp vào Thư viện/Phục hồi/Quản trị/Học hát/Phân tích
- AudioPlayerBar v2: loading không nhảy layout, tooltip, trạng thái buffering, API bản compact cho màn nhỏ
- Chart kit thống nhất: 1 bảng màu cho cả app (vàng = bản mẫu, xanh = giọng bạn) thay 3 bộ màu riêng lẻ
- Màn Học hát polish: nhịp thu âm nhấp nháy, VU meter theo theme, switch đúng kích thước chạm, badge điểm thành card
- Login polish: chip vai trò theo theme, nút hiện/ẩn mật khẩu trên cả 3 ô nhập
- A11y + i18n sweep: đủ tooltip, touch target ≥ 40px, chuẩn hóa toàn bộ chuỗi lọt tiếng Anh

### Polish luyện tập
- Xem trước giọng trên máy ẩn ở web (hết khựng 1-3s khi chấm take trên trình duyệt)
- Đếm nhập viết lại: hủy được, lỗi metronome hiển thị thay vì nuốt lặng lẽ
- Chip verdict render từ `verdict_code` — hết so chuỗi literal tiếng Việt
- Gỡ mâu thuẫn trần thời lượng: câu dài tới 35s được chấm đủ thay vì cụt 30s
- Lưu tiến độ/MIDI lỗi được ghi log thay vì nuốt im lặng

### Hạ tầng
- `/health` thành endpoint async: giám sát luôn trả lời kể cả khi server quá tải (không xếp hàng threadpool)
- Admin trưởng luôn đăng nhập được dưới flood đăng nhập (miễn trừ IP-flood-bucket cho admin trưởng — mọi khóa khác giữ nguyên)
- Version app khớp server `0.0.2-beta1` (alpha2 trước đây bị lệch app=alpha1)
- `.env.example` đủ biến cấu hình (`ADMIN_TRUONG_USERNAME`, `STORAGE_DIR`, `MODELS_DIR`, `DATASETS_DIR`, `WEB_DIR`) + ghi rõ default

## 0.0.2-alpha2 (2026-11-05) — "Học hát cho người dùng"

> Bản nâng cấp lớn của chế độ Học hát: thuật toán so khớp làm lại từ gốc, thu âm mẫu nghệ nhân theo câu, hướng dẫn từng nốt, luyện thang ngũ cung chấm bằng DTW thật.

### Thuật toán so khớp (server)
- **Hợp nhất lưới thời gian 16kHz**: bản gốc, bản mẫu và bản thu đều được đưa về 16kHz mono trước khi so khớp — hết cảnh hai bên so trên hai độ phân giải frame khác nhau; cache bài học cũ tự nhận và dựng lại
- **DTW banded + numpy vector hóa**: Sakoe-Chiba band 12% thay vì full-band O(n·m) thuần Python — chấm bản thu 30s từ nhiều giây xuống ~50-300ms, kết quả tối ưu tương đương (đã kiểm chứng 120 ca ngẫu nhiên so với bản chuẩn)
- **Chấm theo nốt, không phạt luyến láy**: tách nốt cả hai bên (median-smooth 7 frame + lọc mảnh rác ranh giới), ghép cặp nốt giữ thứ tự (sequence alignment, cho phép bỏ nốt thừa/thiếu), so median nốt — rền/vọng đúng nốt không còn bị trừ điểm
- **Điểm mới 3 thành phần**: Pitch 50% · Nhịp 30% (lệch onset từng cặp nốt qua DTW, phạt nốt thiếu/thừa) · Đều giọng 20% (MAD so với moving-median — rung đẹp không bị tính là nhiễu)
- **Phát hiện "Sai quãng tám"**: lệch ±1050-1350 cents được báo riêng thay vì gộp chung "Lệch" — lỗi phổ biến nhất của người mới
- **Verdict code hóa**: trả thêm `verdict_code` (ok/minor/off/octave/unclear) — client tô màu theo code, không còn so chuỗi literal
- **Fix tracker pitch vỡ trên rền sâu**: ngưỡng chọn đỉnh 0.98×best (đỉnh subharmonic ngang best mới được nhặt) + spike-fix median (lệch >700 cents so với median trượt bị thay) — vibrato ±60c @5.5Hz giờ track chuẩn (trước đây nhảy 158→1032Hz)
- `/api/music/compare` giữ nguyên các field cũ — màn Phục hồi/Phân tích không bị vỡ

### Thu âm mẫu nghệ nhân theo câu (tính năng mới)
- `POST/DELETE /api/lessons/{id}/sections/{n}/sample.wav` — chỉ admin trưởng (bắt buộc admin-unlock), magic-byte WAV, ≤15MB; `GET` auth audio (Bearer/signed URL gắn scope visibility)
- Storage `storage/heritage/lesson_samples/<sha>/<section>.wav` — 1 mẫu active mỗi câu, upload mới thay cái cũ
- Khi có mẫu, luyện tập **so khớp với giọng mẫu nghệ nhân thay vì bản nhạc gốc** — kết quả báo rõ `reference: sample|original`
- Lesson detail trả thêm `has_sample` + `sample_url` từng câu
- AdminScreen thêm tab **"Mẫu học hát"**: chọn bài → từng câu → upload/thay/xóa/nghe thử ngay tại chỗ, kèm thống kê luyện tập (`GET /api/admin/learning/stats`)
- play-url nhận diện đường sample và ký URL gắn scope visibility (bản ghi "Chỉ admin" không lộ qua URL ký)

### Hướng dẫn từng nốt + UX luyện tập (client)
- **Chip nốt mới**: mũi tên ↑/↓ + số cents lệch, màu theo verdict_code; giữ nền có sóng rền; **chạm chip → nghe đúng đoạn đó của bản mẫu** (lùi 0.25s)
- **Hint hành động được từng nốt**: "Cao hơn 45 cents — hát trầm xuống", "Vào trễ 180ms", "Giữ nốt dài hơn", "Rền đẹp — giữ chất này" (tooltip chip)
- **Tổng quan câu**: 4 badge Tổng/Cao độ/Nhịp/Đều giọng + chỉ số Hoa mỹ (% nốt có rền + rate Hz) + tóm tắt tiếng Việt ("5 nốt chuẩn, 2 nốt lệch cao độ, thiếu 1 nốt so với mẫu")
- **A-B loop + tốc độ chậm**: chọn 0.5x/0.75x/1.0x cho toàn màn luyện — học câu khó chậm rãi
- **Bộ thu thông minh**: tự dừng khi im lặng ~1.2s (VU meter trực tiếp khi thu, DBFS realtime) thay vì Timer cứng; vẫn có trần an toàn
- **Quản lý take**: giữ tối đa 3 take gần nhất mỗi câu, chip chọn take, nghe lại từng take, nút "Chấm lại" chấm lại take đã chọn không cần thu lại
- **Xem trước giọng trên máy** (không cần server): decode WAV + autocorrelation ngay trên device, vẽ đường pitch của take so với đường mục tiêu của câu (dữ liệu contour bài học vốn có, trước đây lấy về nhưng không vẽ)
- **Tiến độ trên máy chủ**: bảng `practice_sessions` (user, lesson, section, 4 điểm + metrics JSON) — biểu đồ tiến độ lấy từ server khi đăng nhập (đổi máy không mất), không có server thì fallback lịch sử cục bộ; tag nguồn hiển thị rõ

### Luyện thang ngũ cung làm lại
- Chấm bằng **DTW thật với reference contour phân tích** thay vì histogram chroma — kiểm soát đúng octave, đúng thứ tự, đúng nhịp từng nốt; sai octave giờ bị trừ điểm thật (trước đây ăn điểm tuyệt đối)
- Thêm **chọn tone nền (transpose)** −6..+6 nửa cung cho cả bản mẫu (.wav) và chấm điểm
- Kết quả trả kèm "Từng nốt": tên nốt + lệch cents + verdict code + hint

### Hạ tầng
- Body limit per-route: `/api/lessons/*`, `/api/music/analyze-pitch`, `/api/music/compare` lên 15MB (khớp ngưỡng endpoint tuyên bố, hết dead code); `/api/lessons/*` POST vào nhóm rate-limit nặng
- Bảng `practice_sessions` tự migrate khi khởi động (index user+lesson); `GET /api/lessons/my-progress`; `GET /api/admin/learning/stats`

### Kiểm định
- pytest **168/168** (thêm 14 test hồi quy alpha2: DTW equivalence, chấm điểm tổng thể, vibrato không bị phạt, octave, thiếu nốt, transpose, 16k resample + cache rebuild, sample flow + visibility + signed URL, practice_sessions + my-progress, body limit lớn)
- flutter analyze **0** · flutter test **36/36** · build web release OK

## 0.0.2-alpha1 (2026-11-03)

> Bản 0.0.2-preview nội bộ (chưa phát hành) chốt thành 0.0.2-alpha1.

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
- Mở rộng nút Dọn dẹp: quét toàn bộ cây `storage/analysis` (nhóm cache phân tích, `ANALYSIS_RETENTION_DAYS=30`) trừ cache bài học đã có mốc hạn riêng; app hiển thị dung lượng thu hồi theo từng nhóm

### Hardening
- `AUTH_REQUIRED` mặc định **true** ngay trong code — server quên cấu hình không còn mở cửa hoàn toàn
- `.env.example` bổ sung 4 biến retention + `ENABLE_DOCS` (khớp tên biến thật trong code)

### Bảo mật — vòng rà soát cuối (2026-11-04)
- **Vá DoS khóa tài khoản admin duy nhất**: kẻ tấn công chỉ cần 5 lần đăng nhập sai là khóa tài khoản admin 15 phút (lặp vô hạn = khóa vĩnh viễn). Thứ tự đăng nhập mới: mật khẩu ĐÚNG luôn được vào và xóa bộ đếm; chỉ mật khẩu SAI khi đang khóa mới nhận 429
- **Chính sách mật khẩu đồng nhất**: mọi mật khẩu mới (đăng ký, đổi mật khẩu, admin tạo user) tối thiểu 8 ký tự gồm cả chữ và số (admin giữ tối thiểu 12)
- **Khóa đăng nhập sai hợp nhất**: cùng một tài khoản qua username hay email chung một bộ đếm — hết cảnh ngân sách dò gấp đôi
- **Thêm Content-Security-Policy** cho toàn bộ response (chống XSS lớp hai, frame-ancestors 'none')
- **Tự nâng hạn mức file descriptor khi khởi động** — hết cảnh SQLite không mở được DB khi chạy qua launchd dưới tải lớn
- **Dọn thêm cây `storage/analysis`** theo `ANALYSIS_RETENTION_DAYS` trong nút Dọn dẹp
- Kho kiểm thử mới: raid SQLi, raid XSS, raid CSRF, raid dò mật khẩu, raid xâm nhập admin, raid kill-chain 8 chuỗi phối hợp, tổng tấn công tổ chức hacker trên nền 10k-15k người dùng — toàn bộ SẠCH

### Khác
- Version app `0.0.2+1`, server stage `0.0.2-alpha1`
- Quét liên tục (`continuous_sweep.py`) mở rộng từ 4 bộ → 28 mục: thêm 3 suite tấn công basic/intermediate/advanced (95 + 66 + 81 checks) + 21 tool atk thời beta vào chu kỳ 6 giờ
- Kiểm định: pytest 154/154 (test hồi quy mới: analysis, SQLi, CSRF, password-hardening), flutter analyze 0, flutter test 30/30, build web release OK, smoke E2E 23/23, quét liên tục 28/28 SẠCH (~400+ kịch bản) + 7 raid chuyên sâu toàn SẠCH, LAN chạy 0.0.2-alpha1

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
