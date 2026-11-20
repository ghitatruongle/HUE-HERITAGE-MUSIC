import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'heritage_motif.dart';

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
    const gold = AppTheme.imperialGold;
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
          child: Row(
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
                  child: Icon(icon, size: 20, color: gold),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTheme.displayFontFamily,
                        fontFamilyFallback: [AppTheme.bodyFontFamily],
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: Colors.white,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTheme.bodyFontFamily,
                          fontSize: 12,
                          height: 1.3,
                          color: Colors.white.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (actions != null) ...[...actions!],
            ],
          ),
        ),
      ),
    );
  }
}
