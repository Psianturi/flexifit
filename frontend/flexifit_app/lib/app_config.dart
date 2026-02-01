import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

class AppConfig {
  /// Override at build/run time:
  /// - Railway/prod: `--dart-define=API_BASE_URL=https://flexifit-production.up.railway.app`
  /// - Local dev: `--dart-define=USE_LOCAL_API=true`
  static const String _definedBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const bool _useLocalApi = bool.fromEnvironment('USE_LOCAL_API', defaultValue: false);

  static const String _railwayBaseUrl = 'https://flexifit-production.up.railway.app';

  /// Debug-only: show LLM-as-judge metrics in the UI.
  static const bool showDebugEvals =
      bool.fromEnvironment('SHOW_DEBUG_EVALS', defaultValue: false);

  static String get apiBaseUrl {
    if (_definedBaseUrl.isNotEmpty) {
      return _definedBaseUrl.replaceAll(RegExp(r'/*$'), '');
    }

    if (_useLocalApi) {
      if (kIsWeb) {
        return 'http://127.0.0.1:8000';
      }

      if (Platform.isAndroid) {
        return 'http://10.0.2.2:8000';
      }

      return 'http://localhost:8000';
    }

    return _railwayBaseUrl;
  }
}
