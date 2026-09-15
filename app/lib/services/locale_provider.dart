import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/localization/app_strings.dart';

class LocaleProvider extends ChangeNotifier {
  static const String _prefKey = 'selected_language';

  String _languageCode = 'en';

  String get languageCode => _languageCode;

  bool get isVietnamese => _languageCode == 'vi';

  AppStrings get strings => AppStrings(_languageCode);

  Locale get currentLocale => Locale(_languageCode);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null && (saved == 'en' || saved == 'vi')) {
        _languageCode = saved;
      } else {
        final systemCode = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
        if (systemCode == 'vi') {
          _languageCode = 'vi';
        } else {
          _languageCode = 'en';
        }
      }
    } catch (_) {
      _languageCode = 'en';
    }
    notifyListeners();
  }

  void setLocale(String languageCode) {
    if (languageCode != 'en' && languageCode != 'vi') {
      return;
    }
    if (_languageCode == languageCode) {
      return;
    }
    _languageCode = languageCode;
    notifyListeners();
    unawaited(_save(languageCode));
  }

  void toggleLanguage() {
    if (_languageCode == 'vi') {
      setLocale('en');
    } else {
      setLocale('vi');
    }
  }

  Future<void> _save(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, code);
    } catch (_) {}
  }
}
