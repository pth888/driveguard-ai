// lib/services/push_service.dart
//
// FCM(원격 푸시) 수신 + 백엔드 토큰 등록
//
// 역할:
//   1) firebase_messaging 으로 이 기기의 FCM 토큰을 얻는다.
//   2) 얻은 토큰을 백엔드에 등록한다:  PUT /api/v1/push/tokens
//        { "provider": "fcm", "token": "...", "device_label": "..." }
//   3) 블랙박스가 사고를 감지하면 백엔드가 이 기기로 푸시를 보낸다.
//      그 푸시를 수신하면( data.type == "accident" ) 사고 트리거 콜백을 호출한다.
//
// 흐름:  블박(충격 감지) → 백엔드 /device-events → FCM 푸시 → 이 서비스 수신
//                                                             → onAccidentPush 콜백
//                                                             → SensorNotifier.triggerFromExternal()
//
// 사용 패키지: firebase_messaging, dio, flutter_riverpod
//   (firebase_core / firebase_options 는 이미 main.dart 에서 초기화됨)
//
// NOTE: 서버 쪽 FCM 발송이 아직 Mock 이면 실제 푸시는 오지 않는다.
//       앱 구조는 완성해 두고, 서버가 실제 발송을 켜면 바로 동작한다.

import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';

// 사고 푸시가 왔을 때 전달되는 정보
class AccidentPush {
  final double? lat;
  final double? lon;
  final String? caseId;
  final double? gForce;

  const AccidentPush({this.lat, this.lon, this.caseId, this.gForce});

  factory AccidentPush.fromData(Map<String, dynamic> data) {
    double? toD(dynamic v) =>
        v == null ? null : double.tryParse(v.toString());
    return AccidentPush(
      lat: toD(data['lat']),
      lon: toD(data['lon']),
      caseId: data['case_id']?.toString(),
      gForce: toD(data['g_force'] ?? data['gforce']),
    );
  }
}

// 백그라운드(앱 종료/백그라운드 상태) 메시지 핸들러.
// 반드시 최상위 함수여야 한다. (firebase_messaging 요구사항)
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // 백그라운드에서는 UI 트리거가 어려우므로, 시스템 알림 표시는
  // 서버가 notification 페이로드로 함께 보내면 OS가 자동 표시한다.
  // 여기서는 별도 처리 없이 둔다. (앱을 열면 onMessageOpenedApp 로 이어짐)
}

class PushService {
  PushService(this._ref) {
    _dio = Dio(BaseOptions(
      baseUrl: kApiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
      validateStatus: (code) => code != null && code < 500,
    ));
  }

  final Ref _ref;
  late final Dio _dio;
  final _fcm = FirebaseMessaging.instance;

  bool _initialized = false;

  // 사고 푸시 수신 시 호출될 콜백 (main 에서 sensor 트리거로 연결)
  void Function(AccidentPush push)? onAccidentPush;

  // ── 초기화: 권한 요청 → 토큰 등록 → 수신 리스너 연결 ──────
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 1) 알림 권한 요청 (iOS 필수, Android 13+ 권장)
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    // 2) 토큰 얻어 백엔드 등록
    await registerToken();

    // 3) 토큰 갱신 시 재등록
    _fcm.onTokenRefresh.listen((token) {
      _sendTokenToBackend(token);
    });

    // 4) 포그라운드 수신
    FirebaseMessaging.onMessage.listen(_handleMessage);

    // 5) 백그라운드 상태에서 알림을 눌러 앱이 열린 경우
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

    // 6) 앱이 완전히 종료된 상태에서 알림으로 실행된 경우
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _handleMessage(initial);
  }

  // ── 현재 기기의 FCM 토큰을 얻어 백엔드에 등록 ────────────
  Future<void> registerToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _sendTokenToBackend(token);
      }
    } catch (_) {
      // 토큰 획득 실패(에뮬레이터에 Google Play 없음 등) 시 조용히 패스
    }
  }

  Future<void> _sendTokenToBackend(String token) async {
    final access =
        await _ref.read(authProvider.notifier).validAccessToken();
    if (access == null) return; // 로그인 안 돼 있으면 등록 보류

    // Android=fcm, iOS=apns. 현재 FCM 토큰이므로 Android 는 fcm 그대로,
    // iOS 도 firebase_messaging 사용 시 fcm 토큰을 쓰도록 fcm 로 등록한다.
    final provider = Platform.isIOS ? 'apns' : 'fcm';
    final label = Platform.isIOS ? 'iOS device' : 'Android device';
    try {
      await _dio.put(
        '/api/v1/push/tokens',
        data: {
          'provider': provider,
          'token': token,
          'device_label': label,
        },
        options: Options(headers: {'Authorization': 'Bearer $access'}),
      );
    } catch (_) {
      // 등록 실패는 치명적이지 않음(다음 갱신/재시도 때 다시 보냄)
    }
  }

  // ── 수신 메시지 처리 ─────────────────────────────────────
  void _handleMessage(RemoteMessage message) {
    final data = message.data;
    final type = (data['type'] ?? '').toString();
    // 사고 관련 푸시만 트리거. (분석완료 등 다른 타입은 무시 or 추후 확장)
    if (type == 'accident' || type == 'impact' || type == 'device_event') {
      onAccidentPush?.call(AccidentPush.fromData(data));
    }
  }
}

// ── Provider ──────────────────────────────────────────────
final pushServiceProvider =
    Provider<PushService>((ref) => PushService(ref));
