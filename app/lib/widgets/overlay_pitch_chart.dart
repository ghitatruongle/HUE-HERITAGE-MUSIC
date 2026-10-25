import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/lesson.dart';

class OverlayPitchChart extends StatelessWidget {
  final PracticeResult result;

  const OverlayPitchChart({super.key, required this.result});

  static const int _maxPoints = 300;

  List<FlSpot> _spots(List<double> times, List<double> f0) {
    if (times.isEmpty || f0.isEmpty) return const [];
    final n = times.length;
    final step = n / _maxPoints;
    final spots = <FlSpot>[];
    double k = 0;
    while (k.toInt() < n && spots.length < _maxPoints) {
      final i = k.toInt();
      if (f0[i] > 0) {
        spots.add(FlSpot(times[i], f0[i]));
      }
      k += step == 0 ? 1 : step;
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    final ref = _spots(result.refTimes, result.refF0);
    final user = _spots(result.refTimes, result.userF0);
    final all = [...ref, ...user];
    if (all.isEmpty) {
      return const SizedBox.shrink();
    }
    var minX = all.first.x;
    var maxX = all.last.x;
    var maxY = 0.0;
    for (final s in all) {
      if (s.y > maxY) maxY = s.y;
      if (s.x < minX) minX = s.x;
      if (s.x > maxX) maxX = s.x;
    }
    if (maxX <= minX) maxX = minX + 1;
    if (maxY <= 0) maxY = 1;
    final theme = Theme.of(context);
    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: 0,
          maxY: maxY * 1.1,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: true, border: Border.all(color: theme.dividerColor)),
          titlesData: const FlTitlesData(
            leftTitles: AxisTitles(
              axisNameWidget: Text('Hz', style: TextStyle(fontSize: 10)),
            ),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: ref,
              isCurved: false,
              barWidth: 2,
              color: const Color(0xFFD4AF37),
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: user,
              isCurved: false,
              barWidth: 2,
              color: Colors.lightBlueAccent,
              dashArray: [6, 3],
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}
