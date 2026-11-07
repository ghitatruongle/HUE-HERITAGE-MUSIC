import 'package:flutter/foundation.dart';

class SessionMedia extends ChangeNotifier {
  String? recordingPath;
  Uint8List? recordingBytes;

  void setRecording({String? path, Uint8List? bytes}) {
    recordingPath = path;
    recordingBytes = bytes;
    notifyListeners();
  }

  void clearRecording() {
    if (recordingPath == null && recordingBytes == null) {
      return;
    }
    recordingPath = null;
    recordingBytes = null;
    notifyListeners();
  }
}
