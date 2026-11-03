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
  final List<DerivedFile> derivedFiles;
  final int derivedBytes;

  StorageEntry({
    required this.id,
    required this.title,
    required this.filename,
    required this.size,
    required this.createdAt,
    required this.originalExists,
    required this.derivedFiles,
    required this.derivedBytes,
  });

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
      derivedFiles: files,
      derivedBytes: j['derived_bytes'] is num ? (j['derived_bytes'] as num).toInt() : 0,
    );
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

class AdminEndpoints {
  final Dio dio;

  AdminEndpoints(this.dio);

  Future<AdminStats> stats() async {
    final res = await dio.get('/api/admin/stats');
    return AdminStats.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<List<StorageEntry>> storage({String q = '', int limit = 100}) async {
    final res = await dio.get('/api/admin/storage', queryParameters: {'q': q, 'limit': limit});
    final raw = res.data;
    final list = <StorageEntry>[];
    if (raw is Map) {
      final items = raw['items'];
      if (items is List) {
        for (final e in items) {
          if (e is Map) {
            list.add(StorageEntry.fromJson(Map<String, dynamic>.from(e)));
          }
        }
      }
    }
    return list;
  }

  Future<void> deleteStorageItem(String id) async {
    await dio.delete('/api/admin/storage/$id');
  }
}
