import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_screen.dart';

class WebIntroScreen extends StatelessWidget {
  const WebIntroScreen({super.key});

  static const String _seenKey = 'web_intro_seen_v1';

  static Future<bool> shouldShow() async {
    if (!kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_seenKey) ?? false);
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey, true);
  }

  Future<void> _start(BuildContext context) async {
    await markSeen();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          const _WebIntroBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              color: theme.colorScheme.surface.withValues(
                                alpha: isDark ? 0.92 : 0.88,
                              ),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.45),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 28,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: LayoutBuilder(
                              builder: (context, inner) {
                                final twoColumn = inner.maxWidth >= 860;

                                final left = _IntroLeft(
                                  onStart: () => _start(context),
                                );
                                final right = const _IntroRight();

                                if (!twoColumn) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      left,
                                      const SizedBox(height: 18),
                                      right,
                                    ],
                                  );
                                }

                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: left),
                                    const SizedBox(width: 18),
                                    SizedBox(width: 420, child: right),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Tip: On wide screens, the background is decorative only — your data stays in the app.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroLeft extends StatelessWidget {
  const _IntroLeft({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Colors.teal.withValues(alpha: 0.75),
                    Colors.cyan.withValues(alpha: 0.65),
                  ],
                ),
              ),
              child: const Icon(
                Icons.fitness_center,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FlexiFit',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'AI wellness negotiator — tiny wins, daily.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          runSpacing: 10,
          spacing: 10,
          children: const [
            _Pill(
              icon: Icons.chat_bubble_outline,
              label: 'Chat → negotiate a realistic plan',
            ),
            _Pill(
              icon: Icons.check_circle_outline,
              label: 'Progress → mark done for today',
            ),
            _Pill(
              icon: Icons.history,
              label: 'Journey → archive goals (completed/failed)',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Quick guide',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const _Bullet(text: 'Set 1 main goal (e.g., “Push up 100 times”).'),
        const _Bullet(
          text:
              'Tell the coach your energy level, then pick a tiny step you can do today.',
        ),
        const _Bullet(
          text:
              'Use DONE/Undo to track today — goal status changes in Journey.',
        ),
        const SizedBox(height: 12),
        Text(
          'Note: FlexiFit is a coaching tool, not medical advice.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Start'),
            ),
          ],
        ),
      ],
    );
  }
}

class _IntroRight extends StatelessWidget {
  const _IntroRight();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Features',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        const _FeatureCard(
          icon: Icons.smart_toy_outlined,
          title: 'AI Coach Chat',
          body: 'Negotiates a plan that matches your energy & time.',
        ),
        const SizedBox(height: 10),
        const _FeatureCard(
          icon: Icons.mic_none,
          title: 'Voice Input',
          body: 'Talk naturally when typing feels annoying.',
        ),
        const SizedBox(height: 10),
        const _FeatureCard(
          icon: Icons.local_fire_department_outlined,
          title: 'Streak & Daily DONE',
          body: 'Track daily consistency with DONE / Undo.',
        ),
        const SizedBox(height: 10),
        const _FeatureCard(
          icon: Icons.insights_outlined,
          title: 'Progress Insights',
          body: 'Weekly consistency + trends + motivation tips.',
        ),
        const SizedBox(height: 10),
        const _FeatureCard(
          icon: Icons.badge_outlined,
          title: 'Flexi Identity',
          body: 'A fun persona snapshot that evolves with progress.',
        ),
        const SizedBox(height: 10),
        const _FeatureCard(
          icon: Icons.history,
          title: 'Journey History',
          body: 'Archive goals as completed or failed, anytime.',
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.22),
                  theme.colorScheme.tertiary.withValues(alpha: 0.16),
                ],
              ),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
              ),
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.70),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              Icons.circle,
              size: 8,
              color: theme.colorScheme.primary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebIntroBackdrop extends StatelessWidget {
  const _WebIntroBackdrop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final base = isDark ? const Color(0xFF0F1112) : const Color(0xFFF4FAF9);

    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: base,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              base,
              (isDark ? const Color(0xFF12181A) : const Color(0xFFEAF7F4))
                  .withValues(alpha: 0.90),
              (isDark ? const Color(0xFF0B0F10) : const Color(0xFFF7FBFF))
                  .withValues(alpha: 0.95),
            ],
          ),
        ),
        child: Stack(
          children: [
            _Blob(
              alignment: const Alignment(-0.9, -0.8),
              color: Colors.teal.withValues(alpha: isDark ? 0.18 : 0.20),
              size: 560,
            ),
            _Blob(
              alignment: const Alignment(0.9, -0.7),
              color: Colors.cyan.withValues(alpha: isDark ? 0.16 : 0.16),
              size: 480,
            ),
            _Blob(
              alignment: const Alignment(0.2, 0.95),
              color: Colors.tealAccent.withValues(alpha: isDark ? 0.10 : 0.12),
              size: 620,
            ),
          ],
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required this.alignment,
    required this.color,
    required this.size,
  });

  final Alignment alignment;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color,
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
