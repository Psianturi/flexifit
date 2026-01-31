import 'package:flutter/material.dart';
import 'home_screen.dart';

void main() {
  runApp(const FlexiFitApp());
}

class FlexiFitApp extends StatelessWidget {
  const FlexiFitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlexiFit - AI Wellness Negotiator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.teal.shade100,
          foregroundColor: Colors.teal.shade900,
        ),
      ),
        home: const HomeScreen(),
    );
  }
}