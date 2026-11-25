import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../services/locale_provider.dart';
import 'chart_palette.dart';

class CompareChart extends StatelessWidget {
  final List<double> times;
  final List<double> sampleF0;
  final List<double> warpedF0;
  final String? sampleLabel;
  final String? targetLabel;

  const CompareChart({
    super.key,
    required this.times,
    required this.sampleF0,
    required this.warpedF0,
    this.sampleLabel,
    this.targetLabel,
  });

  List<FlSpot> _spots(List<double> f0) {
    final out = <FlSpot>[];
    var step = 1;
    if (times.length > 300) {
      step = times.length ~/ 300;
    }
    if (step < 1) step = 1;
    for (var i = 0; i < times.length && i < f0.length; i += step) {
      final t = times[i];
      final f = f0[i];
      if (t.isFinite && f.isFinite && f > 0) {
        out.add(FlSpot(t, f));
      } else if (out.isNotEmpty && out.last != FlSpot.nullSpot) {
        out.add(FlSpot.nullSpot);
      }
    }
    if (out.isNotEmpty && out.last == FlSpot.nullSpot) {
      out.removeLast();
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    if (times.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Text(strings.noData)));
    }
    final palette = ChartPalette.of(context);
    var peak = 100.0;
    for (final f in sampleF0) {
      if (f.isFinite && f > peak) {
        peak = f;
      }
    }
    for (final f in warpedF0) {
      if (f.isFinite && f > peak) {
        peak = f;
      }
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                sampleLabel ?? strings.compareChartSample,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.reference, fontWeight: FontWeight.w600, fontSize: AppFontSize.sm),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                targetLabel ?? strings.compareChartTarget,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.user, fontWeight: FontWeight.w600, fontSize: AppFontSize.sm),
              ),
            ),
          ],
        ),
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: peak * 1.2,
              gridData: ChartPalette.styledGrid(context),
              titlesData: ChartPalette.styledTitles(context),
              lineTouchData: ChartPalette.styledTouch(context),
              lineBarsData: [
                LineChartBarData(
                  spots: _spots(sampleF0),
                  dotData: const FlDotData(show: false),
                  color: palette.reference,
                ),
                LineChartBarData(
                  spots: _spots(warpedF0),
                  dotData: const FlDotData(show: false),
                  color: palette.user,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
