import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class HeritageMotif extends StatelessWidget {
  final Color color;
  final double opacity;
  final double radius;
  final Widget? child;

  const HeritageMotif({
    super.key,
    required this.color,
    this.opacity = 0.1,
    this.radius = 16,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _HeritagePatternPainter(
        color: color,
        opacity: opacity,
        radius: radius,
      ),
      child: child,
    );
  }
}

class _HeritagePatternPainter extends CustomPainter {
  final Color color;
  final double opacity;
  final double radius;

  _HeritagePatternPainter({
    required this.color,
    required this.opacity,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (radius > 0) {
      final clip = Path()
        ..addRRect(
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
        );
      canvas.clipPath(clip);
    }
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    const waveWidth = 26.0;
    const waveHeight = 11.0;
    final bottom = size.height - 4.0;
    final upperWave = math.max(bottom - 12.0, size.height * 0.5);
    for (final y in [bottom, upperWave]) {
      final path = Path();
      var x = -waveWidth / 2.0;
      while (x < size.width) {
        path.moveTo(x, y);
        path.quadraticBezierTo(
            x + waveWidth / 4, y - waveHeight, x + waveWidth / 2, y);
        path.quadraticBezierTo(
            x + waveWidth * 3 / 4, y + waveHeight, x + waveWidth, y);
        x += waveWidth;
      }
      canvas.drawPath(path, paint);
    }

    const cell = 46.0;
    var row = 0;
    for (double y = cell / 2; y < upperWave - cell / 2; y += cell) {
      final dx = row.isEven ? 0.0 : cell / 2;
      for (double x = cell / 2; x < size.width + cell; x += cell) {
        _drawDiamond(canvas, Offset(x + dx, y), 4.5, paint);
      }
      row++;
    }
  }

  void _drawDiamond(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r, c.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeritagePatternPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.opacity != opacity ||
      oldDelegate.radius != radius;
}

class DanNguyetDisc extends StatelessWidget {
  final double size;
  final Color discColor;
  final Color grooveColor;
  final Color labelColor;

  const DanNguyetDisc({
    super.key,
    required this.size,
    this.discColor = AppTheme.recordDiscDark,
    this.grooveColor = Colors.white,
    this.labelColor = AppTheme.amberGold,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _DanNguyetPainter(
        discColor: discColor,
        grooveColor: grooveColor,
        labelColor: labelColor,
      ),
    );
  }
}

class _DanNguyetPainter extends CustomPainter {
  final Color discColor;
  final Color grooveColor;
  final Color labelColor;

  _DanNguyetPainter({
    required this.discColor,
    required this.grooveColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final body = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0xFFA85B32),
          Color(0xFF8C4A2F),
          Color(0xFF6B3520),
        ],
        stops: [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, body);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFFE8DCC8).withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, radius * 0.045),
    );

    final grain = Paint()
      ..color = grooveColor.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const grainRings = 7;
    for (var i = 1; i <= grainRings; i++) {
      final r = radius * (0.52 + 0.42 * i / grainRings);
      canvas.drawCircle(center, r, grain);
    }

    final rosetteRadius = radius * 0.34;
    canvas.drawCircle(center, rosetteRadius, Paint()..color = labelColor);
    final petal = Paint()
      ..color = discColor.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, radius * 0.018);
    const petals = 8;
    for (var i = 0; i < petals; i++) {
      final angle = i * math.pi / (petals / 2);
      final a = Offset(
        center.dx + rosetteRadius * 0.62 * math.cos(angle),
        center.dy + rosetteRadius * 0.62 * math.sin(angle),
      );
      final b = Offset(
        center.dx + rosetteRadius * 0.62 * math.cos(angle + math.pi / petals),
        center.dy + rosetteRadius * 0.62 * math.sin(angle + math.pi / petals),
      );
      canvas.drawLine(a, b, petal);
    }
    canvas.drawCircle(
      center,
      rosetteRadius,
      Paint()
        ..color = discColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, radius * 0.02),
    );
    canvas.drawCircle(center, radius * 0.05, Paint()..color = discColor);

    final stringPaint = Paint()
      ..color = const Color(0xFFF2E8D5).withValues(alpha: 0.85)
      ..strokeWidth = math.max(1.0, radius * 0.014);
    for (final dx in [-radius * 0.13, radius * 0.13]) {
      canvas.drawLine(
        Offset(center.dx + dx, center.dy - radius * 0.80),
        Offset(center.dx + dx, center.dy + radius * 0.80),
        stringPaint,
      );
    }

    final bridgeY = center.dy + radius * 0.62;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(center.dx, bridgeY),
        width: radius * 0.52,
        height: radius * 0.09,
      ),
      Paint()..color = const Color(0xFF3B1D0E).withValues(alpha: 0.85),
    );

    final sheen = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.12),
          Colors.white.withValues(alpha: 0.0),
        ],
        transform: const GradientRotation(-math.pi / 3),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.75;
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(center, radius * 0.72, sheen);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DanNguyetPainter oldDelegate) =>
      oldDelegate.discColor != discColor ||
      oldDelegate.grooveColor != grooveColor ||
      oldDelegate.labelColor != labelColor;
}

class ImperialTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController? controller;
  final List<Widget> tabs;
  final EdgeInsetsGeometry margin;

  const ImperialTabBar({
    super.key,
    this.controller,
    required this.tabs,
    this.margin = EdgeInsets.zero,
  });

  @override
  Size get preferredSize => const Size.fromHeight(74);

  @override
  Widget build(BuildContext context) {
    final gold = AppTheme.goldReadable(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: margin,
      child: TabBar(
        controller: controller,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: gold,
        indicatorWeight: 2.6,
        dividerColor: Colors.transparent,
        labelColor: gold,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFontSize.md),
        tabs: tabs,
      ),
    );
  }
}
