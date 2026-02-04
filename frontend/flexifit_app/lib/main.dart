import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:google_fonts/google_fonts.dart';
import 'home_screen.dart';
import 'notification_service.dart';
import 'theme_controller.dart';
import 'web_intro_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  await ThemeController.instance.load();

  final showWebIntro = kIsWeb ? await WebIntroScreen.shouldShow() : false;
  runApp(FlexiFitApp(showWebIntro: showWebIntro));
}

class FlexiFitApp extends StatelessWidget {
  const FlexiFitApp({super.key, required this.showWebIntro});

  final bool showWebIntro;

  @override
  Widget build(BuildContext context) {
    final lightScheme = ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: Brightness.light,
    );

    const darkBackground = Color(0xFF121212);
    final darkScheme = ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: Brightness.dark,
      surface: const Color(0xFF1B1B1B),
      surfaceContainerHighest: const Color(0xFF232323),
    );

    final lightTheme = ThemeData(
      colorScheme: lightScheme,
      scaffoldBackgroundColor: const Color(0xFFF7FAF9),
      useMaterial3: true,
      textTheme: GoogleFonts.poppinsTextTheme(),
    );

    final darkTheme = ThemeData(
      colorScheme: darkScheme,
      scaffoldBackgroundColor: darkBackground,
      useMaterial3: true,
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'FlexiFit - AI Wellness Negotiator',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: mode,
          home: showWebIntro ? const WebIntroScreen() : const HomeScreen(),
        );
      },
    );
  }
}
