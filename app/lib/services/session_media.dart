import 'package:flutter/foundation.dart';

class SessionMedia extends ChangeNotifier {
  String? samplePath;
  Uint8List? sampleBytes;
  String? recordingPath;
  Uint8List? recordingBytes;

  bool get hasSample => samplePath != null || sampleBytes != null;
  bool get hasRecording => recordingPath != null || recordingBytes != null;

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
}
