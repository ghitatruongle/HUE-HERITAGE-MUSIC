import 'dart:async';
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
import '../../services/app_lifecycle_service.dart';
import '../../services/recording_controller.dart';
import '../../services/history_service.dart';
import '../../core/theme/app_theme.dart';
import '../../services/locale_provider.dart';
import '../../services/practice_resume.dart';
import '../../services/server_config.dart';
import '../../services/session_media.dart';
import '../../widgets/common_button.dart';
import '../../widgets/heritage_motif.dart';
import '../../widgets/pitch_contour_chart.dart';
import '../../widgets/error_panel.dart';
import 'lesson_practice_view.dart';
import '../../widgets/hue_icons.dart';

class LearningScreen extends StatefulWidget {
  const LearningScreen({super.key});

  @override
  State<LearningScreen> createState() => _LearningScreenState();
}

class _LearningScreenState extends State<LearningScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  bool _arming = false;
  bool _stopping = false;
  bool _busy = false;
  String? _filePath;
  PitchData? _result;
  String? _error;
  double _progress = 0;
  late AppStrings strings;
  late AppLifecycleHooks _lifecycleHooks;

  void _syncResumeTab() {
    final pending = PracticeResume.lessonId.value;
    if (pending != null && pending.isNotEmpty && mounted && _tabController.index != 1) {
      _tabController.animateTo(1);
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    PracticeResume.lessonId.addListener(_syncResumeTab);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncResumeTab());
    _lifecycleHooks = AppLifecycleHooks(
      onPause: () {
        unawaited(_stopAndKeep());
      },
    );
    AppLifecycleService.instance.register(_lifecycleHooks);
  }

  @override
  void dispose() {
    PracticeResume.lessonId.removeListener(_syncResumeTab);
    AppLifecycleService.instance.unregister(_lifecycleHooks);
    _tabController.dispose();
    if (_recording) {
      _recorder.stop().catchError((_) => null).whenComplete(() => _recorder.dispose());
    } else {
      _recorder.dispose();
    }
    super.dispose();
  }

  String _tmpPath() {
    return '${Directory.systemTemp.path}/hue_learn.wav';
  }

  Future<void> _stopAndKeep() async {
    if (!_recording || _stopping) {
      return;
    }
    _stopping = true;
    String? p;
    try {
      p = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _filePath = p;
      });
      if (p != null) {
        final media = context.read<SessionMedia>();
        if (kIsWeb) {
          try {
            final bytes = await XFile(p).readAsBytes();
            if (mounted) media.setRecording(bytes: bytes);
          } catch (_) {}
        } else {
          media.setRecording(path: p);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _recording = false);
      }
    } finally {
      _stopping = false;
    }
  }

  Future<void> _toggle() async {
    if (_arming || _stopping || _busy) return;
    if (_recording) {
      await _stopAndKeep();
      return;
    }
    if (RecordingController.anyBusy) {
      setState(() => _error = strings.practiceBusySection);
      return;
    }
    _arming = true;
    try {
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
        try {
          await _recorder.stop();
        } catch (_) {}
        return;
      }
      setState(() {
        _recording = true;
        _error = null;
        _result = null;
      });
    } finally {
      _arming = false;
    }
  }

  Future<void> _analyze() async {
    if (_busy || _arming || _stopping) return;
    final path = _filePath;
    if (path == null) {
      return;
    }
    final history = context.read<HistoryService>();
    final analyzeTitle = strings.learnAnalyzeBtn;
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
      history.add(
            HistoryEntry(id: HistoryService.newId(), kind: 'analyze-pitch', title: analyzeTitle, status: 'done', at: DateTime.now()),
          );
      setState(() => _result = data);
    } catch (e) {
      history.add(
            HistoryEntry(id: HistoryService.newId(), kind: 'analyze-pitch', title: analyzeTitle, status: 'error', at: DateTime.now()),
          );
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
        ImperialTabBar(
          controller: _tabController,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
          tabs: [
            Tab(icon: const HueIcon(HueIcons.graphicEq), text: strings.listenTabTitle),
            Tab(icon: const HueIcon(HueIcons.school), text: strings.practiceTabTitle),
          ],
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
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        CommonButton(
          label: _recording ? strings.learnStopBtn : strings.learnRecordBtn,
          onPressed: _busy ? null : _toggle,
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
          onPressed: (_filePath == null || _recording) ? null : _analyze,
        ),
        const SizedBox(height: 8),
        if (_error != null) ErrorPanel(message: _error!, onRetry: _busy ? null : _retry),
        if (_busy) LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        if (_result != null) ...[
          const SizedBox(height: 12),
          Text(strings.analysisMeanF0(_result!.meanF0.toStringAsFixed(1))),
          Text(strings.learnFrames(_result!.frames), style: Theme.of(context).textTheme.bodySmall),
          PitchContourChart(data: _result!),
          if (_result!.truncated)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                strings.analysisTruncatedNote(
                  '${_result!.maxSeconds?.toStringAsFixed(0) ?? '35'}s',
                  _result!.durationFull?.toStringAsFixed(1),
                ),
                style: TextStyle(fontSize: AppFontSize.sm, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
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
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final CurvedAnimation _curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  late final Animation<double> _opacity = Tween<double>(begin: 0.35, end: 1.0).animate(_curved);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.stop();
      _ctrl.value = 1.0;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: HueIcon(HueIcons.recordDot, color: AppTheme.statusReadable(context, AppStatusKind.danger), size: 14),
    );
  }
}
