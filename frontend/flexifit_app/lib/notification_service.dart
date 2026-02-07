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

  static const String channelId = 'flexifit_daily_nudge_v2';

  Future<void> init() async {
    if (kIsWeb) return;

    tz.initializeTimeZones();
    try {
      final timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      debugPrint('[NotificationService] Timezone set to $timeZoneName');
    } catch (e) {
      // Default to UTC if timezone detection fails.
      tz.setLocalLocation(tz.UTC);
      debugPrint(
          '[NotificationService] Timezone detection failed: $e, using UTC');
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
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

    // Android 13+ runtime permission for notifications.
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidImpl != null) {
      final notifGranted = await androidImpl.requestNotificationsPermission();
      debugPrint(
          '[NotificationService] Notification permission granted: $notifGranted');

      final exactAlarmGranted =
          await androidImpl.requestExactAlarmsPermission();
      debugPrint(
          '[NotificationService] Exact alarm permission granted: $exactAlarmGranted');
    }

    await _ensureAndroidChannel();
    debugPrint('[NotificationService] Initialized successfully');
  }

  Future<void> _ensureAndroidChannel() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl == null) return;

    const channel = AndroidNotificationChannel(
      channelId,
      'Daily Nudge',
      description: 'A gentle daily check-in to negotiate a tiny step.',
      importance: Importance.high,
    );

    await androidImpl.createNotificationChannel(channel);
  }

  Future<void> cancelDailyNudge() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(dailyNudgeId);
      debugPrint('[NotificationService] Daily nudge cancelled');
    } catch (e) {
      debugPrint('[NotificationService] Cancel failed: $e');
    }
  }

  Future<void> scheduleDailyNudge({
    required TimeOfDay time,
    String? goal,
  }) async {
    if (kIsWeb) return;

    await cancelDailyNudge();

    final scheduledAt = _nextInstanceOf(time);
    debugPrint(
        '[NotificationService] Scheduling daily nudge for $scheduledAt (local: ${time.hour}:${time.minute})');

    final localeCode = WidgetsBinding
        .instance.platformDispatcher.locale.languageCode
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
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Prefer exact delivery on Android; fall back if the OS/device disallows it.
    try {
      await _plugin.zonedSchedule(
        dailyNudgeId,
        'Daily Nudge',
        message,
        scheduledAt,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('[NotificationService] Scheduled with exactAllowWhileIdle');
    } catch (e) {
      debugPrint(
          '[NotificationService] Exact scheduling failed: $e, trying inexact');
      try {
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
        debugPrint(
            '[NotificationService] Scheduled with inexactAllowWhileIdle');
      } catch (e2) {
        debugPrint('[NotificationService] All scheduling failed: $e2');
      }
    }
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
