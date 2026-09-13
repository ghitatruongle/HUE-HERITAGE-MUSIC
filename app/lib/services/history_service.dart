import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryEntry {
  final String id;
  final String kind;
  final String title;
  final String status;
  final DateTime at;

  HistoryEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.status,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'status': status,
        'at': at.toIso8601String(),
      };

  static HistoryEntry fromJson(Map<String, dynamic> j) => HistoryEntry(
        id: j['id']?.toString() ?? '',
        kind: j['kind']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        status: j['status']?.toString() ?? '',
        at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime.now(),
      );
}

class HistoryService extends ChangeNotifier {
  static const String _key = 'task_history';
  static const int _maxEntries = 200;
  List<HistoryEntry> _entries = [];

  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      _entries = list
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (_) {
      _entries = [];
    }
  }

  Future<void> add(HistoryEntry entry) async {
    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) {
      _entries = _entries.sublist(0, _maxEntries);
    }
    await _persist();
  }

  Future<void> updateStatus(String id, String status) async {
    final idx = _entries.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      _entries[idx] = HistoryEntry(
        id: _entries[idx].id,
        kind: _entries[idx].kind,
        title: _entries[idx].title,
        status: status,
        at: _entries[idx].at,
      );
      await _persist();
    }
  }

  Future<void> clear() async {
    _entries = [];
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    notifyListeners();
  }
}
