import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/models/lesson.dart';
import 'package:hue_heritage_music/screens/admin/admin_screen.dart';
import 'package:hue_heritage_music/screens/analysis/analysis_screen.dart';
import 'package:hue_heritage_music/screens/creation/creation_screen.dart';
import 'package:hue_heritage_music/screens/history/history_screen.dart';
import 'package:hue_heritage_music/screens/home/home_screen.dart';
import 'package:hue_heritage_music/screens/learning/lesson_practice_view.dart';
import 'package:hue_heritage_music/screens/learning/scale_practice_card.dart';
import 'package:hue_heritage_music/screens/restoration/restoration_screen.dart';
import 'package:hue_heritage_music/screens/transcription/transcription_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/session_media.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:hue_heritage_music/widgets/compare_chart.dart';
import 'package:hue_heritage_music/widgets/feature_header.dart';
import 'package:hue_heritage_music/widgets/hue_icons.dart';
import 'package:hue_heritage_music/widgets/result_card.dart';
import 'package:hue_heritage_music/widgets/sheet_music_view.dart';
import 'package:hue_heritage_music/widgets/stat_card.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, List<String>> get _jsonHeaders => {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    };

Uint8List _wavBytes({double freqHz = 440, int sampleRate = 16000, double seconds = 0.2}) {
  final count = (sampleRate * seconds).round();
  final dataLen = count * 2;
  final out = Uint8List(44 + dataLen);
  final bd = ByteData.sublistView(out);
  out.setRange(0, 4, [0x52, 0x49, 0x46, 0x46]);
  bd.setUint32(4, 36 + dataLen, Endian.little);
  out.setRange(8, 12, [0x57, 0x41, 0x56, 0x45]);
  out.setRange(12, 16, [0x66, 0x6D, 0x74, 0x20]);
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little);
  bd.setUint16(22, 1, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * 2, Endian.little);
  bd.setUint16(32, 2, Endian.little);
  bd.setUint16(34, 16, Endian.little);
  out.setRange(36, 40, [0x64, 0x61, 0x74, 0x61]);
  bd.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < count; i++) {
    final s = (12000.0 * math.sin(2 * math.pi * freqHz * i / sampleRate)).round();
    bd.setInt16(44 + i * 2, s, Endian.little);
  }
  return out;
}

class _PopulatedMockAdapter implements HttpClientAdapter {
  static final List<Map<String, dynamic>> heritageItems = [
    {
      'id': 'h1',
      'title': 'Bài Lý Mười Thương cổ truyền của cố nghệ nhân vùng Kinh Bắc và Thuận Hóa rất dài',
      'type': 'Ca Huế',
      'artist': 'Nghệ nhân ưu tú Trần Văn Tý',
      'sha256': 'sha-h1',
      'size': 204800,
      'created_at': '2026-11-01',
      'mode_system': 'Bắc',
      'bpm': 60,
      'featured_in_creation': true,
    },
    {
      'id': 'h2',
      'title': 'Bản thu âm đối chiếu giọng ca Huế dân gian dài dòng năm 1998 cần phục dựng sâu',
      'type': 'Nhã nhạc',
      'artist': 'Dàn nhạc cung đình Huế',
      'sha256': 'sha-h2',
      'size': 409600,
      'created_at': '2026-11-02',
      'mode_system': 'Nam',
      'bpm': 72,
      'featured_in_creation': true,
    },
  ];

  static final Map<String, dynamic> lessonJson = {
    'id': 'l1',
    'title': 'Nam Bình — Khúc ca Huế cổ truyền của cố nghệ nhân dân gian đất Cố Đô',
    'type': 'Ca Huế',
    'artist': 'Nghệ nhân dân gian',
    'mode_system': 'Nam',
    'bpm': 60,
    'has_ornaments': true,
    'sections': 2,
  };

