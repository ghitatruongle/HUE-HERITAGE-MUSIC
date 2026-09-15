import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/heritage_api.dart';
import '../../api/endpoints/instrument_api.dart';
import '../../api/endpoints/restoration_api.dart';
import '../../core/theme/app_theme.dart';
import '../../models/heritage_item.dart';
import '../../models/instrument_result.dart';
import '../../models/restore_result.dart';
import '../../services/history_service.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';
import '../../services/session_media.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/common_button.dart';

class HeritageListScreen extends StatefulWidget {
  final bool restorationMode;

  const HeritageListScreen({super.key, this.restorationMode = false});

  @override
  State<HeritageListScreen> createState() => _HeritageListScreenState();
}

class _HeritageListScreenState extends State<HeritageListScreen> {
  final _search = TextEditingController();
  Future<List<HeritageItem>>? _future;
  HeritageItem? _selectedItem;

  @override
  void initState() {
    super.initState();
    _future = _load('');
  }

  Future<List<HeritageItem>> _load(String q) {
    final dio = context.read<ServerConfig>().api.dio;
    return HeritageApi(dio).list(q: q);
  }

  void _reload() {
    setState(() => _future = _load(_search.text));
  }

  void _log(String kind, String title, String status) {
    context.read<HistoryService>().add(
          HistoryEntry(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            kind: kind,
            title: title,
            status: status,
            at: DateTime.now(),
          ),
        );
  }

  void _playTrack(HeritageItem item) {
    final dio = context.read<ServerConfig>().api.dio;
    final url = HeritageApi(dio).audioUrl(item.id);

    context.read<SessionMedia>().playTrack(
      title: item.title,
      subtitle: [item.artist, item.type].where((s) => s.isNotEmpty).join(' • '),
      url: url,
    );
  }

