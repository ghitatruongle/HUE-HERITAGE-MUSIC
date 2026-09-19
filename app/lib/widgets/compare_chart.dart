import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class CompareChart extends StatelessWidget {
  final List<double> times;
  final List<double> sampleF0;
  final List<double> warpedF0;
  final String sampleLabel;
  final String targetLabel;

  const CompareChart({
    super.key,
    required this.times,
    required this.sampleF0,
    required this.warpedF0,
    this.sampleLabel = 'Bản ghi mẫu',
    this.targetLabel = 'Bản ghi đối chiếu',
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
      if (t.isFinite && f.isFinite) {
        out.add(FlSpot(t, f));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (times.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Chưa có dữ liệu')));
    }
    var peak = 100.0;
    for (final f in sampleF0) {
      if (f > peak) {
        peak = f;
      }
    }
    for (final f in warpedF0) {
      if (f > peak) {
        peak = f;
      }
    }
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Text(sampleLabel, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w600, fontSize: 12)),
            Text(targetLabel, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 12)),
          ],
        ),
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: peak * 1.2,
              gridData: const FlGridData(show: true),
              titlesData: const FlTitlesData(show: true),
              lineBarsData: [
                LineChartBarData(
                  spots: _spots(sampleF0),
                  dotData: const FlDotData(show: false),
                  color: Colors.blue,
                ),
                LineChartBarData(
                  spots: _spots(warpedF0),
                  dotData: const FlDotData(show: false),
                  color: Colors.red,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
