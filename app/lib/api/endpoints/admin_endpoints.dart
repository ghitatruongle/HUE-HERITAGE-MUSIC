import 'package:dio/dio.dart';

class AdminStats {
  final int usersTotal;
  final int usersActive;
  final int invitesTotal;
  final int invitesUnused;
  final int itemsTotal;
  final int itemsBytes;
  final int derivedFiles;
  final int derivedBytes;
  final int generatedBytes;
  final Map<String, int> tasksByStatus;
  final Map<String, int> tasksByKind;
  final bool engineOnline;

  AdminStats({
    required this.usersTotal,
    required this.usersActive,
    required this.invitesTotal,
    required this.invitesUnused,
    required this.itemsTotal,
    required this.itemsBytes,
    required this.derivedFiles,
    required this.derivedBytes,
    required this.generatedBytes,
    required this.tasksByStatus,
    required this.tasksByKind,
    required this.engineOnline,
  });

  static AdminStats fromJson(Map<String, dynamic> j) {
    int users(Map<String, dynamic> m, String k) {
      final v = m[k];
      return v is num ? v.toInt() : 0;
    }

    final usersMap = Map<String, dynamic>.from((j['users'] ?? {}) as Map);
    final invitesMap = Map<String, dynamic>.from((j['invites'] ?? {}) as Map);
    final storageMap = Map<String, dynamic>.from((j['storage'] ?? {}) as Map);
    final tasksMap = Map<String, dynamic>.from((j['tasks'] ?? {}) as Map);
    Map<String, int> toIntMap(dynamic raw) {
      final out = <String, int>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is num) {
            out[k.toString()] = v.toInt();
          }
        });
      }
      return out;
    }

    return AdminStats(
      usersTotal: users(usersMap, 'total'),
      usersActive: users(usersMap, 'active'),
      invitesTotal: users(invitesMap, 'total'),
      invitesUnused: users(invitesMap, 'unused'),
      itemsTotal: users(storageMap, 'items_total'),
      itemsBytes: users(storageMap, 'items_bytes'),
      derivedFiles: users(storageMap, 'derived_files'),
      derivedBytes: users(storageMap, 'derived_bytes'),
      generatedBytes: users(storageMap, 'generated_bytes'),
      tasksByStatus: toIntMap(tasksMap['by_status']),
      tasksByKind: toIntMap(tasksMap['by_kind']),
      engineOnline: j['engine_online'] == true,
    );
  }
}

class StorageEntry {
  final String id;
  final String title;
  final String filename;
  final int size;
  final String createdAt;
  final bool originalExists;
  final String visibility;
  final String ownerUsername;
  final List<DerivedFile> derivedFiles;
  final int derivedBytes;

  StorageEntry({
    required this.id,
    required this.title,
    required this.filename,
    required this.size,
    required this.createdAt,
    required this.originalExists,
    required this.visibility,
    required this.ownerUsername,
    required this.derivedFiles,
    required this.derivedBytes,
  });

  bool get adminOnly => visibility == 'admin_only';

  StorageEntry copyWith({String? visibility}) => StorageEntry(
        id: id,
        title: title,
        filename: filename,
        size: size,
        createdAt: createdAt,
        originalExists: originalExists,
        visibility: visibility ?? this.visibility,
        ownerUsername: ownerUsername,
        derivedFiles: derivedFiles,
        derivedBytes: derivedBytes,
      );

