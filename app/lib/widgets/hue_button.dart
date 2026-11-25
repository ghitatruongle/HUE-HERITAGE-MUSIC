import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'hue_icons.dart';

enum HueButtonVariant { primary, gold, danger, ghost }

enum HueButtonSize { normal, small }

class HueButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final HueButtonVariant variant;
  final HueButtonSize size;

  const HueButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
    this.variant = HueButtonVariant.primary,
    this.size = HueButtonSize.normal,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gold = AppTheme.goldReadable(context);
    final danger = AppTheme.statusReadable(context, AppStatusKind.danger);
    final onDanger = Theme.of(context).brightness == Brightness.dark
        ? AppTheme.darkSurface
        : Colors.white;
    final enabled = !loading && onPressed != null;
    final textStyle = size == HueButtonSize.small
        ? Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)
        : Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600);
    final tapTarget = size == HueButtonSize.small ? const Size(48, 48) : const Size(64, 48);
    final padding = size == HueButtonSize.small
        ? const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm)
        : const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg);
    final radius = BorderRadius.circular(size == HueButtonSize.small ? AppRadius.md : AppRadius.lg);

    ButtonStyle style;
    switch (variant) {
      case HueButtonVariant.primary:
        style = FilledButton.styleFrom(
          minimumSize: tapTarget,
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.primary.withValues(alpha: AppAlpha.hover),
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textStyle,
        );
        break;
      case HueButtonVariant.gold:
        style = OutlinedButton.styleFrom(
          minimumSize: tapTarget,
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
          foregroundColor: gold,
          side: BorderSide(color: gold.withValues(alpha: 0.6)),
          disabledForegroundColor: gold.withValues(alpha: AppAlpha.hover),
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textStyle,
        );
        break;
      case HueButtonVariant.danger:
        style = FilledButton.styleFrom(
          minimumSize: tapTarget,
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
          backgroundColor: danger,
          foregroundColor: onDanger,
          disabledBackgroundColor: danger.withValues(alpha: AppAlpha.hover),
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textStyle,
        );
        break;
      case HueButtonVariant.ghost:
        style = TextButton.styleFrom(
          minimumSize: tapTarget,
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
          foregroundColor: scheme.primary,
          disabledForegroundColor: scheme.primary.withValues(alpha: AppAlpha.hover),
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textStyle,
        );
        break;
    }

    Widget child = loading
        ? SizedBox(
            width: size == HueButtonSize.small ? 16 : 20,
            height: size == HueButtonSize.small ? 16 : 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: _progressColor(context)),
          )
        : (icon != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HueIcon(icon!, size: size == HueButtonSize.small ? 16 : 18, decorative: true),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Text(label));

    switch (variant) {
      case HueButtonVariant.primary:
      case HueButtonVariant.danger:
        child = FilledButton(style: style, onPressed: enabled ? onPressed : null, child: child);
        break;
      case HueButtonVariant.gold:
        child = OutlinedButton(style: style, onPressed: enabled ? onPressed : null, child: child);
        break;
      case HueButtonVariant.ghost:
        child = TextButton(style: style, onPressed: enabled ? onPressed : null, child: child);
        break;
    }
    return child;
  }

  Color _progressColor(BuildContext context) {
    switch (variant) {
      case HueButtonVariant.primary:
        return Theme.of(context).colorScheme.onPrimary;
      case HueButtonVariant.gold:
        return AppTheme.goldReadable(context);
      case HueButtonVariant.danger:
        return Theme.of(context).brightness == Brightness.dark
            ? AppTheme.darkSurface
            : Colors.white;
      case HueButtonVariant.ghost:
        return Theme.of(context).colorScheme.primary;
    }
  }
}