  void _play(HeritageItem item) {
    final strings = context.read<LocaleProvider>().strings;

    _playTrack(item);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CommonButton(
              label: strings.detailsBtn,
              onPressed: () {
                Navigator.pop(context);
                _showDetail(item);
              },
            ),
            const SizedBox(height: 8),
            CommonButton(
              label: strings.restoreActionBtn,
              onPressed: () {
                Navigator.pop(context);
                _restore(item);
              },
            ),
            const SizedBox(height: 8),
            CommonButton(
              label: strings.detectInstrumentsBtn,
              onPressed: () {
                Navigator.pop(context);
                _detect(item);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.closeBtn),
          ),
        ],
      ),
    );
  }

  void _showDetail(HeritageItem item) {
    final rows = item.metadataRows();

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'SHA-256: ${item.sha256.length > 16 ? item.sha256.substring(0, 16) : item.sha256}...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const Divider(height: 24),
              for (final e in rows.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 140,
                        child: Text(e.key, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ),
                      Expanded(child: Text(e.value)),
                    ],
                  ),
                ),
              if (item.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.description),
              ],
              if (item.lyrics.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Lyrics / Lời bài hát', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(item.lyrics),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.verified_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  const Expanded(child: Text('Bản thu gốc (ORIGINAL) được bảo toàn, không ghi đè.')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _uploadDialog() async {
    final config = context.read<ServerConfig>();
    final strings = context.read<LocaleProvider>().strings;

    if (!config.hasServer) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.isVi ? 'Chưa cấu hình máy chủ. Vào Cài đặt để nhập địa chỉ.' : 'Server not configured. Please set URL in Settings.')),
      );
      return;
    }
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
    final file = picked?.files.single;
    if (file == null) return;
    final data = await _metadataForm();
    if (data == null) return;
    try {
      final api = HeritageApi(config.api.dio);
      final item = kIsWeb || file.bytes != null
          ? await api.uploadBytes(bytes: file.bytes ?? (await File(file.path!).readAsBytes()), filename: file.name, data: data)
          : await api.upload(filePath: file.path!, data: data);
      _log('heritage-upload', item.title, 'done');
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.isVi ? 'Đã thêm "${item.title}" vào kho di sản.' : 'Added "${item.title}" to heritage archive.')));
      }
    } catch (e) {
      _log('heritage-upload', file.name, 'error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.describe(e))));
      }
    }
  }

  Future<HeritageUploadData?> _metadataForm() async {
    final strings = context.read<LocaleProvider>().strings;
    final ctrls = {
      'title': TextEditingController(),
      'type': TextEditingController(),
      'artist': TextEditingController(),
      'genre': TextEditingController(),
      'composer': TextEditingController(),
      'performers': TextEditingController(),
      'artisans': TextEditingController(),
      'collector': TextEditingController(),
      'recorded_time': TextEditingController(),
      'location': TextEditingController(),
      'source': TextEditingController(),
      'license': TextEditingController(),
      'instruments': TextEditingController(),
      'tonal': TextEditingController(),
      'description': TextEditingController(),
      'notes': TextEditingController(),
      'lyrics': TextEditingController(),
      'bpm': TextEditingController(),
    };
    final labels = {
      'title': strings.isVi ? 'Tên tác phẩm *' : 'Title *',
      'type': strings.isVi ? 'Loại hình (Ca Huế, Nhã nhạc...)' : 'Type (Ca Hue, Court Music...)',
      'artist': strings.isVi ? 'Nghệ nhân / Nghệ sĩ' : 'Artisan / Artist',
      'genre': strings.isVi ? 'Thể loại' : 'Genre',
      'composer': strings.isVi ? 'Tác giả' : 'Composer',
      'performers': strings.isVi ? 'Người biểu diễn' : 'Performers',
      'artisans': strings.isVi ? 'Nghệ nhân liên quan' : 'Related Artisans',
      'collector': strings.isVi ? 'Người sưu tầm' : 'Collector',
      'recorded_time': strings.isVi ? 'Thời gian thu' : 'Recorded Date',
      'location': strings.isVi ? 'Địa điểm' : 'Location',
      'source': strings.isVi ? 'Nguồn' : 'Source',
      'license': strings.isVi ? 'Quyền sử dụng' : 'License',
      'instruments': strings.isVi ? 'Nhạc cụ' : 'Instruments',
      'tonal': strings.isVi ? 'Cung bậc / Tông' : 'Tonal / Scale',
      'description': strings.isVi ? 'Mô tả' : 'Description',
      'notes': strings.isVi ? 'Ghi chú nghiên cứu' : 'Research Notes',
      'lyrics': strings.isVi ? 'Lời bài hát' : 'Lyrics',
      'bpm': strings.isVi ? 'BPM (nếu biết)' : 'BPM',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(strings.isVi ? 'Thông tin tác phẩm' : 'Work Metadata'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in labels.entries) ...[
                  TextField(
                    controller: ctrls[e.key],
                    decoration: InputDecoration(labelText: e.value, isDense: true, border: const OutlineInputBorder()),
                    minLines: e.key == 'lyrics' || e.key == 'description' ? 2 : 1,
                    maxLines: e.key == 'lyrics' || e.key == 'description' ? 4 : 1,
                    keyboardType: e.key == 'bpm' ? TextInputType.number : TextInputType.text,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(strings.cancelBtn)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(strings.submitBtn)),
        ],
      ),
    );
    if (ok != true) return null;
    return HeritageUploadData(
      title: ctrls['title']!.text.trim(),
      type: ctrls['type']!.text.trim(),
      artist: ctrls['artist']!.text.trim(),
      genre: ctrls['genre']!.text.trim(),
      composer: ctrls['composer']!.text.trim(),
      performers: ctrls['performers']!.text.trim(),
      artisans: ctrls['artisans']!.text.trim(),
      collector: ctrls['collector']!.text.trim(),
      recordedTime: ctrls['recorded_time']!.text.trim(),
      location: ctrls['location']!.text.trim(),
      source: ctrls['source']!.text.trim(),
      license: ctrls['license']!.text.trim(),
      instruments: ctrls['instruments']!.text.trim(),
      tonal: ctrls['tonal']!.text.trim(),
      description: ctrls['description']!.text.trim(),
      notes: ctrls['notes']!.text.trim(),
      lyrics: ctrls['lyrics']!.text.trim(),
      bpm: ctrls['bpm']!.text.trim(),
    );
  }

  void _restore(HeritageItem item) {
    final dio = context.read<ServerConfig>().api.dio;
    final fut = RestorationApi(dio).restoreItem(item.id);
    _log('restore', item.title, 'running');
    final strings = context.read<LocaleProvider>().strings;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(strings.featRestorationTitle),
        content: FutureBuilder<RestoreResult>(
          future: fut,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(strings.processing),
                ],
              );
            }
            if (snap.hasError) {
              return Text('${strings.isVi ? 'Lỗi' : 'Error'}: ${ApiClient.describe(snap.error!)}');
            }
            final r = snap.data!;
            final url = RestorationApi(dio).restoredUrl(r.sha);
            WidgetsBinding.instance.addPostFrameCallback((_) => _log('restore', item.title, 'done'));
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('DC: ${r.dcRemoved} · Clicks: ${r.clicksFixed}'),
                Text('Peak: ${r.peakBefore} -> ${r.peakAfter}'),
                const SizedBox(height: 12),
                AudioPlayerBar(url: url),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.closeBtn),
          ),
        ],
      ),
    );
  }

  void _useAsSample(HeritageItem item) async {
    final strings = context.read<LocaleProvider>().strings;
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final api = HeritageApi(dio);
      final media = context.read<SessionMedia>();
      if (kIsWeb) {
        final bytes = await api.audioBytes(item.id);
        if (!mounted) return;
        media.setSample(bytes: bytes);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.isVi ? 'Đã chọn làm bản mẫu luyện hát' : 'Set as singing sample')),
        );
        return;
      }
      final savePath = '${Directory.systemTemp.path}/hue_sample.wav';
      await api.downloadAudio(item.id, savePath);
      if (!mounted) return;
      media.setSample(path: savePath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.isVi ? 'Đã tải bản mẫu luyện hát' : 'Singing sample downloaded')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.describe(e))),
        );
      }
    }
  }

  void _detect(HeritageItem item) {
    final dio = context.read<ServerConfig>().api.dio;
    final fut = InstrumentApi(dio).detectByItem(item.id);
    final strings = context.read<LocaleProvider>().strings;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(strings.featInstrumentsTitle),
        content: FutureBuilder<InstrumentResult>(
          future: fut,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(strings.processing),
                ],
              );
            }
            if (snap.hasError) {
              return Text('${strings.isVi ? 'Lỗi' : 'Error'}: ${ApiClient.describe(snap.error!)}');
            }
            final r = snap.data!;
            return Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    for (final s in r.segments)
                      ListTile(
                        dense: true,
                        title: Text(s.instrument),
                        subtitle: Text('${s.start}s - ${s.end}s'),
                        trailing: Text('${(s.confidence * 100).toInt()}%'),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.closeBtn),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    final width = MediaQuery.of(context).size.width;
    final isMasterDetail = width >= 900;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'heritage-upload',
        onPressed: _uploadDialog,
        icon: const Icon(Icons.upload_file),
        label: Text(strings.addRecordingBtn),
      ),
      body: isMasterDetail ? _buildMasterDetail(context, strings) : _buildSingleList(context, strings),
    );
  }

  Widget _buildSingleList(BuildContext context, dynamic strings) {
    return Column(
      children: [
        _buildSearchBar(strings),
        Expanded(
          child: _buildItemsFuture(
            (items) => ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) => _buildItemTile(items[i], strings, false),
            ),
            strings,
          ),
        ),
      ],
    );
  }

  Widget _buildMasterDetail(BuildContext context, dynamic strings) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? const Color(0xFF2E2B48) : const Color(0xFFE4DFEE);

    return Row(
      children: [
        SizedBox(
          width: 380,
          child: Column(
            children: [
              _buildSearchBar(strings),
              Expanded(
                child: _buildItemsFuture(
                  (items) {
                    if (_selectedItem == null && items.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _selectedItem = items.first);
                      });
                    }
                    return ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final it = items[i];
                        final isSel = _selectedItem?.id == it.id;
                        return _buildItemTile(it, strings, isSel);
                      },
                    );
                  },
                  strings,
                ),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: borderColor),
        Expanded(
          child: _selectedItem == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.library_music, size: 64, color: AppTheme.primaryPurple.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      Text(strings.masterDetailEmptyTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text(strings.masterDetailEmptySubtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                )
              : _buildDetailPane(_selectedItem!, strings),
        ),
      ],
    );
  }

  Widget _buildSearchBar(dynamic strings) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              onSubmitted: (_) => _reload(),
              decoration: InputDecoration(
                hintText: strings.searchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CommonButton(
            label: strings.searchBtn,
            onPressed: _reload,
          ),
        ],
      ),
    );
  }

  Widget _buildItemsFuture(Widget Function(List<HeritageItem>) builder, dynamic strings) {
    return FutureBuilder<List<HeritageItem>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('${strings.isVi ? 'Lỗi' : 'Error'}: ${ApiClient.describe(snap.error!)}'));
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Center(child: Text(strings.noRecordings));
        }
        return builder(items);
      },
    );
  }

  Widget _buildItemTile(HeritageItem it, dynamic strings, bool isSelected) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.primaryPurple.withValues(alpha: isDark ? 0.25 : 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: isSelected
            ? Border.all(color: AppTheme.primaryPurpleLight, width: 1.5)
            : null,
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(it.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(
          [
            if (it.type.isNotEmpty) it.type,
            if (it.artist.isNotEmpty) it.artist,
            if (it.recordedTime.isNotEmpty) it.recordedTime,
          ].join(' • '),
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
        onTap: () {
          setState(() => _selectedItem = it);
        },
        trailing: IconButton(
          icon: const Icon(Icons.play_circle_filled, color: AppTheme.primaryPurpleLight),
          tooltip: strings.originalAudio,
          onPressed: () => _play(it),
        ),
      ),
    );
  }

  Widget _buildDetailPane(HeritageItem item, dynamic strings) {
    final rows = item.metadataRows();

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (item.type.isNotEmpty)
                        Chip(
                          label: Text(item.type, style: const TextStyle(fontSize: 12)),
                          backgroundColor: AppTheme.primaryPurple.withValues(alpha: 0.15),
                        ),
                      if (item.artist.isNotEmpty)
                        Chip(
                          label: Text(item.artist, style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.audiotrack, size: 18, color: AppTheme.amberGold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(strings.originalAudio, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                FilledButton.icon(
                  onPressed: () => _playTrack(item),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(strings.playBtn),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.school, size: 18),
              label: Text(strings.useAsSampleBtn),
              onPressed: () => _useAsSample(item),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.healing, size: 18),
              label: Text(strings.restoreActionBtn),
              onPressed: () => _restore(item),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.piano, size: 18),
              label: Text(strings.detectInstrumentsBtn),
              onPressed: () => _detect(item),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Metadata / Thông tin lưu trữ', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final e in rows.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 160,
                          child: Text(e.key, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ),
                        Expanded(child: Text(e.value)),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 160,
                        child: Text('SHA-256', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ),
                      Expanded(
                        child: SelectableText(item.sha256, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (item.lyrics.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Lyrics / Lời bài hát', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                item.lyrics,
                style: const TextStyle(height: 1.6),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
