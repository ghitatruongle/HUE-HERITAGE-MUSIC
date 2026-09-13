import 'dart:typed_data';

import 'package:flutter/material.dart';

class WaveformData {
  final List<double> peaks;

  const WaveformData(this.peaks);

  static WaveformData fromWavBytes(Uint8List bytes, {int buckets = 120}) {
    if (bytes.length < 44) return const WaveformData([]);
    final bd = ByteData.sublistView(bytes);
    int pos = 12;
    int channels = 1;
    int bits = 16;
    int dataStart = -1;
    int dataLen = 0;
    while (pos + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final size = bd.getUint32(pos + 4, Endian.little);
      if (id == 'fmt ') {
        channels = bd.getUint16(pos + 10, Endian.little);
        bits = bd.getUint16(pos + 22, Endian.little);
      } else if (id == 'data') {
        dataStart = pos + 8;
        dataLen = size;
        break;
      }
      pos += 8 + size + (size % 2);
    }
    if (dataStart < 0 || bits != 16 || channels < 1) return const WaveformData([]);
    final frames = dataLen ~/ (2 * channels);
    if (frames <= 0) return const WaveformData([]);
    final step = (frames / buckets).ceil().clamp(1, 1 << 30);
    final peaks = <double>[];
    for (int b = 0; b < buckets; b++) {
      double peak = 0;
      final start = b * step;
      if (start >= frames) break;
      final end = (start + step).clamp(0, frames);
      for (int f = start; f < end; f++) {
        final idx = dataStart + f * channels * 2;
        if (idx + 1 >= bytes.length) break;
        final v = bd.getInt16(idx, Endian.little).abs() / 32768.0;
        if (v > peak) peak = v;
      }
      peaks.add(peak);
    }
    return WaveformData(peaks);
  }
}

class WaveformView extends StatelessWidget {
  final WaveformData data;
  final Color color;

  const WaveformView({super.key, required this.data, this.color = const Color(0xFF5B3B8C)});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: data.peaks.isEmpty
          ? const Center(child: Text('Chưa có dữ liệu sóng âm'))
          : CustomPaint(size: Size.infinite, painter: _WavePainter(peaks: data.peaks, color: color)),
    );
  }
}

class _WavePainter extends CustomPainter {
  final List<double> peaks;
  final Color color;

  _WavePainter({required this.peaks, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final n = peaks.length;
    if (n == 0) return;
    final barW = size.width / n;
    for (int i = 0; i < n; i++) {
      final h = (peaks[i].clamp(0.0, 1.0)) * size.height * 0.9;
      final x = i * barW;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + barW * 0.15, (size.height - h) / 2, barW * 0.7, h),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.peaks != peaks;
}
