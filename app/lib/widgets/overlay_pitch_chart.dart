import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/localization/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../models/lesson.dart';
import '../services/local_pitch.dart';
import '../services/locale_provider.dart';
import 'chart_palette.dart';
import 'hue_icons.dart';

class OverlayPitchChart extends StatefulWidget {
  final PracticeResult result;
  final bool initialFoldOctave;

  const OverlayPitchChart({
    super.key,
    required this.result,
    this.initialFoldOctave = false,
  });

  @override
  State<OverlayPitchChart> createState() => _OverlayPitchChartState();
}

class _OverlayPitchChartState extends State<OverlayPitchChart> {
  static const int _maxPoints = 300;
  late bool _foldOctave;

  @override
  void initState() {
    super.initState();
    _foldOctave = widget.initialFoldOctave;
  }

  AppStrings _strings(BuildContext context) {
    try {
      return context.watch<LocaleProvider>().strings;
    } catch (_) {
      return const AppStrings('vi');
    }
  }

  double _foldToRef(double f0, double refF0) {
    if (f0 <= 0 || refF0 <= 0) return f0;
    var val = f0;
    while (val > refF0 * 1.4142) {
      val *= 0.5;
    }
    while (val < refF0 * 0.7071) {
      val *= 2.0;
    }
    return val;
  }

  List<FlSpot> _spots(
    List<double> times,
    List<double> f0, {
    List<double>? refF0,
    bool fold = false,
  }) {
    if (times.isEmpty || f0.isEmpty) return const [];
    final n = math.min(times.length, f0.length);
    final step = n <= _maxPoints ? 1.0 : n / _maxPoints;
    final spots = <FlSpot>[];
    double k = 0;
    while (k.toInt() < n && spots.length < _maxPoints) {
      final i = k.toInt();
      final t = times[i];
      var y = f0[i];
      if (t.isFinite && y.isFinite && y > 0) {
        if (fold && refF0 != null && i < refF0.length && refF0[i].isFinite && refF0[i] > 0) {
          y = _foldToRef(y, refF0[i]);
        } else if (fold && widget.result.metrics.octaveShift.isFinite && widget.result.metrics.octaveShift > 0 && widget.result.metrics.octaveShift != 1.0) {
          y = y * widget.result.metrics.octaveShift;
        }
        spots.add(FlSpot(t, y));
      } else if (spots.isNotEmpty && spots.last != FlSpot.nullSpot) {
        spots.add(FlSpot.nullSpot);
      }
      k += step == 0 ? 1 : step;
    }
    if (spots.isNotEmpty && spots.last == FlSpot.nullSpot) {
      spots.removeLast();
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final strings = _strings(context);
    final ref = _spots(result.refTimes, result.refF0);
    final user = _spots(
      result.refTimes,
      result.userF0,
      refF0: result.refF0,
      fold: _foldOctave,
    );
    final all = [...ref, ...user];
    if (all.isEmpty) {
      return const SizedBox.shrink();
    }
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = 0.0;
    for (final s in all) {
      if (s == FlSpot.nullSpot || !s.x.isFinite || !s.y.isFinite) continue;
      if (s.y > maxY) maxY = s.y;
      if (s.x < minX) minX = s.x;
      if (s.x > maxX) maxX = s.x;
    }
    if (!minX.isFinite || !maxX.isFinite) {
      return const SizedBox.shrink();
    }
    if (maxX <= minX) maxX = minX + 1;
    if (maxY <= 0) maxY = 1;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = ChartPalette.of(context);
    final hasBoth = ref.any((s) => s != FlSpot.nullSpot) && user.any((s) => s != FlSpot.nullSpot);
    final touch = LineTouchData(
      handleBuiltInTouches: true,
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => scheme.inverseSurface,
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        getTooltipItems: (spots) => [
          for (final s in spots)
            LineTooltipItem(
              LocalPitch.noteLabel(s.y) == null
                  ? '${s.y.toStringAsFixed(0)} Hz'
                  : '${s.y.toStringAsFixed(0)} Hz (${LocalPitch.noteLabel(s.y)})',
              TextStyle(
                color: scheme.onInverseSurface,
                fontWeight: FontWeight.bold,
                fontSize: AppFontSize.sm,
              ),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasBoth)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  visualDensity: VisualDensity.standard,
                  selected: _foldOctave,
                  avatar: const HueIcon(HueIcons.waves, size: 14),
                  label: Text(
                    _foldOctave ? strings.overlayFoldOctave : strings.overlayShowRaw,
                    style: const TextStyle(fontSize: AppFontSize.xs),
                  ),
                  onSelected: (v) => setState(() => _foldOctave = v),
                ),
                if (result.metrics.octaveShift != 1.0)
                  Text(
                    strings.overlayOctaveShifted(result.metrics.octaveShift),
                    style: TextStyle(fontSize: AppFontSize.xs, color: AppTheme.goldReadable(context)),
                  ),
              ],
            ),
          ),
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minX: minX,
              maxX: maxX,
              minY: 0,
              maxY: maxY * 1.1,
              gridData: ChartPalette.styledGrid(context),
              borderData: FlBorderData(show: true, border: Border.all(color: theme.dividerColor)),
              titlesData: ChartPalette.styledTitles(context, axisName: 'Hz'),
              lineTouchData: touch,
              lineBarsData: [
                LineChartBarData(
                  spots: ref,
                  isCurved: false,
                  barWidth: 2,
                  color: palette.reference,
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: user,
                  isCurved: false,
                  barWidth: 2,
                  color: palette.user,
                  dashArray: [6, 3],
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
