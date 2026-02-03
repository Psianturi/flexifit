import 'package:flutter/material.dart';

import 'progress_store.dart';

class ThemeController {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);

  Future<void> load() async {
    final enabled = await ProgressStore.getNightModeEnabled();
    themeMode.value = enabled ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> setNightModeEnabled(bool enabled) async {
    await ProgressStore.setNightModeEnabled(enabled);
    themeMode.value = enabled ? ThemeMode.dark : ThemeMode.light;
  }
}
