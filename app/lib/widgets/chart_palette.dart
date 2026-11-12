import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class ChartPalette {
  final Color reference;
  final Color user;

  const ChartPalette({
    required this.reference,
    required this.user,
  });

  static ChartPalette of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ChartPalette(
      reference: isDark ? AppTheme.imperialGold : AppTheme.imperialGoldInk,
      user: isDark ? const Color(0xFF7DD3FC) : const Color(0xFF2563EB),
    );
  }

  static FlGridData styledGrid(BuildContext context) {
    final divider = Theme.of(context).dividerColor.withValues(alpha: 0.45);
    return FlGridData(
      show: true,
      drawVerticalLine: false,
      getDrawingHorizontalLine: (value) =>
          FlLine(color: divider, strokeWidth: 1),
      getDrawingVerticalLine: (value) =>
          const FlLine(color: Colors.transparent, strokeWidth: 0),
    );
  }

  static FlTitlesData styledTitles(
    BuildContext context, {
    String? axisName,
    bool bottomNumbers = true,
  }) {
    final style = TextStyle(
        fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        axisNameWidget: axisName != null ? Text(axisName, style: style) : null,
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            axisSide: meta.axisSide,
            child: Text(_hz(value), style: style),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: bottomNumbers,
          reservedSize: 22,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            axisSide: meta.axisSide,
            child: Text('${value.toStringAsFixed(value < 10 ? 1 : 0)}s',
                style: style),
          ),
        ),
      ),
    );
  }

  static String _hz(double v) =>
      v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toStringAsFixed(0);

  static LineTouchData styledTouch(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LineTouchData(
      handleBuiltInTouches: true,
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => scheme.inverseSurface,
        getTooltipItems: (spots) => [
          for (final s in spots)
            LineTooltipItem(
              s.y.toString(),
              TextStyle(
                color: scheme.onInverseSurface,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
        ],
        fitInsideHorizontally: true,
        fitInsideVertically: true,
      ),
    );
  }
}
