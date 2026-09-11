import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class CompareChart extends StatelessWidget {
  final List<double> times;
  final List<double> sampleF0;
  final List<double> warpedF0;

  const CompareChart({
    super.key,
    required this.times,
    required this.sampleF0,
    required this.warpedF0,
  });

  List<FlSpot> _spots(List<double> f0) {
    final out = <FlSpot>[];
    var step = 1;
    if (times.length > 300) {
      step = times.length ~/ 300;
    }
    for (var i = 0; i < times.length && i < f0.length; i += step) {
      out.add(FlSpot(times[i], f0[i]));
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
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Text('Mẫu', style: TextStyle(color: Colors.blue)),
            Text('Bạn hát', style: TextStyle(color: Colors.red)),
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
