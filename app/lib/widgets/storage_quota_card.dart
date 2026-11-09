import 'package:flutter/material.dart';

import '../core/localization/app_strings.dart';

class StorageQuotaCard extends StatelessWidget {
  final AppStrings strings;
  final int usedBytes;
  final int? quotaBytes;

  const StorageQuotaCard({
    super.key,
    required this.strings,
    required this.usedBytes,
    this.quotaBytes,
  });

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final mb = bytes / (1024 * 1024);
    if (mb < 1) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasQuota = quotaBytes != null && quotaBytes! > 0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(strings.storageTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            _row(context, strings.storageUsed, formatBytes(usedBytes)),
            if (hasQuota) ...[
              _row(
                context,
                strings.storageQuota,
                '${formatBytes(usedBytes)} / ${formatBytes(quotaBytes!)}',
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: quotaBytes! > 0 ? (usedBytes / quotaBytes!).clamp(0.0, 1.0) : 0.0,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
                color: usedBytes >= quotaBytes! ? scheme.error : scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ] else
              _row(context, strings.storageQuota, strings.storageUnlimited),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
