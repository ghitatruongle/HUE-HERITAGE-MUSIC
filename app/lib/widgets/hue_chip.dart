import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class HueChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final AppStatusKind? kind;
  final bool selected;
  final VoidCallback? onTap;

  const HueChip({
    super.key,
    required this.label,
    this.icon,
    this.kind,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = kind != null ? AppTheme.statusReadable(context, kind!) : null;
    final bg = statusColor != null
        ? Color.alphaBlend(statusColor.withAlpha(40), scheme.surface)
        : scheme.surfaceContainerHighest;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: statusColor ?? scheme.onSurfaceVariant),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ],
    );
    return Material(
      color: bg,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? AppTheme.goldReadable(context).withValues(alpha: 0.7)
              : (statusColor?.withValues(alpha: 0.35) ?? scheme.outline),
          width: selected ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: content,
        ),
      ),
    );
  }
}
