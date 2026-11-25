import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

Color statusColor(BuildContext context, String code) {
  switch (code) {
    case 'ok':
    case 'done':
    case 'success':
    case 'approved':
      return AppTheme.statusReadable(context, AppStatusKind.success);
    case 'minor':
    case 'warn':
    case 'warning':
    case 'blocked':
    case 'cancelled':
    case 'pending':
      return AppTheme.statusReadable(context, AppStatusKind.warning);
    case 'off':
    case 'octave':
    case 'error':
    case 'failed':
      return AppTheme.statusReadable(context, AppStatusKind.danger);
    case 'info':
    case 'running':
    case 'queued':
      return AppTheme.statusReadable(context, AppStatusKind.info);
    default:
      return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}

