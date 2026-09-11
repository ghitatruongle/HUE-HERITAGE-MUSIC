# HUE HERITAGE MUSIC

<p align="center">
  <b>Hệ thống AI bảo tồn và phát huy di sản âm nhạc truyền thống Huế</b><br>
  <i>An AI-Powered Platform for Preserving and Promoting Hue Traditional Music Heritage</i>
</p>

---

## 🇻🇳 TIẾNG VIỆT

### 1. Giới thiệu tổng quan
**HUE HERITAGE MUSIC** là một giải pháp công nghệ toàn diện kết hợp giữa trí tuệ nhân tạo (AI), xử lý tín hiệu âm thanh (Digital Signal Processing - DSP), phiên âm tự động (Automatic Music Transcription - AMT) và hệ thống lưu trữ số có cấu trúc nhằm bảo tồn, số hóa, truyền dạy và phát huy các giá trị đặc sắc của âm nhạc truyền thống Cố đô Huế.

Hệ thống tập trung vào các loại hình di sản:
- **Ca Huế** (Di sản văn hóa phi vật thể quốc gia)
- **Nhã nhạc cung đình Huế** (Kiệt tác truyền khẩu và phi vật thể nhân loại được UNESCO công nhận)
- **Âm nhạc lễ nhạc & nhạc cụ truyền thống** (Đàn tranh, đàn nguyệt, đàn bầu, tỳ bà, sáo trúc, v.v.)

---

### 2. Triết lý & Nguyên tắc cốt lõi
Hệ thống không được xây dựng chỉ với mục đích "AI tạo nhạc", mà hướng đến việc **bảo tồn, nghiên cứu khoa học và phát huy di sản**:
1. **Bảo toàn nguyên bản:** Bản ghi gốc (`ORIGINAL`) luôn được bảo vệ toàn vẹn, tính toán mã băm (Hash SHA-256) và tuyệt đối không bao giờ bị ghi đè.
2. **Minh bạch dữ liệu:** Mọi tác phẩm sinh ra từ AI hoặc có AI can thiệp đều phải gắn nhãn rõ ràng (`AI_GENERATED` hoặc `AI_ASSISTED`).
3. **Đo lường định lượng:** Phân hệ học hát và phiên âm sử dụng các thuật toán xử lý tín hiệu chính xác (F0 tracking, Dynamic Time Warping), không suy đoán cảm tính.
4. **Con người là trung tâm:** AI đóng vai trò công cụ trợ giảng, trợ lý nghiên cứu; nghệ nhân và các nhà nghiên cứu âm nhạc luôn giữ vai trò thẩm định cuối cùng.

---

### 3. Bốn phân hệ chức năng chính
| Phân hệ | Nhiệm vụ chính | Công nghệ nền tảng |
| :--- | :--- | :--- |
| **1. Hỗ trợ học hát Ca Huế** | Thu âm giọng hát, căn chỉnh thời gian, so sánh cao độ với bản mẫu của nghệ nhân, chỉ ra sai số theo cents và nhịp phách. | DSP, F0 Pitch Tracking (YIN/CREPE), DTW Alignment |
| **2. Kho di sản số có cấu trúc** | Quản lý bản ghi, tác giả, nghệ nhân, lời bài hát, siêu dữ liệu (metadata), lưu trữ phân tầng bản gốc và bản phục chế. | Structured Database, Object Storage, Version Control |
| **3. AI Sáng tạo & Cover** | Sáng tác tác phẩm mới mang âm hưởng Huế, cover hoặc chuyển đổi phong cách phối khí kết hợp nhạc cụ truyền thống. | ACE-Step 1.5 Base kết hợp HueMusic-LoRA |
| **4. Ký âm tự động (Audio -> Sheet)** | Chuyển bản thu âm bài bản Huế thành dữ liệu số MIDI và bản phổ MusicXML phục vụ giảng dạy và lưu trữ. | Automatic Music Transcription (Basic Pitch), Post-quantization |

---

