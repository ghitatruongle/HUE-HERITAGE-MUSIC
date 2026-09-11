import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/pitch_data.dart';

class PitchContourChart extends StatelessWidget {
  final PitchData data;

  const PitchContourChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.times.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Chưa có dữ liệu')));
    }
    var step = 1;
    if (data.times.length > 500) {
      step = data.times.length ~/ 500;
    }
    final spots = <FlSpot>[];
    for (var i = 0; i < data.times.length && i < data.f0.length; i += step) {
      spots.add(FlSpot(data.times[i], data.f0[i]));
    }
    var peak = 100.0;
    for (final f in data.f0) {
      if (f > peak) {
        peak = f;
      }
    }
    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: peak * 1.2,
          gridData: const FlGridData(show: true),
          titlesData: const FlTitlesData(show: true),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}