  static StorageEntry fromJson(Map<String, dynamic> j) {
    final files = <DerivedFile>[];
    final raw = j['derived_files'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          files.add(DerivedFile.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return StorageEntry(
      id: j['id']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      filename: j['filename']?.toString() ?? '',
      size: j['size'] is num ? (j['size'] as num).toInt() : 0,
      createdAt: j['created_at']?.toString() ?? '',
      originalExists: j['original_exists'] == true,
      visibility: j['visibility']?.toString() ?? 'public',
      ownerUsername: j['owner_username']?.toString() ?? '',
      derivedFiles: files,
      derivedBytes: j['derived_bytes'] is num ? (j['derived_bytes'] as num).toInt() : 0,
    );
  }
}

class StoragePage {
  final List<StorageEntry> items;
  final int total;

  StoragePage({required this.items, required this.total});
}

class CleanupResult {
  final int freedBytes;
  final int tasksDeleted;
  final Map<String, int> groupBytes;

  CleanupResult({required this.freedBytes, required this.tasksDeleted, this.groupBytes = const {}});

  static CleanupResult fromJson(Map<String, dynamic> j) {
    int n(Map<String, dynamic> m, String k) {
      final v = m[k];
      return v is num ? v.toInt() : 0;
    }

    final details = Map<String, dynamic>.from((j['details'] ?? {}) as Map);
    final tasks = Map<String, dynamic>.from((details['tasks'] ?? {}) as Map);
    final groups = <String, int>{};
    for (final entry in details.entries) {
      if (entry.key == 'tasks' || entry.value is! Map) continue;
      final bytes = (entry.value as Map)['bytes'];
      if (bytes is num && bytes > 0) groups[entry.key] = bytes.toInt();
    }
    return CleanupResult(
      freedBytes: n(Map<String, dynamic>.from(j), 'freed_bytes'),
      tasksDeleted: n(tasks, 'deleted'),
      groupBytes: groups,
    );
  }
}

class SecurityEvent {
  final String ts;
  final String level;
  final String event;
  final Map<String, String> fields;

  SecurityEvent({required this.ts, required this.level, required this.event, required this.fields});

  static SecurityEvent fromJson(Map<String, dynamic> j) {
    final raw = j['fields'];
    final fields = <String, String>{};
    if (raw is Map) {
      raw.forEach((k, v) => fields[k.toString()] = v?.toString() ?? '');
    }
    return SecurityEvent(
      ts: j['ts']?.toString() ?? '',
      level: j['level']?.toString() ?? '',
      event: j['event']?.toString() ?? '',
      fields: fields,
    );
  }
}

class SecurityEventsPage {
  final List<SecurityEvent> events;
  final int total;
  final bool truncated;

  SecurityEventsPage({required this.events, required this.total, required this.truncated});
}

class SecuritySummary {
  final Map<String, int> counts;
  final String? lastAdminLoginTs;

  SecuritySummary({required this.counts, this.lastAdminLoginTs});

  static SecuritySummary fromJson(Map<String, dynamic> j) {
    final counts = <String, int>{};
    final raw = j['counts'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num) counts[k.toString()] = v.toInt();
      });
    }
    String? last;
    final lastLogin = j['last_admin_login'];
    if (lastLogin is Map) {
      last = lastLogin['ts']?.toString();
    }
    return SecuritySummary(counts: counts, lastAdminLoginTs: last);
  }
}

class DerivedFile {
  final String kind;
  final int size;

  DerivedFile({required this.kind, required this.size});

  static DerivedFile fromJson(Map<String, dynamic> j) => DerivedFile(
        kind: j['kind']?.toString() ?? '',
        size: j['size'] is num ? (j['size'] as num).toInt() : 0,
      );
}

class LearningStats {
  final int totalSessions;
  final int activeUsers;
  final int sessionsLast7d;

  LearningStats({required this.totalSessions, required this.activeUsers, required this.sessionsLast7d});

  static LearningStats fromJson(Map<String, dynamic> j) {
    int n(dynamic v) => v is num ? v.toInt() : 0;
    return LearningStats(
      totalSessions: n(j['total_sessions']),
      activeUsers: n(j['active_users']),
      sessionsLast7d: n(j['sessions_last_7d']),
    );
  }
}

class AdminEndpoints {
  final Dio dio;

  AdminEndpoints(this.dio);

  Future<AdminStats> stats() async {
    final res = await dio.get('/api/admin/stats');
    return AdminStats.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<LearningStats> learningStats() async {
    final res = await dio.get('/api/admin/learning/stats');
    return LearningStats.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<StoragePage> storage({String q = '', int limit = 100, int offset = 0}) async {
    final res = await dio.get(
      '/api/admin/storage',
      queryParameters: {'q': q, 'limit': limit, 'offset': offset},
    );
    final raw = res.data;
    final list = <StorageEntry>[];
    int total = 0;
    if (raw is Map) {
      total = raw['items_total'] is num ? (raw['items_total'] as num).toInt() : 0;
      final items = raw['items'];
      if (items is List) {
        for (final e in items) {
          if (e is Map) {
            list.add(StorageEntry.fromJson(Map<String, dynamic>.from(e)));
          }
        }
      }
    }
    return StoragePage(items: list, total: total);
  }

  Future<void> deleteStorageItem(String id) async {
    await dio.delete('/api/admin/storage/$id');
  }

  Future<void> setVisibility(String id, String visibility) async {
    await dio.patch('/api/admin/storage/$id/visibility', data: {'visibility': visibility});
  }

  Future<CleanupResult> cleanup() async {
    final res = await dio.post('/api/admin/maintenance/cleanup');
    return CleanupResult.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<SecurityEventsPage> securityEvents({int limit = 100, int offset = 0, String event = '', String q = ''}) async {
    final res = await dio.get(
      '/api/admin/security/events',
      queryParameters: {'limit': limit, 'offset': offset, 'event': event, 'q': q},
    );
    final raw = res.data;
    final list = <SecurityEvent>[];
    int total = 0;
    bool truncated = false;
    if (raw is Map) {
      total = raw['total'] is num ? (raw['total'] as num).toInt() : 0;
      truncated = raw['truncated'] == true;
      final items = raw['events'];
      if (items is List) {
        for (final e in items) {
          if (e is Map) {
            list.add(SecurityEvent.fromJson(Map<String, dynamic>.from(e)));
          }
        }
      }
    }
    return SecurityEventsPage(events: list, total: total, truncated: truncated);
  }

  Future<SecuritySummary> securitySummary() async {
    final res = await dio.get('/api/admin/security/summary');
    return SecuritySummary.fromJson(Map<String, dynamic>.from(res.data as Map));
  }
}
