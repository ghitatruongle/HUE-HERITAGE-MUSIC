import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import 'heritage_motif.dart';
import 'hue_icons.dart';

class FeatureHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget>? actions;

  const FeatureHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    const gold = AppTheme.gradientAccentGold;
    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          gradient: AppTheme.brandGradientOf(context),
          border: Border(
            bottom: BorderSide(color: gold.withValues(alpha: 0.2), width: 1),
          ),
        ),
        child: HeritageMotif(
          color: Colors.white,
          opacity: 0.09,
          radius: 0,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final hasActions = actions != null && actions!.isNotEmpty;
              final stackActions = hasActions && constraints.maxWidth < AppBreakpoints.compact;
              final headerRow = Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: gold.withValues(alpha: 0.55), width: 1.4),
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      child: HueIcon(icon!, size: 20, color: gold),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTheme.displayFontFamily,
                            fontFamilyFallback: [AppTheme.bodyFontFamily],
                            fontSize: AppFontSize.title,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: Colors.white,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTheme.bodyFontFamily,
                              fontSize: AppFontSize.sm,
                              height: 1.3,
                              color: Colors.white.withValues(alpha: 0.88),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (hasActions && !stackActions) ...[
                    const SizedBox(width: AppSpacing.sm),
                    ...actions!,
                  ],
                ],
              );
              if (!stackActions) return headerRow;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  headerRow,
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: actions!,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
