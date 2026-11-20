import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'hue_chip.dart';

class ResultSummaryCard extends StatelessWidget {
  final String title;
  final AppStatusKind? status;
  final String? statusLabel;
  final IconData? leadingIcon;
  final List<Widget> children;
  final Widget? footer;

  const ResultSummaryCard({
    super.key,
    required this.title,
    this.status,
    this.statusLabel,
    this.leadingIcon,
    required this.children,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
            child: Row(
              children: [
                if (leadingIcon != null) ...[
                  Icon(leadingIcon, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (status != null)
                  HueChip(
                    label: statusLabel ?? status!.name,
                    kind: status,
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: AppAlpha.hover)),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
              child: footer!,
            ),
        ],
      ),
    );
  }
}

class MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final AppStatusKind? valueKind;

  const MetricRow({
    super.key,
    required this.label,
    required this.value,
    this.valueKind,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: valueKind != null
                        ? AppTheme.statusReadable(context, valueKind!)
                        : scheme.onSurface,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScoreBadge extends StatelessWidget {
  final String label;
  final String value;
  final AppStatusKind kind;

  const ScoreBadge({
    super.key,
    required this.label,
    required this.value,
    required this.kind,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = AppTheme.statusReadable(context, kind);
    final bg = Color.alphaBlend(statusColor.withAlpha(40), Theme.of(context).colorScheme.surface);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class GaugeScore extends StatelessWidget {
  final double value;
  final String? caption;
  final double size;

  const GaugeScore({
    super.key,
    required this.value,
    this.caption,
    this.size = 96,
  });

  AppStatusKind get kind {
    final v = value.clamp(0, 100);
    if (v >= 80) return AppStatusKind.success;
    if (v >= 50) return AppStatusKind.warning;
    return AppStatusKind.danger;
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = AppTheme.statusReadable(context, kind);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(
          progress: value.clamp(0, 100) / 100,
          color: statusColor,
          trackColor: scheme.outlineVariant,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value.round().toString(),
                style: TextStyle(
                  fontFamily: AppTheme.displayFontFamily,
                  fontFamilyFallback: const [AppTheme.bodyFontFamily],
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              if (caption != null && caption!.isNotEmpty)
                Text(
                  caption!,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _GaugePainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = trackColor;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawCircle(center, radius, track);
    const start = -math.pi / 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      2 * math.pi * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor;
  }
}
