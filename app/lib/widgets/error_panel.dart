import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/locale_provider.dart';

class ErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorPanel({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.errorContainer),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 20, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: scheme.onSurface, height: 1.4),
            ),
          ),
          if (onRetry != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              tooltip: context.watch<LocaleProvider>().strings.learnRetry,
              onPressed: onRetry,
            ),
        ],
      ),
    );
  }
}
