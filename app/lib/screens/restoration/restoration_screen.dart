import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/heritage_api.dart';
import '../../api/endpoints/restoration_api.dart';
import '../../api/endpoints/sing_api.dart';
import '../../core/theme/app_theme.dart';
import '../../models/compare_result.dart';
import '../../models/heritage_item.dart';
import '../../models/restore_result.dart';
import '../../services/history_service.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/compare_chart.dart';

class RestorationScreen extends StatefulWidget {
  const RestorationScreen({super.key});

  @override
  State<RestorationScreen> createState() => _RestorationScreenState();
}

class _RestorationScreenState extends State<RestorationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();
  Future<List<HeritageItem>>? _itemsFuture;
  List<HeritageItem> _allTracks = [];

  HeritageItem? _selectedItem;
  RestoreResult? _restoreResult;
  bool _isRestoring = false;
  String? _restoreError;

  HeritageItem? _compareSampleItem;
  HeritageItem? _compareTargetItem;
  Uint8List? _uploadedTargetBytes;
  String _uploadedTargetName = '';
  CompareResult? _compareResult;
  bool _isComparing = false;
  String? _compareError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _itemsFuture = _loadItems('');
  }

  Future<List<HeritageItem>> _loadItems(String q) async {
    final dio = context.read<ServerConfig>().api.dio;
    final list = await HeritageApi(dio).list(q: q);
    if (mounted) {
      setState(() {
        _allTracks = list;
        if (_selectedItem == null && list.isNotEmpty) {
          _selectedItem = list.first;
        }
        if (_compareSampleItem == null && list.isNotEmpty) {
          _compareSampleItem = list.first;
        }
        if (_compareTargetItem == null && list.length > 1) {
          _compareTargetItem = list[1];
        }
      });
    }
    return list;
  }

  void _reloadItems() {
    setState(() => _itemsFuture = _loadItems(_searchCtrl.text));
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

  Future<void> _runDspRestoration(HeritageItem item) async {
    setState(() {
      _isRestoring = true;
      _restoreError = null;
    });
    final dio = context.read<ServerConfig>().api.dio;
    _log('restore', item.title, 'running');
    try {
      final res = await RestorationApi(dio).restoreItem(item.id);
      _log('restore', item.title, 'done');
      if (mounted) {
        setState(() {
          _restoreResult = res;
          _isRestoring = false;
        });
      }
    } catch (e) {
      _log('restore', item.title, 'error');
      if (mounted) {
        setState(() {
          _restoreError = ApiClient.describe(e);
          _isRestoring = false;
        });
      }
    }
  }

  Future<void> _uploadAndRestoreFile() async {
    final config = context.read<ServerConfig>();
    final strings = context.read<LocaleProvider>().strings;

    if (!config.hasServer) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.isVi ? 'Chưa cấu hình máy chủ.' : 'Server not configured.')),
      );
      return;
    }
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes ?? (file.path != null && !kIsWeb ? await File(file.path!).readAsBytes() : null);
    if (bytes == null || !mounted) return;

    final dio = config.api.dio;
    _log('restore-upload', file.name, 'running');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(strings.processing),
          ],
        ),
      ),
    );

    try {
      final res = await RestorationApi(dio).restoreUpload(bytes: bytes, filename: file.name);
      _log('restore-upload', file.name, 'done');
      if (!mounted) return;
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.amberGold.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppTheme.amberGold),
                ),
                child: const Text('BETA', style: TextStyle(color: AppTheme.amberGold, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(res.label, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('${strings.restorationDcRemoved}: ${res.dcRemoved.toStringAsFixed(4)}'),
              Text('${strings.restorationClicksFixed}: ${res.clicksFixed}'),
              Text('${strings.restorationPeakChange}: ${res.peakBefore.toStringAsFixed(2)} -> ${res.peakAfter.toStringAsFixed(2)}'),
              Text('${strings.restorationNoiseFloor}: ${res.noiseFloorDb.toStringAsFixed(1)} dB'),
              const SizedBox(height: 12),
              AudioPlayerBar(url: RestorationApi(dio).restoredUrl(res.sha), label: strings.restoredAudio),
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
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.describe(e))));
      }
    }
  }

  Future<void> _pickTargetAudioForComparison() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes ?? (file.path != null && !kIsWeb ? await File(file.path!).readAsBytes() : null);
    if (bytes == null || !mounted) return;

    setState(() {
      _uploadedTargetBytes = bytes;
      _uploadedTargetName = file.name;
      _compareTargetItem = null;
      _compareResult = null;
      _compareError = null;
    });
  }

  Future<void> _runCrossComparison() async {
    if (_compareSampleItem == null) return;
    final config = context.read<ServerConfig>();
    final dio = config.api.dio;
    final heritageApi = HeritageApi(dio);

    setState(() {
      _isComparing = true;
      _compareError = null;
    });

    try {
      final sampleBytes = await heritageApi.audioBytes(_compareSampleItem!.id);
      Uint8List targetBytes;
      if (_uploadedTargetBytes != null) {
        targetBytes = _uploadedTargetBytes!;
      } else if (_compareTargetItem != null) {
        targetBytes = await heritageApi.audioBytes(_compareTargetItem!.id);
      } else {
        throw StateError('Chưa chọn bản ghi cần đối chiếu');
      }

      final res = await SingApi(dio).compareBytes(sampleBytes, targetBytes);
      _log('compare-tune', '${_compareSampleItem!.title} vs ${_uploadedTargetName.isNotEmpty ? _uploadedTargetName : _compareTargetItem?.title}', 'done');

      if (mounted) {
        setState(() {
          _compareResult = res;
          _isComparing = false;
        });
      }
    } catch (e) {
      _log('compare-tune', _compareSampleItem!.title, 'error');
      if (mounted) {
        setState(() {
          _compareError = ApiClient.describe(e);
          _isComparing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildBetaBanner(strings),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1A33) : const Color(0xFFEBE6F5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: AppTheme.primaryPurple,
                borderRadius: BorderRadius.circular(12),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: [
                Tab(
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  text: strings.restorationTabDsp,
                ),
                Tab(
                  icon: const Icon(Icons.compare_arrows, size: 18),
                  text: strings.restorationTabCompare,
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDspRestorationTab(strings),
                _buildCrossComparisonTab(strings),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBetaBanner(dynamic strings) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.amberGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.amberGold.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.amberGold.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.amberGold, width: 1),
            ),
            child: const Text('BETA', style: TextStyle(color: AppTheme.amberGold, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.restorationLabTitle,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  strings.restorationLabDesc,
                  style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDspRestorationTab(dynamic strings) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 900;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? const Color(0xFF2E2B48) : const Color(0xFFE4DFEE);

    if (!isDesktop) {
      return Column(
        children: [
          _buildSearchAndUploadBar(strings),
          Expanded(
            child: _buildTracksList(
              (item) => _showDspModalSheet(item, strings),
              strings,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 380,
          child: Column(
            children: [
              _buildSearchAndUploadBar(strings),
              Expanded(
                child: _buildTracksList(
                  (item) {
                    setState(() {
                      if (_selectedItem?.id != item.id) {
                        _restoreResult = null;
                        _restoreError = null;
                        _isRestoring = false;
                      }
                      _selectedItem = item;
                    });
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
                      Icon(Icons.auto_fix_high, size: 64, color: AppTheme.amberGold.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      Text(strings.restorationEmptyTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text(strings.restorationEmptySubtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                )
              : _buildDspDetailWorkspace(_selectedItem!, strings),
        ),
      ],
    );
  }

  Widget _buildSearchAndUploadBar(dynamic strings) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (_) => _reloadItems(),
              decoration: InputDecoration(
                hintText: strings.searchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            icon: const Icon(Icons.upload_file, size: 20),
            tooltip: strings.restorationUploadVintageBtn,
            onPressed: _uploadAndRestoreFile,
          ),
        ],
      ),
    );
  }

  Widget _buildTracksList(void Function(HeritageItem) onSelect, dynamic strings) {
    return FutureBuilder<List<HeritageItem>>(
      future: _itemsFuture,
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
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isSel ? AppTheme.amberGold.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: isSel ? Border.all(color: AppTheme.amberGold, width: 1.2) : null,
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: Text(it.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                subtitle: Text(
                  [it.type, it.artist].where((s) => s.isNotEmpty).join(' • '),
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                trailing: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    side: const BorderSide(color: AppTheme.amberGold),
                  ),
                  icon: const Icon(Icons.auto_fix_high, size: 14, color: AppTheme.amberGold),
                  label: Text(strings.restoreActionBtn, style: const TextStyle(fontSize: 11, color: AppTheme.amberGold)),
                  onPressed: () {
                    onSelect(it);
                    _runDspRestoration(it);
                  },
                ),
                onTap: () => onSelect(it),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDspDetailWorkspace(HeritageItem item, dynamic strings) {
    final dio = context.read<ServerConfig>().api.dio;
    final originalUrl = HeritageApi(dio).audioUrl(item.id);

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 40),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (item.type.isNotEmpty) Chip(label: Text(item.type, style: const TextStyle(fontSize: 11.5))),
                      if (item.artist.isNotEmpty) Chip(label: Text(item.artist, style: const TextStyle(fontSize: 11.5))),
                      if (item.tonal.isNotEmpty) Chip(label: Text(item.tonal, style: const TextStyle(fontSize: 11.5))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text('So sánh Đối chứng A/B (Trước & Sau phục dựng)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.history, size: 18, color: AppTheme.amberGold),
                    const SizedBox(width: 8),
                    Text(strings.restorationBeforeLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 10),
                AudioPlayerBar(url: originalUrl, label: strings.originalAudio),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_fix_high, size: 18, color: AppTheme.emeraldGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(strings.restorationAfterLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    if (_restoreResult != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('DSP Done', style: TextStyle(color: AppTheme.emeraldGreen, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_isRestoring)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(strings.processing),
                        ],
                      ),
                    ),
                  )
                else if (_restoreResult != null) ...[
                  AudioPlayerBar(
                    url: RestorationApi(dio).restoredUrl(_restoreResult!.sha),
                    label: strings.restoredAudio,
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.auto_fix_high, size: 18),
                        label: Text(strings.restorationRunBtn),
                        onPressed: () => _runDspRestoration(item),
                      ),
                    ),
                  ),
                ],
                if (_restoreError != null) ...[
                  const SizedBox(height: 8),
                  Text(_restoreError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
        if (_restoreResult != null) ...[
          const SizedBox(height: 18),
          Text(strings.restorationMetricsTitle, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _metricRow(strings.restorationDcRemoved, _restoreResult!.dcRemoved.toStringAsFixed(4)),
                  const Divider(height: 16),
                  _metricRow(strings.restorationClicksFixed, '${_restoreResult!.clicksFixed} clicks'),
                  const Divider(height: 16),
                  _metricRow(strings.restorationPeakChange, '${_restoreResult!.peakBefore.toStringAsFixed(2)} -> ${_restoreResult!.peakAfter.toStringAsFixed(2)}'),
                  const Divider(height: 16),
                  _metricRow(strings.restorationNoiseFloor, '${_restoreResult!.noiseFloorDb.toStringAsFixed(1)} dB'),
                  const Divider(height: 16),
                  _metricRow('Sample Rate', '${_restoreResult!.sampleRate} Hz'),
                  const Divider(height: 16),
                  _metricRow('Algorithm', strings.restorationAlgorithm),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(strings.restorationRunBtn),
              onPressed: () => _runDspRestoration(item),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file, size: 18),
              label: Text(strings.restorationUploadVintageBtn),
              onPressed: _uploadAndRestoreFile,
            ),
          ],
        ),
      ],
    );
  }

  Widget _showDspModalSheet(HeritageItem item, dynamic strings) {
    setState(() => _selectedItem = item);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: _buildDspDetailWorkspace(item, strings),
      ),
    );
    return const SizedBox.shrink();
  }

  Widget _buildCrossComparisonTab(dynamic strings) {
    final dio = context.read<ServerConfig>().api.dio;
    final heritageApi = HeritageApi(dio);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primaryPurple.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primaryPurple.withValues(alpha: 0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.compare_arrows, color: AppTheme.primaryPurpleLight, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings.isVi
                      ? 'Đối chiếu bản thu âm cổ chưa rõ nguồn gốc với cơ sở dữ liệu làn điệu Ca Huế và Nhã nhạc cung đình để tìm ra tên bài và kiểm định âm luật.'
                      : 'Cross-compare vintage recordings against Hue heritage database to identify song names and verify musical scales.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final cardA = Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified, size: 18, color: AppTheme.emeraldGreen),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(strings.comparePickSample, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    InputDecorator(
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<HeritageItem>(
                          value: _compareSampleItem,
                          isDense: true,
                          isExpanded: true,
                          items: [
                            for (final t in _allTracks)
                              DropdownMenuItem(
                                value: t,
                                child: Text('${t.title} (${t.artist.isNotEmpty ? t.artist : t.type})', maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _compareSampleItem = val;
                              _compareResult = null;
                            });
                          },
                        ),
                      ),
                    ),
                    if (_compareSampleItem != null) ...[
                      const SizedBox(height: 12),
                      AudioPlayerBar(url: heritageApi.audioUrl(_compareSampleItem!.id), label: _compareSampleItem!.title),
                    ],
                  ],
                ),
              ),
            );

            final cardB = Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.help_outline, size: 18, color: AppTheme.amberGold),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(strings.comparePickTarget, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_uploadedTargetBytes != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.amberGold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.audio_file, size: 20, color: AppTheme.amberGold),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_uploadedTargetName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () => setState(() {
                                _uploadedTargetBytes = null;
                                _uploadedTargetName = '';
                                _compareResult = null;
                              }),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      AudioPlayerBar(bytes: _uploadedTargetBytes!, label: _uploadedTargetName),
                    ] else ...[
                      InputDecorator(
                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<HeritageItem>(
                            value: _compareTargetItem,
                            isDense: true,
                            isExpanded: true,
                            items: [
                              for (final t in _allTracks)
                                DropdownMenuItem(
                                  value: t,
                                  child: Text('${t.title} (${t.artist.isNotEmpty ? t.artist : t.type})', maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _compareTargetItem = val;
                                _compareResult = null;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.upload_file, size: 16),
                        label: Text(strings.compareUploadPrompt),
                        onPressed: _pickTargetAudioForComparison,
                      ),
                      if (_compareTargetItem != null) ...[
                        const SizedBox(height: 10),
                        AudioPlayerBar(url: heritageApi.audioUrl(_compareTargetItem!.id), label: _compareTargetItem!.title),
                      ],
                    ],
                  ],
                ),
              ),
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cardA),
                  const SizedBox(width: 16),
                  Expanded(child: cardB),
                ],
              );
            }
            return Column(
              children: [
                cardA,
                const SizedBox(height: 12),
                cardB,
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
            icon: _isComparing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.compare_arrows, size: 20),
            label: Text(strings.compareRunBtn, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            onPressed: _isComparing ? null : _runCrossComparison,
          ),
        ),
        if (_compareError != null) ...[
          const SizedBox(height: 12),
          Center(child: Text(_compareError!, style: const TextStyle(color: Colors.red))),
        ],
        if (_compareResult != null) ...[
          const SizedBox(height: 24),
          _buildComparisonResults(_compareResult!, strings),
        ],
      ],
    );
  }

  Widget _buildComparisonResults(CompareResult r, dynamic strings) {
    final score = r.metrics.score;
    final matchVerdict = score >= 80
        ? (strings.isVi ? 'Trùng khớp điệu thức cao' : 'High Match')
        : score >= 50
            ? (strings.isVi ? 'Tương đồng một phần điệu thức' : 'Moderate Match')
            : (strings.isVi ? 'Khác làn điệu hoặc chênh lệch âm giai' : 'Different Tune');

    final color = score >= 80 ? AppTheme.emeraldGreen : (score >= 50 ? AppTheme.amberGold : Colors.orange);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.isVi ? 'Kết quả Nhận diện & Đối chiếu' : 'Identification & Match Results', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      '${score.toStringAsFixed(0)}%',
                      style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${strings.compareIdentifiedMatch}: ${_compareSampleItem?.title ?? ""}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Nhận định: $matchVerdict',
                        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sai số cao độ: ${r.metrics.meanAbsCents.toStringAsFixed(1)} cents · Lệch thời gian: ${r.metrics.meanOffsetMs.toStringAsFixed(0)} ms',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(strings.compareContourTitle, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CompareChart(
              times: r.times,
              sampleF0: r.sampleF0,
              warpedF0: r.warpedF0,
              sampleLabel: strings.isVi ? 'Bản ghi mẫu (Dataset)' : 'Sample track',
              targetLabel: strings.isVi ? 'Bản ghi đối chiếu' : 'Comparison track',
            ),
          ),
        ),
      ],
    );
  }

  Widget _metricRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
        ),
        Expanded(
          flex: 3,
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ],
    );
  }
}