  static final Map<String, dynamic> lessonDetailJson = {
    'id': 'l1',
    'title': 'Nam Bình — Khúc ca Huế cổ truyền của cố nghệ nhân dân gian đất Cố Đô',
    'lyrics': 'Chiều chiều bên bến Văn Lâu\nAi ngồi ai câu ai sầu ai thảm',
    'mode_system': 'Nam',
    'bpm': 60,
    'sections': [
      {
        'index': 0,
        'start': 0.0,
        'end': 4.0,
        'duration': 4.0,
        'lyrics': 'Chiều chiều bên bến Văn Lâu',
        'has_sample': true,
        'sample_url': '/api/lessons/l1/sections/0/sample.wav',
        'line_times': [
          {'start': 0.0, 'end': 4.0},
        ],
      },
      {
        'index': 1,
        'start': 4.0,
        'end': 8.0,
        'duration': 4.0,
        'lyrics': 'Ai ngồi ai câu ai sầu ai thảm',
        'has_sample': false,
        'sample_url': '',
      },
    ],
    'contour': {
      'times': [0.0, 1.0, 2.0, 3.0],
      'f0': [220.0, 246.9, 261.6, 293.7],
    },
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path.contains('/api/music/play-url')) {
      return ResponseBody.fromString(
        jsonEncode({'url': '/api/music/signed/sample.wav'}),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/music/restore-item/')) {
      return ResponseBody.fromString(
        jsonEncode({
          'label': 'Bản phục dựng siêu sạch (44.1kHz)',
          'sha': 'sha-restored-1',
          'sample_rate': 44100,
          'duration': 15.2,
          'dc_removed': 0.0042,
          'clicks_fixed': 7,
          'peak_before': -1.2,
          'peak_after': -2.0,
          'noise_floor_db': -58.5,
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/music/compare-items')) {
      return ResponseBody.fromString(
        jsonEncode({
          'metrics': {
            'mean_abs_cents': 12.4,
            'median_cents': 9.1,
            'mean_offset_ms': 42.0,
            'start_offset_ms': 15.0,
            'pairs': 14,
            'dtw_distance': 0.25,
            'pitch_score': 91.0,
            'time_score': 88.0,
            'score': 90.0,
          },
          'sample': {
            'times': [0.0, 0.5, 1.0, 1.5],
            'f0': [220.0, 246.9, 261.6, 293.7],
          },
          'user_warped': {
            'f0': [222.0, 245.0, 260.0, 291.0],
          },
          'notes': [
            {'midi': 60, 'start': 0.0, 'end': 0.5, 'err_cents': 8.0, 'verdict': 'ok'},
          ],
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/music/analyze-pitch')) {
      return ResponseBody.fromString(
        jsonEncode({
          'mean_f0': 245.5,
          'frames': 4,
          'times': [0.0, 0.5, 1.0, 1.5],
          'f0': [220.0, 246.9, 261.6, 293.7],
          'truncated': false,
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/music/instruments')) {
      return ResponseBody.fromString(
        jsonEncode({
          'label': 'Đàn nguyệt & Ca Huế cổ truyền',
          'segments': [
            {'start': 0.0, 'end': 1.2, 'instrument': 'Đàn nguyệt', 'confidence': 0.94},
            {'start': 1.2, 'end': 2.0, 'instrument': 'Phách tiền', 'confidence': 0.87},
          ],
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/music/transcribe')) {
      return ResponseBody.fromString(
        jsonEncode({
          'label': 'Nam Bình ký âm mẫu chuẩn',
          'bpm': 60,
          'sha': 'sha-tr-1',
          'notes': [
            {'midi': 60, 'start': 0.0, 'end': 0.4},
            {'midi': 62, 'start': 0.4, 'end': 0.8},
            {'midi': 64, 'start': 0.8, 'end': 1.2},
            {'midi': 67, 'start': 1.2, 'end': 1.6},
          ],
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/music/heritage-tunes')) {
      return ResponseBody.fromString(jsonEncode(heritageItems), 200, headers: _jsonHeaders);
    }
    if (path.contains('/api/music/models')) {
      return ResponseBody.fromString(
        jsonEncode({
          'adapters': [
            {'name': 'hue_dan_nguyet_ep50', 'ready': true},
          ],
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/heritage')) {
      return ResponseBody.fromString(
        jsonEncode({'items': heritageItems, 'total': heritageItems.length}),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/lessons/scales')) {
      return ResponseBody.fromString(
        jsonEncode([
          {
            'id': 'ngu-cung',
            'name': 'Ngũ cung Hò Xự Xang Xê Cống (Điệu Nam)',
            'note_names': ['Hò', 'Xự', 'Xang', 'Xê', 'Cống'],
          },
        ]),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/lessons/my-progress')) {
      return ResponseBody.fromString(
        jsonEncode({
          'server_today': '2026-11-24',
          'server_utc_now': '2026-11-24T00:00:00Z',
          'items': [
            {
              'lesson_id': 'l1',
              'section': 0,
              'score': 89.0,
              'pitch_score': 91.0,
              'rhythm_score': 87.0,
              'stability_score': 88.0,
              'created_at': '2026-11-24T00:00:00Z',
            },
            {
              'lesson_id': 'l1',
              'section': 1,
              'score': 92.0,
              'pitch_score': 94.0,
              'rhythm_score': 90.0,
              'stability_score': 91.0,
              'created_at': '2026-11-23T00:00:00Z',
            },
          ],
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/lessons/l1/practice')) {
      return ResponseBody.fromString(
        jsonEncode({
          'metrics': {
            'score': 89.5,
            'pitch_score': 91.0,
            'time_score': 88.0,
            'mean_abs_cents': 14.0,
            'rhythm_score': 87.5,
            'stability_score': 90.0,
            'matched_notes': 4,
            'unmatched_notes': 0,
            'missing_notes': 0,
            'summary_codes': [],
          },
          'sample': {
            'times': [0.0, 0.5, 1.0],
            'f0': [220.0, 247.0, 261.6],
          },
          'user_warped': {
            'f0': [222.0, 245.0, 260.0],
          },
          'notes': [
            {
              'start': 0.0,
              'end': 0.5,
              'err_cents': 10.0,
              'verdict': 'Chuẩn',
              'verdict_code': 'ok',
              'hint': '',
              'hint_codes': [],
            },
          ],
          'words': [
            {
              'line': 0,
              'index': 0,
              'text': 'Chiều',
              'start': 0.0,
              'end': 0.5,
              'voiced_ratio': 1.0,
              'err_cents': 8.0,
              'verdict_code': 'ok',
              'verdict': 'Chuẩn',
            },
            {
              'line': 0,
              'index': 1,
              'text': 'chiều',
              'start': 0.5,
              'end': 1.0,
              'voiced_ratio': 0.8,
              'err_cents': -22.0,
              'verdict_code': 'minor',
              'verdict': 'Lệch nhẹ',
            },
            {
              'line': 0,
              'index': 2,
              'text': 'Văn',
              'start': 1.0,
              'end': 1.5,
              'voiced_ratio': 0.0,
              'err_cents': null,
              'verdict_code': 'unclear',
              'verdict': 'Không rõ',
            },
          ],
          'words_alignment': 'line_voiced_word_proportional',
          'section': {'index': 0},
          'lesson_title': 'Nam Bình',
          'reference': 'sample',
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/lessons/l1')) {
      return ResponseBody.fromString(jsonEncode(lessonDetailJson), 200, headers: _jsonHeaders);
    }
    if (path.contains('/api/lessons')) {
      return ResponseBody.fromString(jsonEncode([lessonJson]), 200, headers: _jsonHeaders);
    }
    if (path.contains('/api/admin/stats')) {
      return ResponseBody.fromString(
        jsonEncode({
          'users': {'total': 6, 'active': 5, 'workers': 2},
          'invites': {'total': 8, 'unused': 3},
          'storage': {
            'items_total': 24,
            'items_bytes': 12582912,
            'derived_files': 18,
            'derived_bytes': 2097152,
            'generated_bytes': 5242880,
          },
          'tasks': {
            'by_status': {'done': 10, 'error': 1},
            'by_kind': {'sing_original': 6, 'transcribe': 5},
          },
          'engine_online': true,
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/auth/users')) {
      return ResponseBody.fromString(
        jsonEncode({
          'total': 2,
          'items': [
            {
              'id': 'u1',
              'username': 'ghitatruongle',
              'email': 'ghitatruongle.codohue@hueheritage.example.com',
              'role': 'admin',
              'active': true,
              'must_change_password': false,
              'avatar': '',
            },
            {
              'id': 'u2',
              'username': 'nghe_nhan_ca_hue_dai_ten',
              'email': 'nghenhan.cahue.codohue.vietnam@hueheritage.example.com',
              'role': 'worker',
              'active': true,
              'must_change_password': false,
              'avatar': '',
            },
          ],
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/auth/invites')) {
      return ResponseBody.fromString(
        jsonEncode({
          'total': 1,
          'items': [
            {
              'id': 'inv1',
              'code': 'HUE-2026-INVITE-CODE-01',
              'note': 'Mã mời dành cho nghệ nhân Ca Huế',
              'used': false,
            },
          ],
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/admin/storage')) {
      return ResponseBody.fromString(
        jsonEncode({
          'items_total': 1,
          'items': [
            {
              'id': 'st1',
              'title': 'Bài Lý Mười Thương dài của cố nghệ nhân Thuận Hóa',
              'filename': 'ly_muoi_thuong_master_restored_v2_final.wav',
              'size': 2048576,
              'created_at': '2026-11-24T06:00:00Z',
              'original_exists': true,
              'visibility': 'public',
              'owner_username': 'ghitatruongle',
              'derived_files': [
                {'kind': 'restored_wav', 'size': 1024000},
                {'kind': 'midi', 'size': 4096},
              ],
              'derived_bytes': 1028096,
            },
          ],
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/admin/learning/stats')) {
      return ResponseBody.fromString(
        jsonEncode({'total_sessions': 42, 'active_users': 9, 'sessions_last_7d': 15}),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/admin/security/summary')) {
      return ResponseBody.fromString(
        jsonEncode({
          'counts': {'login_failed': 3, 'role_change': 1},
          'last_admin_login': {'ts': '2026-11-24T08:00:00Z'},
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/admin/security/events')) {
      return ResponseBody.fromString(
        jsonEncode({
          'total': 1,
          'truncated': false,
          'events': [
            {
              'ts': '2026-11-24T08:00:00Z',
              'level': 'warning',
              'event': 'login_failed',
              'fields': {'ip': '127.0.0.1', 'username': 'test_user'},
            },
          ],
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/admin/crash-reports')) {
      return ResponseBody.fromString(
        jsonEncode({
          'items': [
            {
              'id': 'c1',
              'user_id': 'u1',
              'app_version': '0.0.5',
              'platform': 'macos',
              'summary': 'Socket reset during upload session on mobile network',
              'detail': 'stack trace line',
              'created_at': '2026-11-24T07:00:00Z',
            },
          ],
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    return ResponseBody.fromString('{}', 200, headers: _jsonHeaders);
  }

  @override
  void close({bool force = false}) {}
}

class _FakePicker extends FilePicker {
  final String path;
  final Uint8List bytes;
  _FakePicker(this.path, this.bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return FilePickerResult([
      PlatformFile(name: 'sample_hue_heritage.wav', path: path, bytes: bytes, size: bytes.length),
    ]);
  }
}

class _FakeJustAudio extends JustAudioPlatform {
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async => _FakePlayer(request.id);

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async =>
      DisposePlayerResponse();

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest request) async =>
      DisposeAllPlayersResponse();
}

class _FakePlayer extends AudioPlayerPlatform {
  _FakePlayer(super.id);

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => const Stream.empty();

  @override
  Future<LoadResponse> load(LoadRequest request) async => LoadResponse(duration: null);

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async => SetVolumeResponse();

  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse();

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async => SetSpeedResponse();

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async => SetPitchResponse();

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) async =>
      SetSkipSilenceResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async => SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();

  @override
  Future<SeekResponse> seek(SeekRequest request) async => SeekResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async => DisposeResponse();

  @override
  Future<AudioEffectSetEnabledResponse> audioEffectSetEnabled(AudioEffectSetEnabledRequest request) async =>
      AudioEffectSetEnabledResponse();

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(SetShuffleOrderRequest request) async =>
      SetShuffleOrderResponse();

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
          ConcatenatingInsertAllRequest request) async =>
      ConcatenatingInsertAllResponse();

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
          ConcatenatingRemoveRangeRequest request) async =>
      ConcatenatingRemoveRangeResponse();

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(ConcatenatingMoveRequest request) async =>
      ConcatenatingMoveResponse();

  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(
          SetPreferredPeakBitRateRequest request) async =>
      SetPreferredPeakBitRateResponse();

  @override
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(
          SetAllowsExternalPlaybackRequest request) async =>
      SetAllowsExternalPlaybackResponse();

  @override
  Future<SetWebCrossOriginResponse> setWebCrossOrigin(SetWebCrossOriginRequest request) async =>
      SetWebCrossOriginResponse();

  @override
  Future<SetWebSinkIdResponse> setWebSinkId(SetWebSinkIdRequest request) async =>
      SetWebSinkIdResponse();

  @override
  Future<AndroidEqualizerGetParametersResponse> androidEqualizerGetParameters(
          AndroidEqualizerGetParametersRequest request) async =>
      AndroidEqualizerGetParametersResponse(
        parameters: AndroidEqualizerParametersMessage(
          minDecibels: -20,
          maxDecibels: 20,
          bands: const <AndroidEqualizerBandMessage>[],
        ),
      );

  @override
  Future<AndroidEqualizerBandSetGainResponse> androidEqualizerBandSetGain(
          AndroidEqualizerBandSetGainRequest request) async =>
      AndroidEqualizerBandSetGainResponse();

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
          SetAndroidAudioAttributesRequest request) async =>
      SetAndroidAudioAttributesResponse();
}

Future<void> _loadFonts() async {
  final be = FontLoader('BeVietnamPro');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    be.addFont(rootBundle.load('assets/fonts/BeVietnamPro-$f.ttf'));
  }
  await be.load();
  final pf = FontLoader('PlayfairDisplay')
    ..addFont(rootBundle.load('assets/fonts/PlayfairDisplay.ttf'))
    ..addFont(rootBundle.load('assets/fonts/PlayfairDisplay-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/PlayfairDisplay-Bold.ttf'));
  await pf.load();
  final mono = FontLoader('JetBrainsMono')
    ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'));
  await mono.load();
}

Future<ServerConfig> _configuredServer() async {
  SharedPreferences.setMockInitialValues({'hue_server_url': 'http://127.0.0.1:8005'});
  final server = ServerConfig();
  await server.load();
  server.api.dio.httpClientAdapter = _PopulatedMockAdapter();
  return server;
}

Future<HistoryService> _populatedHistory() async {
  final history = HistoryService();
  await history.add(HistoryEntry(
    id: 'e1',
    kind: 'sing_original',
    title: 'Hát nguyên bản: Lý Mười Thương cổ truyền rất dài',
    status: 'done',
    at: DateTime(2026, 11, 24, 9, 0),
  ));
  await history.add(HistoryEntry(
    id: 'e2',
    kind: 'practice',
    title: 'Luyện tập Nam Bình câu 1',
    status: 'done',
    score: 89.5,
    at: DateTime(2026, 11, 24, 9, 10),
    detail: 'l1',
  ));
  await history.add(HistoryEntry(
    id: 'e3',
    kind: 'restore',
    title: 'Phục dựng bản ghi âm cổ năm 1998',
    status: 'done',
    at: DateTime(2026, 11, 24, 9, 20),
  ));
  return history;
}

Widget _appShell({
  required Widget child,
  required ServerConfig server,
  required AuthService auth,
  required HistoryService history,
  required ThemeProvider themeProvider,
  bool wrapInScaffold = true,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: server),
      ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
      ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider<HistoryService>.value(value: history),
      ChangeNotifierProvider<SessionMedia>(create: (_) => SessionMedia()),
    ],
    child: Consumer<ThemeProvider>(
      builder: (_, theme, __) => MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: theme.mode,
        home: wrapInScaffold ? Scaffold(body: child) : child,
      ),
    ),
  );
}

Future<void> _pumpAndCheckErrors(
  WidgetTester tester,
  String label,
) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _tapScrolled(WidgetTester tester, Finder target) async {
  final vertical = find
      .byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      )
      .hitTestable();
  final viewH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (var i = 0; i < 10; i++) {
    if (target.evaluate().isNotEmpty) {
      final box = tester.renderObject(target.first) as RenderBox;
      final topLeft = box.localToGlobal(Offset.zero);
      final bottom = topLeft.dy + box.size.height;
      if (topLeft.dy >= 0 && bottom <= viewH) {
        break;
      }
    }
    if (vertical.evaluate().isEmpty) break;
    await tester.drag(vertical.last, const Offset(0, -140));
    await tester.pump(const Duration(milliseconds: 80));
  }
  await tester.tap(target.first);
}

void main() {
  late Directory tmpDir;
  late String wavPath;
  late String recWavPath;
  late Uint8List wavData;
  late Uint8List recWavData;
  String? activeRecPath;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JustAudioPlatform.instance = _FakeJustAudio();
    wavData = _wavBytes();
    recWavData = _wavBytes(seconds: 2.1);
    tmpDir = await Directory.systemTemp.createTemp('hue_gate_wav_');
    wavPath = '${tmpDir.path}/sample_hue_heritage.wav';
    recWavPath = '${tmpDir.path}/recorded_hue_heritage.wav';
    await File(wavPath).writeAsBytes(wavData);
    await File(recWavPath).writeAsBytes(recWavData);
    FilePicker.platform = _FakePicker(wavPath, wavData);
    const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      secureChannel,
      (call) async => null,
    );
    const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProviderChannel,
      (call) async => tmpDir.path,
    );
    const connectivityChannel = MethodChannel('dev.fluttercommunity.plus/connectivity');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      connectivityChannel,
      (call) async => <String>['wifi'],
    );
    const recordChannel = MethodChannel('com.llfbandit.record/messages');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      recordChannel,
      (call) async {
        switch (call.method) {
          case 'create':
            final id = call.arguments is Map ? call.arguments['recorderId']?.toString() : null;
            if (id != null && id.isNotEmpty) {
              for (final prefix in [
                'com.llfbandit.record/events/',
                'com.llfbandit.record/eventsRecordState/',
              ]) {
                TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                    .setMockMethodCallHandler(
                  MethodChannel('$prefix$id'),
                  (c) async => null,
                );
              }
            }
            return 'mock-recorder';
          case 'hasPermission':
          case 'isEncoderSupported':
            return true;
          case 'isRecording':
          case 'isPaused':
            return false;
          case 'listInputDevices':
            return <dynamic>[];
          case 'start':
            if (call.arguments is Map && call.arguments['path'] is String) {
              activeRecPath = call.arguments['path'] as String;
              await File(activeRecPath!).writeAsBytes(recWavData);
            }
            return null;
          case 'stop':
            return activeRecPath ?? recWavPath;
          case 'getAmplitude':
            return {'current': -15.0, 'max': -15.0};
          default:
            return null;
        }
      },
    );
    await _loadFonts();
  });

  tearDownAll(() {
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('HomeScreen & HistoryScreen populated render cleanly at 320x640 and 740x360', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final server = await _configuredServer();
    final history = await _populatedHistory();
    final auth = AuthService();
    await auth.save(token: 'tok-h', username: 'ghitatruongle', email: 'g@x.com', role: 'admin');
    addTearDown(() async => auth.clearToken());

    for (final size in [const Size(320, 640), const Size(740, 360), const Size(1280, 800)]) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        final theme = ThemeProvider()..setMode(mode);

        await tester.pumpWidget(_appShell(
          child: HomeScreen(key: ValueKey('home_${size}_$mode')),
          server: server,
          auth: auth,
          history: history,
          themeProvider: theme,
          wrapInScaffold: false,
        ));
        await _pumpAndCheckErrors(tester, 'HomeScreen ${size.width}x${size.height} $mode');

        await tester.pumpWidget(_appShell(
          child: HistoryScreen(key: ValueKey('hist_${size}_$mode')),
          server: server,
          auth: auth,
          history: history,
          themeProvider: theme,
        ));
        await _pumpAndCheckErrors(tester, 'HistoryScreen ${size.width}x${size.height} $mode');
        final header = find.byType(FeatureHeader);
        expect(header, findsOneWidget);
        final headerTexts = tester.widgetList<Text>(find.descendant(of: header, matching: find.byType(Text))).toList();
        expect(headerTexts.any((t) => (t.maxLines ?? 2) >= 2), isTrue);
      }
    }
  });

  testWidgets('RestorationScreen + CompareChart long titles render cleanly at 320x640 and 740x360', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final server = await _configuredServer();
    final history = HistoryService();
    final auth = AuthService();

    for (final size in [const Size(320, 640), const Size(740, 360), const Size(1280, 800)]) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        final theme = ThemeProvider()..setMode(mode);

        await tester.pumpWidget(_appShell(
          child: RestorationScreen(key: ValueKey('rest_${size}_$mode')),
          server: server,
          auth: auth,
          history: history,
          themeProvider: theme,
        ));
        await _pumpAndCheckErrors(tester, 'Restoration initial ${size.width}x${size.height} $mode');

        for (var i = 0; i < 15 && find.textContaining('Lý Mười Thương').evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 60));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        }
        final itemFinder = find.textContaining('Lý Mười Thương').first;
        await tester.ensureVisible(itemFinder);
        await tester.tap(itemFinder);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 60));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        }
        final runRestore = find.text('Chạy phục dựng (Beta)');
        for (var i = 0; i < 6 && runRestore.evaluate().isEmpty; i++) {
          final vertical = find
              .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
              .hitTestable();
          if (vertical.evaluate().isEmpty) break;
          await tester.drag(vertical.last, const Offset(0, -140));
          await tester.pump(const Duration(milliseconds: 80));
        }
        if (runRestore.evaluate().isNotEmpty) {
          await _tapScrolled(tester, runRestore);
        } else {
          await _tapScrolled(tester, find.text('Phục dựng'));
        }
        for (var i = 0; i < 30 && find.byType(ResultSummaryCard).evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 60));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
          if (i >= 8 && find.byType(ResultSummaryCard).evaluate().isEmpty) {
            final vertical = find
                .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
                .hitTestable();
            if (vertical.evaluate().isNotEmpty) {
              await tester.drag(vertical.last, const Offset(0, -140));
            }
          }
        }
        expect(find.byType(ResultSummaryCard), findsOneWidget);
        await _pumpAndCheckErrors(tester, 'Restoration result ${size.width}x${size.height} $mode');

        final nav = Navigator.of(tester.element(find.byType(ResultSummaryCard)));
        if (nav.canPop()) {
          nav.pop();
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 80));
          }
        }

        await tester.tap(find.text('Đối chiếu & Tìm tên bài'));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 80));
        }
        final uploadHit = find.byIcon(HueIcons.uploadFile).hitTestable();
        if (uploadHit.evaluate().isNotEmpty) {
          await tester.tap(uploadHit.last);
        } else {
          final textUpload = find.text('Tải lên bản ghi của bạn để đối chiếu');
          if (textUpload.evaluate().isNotEmpty) {
            await _tapScrolled(tester, textUpload);
          } else {
            final texts = find
                .byType(Text)
                .evaluate()
                .map((e) => (e.widget as Text).data ?? '')
                .where((s) => s.isNotEmpty)
                .toList();
            fail('Compare tab upload control missing; visible texts: $texts');
          }
        }
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 200));
        await _tapScrolled(tester, find.text('Đối chiếu âm học & Nhận diện bài'));
        for (var i = 0; i < 20 && find.byType(CompareChart).evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 60));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
          if (i >= 6 && find.byType(CompareChart).evaluate().isEmpty) {
            final vertical = find
                .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
                .hitTestable();
            if (vertical.evaluate().isNotEmpty) {
              await tester.drag(vertical.last, const Offset(0, -140));
            }
          }
        }
        expect(find.byType(CompareChart), findsOneWidget);
        await _pumpAndCheckErrors(tester, 'CompareChart ${size.width}x${size.height} $mode');
      }
    }
  });

  testWidgets('AnalysisScreen & TranscriptionScreen populated render cleanly at 320x640 and 740x360', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final server = await _configuredServer();
    final history = HistoryService();
    final auth = AuthService();

    for (final size in [const Size(320, 640), const Size(740, 360)]) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        final theme = ThemeProvider()..setMode(mode);

        await tester.pumpWidget(_appShell(
          child: AnalysisScreen(key: ValueKey('ana_${size}_$mode')),
          server: server,
          auth: auth,
          history: history,
          themeProvider: theme,
        ));
        await tester.pump(const Duration(milliseconds: 120));
        final actionBtn = find.byWidgetPredicate((w) => w is FilledButton || w is ElevatedButton);
        await tester.ensureVisible(actionBtn.first);
        await tester.tap(actionBtn.first);
        for (var i = 0; i < 25 && find.byType(StatCard).evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 60));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        }
        expect(find.byType(StatCard), findsAtLeastNWidgets(2));
        await _pumpAndCheckErrors(tester, 'AnalysisScreen ${size.width}x${size.height} $mode');

        await tester.pumpWidget(_appShell(
          child: TranscriptionScreen(key: ValueKey('tr_${size}_$mode')),
          server: server,
          auth: auth,
          history: history,
          themeProvider: theme,
        ));
        await tester.pump(const Duration(milliseconds: 120));
        await tester.tap(find.text('Chọn tệp'));
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
          await tester.pump(const Duration(milliseconds: 60));
        }
        await _tapScrolled(tester, find.text('Phân tích ký âm'));
        for (var i = 0; i < 20 && find.byType(SheetMusicView).evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 60));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        }
        expect(find.byType(SheetMusicView), findsOneWidget);
        await _pumpAndCheckErrors(tester, 'TranscriptionScreen ${size.width}x${size.height} $mode');
      }
    }
  });

  testWidgets('LessonPracticeView populated renders cleanly at 320x640 and 740x360', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final server = await _configuredServer();
    final history = HistoryService();
    final auth = AuthService();

    for (final size in [const Size(320, 640), const Size(740, 360)]) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        final theme = ThemeProvider()..setMode(mode);

        await tester.pumpWidget(_appShell(
          child: LessonPracticeView(key: ValueKey('lpv_${size}_$mode')),
          server: server,
          auth: auth,
          history: history,
          themeProvider: theme,
        ));
        for (var i = 0; i < 12 && find.byWidgetPredicate((w) => w is DropdownButtonFormField).evaluate().isEmpty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
          await tester.pump(const Duration(milliseconds: 60));
        }
        final dd = find.byWidgetPredicate((w) => w is DropdownButtonFormField);
        await tester.ensureVisible(dd.first);
        await tester.tap(dd.first);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.textContaining('Nam Bình').last);
        for (var i = 0; i < 15; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          await tester.pump(const Duration(milliseconds: 60));
        }
        if (find.byType(Switch).evaluate().length >= 2) {
          await _tapScrolled(tester, find.byType(Switch).at(0));
          await tester.pump(const Duration(milliseconds: 80));
          await _tapScrolled(tester, find.byType(Switch).last);
          await tester.pump(const Duration(milliseconds: 80));
        }
        if (find.byIcon(HueIcons.mic).evaluate().isNotEmpty) {
          await _tapScrolled(tester, find.byIcon(HueIcons.mic).first);
          for (var i = 0; i < 10 && find.byIcon(HueIcons.stop).evaluate().isEmpty; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
            await tester.pump(const Duration(milliseconds: 60));
          }
          if (find.byIcon(HueIcons.stop).evaluate().isEmpty) {
            final texts = find
                .byType(Text)
                .evaluate()
                .map((e) => (e.widget as Text).data ?? '')
                .where((s) => s.isNotEmpty)
                .toList();
            fail('Recorder did not start (no stop icon); visible texts: $texts');
          }
          await _tapScrolled(tester, find.byIcon(HueIcons.stop).first);
          for (var i = 0; i < 40 && find.text('Chấm theo từ').evaluate().isEmpty; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
            await tester.pump(const Duration(milliseconds: 60));
          }
          if (find.text('Chấm theo từ').evaluate().isEmpty && find.text('Chấm điểm').evaluate().isNotEmpty) {
            await _tapScrolled(tester, find.text('Chấm điểm').first);
            for (var i = 0; i < 25 && find.text('Chấm theo từ').evaluate().isEmpty; i++) {
              await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
              await tester.pump(const Duration(milliseconds: 60));
            }
          }
        }
        if (find.text('Chấm theo từ').evaluate().isEmpty) {
          final texts = find
              .byType(Text)
              .evaluate()
              .map((e) => (e.widget as Text).data ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
          fail('PracticeResult missing word scores; visible texts: $texts');
        }
        expect(find.text('Chấm theo từ'), findsOneWidget);
        await _pumpAndCheckErrors(tester, 'LessonPracticeView ${size.width}x${size.height} $mode');

        final scale = ScaleInfo(
          id: 'ngu-cung',
          name: 'Ngũ cung Hò Xự Xang Xê Cống rất dài trên màn hẹp',
          noteNames: const ['Hò', 'Xự', 'Xang', 'Xê', 'Cống'],
        );
        final scaleResult = ScalePractice(
          score: 86,
          pitchScore: 90,
          rhythmScore: 82,
          stabilityScore: 88,
          scaleName: 'Ngũ cung',
          onScaleShare: 0.92,
          transpose: 0,
          notes: [
            ScaleNoteHit(name: 'Hò', share: 0.95, hit: true),
            ScaleNoteHit(name: 'Xự', share: 0.4, hit: false),
          ],
          performance: [
            ScalePerformanceNote(
              name: 'Hò',
              errCents: 12,
              onsetErrMs: 40,
              verdict: 'Chuẩn',
              verdictCode: 'ok',
              hint: '',
            ),
          ],
        );
        await tester.pumpWidget(_appShell(
          child: SingleChildScrollView(
            child: ScalePracticeCard(
              scales: [scale],
              selected: scale,
              onChanged: (_) {},
              recording: false,
              onToggleRecord: () {},
              busy: false,
              onSubmit: () {},
              recordPath: null,
              result: scaleResult,
              transpose: 0,
              onTransposeChanged: (_) {},
            ),
          ),
          server: server,
          auth: auth,
          history: history,
          themeProvider: theme,
        ));
        await _pumpAndCheckErrors(tester, 'ScalePracticeCard ${size.width}x${size.height} $mode');
      }
    }
  });

  testWidgets('AdminScreen all populated tabs render cleanly at 320x640 and 740x360', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final server = await _configuredServer();
    final history = HistoryService();
    final auth = AuthService();
    await auth.save(token: 'tok-adm', username: 'ghitatruongle', email: 'a@x.com', role: 'admin');
    addTearDown(() async => auth.clearToken());

    for (final size in [const Size(320, 640), const Size(740, 360)]) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        final theme = ThemeProvider()..setMode(mode);

        await tester.pumpWidget(_appShell(
          child: AdminScreen(key: ValueKey('adm_${size}_$mode')),
          server: server,
          auth: auth,
          history: history,
          themeProvider: theme,
          wrapInScaffold: false,
        ));
        await _pumpAndCheckErrors(tester, 'Admin tab 0 ${size.width}x${size.height} $mode');

        final tabs = tester.widgetList<Tab>(find.descendant(of: find.byType(TabBar), matching: find.byType(Tab))).length;
        for (var t = 0; t < tabs; t++) {
          final tabFinder = find.descendant(of: find.byType(TabBar), matching: find.byType(Tab)).at(t);
          await tester.ensureVisible(tabFinder);
          await tester.tap(tabFinder);
          await _pumpAndCheckErrors(tester, 'Admin tab $t ${size.width}x${size.height} $mode');
        }
      }
    }
  });

  testWidgets('Hot-switching ThemeProvider on CreationScreen preserves step and lyrics state', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;

    final server = await _configuredServer();
    final history = HistoryService();
    final auth = AuthService();
    final theme = ThemeProvider()..setMode(ThemeMode.light);

    await tester.pumpWidget(_appShell(
      child: const CreationScreen(initialTabIndex: 1),
      server: server,
      auth: auth,
      history: history,
      themeProvider: theme,
    ));
    for (var i = 0; i < 30 && find.text('Viết lời').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.tap(find.text('Viết lời'));
    await tester.pump(const Duration(milliseconds: 120));

    final lyricsField = find.byType(TextField);
    expect(lyricsField, findsOneWidget);
    const typed = 'Sông Hương nước chảy xuôi dòng ca Huế';
    await tester.enterText(lyricsField, typed);
    await tester.pump();

    final stackBefore = tester.widget<IndexedStack>(find.byKey(const Key('wizard-steps')));
    expect(stackBefore.index, 1);
    expect(Theme.of(tester.element(find.byType(CreationScreen))).brightness, Brightness.light);
    expect(Theme.of(tester.element(find.byType(CreationScreen))).colorScheme.surface, AppTheme.lightSurface);

    theme.setMode(ThemeMode.dark);
    await _pumpAndCheckErrors(tester, 'CreationScreen hot-switch to dark');
    final stackDark = tester.widget<IndexedStack>(find.byKey(const Key('wizard-steps')));
    expect(stackDark.index, 1);
    expect(find.text(typed), findsOneWidget);
    expect(Theme.of(tester.element(find.byType(CreationScreen))).brightness, Brightness.dark);
    expect(Theme.of(tester.element(find.byType(CreationScreen))).colorScheme.surface, AppTheme.darkSurface);

    theme.setMode(ThemeMode.light);
    await _pumpAndCheckErrors(tester, 'CreationScreen hot-switch back to light');
    final stackLight = tester.widget<IndexedStack>(find.byKey(const Key('wizard-steps')));
    expect(stackLight.index, 1);
    expect(find.text(typed), findsOneWidget);
    expect(Theme.of(tester.element(find.byType(CreationScreen))).brightness, Brightness.light);
    expect(Theme.of(tester.element(find.byType(CreationScreen))).colorScheme.surface, AppTheme.lightSurface);
  });
}
