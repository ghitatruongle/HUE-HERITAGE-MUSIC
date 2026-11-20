import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../services/locale_provider.dart';
import 'hue_icons.dart';

class ErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorPanel({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.errorContainer),
      ),
      child: Row(
        children: [
          HueIcon(HueIcons.error, size: 20, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: scheme.onSurface, height: 1.4),
            ),
          ),
          if (onRetry != null)
            IconButton(
              icon: const HueIcon(HueIcons.refresh, size: 18),
              tooltip: context.watch<LocaleProvider>().strings.learnRetry,
              onPressed: onRetry,
            ),
        ],
      ),
    );
  }
}
