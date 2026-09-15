import 'package:flutter/foundation.dart';

class SessionMedia extends ChangeNotifier {
  String? samplePath;
  Uint8List? sampleBytes;
  String? recordingPath;
  Uint8List? recordingBytes;

  String? currentTrackTitle;
  String? currentTrackSubtitle;
  String? currentAudioUrl;
  Uint8List? currentAudioBytes;
  String? currentAudioPath;
  bool isPlayerVisible = false;

  bool get hasSample => samplePath != null || sampleBytes != null;
  bool get hasRecording => recordingPath != null || recordingBytes != null;
  bool get hasActiveTrack =>
      isPlayerVisible &&
      (currentAudioUrl != null ||
          currentAudioBytes != null ||
          currentAudioPath != null);

  void setSample({String? path, Uint8List? bytes}) {
    samplePath = path;
    sampleBytes = bytes;
    notifyListeners();
  }

  void setRecording({String? path, Uint8List? bytes}) {
    recordingPath = path;
    recordingBytes = bytes;
    notifyListeners();
  }

  void playTrack({
    required String title,
    String subtitle = '',
    String? url,
    Uint8List? bytes,
    String? filePath,
  }) {
    currentTrackTitle = title;
    currentTrackSubtitle = subtitle;
    currentAudioUrl = url;
    currentAudioBytes = bytes;
    currentAudioPath = filePath;
    isPlayerVisible = true;
    notifyListeners();
  }

  void closePlayer() {
    isPlayerVisible = false;
    currentAudioUrl = null;
    currentAudioBytes = null;
    currentAudioPath = null;
    notifyListeners();
  }
}
