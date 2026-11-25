import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/heritage_api.dart';
import '../../api/endpoints/restoration_api.dart';
import '../../api/endpoints/sing_api.dart';
import '../../core/constants/app_constants.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../models/compare_result.dart';
import '../../models/heritage_item.dart';
import '../../models/restore_result.dart';
import '../../services/history_service.dart';
import '../../services/locale_provider.dart';
import '../../services/connectivity_guard.dart';
import '../../services/server_config.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_panel.dart';
import '../../widgets/compare_chart.dart';
import '../../widgets/heritage_motif.dart';
import '../../widgets/hue_button.dart';
import '../../widgets/hue_icons.dart';
import '../../widgets/result_card.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/staggered_entrance.dart';

class RestorationScreen extends StatefulWidget {
  const RestorationScreen({super.key});

  @override
  State<RestorationScreen> createState() => _RestorationScreenState();
}

class _RestorationScreenState extends State<RestorationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();
  Future<List<HeritageItem>>? _itemsFuture;
  int _itemsEpoch = 0;
  List<HeritageItem> _compareTracks = [];

  HeritageItem? _selectedItem;
  RestoreResult? _restoreResult;
  String? _restoringItemId;
  bool _uploading = false;
  bool _pickingUpload = false;
  bool _pickingCompare = false;
  String? _restoreError;

  String? _compareSampleId;
  String? _compareTargetId;
  Uint8List? _uploadedTargetBytes;
  String _uploadedTargetName = '';
  CompareResult? _compareResult;
  bool _isComparing = false;
  int _compareEpoch = 0;
  String _comparedSampleTitle = '';
  String _comparedTargetTitle = '';
  String? _compareError;
  final ValueNotifier<bool> _abPause = ValueNotifier(false);
  final ValueNotifier<int> _abPlaySignal = ValueNotifier(0);
  StateSetter? _sheetRefresh;

  bool get _isRestoring => _restoringItemId != null;

  HeritageItem? get _compareSampleItem {
    final id = _compareSampleId;
    if (id == null) return null;
    for (final t in _compareTracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  HeritageItem? get _compareTargetItem {
    final id = _compareTargetId;
    if (id == null) return null;
    for (final t in _compareTracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _itemsFuture = _loadItems('');
  }

  Future<List<HeritageItem>> _loadItems(String q) async {
    final epoch = ++_itemsEpoch;
    final dio = context.read<ServerConfig>().api.dio;
    final list = (await HeritageApi(dio).list(q: q, limit: 200)).items;
    if (mounted && epoch == _itemsEpoch) {
      setState(() {
        if (q.trim().isEmpty || _compareTracks.isEmpty) {
          _compareTracks = list;
        }
        if (_selectedItem == null && list.isNotEmpty) {
          _selectedItem = list.first;
        }
        if (_compareSampleItem == null && _compareTracks.isNotEmpty) {
          _compareSampleId = _compareTracks.first.id;
        }
        if (_compareTargetItem == null && _uploadedTargetBytes == null && _compareTracks.length > 1) {
          _compareTargetId = _compareTracks[1].id;
        }
      });
    }
    return list;
  }

  void _reloadItems() {
    final next = _loadItems(_searchCtrl.text);
    setState(() {
      _itemsFuture = next;
    });
  }

  String _log(HistoryService history, String kind, String title, String status) {
    final id = HistoryService.newId();
    history.add(
      HistoryEntry(
        id: id,
        kind: kind,
        title: title,
        status: status,
        at: DateTime.now(),
      ),
    );
    return id;
  }

  Future<void> _runDspRestoration(HeritageItem item) async {
    if (_isRestoring) return;
    final strings = context.read<LocaleProvider>().strings;
    final history = context.read<HistoryService>();
    final dio = context.read<ServerConfig>().api.dio;
    if (!mounted) return;
    setState(() {
      _restoringItemId = item.id;
      _restoreError = null;
    });
    _sheetRefresh?.call(() {});
    if (!await ConnectivityGuard.instance.isOnline) {
      if (mounted) {
        setState(() {
          _restoringItemId = null;
          _restoreError = strings.offlineMessage;
        });
        _sheetRefresh?.call(() {});
      }
      return;
    }
    final logId = _log(history, 'restore', item.title, 'running');
    try {
      final res = await RestorationApi(dio).restoreItem(item.id);
      await history.updateStatus(logId, 'done');
      if (mounted) {
        setState(() {
          _restoringItemId = null;
          if (_selectedItem?.id == item.id) {
            _restoreResult = res;
          }
        });
        _sheetRefresh?.call(() {});
      }
    } catch (e) {
      await history.updateStatus(logId, 'error');
      if (mounted) {
        setState(() {
          _restoringItemId = null;
          if (_selectedItem?.id == item.id) {
            _restoreError = ApiClient.describe(e);
          }
        });
        _sheetRefresh?.call(() {});
      }
    }
  }

  Future<void> _uploadAndRestoreFile() async {
    if (_uploading || _pickingUpload) return;
    final config = context.read<ServerConfig>();
    final strings = context.read<LocaleProvider>().strings;

    if (!config.hasServer) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.serverNotConfigured)),
      );
      return;
    }
    setState(() => _pickingUpload = true);
    Uint8List? bytes;
    String fileName = '';
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.audio, withData: kIsWeb);
      final file = (picked == null || picked.files.isEmpty) ? null : picked.files.first;
      if (file == null) return;
      fileName = file.name;
      bytes = file.bytes ?? (file.path != null && !kIsWeb ? await File(file.path!).readAsBytes() : null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.describe(e))));
      }
      return;
    } finally {
      if (mounted) {
        setState(() => _pickingUpload = false);
      }
    }
    if (bytes == null || !mounted) return;

    final dio = config.api.dio;
    final history = context.read<HistoryService>();
    final logId = _log(history, 'restore-upload', fileName, 'running');
    setState(() => _uploading = true);

    try {
      final res = await RestorationApi(dio).restoreUpload(bytes: bytes, filename: fileName);
      await history.updateStatus(logId, 'done');
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppTheme.goldReadable(dialogCtx).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(color: AppTheme.goldReadable(dialogCtx)),
                ),
                child: Text('BETA', style: TextStyle(color: AppTheme.goldReadable(dialogCtx), fontSize: AppFontSize.xs, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(res.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.md),
                _buildRestoreMetrics(res, strings),
                const SizedBox(height: AppSpacing.md),
                AudioPlayerBar(url: RestorationApi(dio).restoredUrl(res.sha), label: strings.restoredAudio, dio: dio),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(strings.closeBtn),
            ),
          ],
        ),
      );
    } catch (e) {
      await history.updateStatus(logId, 'error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.describe(e))));
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _pickTargetAudioForComparison() async {
    if (_pickingCompare || _isComparing) return;
    setState(() => _pickingCompare = true);
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.audio, withData: kIsWeb);
      final file = (picked == null || picked.files.isEmpty) ? null : picked.files.first;
      if (file == null) return;
      final bytes = file.bytes ?? (file.path != null && !kIsWeb ? await File(file.path!).readAsBytes() : null);
      if (bytes == null || !mounted) return;

      _compareEpoch++;
      setState(() {
        _uploadedTargetBytes = bytes;
        _uploadedTargetName = file.name;
        _compareTargetId = null;
        _compareResult = null;
        _compareError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _compareError = ApiClient.describe(e));
      }
    } finally {
      if (mounted) {
        setState(() => _pickingCompare = false);
      }
    }
  }

  Future<void> _runCrossComparison() async {
    final sample = _compareSampleItem;
    final target = _compareTargetItem;
    final uploadedBytes = _uploadedTargetBytes;
    final uploadedName = _uploadedTargetName;
    if (sample == null || _isComparing) return;
    final history = context.read<HistoryService>();
    final config = context.read<ServerConfig>();
    final dio = config.api.dio;
    final strings = context.read<LocaleProvider>().strings;

    if (uploadedBytes == null && target == null) {
      setState(() => _compareError = strings.compareNoTarget);
      return;
    }

    final epoch = ++_compareEpoch;
    final targetTitle = uploadedName.isNotEmpty ? uploadedName : (target?.title ?? '');
    setState(() {
      _isComparing = true;
      _compareError = null;
    });

    try {
      final res = await SingApi(dio).compareItems(
        sampleItemId: sample.id,
        userItemId: uploadedBytes == null ? (target?.id ?? '') : '',
        userBytes: uploadedBytes,
      );
      _log(history, 'compare-tune', '${sample.title} vs $targetTitle', 'done');

      if (mounted && epoch == _compareEpoch) {
        setState(() {
          _compareResult = res;
          _comparedSampleTitle = sample.title;
          _comparedTargetTitle = targetTitle;
          _isComparing = false;
        });
      } else if (mounted) {
        setState(() => _isComparing = false);
      }
    } catch (e) {
      _log(history, 'compare-tune', sample.title, 'error');
      if (mounted && epoch == _compareEpoch) {
        setState(() {
          _compareError = _compareErrorText(e, strings);
          _isComparing = false;
        });
      } else if (mounted) {
        setState(() => _isComparing = false);
      }
    }
  }

  bool get _abReady =>
      _compareSampleItem != null && (_uploadedTargetBytes != null || _compareTargetItem != null);

  void _playBothAb() {
    _abPause.value = false;
    _abPlaySignal.value++;
  }

  void _stopBothAb() {
    _abPause.value = true;
  }

  String _compareErrorText(Object e, AppStrings strings) {
    switch (ApiClient.errorCode(e)) {
      case 'too_quiet':
        return strings.practiceErrTooQuiet;
      case 'no_voice':
        return strings.practiceErrNoVoice;
      case 'too_short':
        return strings.practiceErrTooShort;
      case 'reference_invalid':
        return strings.practiceErrRefInvalid;
      default:
        return ApiClient.describe(e);
    }
  }

  @override
  void dispose() {
    _abPause.dispose();
    _abPlaySignal.dispose();
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildBetaBanner(strings),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: ImperialTabBar(
              controller: _tabController,
              tabs: [
                Tab(
                  icon: const HueIcon(HueIcons.autoFixHigh, size: 18),
                  text: strings.restorationTabDsp,
                ),
                Tab(
                  icon: const HueIcon(HueIcons.compareArrows, size: 18),
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
      margin: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppTheme.amberGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppTheme.amberGold.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppTheme.goldReadable(context).withValues(alpha: AppAlpha.selected),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppTheme.goldReadable(context), width: 1),
            ),
            child: Text('BETA', style: TextStyle(color: AppTheme.goldReadable(context), fontWeight: FontWeight.bold, fontSize: AppFontSize.xs)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.restorationLabTitle,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: AppFontSize.lg),
                ),
                const SizedBox(height: 4),
                Text(
                  strings.restorationLabDesc,
                  style: TextStyle(fontSize: AppFontSize.sm, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35),
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
    final isDesktop = width >= AppBreakpoints.desktop;
    final borderColor = Theme.of(context).colorScheme.outline;

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
              ? EmptyState(
                  icon: HueIcons.autoFixHigh,
                  title: strings.restorationEmptyTitle,
                  desc: strings.restorationEmptySubtitle,
                )
              : _buildDspDetailWorkspace(_selectedItem!, strings),
        ),
      ],
    );
  }

  Widget _buildSearchAndUploadBar(dynamic strings) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onSubmitted: (_) => _reloadItems(),
                  decoration: InputDecoration(
                    hintText: strings.searchHint,
                    prefixIcon: const HueIcon(HueIcons.search, size: 20),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filledTonal(
                key: const Key('restoration-upload'),
                icon: const HueIcon(HueIcons.uploadFile, size: 20),
                tooltip: strings.restorationUploadVintageBtn,
                onPressed: (_uploading || _pickingUpload) ? null : _uploadAndRestoreFile,
              ),
            ],
          ),
          if (_uploading) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              strings.restorationUploading,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            LinearProgressIndicator(color: Theme.of(context).colorScheme.primary),
          ],
        ],
      ),
    );
  }

  Widget _buildTracksList(void Function(HeritageItem) onSelect, dynamic strings) {
    return FutureBuilder<List<HeritageItem>>(
      future: _itemsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SkeletonList(itemCount: 7, itemHeight: 68);
        }
        if (snap.hasError) {
          return ErrorPanel(message: '${strings.errorPrefix}: ${ApiClient.describe(snap.error!)}', onRetry: _reloadItems);
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return EmptyState(icon: HueIcons.autoFixHigh, title: strings.noRecordings, ctaLabel: strings.learnRetry, onCta: _reloadItems);
        }
        if (_selectedItem == null && items.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedItem == null && items.isNotEmpty) {
              setState(() => _selectedItem = items.first);
            }
          });
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, i) {
            final it = items[i];
            final isSel = _selectedItem?.id == it.id;
            return StaggeredEntrance(
              index: i,
              maxAnimatedIndex: 11,
              child: Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: isSel ? AppTheme.goldReadable(context).withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: isSel ? Border.all(color: AppTheme.goldReadable(context), width: 1.2) : null,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                title: Text(it.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFontSize.md)),
                subtitle: Text(
                  [it.type, it.artist].where((s) => s.isNotEmpty).join(' • '),
                  style: TextStyle(fontSize: AppFontSize.sm, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                trailing: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.padded,
                    visualDensity: VisualDensity.standard,
                    side: BorderSide(color: AppTheme.goldReadable(context)),
                  ),
                  icon: HueIcon(HueIcons.autoFixHigh, size: 14, color: AppTheme.goldReadable(context)),
                  label: Text(strings.restoreActionBtn, style: TextStyle(fontSize: AppFontSize.xs, color: AppTheme.goldReadable(context))),
                  onPressed: _isRestoring ? null : () {
                    onSelect(it);
                    _runDspRestoration(it);
                  },
                ),
                onTap: () => onSelect(it),
                ),
              ),
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
      padding: const EdgeInsets.fromLTRB(AppSpacing.xxxl, AppSpacing.lg, AppSpacing.xxxl, AppSpacing.xxxl),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: const TextStyle(fontSize: AppFontSize.headline, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (item.type.isNotEmpty) Chip(label: Text(item.type, style: const TextStyle(fontSize: AppFontSize.sm))),
                      if (item.artist.isNotEmpty) Chip(label: Text(item.artist, style: const TextStyle(fontSize: AppFontSize.sm))),
                      if (item.tonal.isNotEmpty) Chip(label: Text(item.tonal, style: const TextStyle(fontSize: AppFontSize.sm))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(strings.restorationCompareAB, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    HueIcon(HueIcons.history, size: 18, color: AppTheme.goldReadable(context)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(strings.restorationBeforeLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AudioPlayerBar(url: originalUrl, label: strings.originalAudio, dio: dio),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    HueIcon(HueIcons.autoFixHigh, size: 18, color: AppTheme.emeraldReadable(context)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(strings.restorationAfterLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    if (_restoreResult != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: AppTheme.emeraldReadable(context).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(strings.restoreDspDone, style: TextStyle(color: AppTheme.emeraldReadable(context), fontSize: AppFontSize.xs, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_restoringItemId == item.id)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
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
                    dio: dio,
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Center(
                      child: FilledButton.icon(
                        icon: const HueIcon(HueIcons.autoFixHigh, size: 18),
                        label: Text(strings.restorationRunBtn),
                        onPressed: _isRestoring ? null : () => _runDspRestoration(item),
                      ),
                    ),
                  ),
                ],
                if (_restoreError != null) ...[
                  const SizedBox(height: 8),
                  ErrorPanel(message: _restoreError!),
                ],
              ],
            ),
          ),
        ),
        if (_restoreResult != null) ...[
          const SizedBox(height: 18),
          _buildRestoreMetrics(_restoreResult!, strings),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: const HueIcon(HueIcons.refresh, size: 18),
              label: Text(strings.restorationRunBtn),
              onPressed: _isRestoring ? null : () => _runDspRestoration(item),
            ),
            OutlinedButton.icon(
              icon: const HueIcon(HueIcons.uploadFile, size: 18),
              label: Text(strings.restorationUploadVintageBtn),
              onPressed: (_uploading || _pickingUpload) ? null : _uploadAndRestoreFile,
            ),
          ],
        ),
      ],
    );
  }

  Widget _showDspModalSheet(HeritageItem item, dynamic strings) {
    setState(() {
      if (_selectedItem?.id != item.id) {
        _restoreResult = null;
        _restoreError = null;
      }
      _selectedItem = item;
    });
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          _sheetRefresh = setSheetState;
          return SizedBox(
            height: MediaQuery.of(sheetCtx).size.height * 0.85,
            child: _buildDspDetailWorkspace(item, strings),
          );
        },
      ),
    ).whenComplete(() => _sheetRefresh = null);
    return const SizedBox.shrink();
  }

  Widget _buildCrossComparisonTab(dynamic strings) {
    final dio = context.read<ServerConfig>().api.dio;
    final heritageApi = HeritageApi(dio);

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xxxl),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HueIcon(HueIcons.compareArrows, color: Theme.of(context).colorScheme.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings.compareTabDescription,
                  style: TextStyle(fontSize: AppFontSize.sm, height: 1.4, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= AppBreakpoints.medium;
            final cardA = Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        HueIcon(HueIcons.verified, size: 18, color: AppTheme.emeraldReadable(context)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(strings.comparePickSample, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFontSize.md)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    InputDecorator(
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _compareSampleItem?.id,
                          isDense: true,
                          isExpanded: true,
                          items: [
                            for (final t in _compareTracks)
                              DropdownMenuItem<String>(
                                value: t.id,
                                child: Text('${t.title} (${t.artist.isNotEmpty ? t.artist : t.type})', maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (val) {
                            _compareEpoch++;
                            setState(() {
                              _compareSampleId = val;
                              _compareResult = null;
                              _compareError = null;
                            });
                          },
                        ),
                      ),
                    ),
                    if (_compareSampleItem != null) ...[
                      const SizedBox(height: 12),
                      AudioPlayerBar(
                        key: ValueKey('ab-a-${_compareSampleItem!.id}'),
                        pauseSignal: _abPause,
                        playSignal: _abPlaySignal,
                        url: heritageApi.audioUrl(_compareSampleItem!.id),
                        label: _compareSampleItem!.title,
                        dio: dio,
                      ),
                    ],
                  ],
                ),
              ),
            );

            final cardB = Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        HueIcon(HueIcons.help, size: 18, color: AppTheme.goldReadable(context)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(strings.comparePickTarget, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFontSize.md)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_uploadedTargetBytes != null) ...[
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppTheme.amberGold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Row(
                          children: [
                            HueIcon(HueIcons.audioFile, size: 20, color: AppTheme.goldReadable(context)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_uploadedTargetName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFontSize.sm))),
                            IconButton(
                              tooltip: strings.clearSelectedFile,
                              icon: const HueIcon(HueIcons.close, size: 16),
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
                      AudioPlayerBar(
                        key: ValueKey('ab-b-file-$_uploadedTargetName'),
                        pauseSignal: _abPause,
                        playSignal: _abPlaySignal,
                        bytes: _uploadedTargetBytes!,
                        label: _uploadedTargetName,
                      ),
                    ] else ...[
                      InputDecorator(
                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _compareTargetItem?.id,
                            isDense: true,
                            isExpanded: true,
                            items: [
                              for (final t in _compareTracks)
                                DropdownMenuItem<String>(
                                  value: t.id,
                                  child: Text('${t.title} (${t.artist.isNotEmpty ? t.artist : t.type})', maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (val) {
                              _compareEpoch++;
                              setState(() {
                                _compareTargetId = val;
                                _compareResult = null;
                                _compareError = null;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        icon: const HueIcon(HueIcons.uploadFile, size: 16),
                        label: Text(strings.compareUploadPrompt),
                        onPressed: (_pickingCompare || _isComparing) ? null : _pickTargetAudioForComparison,
                      ),
                      if (_compareTargetItem != null) ...[
                        const SizedBox(height: 10),
                        AudioPlayerBar(
                          key: ValueKey('ab-b-item-${_compareTargetItem!.id}'),
                          pauseSignal: _abPause,
                          playSignal: _abPlaySignal,
                          url: heritageApi.audioUrl(_compareTargetItem!.id),
                          label: _compareTargetItem!.title,
                          dio: dio,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            );

            final abControls = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                HueButton(
                  label: strings.abPlayBoth,
                  variant: HueButtonVariant.gold,
                  icon: HueIcons.playArrow,
                  onPressed: _abReady ? _playBothAb : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                HueButton(
                  label: strings.abStopBoth,
                  variant: HueButtonVariant.ghost,
                  size: HueButtonSize.small,
                  icon: HueIcons.stop,
                  onPressed: _stopBothAb,
                ),
              ],
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: cardA),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: abControls,
                  ),
                  Expanded(child: cardB),
                ],
              );
            }
            return Column(
              children: [
                cardA,
                const SizedBox(height: AppSpacing.md),
                abControls,
                const SizedBox(height: AppSpacing.md),
                cardB,
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl, vertical: AppSpacing.lg)),
            icon: _isComparing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  )
                : const HueIcon(HueIcons.compareArrows, size: 20),
            label: Text(strings.compareRunBtn, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFontSize.lg)),
            onPressed: _isComparing ? null : _runCrossComparison,
          ),
        ),
        if (_compareError != null) ...[
          const SizedBox(height: 12),
          ErrorPanel(message: _compareError!)
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
        ? strings.compareVerdictHigh
        : score >= 50
            ? strings.compareVerdictModerate
            : strings.compareVerdictDifferent;

    final color = score >= 80
        ? AppTheme.emeraldReadable(context)
        : (score >= 50
            ? AppTheme.goldReadable(context)
            : AppTheme.statusReadable(context, AppStatusKind.danger));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.compareResultsTitle, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      '${score.toStringAsFixed(0)}%',
                      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: AppFontSize.heading),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${strings.compareIdentifiedMatch}: ${_comparedSampleTitle.isNotEmpty ? _comparedSampleTitle : (_compareSampleItem?.title ?? "")}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFontSize.title),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strings.compareVerdictLine(matchVerdict),
                        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: AppFontSize.md),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strings.compareMetricsLine(r.metrics.meanAbsCents.toStringAsFixed(1), r.metrics.meanOffsetMs.toStringAsFixed(0)),
                        style: TextStyle(fontSize: AppFontSize.sm, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: CompareChart(
              times: r.times,
              sampleF0: r.sampleF0,
              warpedF0: r.warpedF0,
              sampleLabel: _comparedSampleTitle.isNotEmpty ? _comparedSampleTitle : strings.compareChartSampleDataset,
              targetLabel: _comparedTargetTitle.isNotEmpty ? _comparedTargetTitle : strings.compareChartTarget,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRestoreMetrics(RestoreResult res, AppStrings strings) {
    return ResultSummaryCard(
      title: strings.restorationMetricsTitle,
      status: AppStatusKind.success,
      statusLabel: strings.restoreDspDone,
      leadingIcon: HueIcons.healing,
      children: [
        MetricRow(label: strings.restorationDcRemoved, value: res.dcRemoved.toStringAsFixed(4)),
        MetricRow(label: strings.restorationClicksFixed, value: '${res.clicksFixed} ${strings.restoreClicks}'),
        MetricRow(label: strings.restorationPeakChange, value: '${res.peakBefore.toStringAsFixed(2)} -> ${res.peakAfter.toStringAsFixed(2)}'),
        MetricRow(label: strings.restorationNoiseFloor, value: '${res.noiseFloorDb.toStringAsFixed(1)} dB'),
        MetricRow(label: strings.restoreSampleRate, value: '${res.sampleRate} Hz'),
        MetricRow(label: strings.restoreAlgorithm, value: strings.restorationAlgorithm),
      ],
    );
  }
}
