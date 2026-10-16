// lib/services/notification_service.dart
//
// 사용 패키지:
//   flutter_local_notifications: ^17.1.2
//   firebase_messaging: ^14.7.19

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // ── 초기화 (main.dart에서 호출) ──────────────────────────
  static Future<void> initialize() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
  }

  // ── 충격 감지 긴급 알림 ──────────────────────────────────
  static Future<void> showImpactAlert({required double gForce}) async {
    const androidDetails = AndroidNotificationDetails(
      'impact_channel',
      '충격 감지 알림',
      channelDescription: '사고 충격 감지 시 표시되는 긴급 알림',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,        // 잠금화면에서도 전체 화면으로 표시
      sound: RawResourceAndroidNotificationSound('emergency_alert'),
    );

    await _plugin.show(
      0,
      '⚠️ 충격이 감지되었습니다',
      '사고가 발생했나요? (G-Force: ${gForce.toStringAsFixed(1)}G)\n10초 후 자동으로 신고됩니다.',
      const NotificationDetails(android: androidDetails),
    );
  }

  // ── AI 분석 완료 알림 ────────────────────────────────────
  static Future<void> showAnalysisComplete({
    required String accidentId,
    required double faultRatio,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'analysis_channel',
      'AI 분석 알림',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _plugin.show(
      1,
      '📊 AI 과실 분석이 완료되었습니다',
      '예상 과실 비율: ${(faultRatio * 100).toStringAsFixed(0)}% | 리포트를 확인하세요',
      const NotificationDetails(android: androidDetails),
    );
  }
}
