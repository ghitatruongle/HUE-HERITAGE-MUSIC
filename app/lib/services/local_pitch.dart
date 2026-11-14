import 'dart:math' as math;
import 'dart:typed_data';

class LocalPitchPoint {
  final double t;
  final double f0;
  const LocalPitchPoint(this.t, this.f0);
}

class LocalPitchResult {
  final double duration;
  final int sampleRate;
  final List<LocalPitchPoint> points;

  const LocalPitchResult(this.duration, this.sampleRate, this.points);

  double get meanF0 {
    final voiced = points.where((p) => p.f0 > 0).map((p) => p.f0).toList();
    if (voiced.isEmpty) return 0;
    return voiced.reduce((a, b) => a + b) / voiced.length;
  }

  int get voicedCount => points.where((p) => p.f0 > 0).length;
}

class LocalPitch {
  static const int frameSize = 1024;
  static const int hop = 512;
  static const double fMin = 50;
  static const double fMax = 1000;
  static const int maxSeconds = 20;

  static LocalPitchResult? analyze(Uint8List bytes) {
    final parsed = _parsePcm16(bytes);
    if (parsed == null) return null;
    final samples = parsed.$1;
    final sr = parsed.$2;
    final limit = math.min(samples.length, sr * maxSeconds);
    final points = <LocalPitchPoint>[];
    final lmin = math.max(1, (sr / fMax).floor());
    final lmax = math.min((sr / fMin).floor(), frameSize - 1);
    final norms = Float64List(lmax - lmin + 1);
    for (int pos = 0; pos + frameSize <= limit; pos += hop) {
      var energy = 0.0;
      for (int i = 0; i < frameSize; i++) {
        final v = samples[pos + i];
        energy += v * v;
      }
      energy /= frameSize;
      final t = pos / sr;
      if (energy < 0.000001) {
        points.add(LocalPitchPoint(t, 0));
        continue;
      }
      double best = 0;
      for (int lag = lmin; lag <= lmax; lag++) {
        var corr = 0.0;
        for (int i = 0; i + lag < frameSize; i++) {
          corr += samples[pos + i] * samples[pos + i + lag];
        }
        final norm = corr / ((frameSize - lag) * (energy + 1e-9));
        norms[lag - lmin] = norm;
        if (norm > best) best = norm;
      }
      if (best < 0.3) {
        points.add(LocalPitchPoint(t, 0));
        continue;
      }
      int pick = -1;
      for (int k = 1; k < norms.length - 1; k++) {
        if (norms[k] >= best * 0.98 && norms[k] >= norms[k - 1] && norms[k] >= norms[k + 1]) {
          pick = k;
          break;
        }
      }
      if (pick < 0) {
        for (int k = 0; k < norms.length; k++) {
          if (norms[k] == best) {
            pick = k;
            break;
          }
        }
      }
      if (pick < 0) {
        points.add(LocalPitchPoint(t, 0));
        continue;
      }
      double lagF = (lmin + pick).toDouble();
      if (pick > 0 && pick < norms.length - 1) {
        final y0 = norms[pick - 1];
        final y1 = norms[pick];
        final y2 = norms[pick + 1];
        final den = y0 - 2 * y1 + y2;
        if (den < -1e-12) {
          final delta = 0.5 * (y0 - y2) / den;
          if (delta >= -1.0 && delta <= 1.0) {
            lagF += delta;
          }
        }
      }
      if (lagF < 1.0) lagF = 1.0;
      points.add(LocalPitchPoint(t, sr / lagF));
    }
    final fixed = _spikeFix(points);
    return LocalPitchResult(limit / sr, sr, fixed);
  }

  static List<LocalPitchPoint> _spikeFix(List<LocalPitchPoint> points, {int window = 2, int passes = 2}) {
    var out = List<LocalPitchPoint>.from(points);
    for (var pass = 0; pass < passes; pass++) {
      final next = List<LocalPitchPoint>.from(out);
      for (int i = 0; i < out.length; i++) {
        final f = out[i].f0;
        if (f <= 0) continue;
        final neighbors = <double>[];
        for (int k = math.max(0, i - window); k <= math.min(out.length - 1, i + window); k++) {
          if (k == i) continue;
          if (out[k].f0 > 0) neighbors.add(out[k].f0);
        }
        if (neighbors.length < 3) continue;
        neighbors.sort();
        final median = neighbors[neighbors.length ~/ 2];
        final cents = 1200 * math.log(f / median) / math.ln2;
        if (cents.abs() > 700) {
          next[i] = LocalPitchPoint(out[i].t, median);
        }
      }
      out = next;
    }
    return out;
  }

  static (Float64List, int)? _parsePcm16(Uint8List bytes) {
    if (bytes.length < 44) return null;
    final bd = ByteData.sublistView(bytes);
    if (bytes[0] != 0x52 || bytes[1] != 0x49 || bytes[2] != 0x46 || bytes[3] != 0x46) return null;
    if (bytes[8] != 0x57 || bytes[9] != 0x41 || bytes[10] != 0x56 || bytes[11] != 0x45) return null;
    int offset = 12;
    int format = 1;
    int channels = 1;
    int rate = 16000;
    int bits = 16;
    int? dataStart;
    int? dataLen;
    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = bd.getUint32(offset + 4, Endian.little);
      if (id == 'fmt ') {
        if (offset + 8 + size > bytes.length || size < 16) return null;
        format = bd.getUint16(offset + 8, Endian.little);
        channels = bd.getUint16(offset + 10, Endian.little);
        rate = bd.getUint32(offset + 12, Endian.little);
        bits = bd.getUint16(offset + 22, Endian.little);
      } else if (id == 'data') {
        dataStart = offset + 8;
        dataLen = size;
        break;
      }
      offset += 8 + size + (size % 2);
    }
    if (dataStart == null || dataLen == null || format != 1 || bits != 16) return null;
    if (rate <= 0 || channels <= 0) return null;
    final maxLen = bytes.length - dataStart;
    if (maxLen <= 0) return null;
    if (dataLen <= 0 || dataLen > maxLen) dataLen = maxLen;
    final frames = dataLen ~/ (2 * channels);
    final out = Float64List(frames);
    for (int i = 0; i < frames; i++) {
      var sum = 0.0;
      for (int c = 0; c < channels; c++) {
        sum += bd.getInt16(dataStart + (i * channels + c) * 2, Endian.little);
      }
      out[i] = sum / channels / 32768.0;
    }
    return (out, rate);
  }
}
