import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

Color statusColor(BuildContext context, String code) {
  switch (code) {
    case 'ok':
    case 'done':
    case 'success':
    case 'approved':
      return AppTheme.statusSuccess;
    case 'minor':
    case 'warn':
    case 'warning':
    case 'blocked':
    case 'cancelled':
    case 'pending':
      return AppTheme.statusWarning;
    case 'off':
    case 'octave':
    case 'error':
    case 'failed':
      return AppTheme.statusDanger;
    case 'info':
    case 'running':
    case 'queued':
      return AppTheme.statusInfo;
    default:
      return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}

