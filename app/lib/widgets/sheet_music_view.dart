import 'package:flutter/material.dart';

class SheetNote {
  final int midi;
  final double start;
  final double end;

  const SheetNote({required this.midi, required this.start, required this.end});

  String get name {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    return '${names[midi % 12]}${midi ~/ 12 - 1}';
  }
}

class SheetMusicView extends StatelessWidget {
  final List<SheetNote> notes;
  final String disclaimer;

  const SheetMusicView({super.key, required this.notes, this.disclaimer = 'Bản nhạc dự đoán tự động – cần nghệ nhân kiểm duyệt.'});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (notes.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        ),
        child: const Center(child: Text('Chưa có nốt nhạc để hiển thị')),
      );
    }
    final minMidi = notes.map((n) => n.midi).reduce((a, b) => a < b ? a : b) - 2;
    final maxMidi = notes.map((n) => n.midi).reduce((a, b) => a > b ? a : b) + 2;
    final maxTime = notes.map((n) => n.end).reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          ),
          padding: const EdgeInsets.all(8),
          child: CustomPaint(
            size: Size.infinite,
            painter: _PianoRollPainter(
              notes: notes,
              minMidi: minMidi,
              maxMidi: maxMidi,
              maxTime: maxTime <= 0 ? 1 : maxTime,
              color: scheme.primary,
              gridColor: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.info_outline, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                disclaimer,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PianoRollPainter extends CustomPainter {
  final List<SheetNote> notes;
  final int minMidi;
  final int maxMidi;
  final double maxTime;
  final Color color;
  final Color gridColor;

  _PianoRollPainter({
    required this.notes,
    required this.minMidi,
    required this.maxMidi,
    required this.maxTime,
    required this.color,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final rows = (maxMidi - minMidi).clamp(1, 96);
    for (int r = 0; r <= rows; r++) {
      final y = r * size.height / rows;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (int s = 0; s <= 8; s++) {
      final x = s * size.width / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    final paint = Paint()..color = color.withValues(alpha: 0.85);
    final span = (maxMidi - minMidi).clamp(1, 1 << 30).toDouble();
    for (final n in notes) {
      final y0 = (maxMidi - n.midi) / span * size.height;
      final y1 = (maxMidi - n.midi + 1) / span * size.height;
      final x0 = n.start / maxTime * size.width;
      final x1 = (n.end / maxTime).clamp(x0 / size.width + 0.01, 1.0) * size.width;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(x0, y0, x1, y1), const Radius.circular(3)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PianoRollPainter old) => old.notes != notes;
}
