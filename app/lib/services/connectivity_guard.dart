import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityGuard {
  ConnectivityGuard._();

  static final ConnectivityGuard instance = ConnectivityGuard._();

  final Connectivity _connectivity = Connectivity();

  Future<bool> get isOnline async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.isEmpty) {
        return false;
      }
      return !results.contains(ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }
}
