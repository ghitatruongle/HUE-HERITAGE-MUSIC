import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/heritage_api.dart';
import '../../api/endpoints/music_api.dart';
import '../../core/theme/app_theme.dart';
import 'task_result_card.dart';
import '../../models/heritage_item.dart';
import '../../models/music_task.dart';
import '../../services/history_service.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/common_button.dart';

class CreationScreen extends StatefulWidget {
  final int initialTabIndex;

  const CreationScreen({super.key, this.initialTabIndex = 0});

  @override
  State<CreationScreen> createState() => _CreationScreenState();
}

class _CreationScreenState extends State<CreationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<HeritageItem> _tunes = [];
  HeritageItem? _selectedTune;
  bool _loadingTunes = true;

  List<LoraAdapter> _loras = [];
  String _selectedLora = '';

  bool _showOrnaments = true;
  bool _showMasterPlayer = false;

  final TextEditingController _customLyricsCtrl = TextEditingController();
  String _vocalTab2 = 'Nữ';
  String _tempoTab2 = 'Vừa';
  String _moodTab2 = 'Trữ tình';
  int _durationTab2 = 60;
  double _strengthTab2 = 0.8;

  String _vocalTab1 = 'Nữ';
  String _tempoTab1 = 'Vừa';
  int _durationTab1 = 60;
  double _strengthTab1 = 0.8;

  bool _busyTab1 = false;
  bool _busyTab2 = false;
  bool _polling = false;

  MusicTask? _taskTab1;
  MusicTask? _taskTab2;
  String? _errorTab1;
  String? _errorTab2;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final dio = context.read<ServerConfig>().api.dio;
    final musicApi = MusicApi(dio);

    try {
      final models = await musicApi.models();
      final seenLora = <String>{};
      final uniqueLoras = models.where((l) => seenLora.add(l.name)).toList();
      if (mounted) {
        setState(() => _loras = uniqueLoras);
      }
    } catch (_) {}

    try {
      List<HeritageItem> items = [];
      try {
        items = await musicApi.getHeritageTunes();
      } catch (_) {
        items = (await HeritageApi(dio).list(limit: 200)).items;
      }

      final seenTune = <String>{};
      final uniqueTunes = items.where((it) => seenTune.add(it.id)).toList();

      if (mounted) {
        setState(() {
          _tunes = uniqueTunes;
          if (uniqueTunes.isNotEmpty) {
            _selectedTune = uniqueTunes.first;
          }
          _loadingTunes = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingTunes = false);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customLyricsCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSingOriginal() async {
    if (_selectedTune == null) return;
    setState(() {
      _busyTab1 = true;
      _errorTab1 = null;
      _taskTab1 = null;
    });

    final dio = context.read<ServerConfig>().api.dio;
    final history = context.read<HistoryService>();
    final strings = context.read<LocaleProvider>().strings;

    try {
      final task = await MusicApi(dio).singOriginal(
        heritageId: _selectedTune!.id,
        vocal: _vocalTab1,
        tempo: _tempoTab1,
        lora: _selectedLora,
        strength: _strengthTab1,
        duration: _durationTab1,
      );

      history.add(
        HistoryEntry(
          id: task.id,
          kind: 'sing_original',
          title: strings.historySingOriginal(_selectedTune!.title),
          status: task.status,
          at: DateTime.now(),
        ),
      );

      if (mounted) {
        setState(() => _taskTab1 = task);
        if (task.status == 'running' || task.status == 'pending' || task.status == 'queued') {
          unawaited(_watchTask(task.id, isTab1: true, durationSeconds: _durationTab1));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorTab1 = ApiClient.describe(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busyTab1 = false);
      }
    }
  }

  Future<void> _runSingNewLyrics() async {
    if (_selectedTune == null) return;
    final strings = context.read<LocaleProvider>().strings;
    final lyrics = _customLyricsCtrl.text.trim();
    if (lyrics.isEmpty) {
      setState(() => _errorTab2 = strings.creationLyricsRequired);
      return;
    }

    setState(() {
      _busyTab2 = true;
      _errorTab2 = null;
      _taskTab2 = null;
    });

    final dio = context.read<ServerConfig>().api.dio;
    final history = context.read<HistoryService>();

    try {
      final task = await MusicApi(dio).singNewLyrics(
        heritageId: _selectedTune!.id,
        newLyrics: lyrics,
        vocal: _vocalTab2,
        tempo: _tempoTab2,
        mood: _moodTab2,
        lora: _selectedLora,
        strength: _strengthTab2,
        duration: _durationTab2,
      );

      history.add(
        HistoryEntry(
          id: task.id,
          kind: 'sing_new_lyrics',
          title: strings.historySingNew(_selectedTune!.title),
          status: task.status,
          at: DateTime.now(),
        ),
      );

      if (mounted) {
        setState(() => _taskTab2 = task);
        if (task.status == 'running' || task.status == 'pending' || task.status == 'queued') {
          unawaited(_watchTask(task.id, isTab1: false, durationSeconds: _durationTab2));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorTab2 = ApiClient.describe(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busyTab2 = false);
      }
    }
  }

  Future<void> _watchTask(String id, {required bool isTab1, required int durationSeconds}) async {
    void apply(MusicTask t) {
      if (!mounted) return;
      setState(() {
        if (isTab1) {
          _taskTab1 = t;
        } else {
          _taskTab2 = t;
        }
      });
    }

    if (!kIsWeb) {
      var reachedTerminal = false;
      try {
        final dio = context.read<ServerConfig>().api.dio;
        final history = context.read<HistoryService>();
        if (mounted) {
          setState(() => _polling = true);
        }
        final done = Completer<void>();
        final sub = MusicApi(dio).taskEvents(id).listen(
          (t) {
            apply(t);
            if (t.status != 'running' && t.status != 'pending' && t.status != 'queued') {
              history.updateStatus(id, t.status);
              reachedTerminal = true;
              if (!done.isCompleted) done.complete();
            }
          },
          onError: (_) {
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
        );
        await done.future.timeout(
          Duration(seconds: 150 + durationSeconds * 3),
          onTimeout: () {},
        );
        await sub.cancel();
        if (reachedTerminal) {
          if (mounted) {
            setState(() => _polling = false);
          }
          return;
        }
      } catch (_) {}
    }
    await _pollTask(id, isTab1: isTab1, durationSeconds: durationSeconds);
  }

  Future<void> _pollTask(String id, {required bool isTab1, required int durationSeconds}) async {
    setState(() => _polling = true);
    final dio = context.read<ServerConfig>().api.dio;
    final history = context.read<HistoryService>();
    final deadline = DateTime.now().add(Duration(seconds: 150 + durationSeconds * 3));
    var consecutiveFailures = 0;

    while (mounted && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      try {
        final t = await MusicApi(dio).task(id);
        consecutiveFailures = 0;
        if (mounted) {
          setState(() {
            if (isTab1) {
              _taskTab1 = t;
            } else {
              _taskTab2 = t;
            }
          });
        }
        if (t.status != 'running' && t.status != 'pending' && t.status != 'queued') {
          await history.updateStatus(id, t.status);
          break;
        }
      } catch (_) {
        consecutiveFailures++;
        if (consecutiveFailures >= 5) {
          if (mounted) {
            setState(() {
              final msg = context.read<LocaleProvider>().strings.creationPollLost(consecutiveFailures);
              if (isTab1) {
                _errorTab1 = msg;
              } else {
                _errorTab2 = msg;
              }
            });
          }
          break;
        }
      }
    }

    if (mounted) {
      setState(() => _polling = false);
    }
  }

  Future<void> _cancelTask(String id) async {
    final dio = context.read<ServerConfig>().api.dio;
    final history = context.read<HistoryService>();
    try {
      final t = await MusicApi(dio).cancelTask(id);
      await history.updateStatus(id, t.status);
      if (mounted) {
        setState(() {
          if (_taskTab1?.id == id) _taskTab1 = t;
          if (_taskTab2?.id == id) _taskTab2 = t;
        });
      }
    } catch (_) {}
  }

  void _applySampleVerse(String text) {
    _customLyricsCtrl.text = text;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeaderBanner(context),
            _buildTabBar(context),
            Expanded(
              child: _loadingTunes
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTabOriginal(context),
                        _buildTabNewLyrics(context),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBanner(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.deepPurple.withAlpha(220),
            AppTheme.primaryPurple.withAlpha(180),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: const Border(
          bottom: BorderSide(color: Color(0x33D4AF37), width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.imperialGold.withAlpha(40),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.imperialGold, width: 1.2),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: AppTheme.imperialGold,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.navCreation,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  strings.creationBannerSubtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withAlpha(200),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    return Container(
      color: AppTheme.darkSurfaceVariant,
      child: TabBar(
        controller: _tabController,
        indicatorColor: AppTheme.imperialGold,
        indicatorWeight: 3,
        labelColor: AppTheme.imperialGold,
        unselectedLabelColor: Colors.white60,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
        tabs: [
          Tab(
            icon: const Icon(Icons.menu_book_rounded, size: 19),
            text: strings.creationTabOriginal,
          ),
          Tab(
            icon: const Icon(Icons.draw_rounded, size: 19),
            text: strings.creationTabNewLyrics,
          ),
        ],
      ),
    );
  }

  Widget _buildTabOriginal(BuildContext context) {
    if (_tunes.isEmpty) {
      return _buildEmptyTunesState();
    }
    final item = _selectedTune;
    final server = context.read<ServerConfig>();

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildTuneSelector(),
        const SizedBox(height: 14),
        if (item != null) ...[
          _buildMusicologyCard(item),
          const SizedBox(height: 14),
          _buildMasterLyricsCard(item),
          const SizedBox(height: 14),
          _buildMasterPlaybackControls(item, server),
          const SizedBox(height: 14),
          _buildAiRecreationControls(),
          if (_taskTab1 != null) ...[
            const SizedBox(height: 14),
            TaskResultCard(task: _taskTab1!, polling: _polling, onCancel: _cancelTask),
          ],
        ],
      ],
    );
  }

  Widget _buildTabNewLyrics(BuildContext context) {
    if (_tunes.isEmpty) {
      return _buildEmptyTunesState();
    }
    final item = _selectedTune;
    final strings = context.watch<LocaleProvider>().strings;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildLockedMelodyBanner(),
        const SizedBox(height: 14),
        _buildTuneSelector(),
        const SizedBox(height: 14),
        if (item != null) ...[
          _buildPoeticRhymeAssistant(item),
          const SizedBox(height: 14),
          _buildLyricComposer(),
          const SizedBox(height: 14),
          _buildVocalAndStyleControlsTab2(),
          const SizedBox(height: 14),
          CommonButton(
            label: strings.creationRunNewLyricsBtn,
            loading: _busyTab2,
            onPressed: _runSingNewLyrics,
          ),
          if (_errorTab2 != null) ...[
            const SizedBox(height: 8),
            Text(_errorTab2!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          if (_taskTab2 != null) ...[
            const SizedBox(height: 14),
            TaskResultCard(task: _taskTab2!, polling: _polling, onCancel: _cancelTask),
          ],
        ],
      ],
    );
  }

  Widget _buildTuneSelector() {
    final strings = context.watch<LocaleProvider>().strings;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.library_music_rounded, size: 16, color: AppTheme.imperialGold),
              const SizedBox(width: 6),
              Text(
                strings.creationPickTuneLabel,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey(_selectedTune?.id),
            initialValue: _selectedTune?.id,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.darkBorder),
              ),
            ),
            items: [
              for (final tune in _tunes)
                DropdownMenuItem(
                  value: tune.id,
                  child: Text(
                    '${tune.title} (${tune.modeSystem.isNotEmpty ? tune.modeSystem.split("(")[0].trim() : tune.genre})',
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) {
              if (id == null) return;
              setState(() {
                _selectedTune = _tunes.firstWhere((t) => t.id == id);
                _showMasterPlayer = false;
                _taskTab1 = null;
                _taskTab2 = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMusicologyCard(HeritageItem item) {
    final strings = context.watch<LocaleProvider>().strings;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x33D4AF37)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.imperialGold.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.imperialGold.withAlpha(120)),
                ),
                child: Text(
                  item.type,
                  style: const TextStyle(
                    color: AppTheme.imperialGold,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (item.bpm != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${item.bpm!.toStringAsFixed(0)} BPM',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              const Spacer(),
              Text(
                item.artist.isNotEmpty ? item.artist : strings.creationFolkArtist,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          _infoRow(
            Icons.music_note_rounded,
            strings.creationModeLabel,
            item.modeSystem.isNotEmpty ? item.modeSystem : item.tonal,
            accentColor: AppTheme.amberGold,
          ),
          if (item.verseStructure.isNotEmpty) ...[
            const SizedBox(height: 6),
            _infoRow(
              Icons.format_quote_rounded,
              strings.creationVerseLabel,
              item.verseStructure,
            ),
          ],
          if (item.instruments.isNotEmpty) ...[
            const SizedBox(height: 6),
            _infoRow(
              Icons.piano_rounded,
              strings.creationInstrumentsLabel,
              item.instruments,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMasterLyricsCard(HeritageItem item) {
    final strings = context.watch<LocaleProvider>().strings;
    final hasOrnaments = item.lyricsWithOrnaments.isNotEmpty;
    final displayLyrics = _showOrnaments && hasOrnaments
        ? item.lyricsWithOrnaments
        : item.lyrics;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkSurfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                strings.creationLyricsTitle,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (hasOrnaments)
                GestureDetector(
                  onTap: () => setState(() => _showOrnaments = !_showOrnaments),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _showOrnaments
                          ? AppTheme.primaryPurple.withAlpha(120)
                          : Colors.white10,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _showOrnaments
                            ? AppTheme.primaryPurpleLight
                            : Colors.white24,
                      ),
                    ),
                    child: Text(
                      _showOrnaments ? strings.creationModeOrnamented : strings.creationModePlain,
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.darkBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              displayLyrics.isNotEmpty ? displayLyrics : strings.creationNoLyrics,
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Color(0xFFE2DCED),
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterPlaybackControls(HeritageItem item, ServerConfig server) {
    final strings = context.watch<LocaleProvider>().strings;
    final audioUrl = '${server.baseUrl}/api/heritage/${item.id}/audio';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(
                    _showMasterPlayer ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    color: AppTheme.imperialGold,
                  ),
                  label: Text(
                    _showMasterPlayer ? strings.creationCollapseMaster : strings.creationListenMaster,
                    style: const TextStyle(color: AppTheme.imperialGold, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.imperialGold),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () => setState(() => _showMasterPlayer = !_showMasterPlayer),
                ),
              ),
            ],
          ),
          if (_showMasterPlayer) ...[
            const SizedBox(height: 10),
            AudioPlayerBar(
              key: Key(audioUrl),
              url: audioUrl,
              label: strings.creationOriginalTrack(item.title),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAiRecreationControls() {
    final strings = context.watch<LocaleProvider>().strings;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.creationAiRecreateTitle,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _dropdownField(strings.creationVocalLabel, _vocalTab1, ['Nữ', 'Nam', 'Không lời'], (v) {
                  setState(() => _vocalTab1 = v);
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dropdownField(strings.creationTempoLabel, _tempoTab1, ['Chậm', 'Vừa', 'Nhanh'], (v) {
                  setState(() => _tempoTab1 = v);
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _dropdownField(strings.creationDurationLabel, '$_durationTab1', ['30', '60', '90', '120'], (v) {
                  setState(() => _durationTab1 = int.parse(v));
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dropdownField('LoRA strength', _strengthTab1.toStringAsFixed(1), ['0.4', '0.6', '0.8', '1.0'], (v) {
                  setState(() => _strengthTab1 = double.parse(v));
                }),
              ),
            ],
          ),
          if (_loras.isNotEmpty) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey('tab1-lora-$_selectedLora'),
              initialValue: _selectedLora.isEmpty ? '' : _selectedLora,
              isDense: true,
              decoration: InputDecoration(
                labelText: strings.creationLoraModelLabel,
                labelStyle: const TextStyle(fontSize: 12),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: [
                DropdownMenuItem(value: '', child: Text(strings.creationLoraBaseDefault)),
                for (final l in _loras)
                  DropdownMenuItem(value: l.name, child: Text(l.name)),
              ],
              onChanged: (v) => setState(() => _selectedLora = v ?? ''),
            ),
          ],
          const SizedBox(height: 12),
          CommonButton(
            label: strings.creationRunOriginalBtn,
            loading: _busyTab1,
            onPressed: _runSingOriginal,
          ),
          if (_errorTab1 != null) ...[
            const SizedBox(height: 8),
            Text(_errorTab1!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Widget _buildLockedMelodyBanner() {
    final strings = context.watch<LocaleProvider>().strings;
    final title = _selectedTune?.title ?? strings.creationFallbackTuneTitle;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D163D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.imperialGold.withAlpha(160)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_rounded, size: 18, color: AppTheme.imperialGold),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  strings.creationLockedMelody(title),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.imperialGold,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            strings.creationLockedMelodyDesc,
            style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildPoeticRhymeAssistant(HeritageItem item) {
    final strings = context.watch<LocaleProvider>().strings;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline_rounded, size: 16, color: AppTheme.amberGold),
              const SizedBox(width: 6),
              Text(
                strings.creationRhymeGuideTitle,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.rhymeGuide.isNotEmpty
                ? item.rhymeGuide
                : strings.creationRhymeGuideDefault(item.bpm?.toStringAsFixed(0)),
            style: const TextStyle(fontSize: 12.5, color: Color(0xFFD1D5DB), height: 1.4),
          ),
          const SizedBox(height: 10),
          Text(
            strings.creationSampleVerseTitle,
            style: const TextStyle(fontSize: 11.5, color: Colors.white60),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _sampleButton(
                strings.creationSampleLucBat,
                'Sông Hương sóng vỗ êm đềm,\nThuyền ai thấp thoáng qua rèm trăng thanh.\nDịu dàng tà áo nghiêng vành,\nNón bài thơ thắm nghĩa tình trăm năm.',
              ),
              _sampleButton(
                strings.creationSampleFourWord,
                'Nắng trải cố đô,\nGió lay nhành liễu.\nTiếng đàn ngân vang,\nGợi bao thương nhớ.',
              ),
              _sampleButton(
                strings.creationSampleTuTinh,
                'Chiều chiều trước bến Văn Lâu,\nAi ngồi ai câu ai sầu ai thảm.\nAi thương ai cảm ai nhớ ai trông,\nThuyền ai thấp thoáng bên sông hữu tình.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sampleButton(String label, String text) {
    return InkWell(
      onTap: () => _applySampleVerse(text),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.primaryPurple.withAlpha(60),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.primaryPurpleLight.withAlpha(120)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_circle_outline, size: 13, color: AppTheme.primaryPurpleLight),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(fontSize: 11.5, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLyricComposer() {
    final strings = context.watch<LocaleProvider>().strings;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                strings.creationComposeTitle,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                strings.creationWordCount(_customLyricsCtrl.text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length),
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _customLyricsCtrl,
            maxLines: 5,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 13.5, height: 1.5),
            decoration: InputDecoration(
              hintText: strings.creationLyricsHint,
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 12.5),
              filled: true,
              fillColor: AppTheme.darkBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.darkBorder),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVocalAndStyleControlsTab2() {
    final strings = context.watch<LocaleProvider>().strings;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _dropdownField(strings.creationVocalLabel, _vocalTab2, ['Nữ', 'Nam'], (v) {
                  setState(() => _vocalTab2 = v);
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dropdownField(strings.creationMoodLabel, _moodTab2, ['Trữ tình', 'Thiết tha', 'Tươi vui', 'Hào sảng'], (v) {
                  setState(() => _moodTab2 = v);
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _dropdownField(strings.creationTempoLabel, _tempoTab2, ['Chậm', 'Vừa', 'Nhanh'], (v) {
                  setState(() => _tempoTab2 = v);
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dropdownField(strings.creationDurationLabel, '$_durationTab2', ['30', '60', '90', '120'], (v) {
                  setState(() => _durationTab2 = int.parse(v));
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _dropdownField('LoRA strength', _strengthTab2.toStringAsFixed(1), ['0.4', '0.6', '0.8', '1.0'], (v) {
                  setState(() => _strengthTab2 = double.parse(v));
                }),
              ),
              if (_loras.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('tab2-lora-$_selectedLora'),
                    initialValue: _selectedLora.isEmpty ? '' : _selectedLora,
                    isDense: true,
                    decoration: InputDecoration(
                      labelText: strings.creationLoraModelLabel,
                      labelStyle: const TextStyle(fontSize: 12),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: [
                      DropdownMenuItem(value: '', child: Text(strings.creationDefault)),
                      for (final l in _loras)
                        DropdownMenuItem(value: l.name, child: Text(l.name)),
                    ],
                    onChanged: (v) => setState(() => _selectedLora = v ?? ''),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {Color? accentColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: accentColor ?? Colors.white54),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white70),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              color: accentColor ?? Colors.white,
              fontWeight: accentColor != null ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdownField(String label, String value, List<String> items, ValueChanged<String> onChanged) {
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isDense: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: [
        for (final item in items)
          DropdownMenuItem(
            value: item,
            child: Text(item, style: const TextStyle(fontSize: 12.5)),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _buildEmptyTunesState() {
    final strings = context.watch<LocaleProvider>().strings;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off_rounded, size: 48, color: Colors.white38),
            const SizedBox(height: 12),
            Text(
              strings.creationEmptyTunesTitle,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              strings.creationEmptyTunesDesc,
              style: const TextStyle(fontSize: 12.5, color: Colors.white60, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(strings.creationReloadData),
              onPressed: () {
                setState(() => _loadingTunes = true);
                _loadInitialData();
              },
            ),
          ],
        ),
      ),
    );
  }
}
