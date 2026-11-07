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
      reference: AppTheme.imperialGold,
      user: isDark ? const Color(0xFF7DD3FC) : const Color(0xFF2563EB),
    );
  }
}