### 4. Kiến trúc hệ thống
Hệ thống hoạt động theo mô hình **Client - Server tập trung**:
- **Ứng dụng đa nền tảng (Flutter):** Chạy trên Android, iOS, Windows, macOS, Web. Giao diện mượt mà, tối ưu thu âm, trực quan hóa biểu đồ cao độ và nốt nhạc. Không nhúng các mô hình AI lớn vào máy người dùng.
- **Máy chủ AI tập trung (FastAPI / Mac mini M4 24GB):** Xử lý toàn bộ logic tính toán nặng: phân tích âm thanh, phiên âm ký âm, suy luận mô hình sinh nhạc và lưu trữ cơ sở dữ liệu.

---

## 🇬🇧 ENGLISH

### 1. Overview
**HUE HERITAGE MUSIC** is a comprehensive technology system integrating Artificial Intelligence (AI), Digital Signal Processing (DSP), Automatic Music Transcription (AMT), and structured digital archiving to preserve, digitize, teach, and promote the rich musical traditions of Hue, Vietnam.

Core focus areas:
- **Ca Hue** (National Intangible Cultural Heritage of Vietnam)
- **Nha Nhac - Hue Court Music** (UNESCO Masterpiece of the Oral and Intangible Heritage of Humanity)
- **Ritual music and traditional musical instruments** (Dan Tranh, Dan Nguyet, Dan Bau, Ty Ba, Bamboo Flute, etc.)

---

### 2. Core Philosophy & Principles
The platform is not merely designed for "AI music generation", but fundamentally dedicated to **heritage preservation, academic research, and pedagogical transmission**:
1. **Preservation of Originals:** Master audio recordings (`ORIGINAL`) are cryptographically hashed (SHA-256), strictly protected, and never overwritten.
2. **Provenance & Labeling:** Any AI-synthesized or AI-modified assets must be unequivocally labeled (`AI_GENERATED` or `AI_ASSISTED`).
3. **Quantitative Precision:** Vocal analysis and pitch matching rely on rigorous signal processing algorithms (F0 tracking, Dynamic Time Warping) rather than opaque generative estimations.
4. **Human in the Loop:** AI acts strictly as an assistant to artisans, researchers, and students. Human masters retain the final authority over heritage validation.

---

### 3. Four Core Subsystems
| Subsystem | Primary Function | Core Technology |
| :--- | :--- | :--- |
| **1. Ca Hue Singing Tutor** | Records user performance, warps timeline, compares pitch contours against master recordings, provides feedback in cents and timing deviation. | DSP, F0 Pitch Tracking (YIN/CREPE), DTW Alignment |
| **2. Structured Digital Archive** | Catalogs audio, artist provenance, historical context, lyrics, and comprehensive metadata across raw and restored formats. | Structured Database, Object Storage, Version Control |
| **3. AI Creation & Cover** | Synthesizes new compositions infused with Hue modal aesthetics, provides style transfer and traditional orchestration. | ACE-Step 1.5 Base + HueMusic-LoRA Adapters |
| **4. Automatic Transcription** | Transcribes acoustic recordings into symbolic musical representations (MIDI, MusicXML scores). | Automatic Music Transcription (Basic Pitch), Post-quantization |

---

### 4. System Architecture
The platform is designed around a **Centralized Client - Server** architecture:
- **Cross-Platform Client (Flutter):** Runs across Android, iOS, Windows, macOS, and Web. Handles audio input/output, user interaction, pitch contour rendering, and sheet music visualization without hosting heavy AI models on device.
- **AI Processing Server (FastAPI / Mac mini M4 24GB):** Handles compute-intensive operations, including audio DSP, music transcription, generative AI inference, LoRA training, and repository management.

---

## 📄 LICENSE & COPYRIGHT / BẢN QUYỀN

- Toàn bộ tư liệu di sản, bản thu âm của nghệ nhân và dữ liệu điền dã đều được bảo vệ quyền tác giả và quyền liên quan theo quy định pháp luật.
- *All heritage recordings, artisan performances, and field research assets are protected under applicable copyright and cultural heritage preservation laws.*
