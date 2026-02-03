import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int dailyNudgeId = 1001;
  static const String channelId = 'flexifit_daily_nudge';

  Future<void> init() async {
    if (kIsWeb) return;

    tz.initializeTimeZones();
    try {
      final timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (_) {
      // Default to UTC if timezone detection fails.
      tz.setLocalLocation(tz.UTC);
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);

    // Android 13+ runtime permission.
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();

    await _ensureAndroidChannel();
  }

  Future<void> _ensureAndroidChannel() async {
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl == null) return;

    const channel = AndroidNotificationChannel(
      channelId,
      'Daily Nudge',
      description: 'A gentle daily check-in to negotiate a tiny step.',
      importance: Importance.defaultImportance,
    );

    await androidImpl.createNotificationChannel(channel);
  }

  Future<void> cancelDailyNudge() async {
    if (kIsWeb) return;
    await _plugin.cancel(dailyNudgeId);
  }

  Future<void> scheduleDailyNudge({
    required TimeOfDay time,
    String? goal,
  }) async {
    if (kIsWeb) return;

    final scheduledAt = _nextInstanceOf(time);

    final localeCode = WidgetsBinding.instance.platformDispatcher.locale.languageCode
      .toLowerCase();
    final isIndonesian = localeCode == 'id';

    final message = (goal == null || goal.trim().isEmpty)
      ? (isIndonesian
        ? "Energi kamu tinggal berapa persen hari ini? Yuk, negosiasi targetmu sebentar."
        : "How's your energy today? Let's negotiate a tiny step.")
      : (isIndonesian
        ? "Energi kamu tinggal berapa persen hari ini? Yuk, negosiasi target ‘${goal.trim()}’ sebentar."
        : "How's your energy today? Let's negotiate a tiny step for '${goal.trim()}'.");

    const androidDetails = AndroidNotificationDetails(
      channelId,
      'Daily Nudge',
      channelDescription: 'A gentle daily check-in to negotiate a tiny step.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.zonedSchedule(
      dailyNudgeId,
      'Daily Nudge',
      message,
      scheduledAt,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  tz.TZDateTime _nextInstanceOf(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }
}
