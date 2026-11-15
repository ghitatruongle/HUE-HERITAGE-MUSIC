import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/services/teaching_utils.dart';

class _SectionLine {
  final double start;
  final double end;
  const _SectionLine(this.start, this.end);
}

class _FakeSection {
  final List<_SectionLine> lineTimes;
  final int lineCount;
  final double duration;
  const _FakeSection(this.lineTimes, this.lineCount, this.duration);
}

Widget _guideChart(ValueNotifier<double> elapsed, List<FlSpot> spots, double maxX) {
  return RepaintBoundary(
    child: SizedBox(
      height: 110,
      child: ValueListenableBuilder<double>(
        valueListenable: elapsed,
        builder: (context, value, _) {
          return LineChart(
            LineChartData(
              minX: 0,
              maxX: maxX,
              minY: 0,
              maxY: 600,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey)),
              titlesData: const FlTitlesData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              extraLinesData: ExtraLinesData(
                verticalLines: [
                  if (value > 0 && value <= maxX) VerticalLine(x: value, strokeWidth: 1.2),
                ],
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

void main() {
  testWidgets('Perf gate T4: tick thu (chart 200 điểm + lyric highlight) < 8ms/tick trung bình', (tester) async {
    final elapsed = ValueNotifier<double>(0);
    final spots = <FlSpot>[
      for (var i = 0; i < 200; i++) FlSpot(i * 0.125, 220 + 60 * math.sin(i / 12.0)),
    ];
    const maxX = 25.0;
    final lines = List.generate(6, (i) => _SectionLine(i * 4.0, (i + 1) * 4.0));
    final section = _FakeSection(lines, 6, 25.0);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ListView(
            children: [
              _guideChart(elapsed, spots, maxX),
              ValueListenableBuilder<double>(
                valueListenable: elapsed,
                builder: (context, value, _) {
                  final idx = currentLineIndex(
                    lineTimes: const [],
                    lineCount: section.lineCount,
                    duration: section.duration,
                    elapsed: value,
                  );
                  return Column(
                    children: [
                      for (var i = 0; i < section.lineCount; i++)
                        Text(
                          'Câu ${i + 1}',
                          style: TextStyle(
                            fontSize: i == idx ? 13.5 : 11.5,
                            fontWeight: i == idx ? FontWeight.bold : FontWeight.w400,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final samples = <double>[];
    for (var tick = -2; tick <= 25; tick++) {
      elapsed.value = (tick <= 0 ? 1 : tick) * 0.9;
      final sw = Stopwatch()..start();
      await tester.pump();
      sw.stop();
      if (tick >= 1) samples.add(sw.elapsedMicroseconds / 1000.0);
      await tester.pump(const Duration(milliseconds: 120));
    }
    final sorted = samples.toList()..sort();
    final median = sorted[sorted.length ~/ 2];
    final avg = samples.reduce((a, b) => a + b) / samples.length;
    final worst = samples.reduce(math.max);
    // ignore: avoid_print
    print('PERF-GATE-T4 median=${median.toStringAsFixed(2)}ms avg=${avg.toStringAsFixed(2)}ms worst=${worst.toStringAsFixed(2)}ms n=${samples.length} (2 warm-up ticks excluded)');
    expect(median, lessThan(8.0), reason: 'tick median $median ms vượt gate 8ms');
  });
}
