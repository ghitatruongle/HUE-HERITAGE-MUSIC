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

class VinylDisc extends StatelessWidget {
  final double size;
  final Color discColor;
  final Color grooveColor;
  final Color labelColor;

  const VinylDisc({
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
      painter: _VinylDiscPainter(
        discColor: discColor,
        grooveColor: grooveColor,
        labelColor: labelColor,
      ),
    );
  }
}

class _VinylDiscPainter extends CustomPainter {
  final Color discColor;
  final Color grooveColor;
  final Color labelColor;

  _VinylDiscPainter({
    required this.discColor,
    required this.grooveColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    canvas.drawCircle(center, radius, Paint()..color = discColor);

    final groove = Paint()
      ..color = grooveColor.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const steps = 6;
    for (var i = 1; i <= steps; i++) {
      final r = radius * (0.55 + 0.4 * i / steps);
      canvas.drawCircle(center, r, groove);
    }

    final sheen = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.18),
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

    final labelRadius = radius * 0.42;
    canvas.drawCircle(center, labelRadius, Paint()..color = labelColor);
    canvas.drawCircle(
      center,
      radius * 0.09,
      Paint()..color = discColor,
    );
    canvas.drawCircle(
      center,
      labelRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _VinylDiscPainter oldDelegate) =>
      oldDelegate.discColor != discColor ||
      oldDelegate.grooveColor != grooveColor ||
      oldDelegate.labelColor != labelColor;
}
