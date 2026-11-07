import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/sing_api.dart';
import '../../models/pitch_data.dart';
import '../../core/localization/app_strings.dart';
import '../../services/history_service.dart';
import '../../core/theme/app_theme.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';
import '../../services/session_media.dart';
import '../../widgets/common_button.dart';
import '../../widgets/pitch_contour_chart.dart';
import 'lesson_practice_view.dart';

class LearningScreen extends StatefulWidget {
  const LearningScreen({super.key});

  @override
  State<LearningScreen> createState() => _LearningScreenState();
}

class _LearningScreenState extends State<LearningScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  bool _busy = false;
  String? _filePath;
  PitchData? _result;
  String? _error;
  double _progress = 0;
  late AppStrings strings;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (_recording) {
      _recorder.stop().then<void>((_) => _recorder.dispose());
    } else {
      _recorder.dispose();
    }
    super.dispose();
  }

  String _tmpPath() {
    return '${Directory.systemTemp.path}/hue_learn.wav';
  }

  void _log(String kind, String title, String status) {
    context.read<HistoryService>().add(
          HistoryEntry(id: DateTime.now().microsecondsSinceEpoch.toString(), kind: kind, title: title, status: status, at: DateTime.now()),
        );
  }

  Future<void> _toggle() async {
    if (_recording) {
      final p = await _recorder.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _recording = false;
        _filePath = p;
      });
      if (p != null) {
        final media = context.read<SessionMedia>();
        if (kIsWeb) {
          try {
            final bytes = await XFile(p).readAsBytes();
            media.setRecording(bytes: bytes);
          } catch (_) {}
        } else {
          media.setRecording(path: p);
        }
      }
      return;
    }
    final ok = await _recorder.hasPermission();
    if (!mounted) {
      return;
    }
    if (!ok) {
      setState(() => _error = strings.practiceMicDenied);
      return;
    }
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: kIsWeb ? 'hue_learn.wav' : _tmpPath(),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = strings.practiceMicStartFail);
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _recording = true;
      _error = null;
      _result = null;
    });
  }

  Future<void> _analyze() async {
    final path = _filePath;
    if (path == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final api = SingApi(dio);
      final media = context.read<SessionMedia>();
      final data = kIsWeb
          ? await api.analyzePitchBytes(
              media.recordingBytes ?? (await XFile(path).readAsBytes()),
              onProgress: (a, b) {
                if (mounted && b > 0) {
                  setState(() => _progress = a / b);
                }
              },
            )
          : await api.analyzePitch(
              path,
              onProgress: (a, b) {
                if (mounted && b > 0) {
                  setState(() => _progress = a / b);
                }
              },
            );
      if (!mounted) return;
      _log('analyze-pitch', strings.learnAnalyzeBtn, 'done');
      setState(() => _result = data);
    } catch (e) {
      _log('analyze-pitch', strings.learnAnalyzeBtn, 'error');
      if (mounted) {
        setState(() => _error = ApiClient.describe(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _retry() async {
    await _analyze();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    strings = context.watch<LocaleProvider>().strings;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: AppTheme.primaryPurple,
              borderRadius: BorderRadius.circular(12),
            ),
            dividerColor: Colors.transparent,
            labelColor: Colors.white,
            unselectedLabelColor: scheme.onSurfaceVariant,
            tabs: [
              Tab(icon: const Icon(Icons.graphic_eq), text: strings.listenTabTitle),
              Tab(icon: const Icon(Icons.school), text: strings.practiceTabTitle),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPitchTab(scheme),
              const LessonPracticeView(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPitchTab(ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        CommonButton(
          label: _recording ? strings.learnStopBtn : strings.learnRecordBtn,
          onPressed: _toggle,
        ),
        const SizedBox(height: 8),
        if (_recording)
          Row(
            children: [
              const _PulsingDot(),
              const SizedBox(width: 6),
              Text(strings.learnRecording),
            ],
          ),
        if (_filePath != null && !kIsWeb) Text(_filePath!, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        CommonButton(
          label: strings.learnAnalyzeBtn,
          loading: _busy,
          onPressed: _filePath == null ? null : _analyze,
        ),
        const SizedBox(height: 8),
        if (_error != null)
          Card(
            color: scheme.errorContainer,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer))),
                  TextButton(onPressed: _retry, child: Text(strings.learnRetry)),
                ],
              ),
            ),
          ),
        if (_busy) LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        if (_result != null) ...[
          const SizedBox(height: 12),
          Text(strings.analysisMeanF0(_result!.meanF0.toStringAsFixed(1))),
          Text(strings.learnFrames(_result!.frames), style: Theme.of(context).textTheme.bodySmall),
          PitchContourChart(data: _result!),
        ],
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
      child: const Icon(Icons.fiber_manual_record, color: AppTheme.statusDanger, size: 14),
    );
  }
}
