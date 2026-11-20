import 'package:flutter/foundation.dart';

import 'history_service.dart';

class PracticeResume {
  PracticeResume._();

  static final ValueNotifier<String?> lessonId = ValueNotifier<String?>(null);

  static HistoryEntry? pickLatest(List<HistoryEntry> entries) {
    for (final e in entries) {
      if (e.kind == 'practice' && e.detail.isNotEmpty && !e.detail.startsWith('scale:')) {
        return e;
      }
    }
    return null;
  }
}
