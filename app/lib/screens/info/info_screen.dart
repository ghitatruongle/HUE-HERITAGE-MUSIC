import 'package:flutter/material.dart';

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/images/app_logo.png',
              width: 96,
              height: 96,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.music_note, size: 64),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'HUE HERITAGE MUSIC AI',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Hệ thống AI bảo tồn và phát huy di sản âm nhạc truyền thống Huế: '
          'bảo tồn, số hóa, phân tích, truyền dạy, phục dựng, sáng tạo và phát huy.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        _card(
          context,
          icon: Icons.favorite_outline,
          title: 'Triết lý hệ thống',
          children: const [
            'Bản ghi gốc (ORIGINAL) được bảo toàn bằng mã băm SHA-256, tuyệt đối không bị ghi đè.',
            'Dữ liệu phải có nguồn gốc, metadata và quyền sử dụng rõ ràng.',
            'Kết quả AI luôn được đánh dấu và không được coi là bản nhạc chính thức nếu chưa được kiểm duyệt.',
            'Con người – nghệ nhân, giáo viên, nhà nghiên cứu – luôn là người quyết định cuối cùng.',
            'Các bài toán đo lường (cao độ, thời gian) dùng thuật toán xử lý tín hiệu chính xác, không dùng AI sinh nhạc để đánh giá.',
          ],
        ),
        _card(
          context,
          icon: Icons.label_outline,
          title: 'Nhãn phân loại dữ liệu',
          children: const [
            'ORIGINAL – bản thu gốc của nghệ nhân/nhà sưu tầm.',
            'RESTORED – bản thu đã qua khử nhiễu, phục dựng.',
            'ANALYZED – dữ liệu phân tích cao độ (F0).',
            'TRANSCRIBED – bản ký âm tự động (MIDI, MusicXML), cần kiểm duyệt.',
            'AI_GENERATED – tác phẩm do AI tạo mới hoàn toàn.',
            'AI_ASSISTED – có AI hỗ trợ nhưng đã qua kiểm duyệt của con người.',
          ],
        ),
        _card(
          context,
          icon: Icons.school_outlined,
          title: 'Bốn phân hệ chính',
          children: const [
            'Học hát Ca Huế – so sánh cao độ, thời gian với bản mẫu, chỉ ra sai số theo cents.',
            'Kho di sản số – lưu trữ có cấu trúc, tra cứu theo loại hình, nghệ nhân, nhạc cụ, thời gian, địa điểm.',
            'AI Sáng tạo – sáng tác và cover theo âm hưởng Huế (chức năng này cần model đã huấn luyện trên máy chủ).',
            'Ký âm tự động – chuyển bản thu thành MIDI và MusicXML để giảng dạy, lưu trữ.',
          ],
        ),
        _card(
          context,
          icon: Icons.copyright_outlined,
          title: 'Bản quyền & dữ liệu',
          children: const [
            'Toàn bộ tư liệu di sản, bản thu của nghệ nhân và dữ liệu điền dã được bảo vệ quyền tác giả theo pháp luật.',
            'Dữ liệu chỉ được thu thập và sử dụng khi có cơ sở pháp lý và sự đồng ý của người cung cấp.',
            'Dữ liệu AI tạo ra phải được phân biệt rõ ràng với di sản gốc.',
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Dự án nghiên cứu khoa học – Hệ thống đa nền tảng Flutter + máy chủ AI FastAPI.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _card(BuildContext context, {required IconData icon, required String title, required List<String> children}) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            for (final c in children)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(Icons.circle, size: 6, color: scheme.primary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(c, style: const TextStyle(height: 1.4))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
