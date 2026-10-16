// lib/services/map_service.dart
//
// 사고 위치 지도 PNG 조회 (하드웨어 수집 서버: project-box.life)
//   GET /api/map/event?device_id={device_id}&event_id={event_id}
//
// 응답 필드
//   - map_image_url       : 경로 PNG 이미지 URL (GPS 없으면 null)
//   - map_image_has_route : 이동 경로 포함 여부 (좌표 1개면 지점만, 경로 없음)
//   - map_image_status    : 이미지 제공 상태
//
// 앱은 map_image_url 을 그대로 이미지로 표시하면 된다(경로 재계산 불필요).
// PDF 에도 같은 URL 의 PNG 를 받아 삽입한다.
//
// 유의사항(하드웨어팀 안내)
//   - 첫 조회 시 서버가 PNG 를 생성하고 이후 재사용한다.
//   - HTTP 503 이면 약 30초 후 재시도.
//   - HTTP 409 이면 사건 JSON 을 다시 조회(= 재요청)한다.
//   - 카카오맵 캡처가 아닌 OSM 도로 약도이므로 출처 표기(© OpenStreetMap)를 유지한다.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 하드웨어 수집 서버
const String _hardwareBaseUrl = 'https://project-box.life';
const String _hardwareToken = 'YOUR_HARDWARE_TOKEN';

// 503 재시도 간격 / 최대 재시도 횟수
const Duration _retryDelay = Duration(seconds: 30);
const int _maxRetries = 2; // 503/409 합산 재시도 상한(무한루프 방지)

// ── 지도 PNG 결과 ─────────────────────────────────────────
class AccidentMapImage {
  final String? imageUrl; // 절대 URL (없으면 null = GPS 없음)
  final bool hasRoute; // 이동 경로 포함 여부
  final String status; // 서버가 내려준 상태 문자열

  const AccidentMapImage({
    required this.imageUrl,
    required this.hasRoute,
    required this.status,
  });

  // 서버 상태값(available/ready = 표시 가능, disabled/unavailable/no_gps = 불가)
  bool get available =>
      imageUrl != null &&
      imageUrl!.isNotEmpty &&
      status != 'disabled' &&
      status != 'unavailable' &&
      status != 'no_gps';

  // 상태별 안내 문구 (URL 이 없을 때 사용자에게 보여줄 메시지)
  String get unavailableReason {
    switch (status) {
      case 'no_gps':
        return '위치 정보(GPS)가 없는 사고입니다';
      case 'disabled':
        return '지도 기능이 비활성화되어 있습니다';
      case 'unavailable':
        return '지도를 생성할 수 없습니다';
      default:
        return '위치 정보가 없습니다';
    }
  }

  factory AccidentMapImage.fromJson(Map<String, dynamic> json) {
    // 응답이 {"data": {...}} envelope 로 올 수도, 평탄하게 올 수도 있어 둘 다 대응
    final root = (json['data'] is Map)
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;

    final rawUrl = root['map_image_url'] as String?;
    final url = (rawUrl == null || rawUrl.isEmpty)
        ? null
        : (rawUrl.startsWith('http') ? rawUrl : '$_hardwareBaseUrl$rawUrl');

    return AccidentMapImage(
      imageUrl: url,
      hasRoute: root['map_image_has_route'] == true,
      status: (root['map_image_status'] ?? 'unknown').toString(),
    );
  }

  // GPS 없음(=제공 불가) 상태
  static const AccidentMapImage none = AccidentMapImage(
    imageUrl: null,
    hasRoute: false,
    status: 'no_gps',
  );
}

// 이미지가 아직 생성 중임을 나타내는 예외 (503 소진 시)
class MapImagePendingException implements Exception {
  final String message;
  MapImagePendingException([this.message = '지도 이미지를 생성하는 중입니다.']);
  @override
  String toString() => message;
}

class MapService {
  MapService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _hardwareBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Authorization': 'Bearer $_hardwareToken',
          'User-Agent': 'Blackbox-Collector/1.0',
        },
        // 503/409 를 직접 처리하기 위해 5xx/4xx 도 예외로 던지지 않고 받아본다
        validateStatus: (code) => code != null && code < 600,
      ),
    );
  }

  late final Dio _dio;

  // ── 사고 위치 지도 PNG 조회 ─────────────────────────────
  // 503 → 30초 후 재시도, 409 → 재조회. 둘 다 _maxRetries 회까지.
  // GPS 가 없어 URL 이 null 이면 AccidentMapImage.none 반환.
  Future<AccidentMapImage> fetchEventMap({
    required String deviceId,
    required String eventId,
  }) async {
    if (deviceId.isEmpty || eventId.isEmpty) {
      return AccidentMapImage.none;
    }

    var attempt = 0;
    while (true) {
      final res = await _dio.get(
        '/api/map/event',
        queryParameters: {'device_id': deviceId, 'event_id': eventId},
      );
      final code = res.statusCode ?? 0;

      // 정상
      if (code == 200) {
        final data = res.data;
        if (data is Map<String, dynamic>) {
          return AccidentMapImage.fromJson(data);
        }
        return AccidentMapImage.none;
      }

      // 503: 일시 혼잡/렌더 중 → retry_after_seconds(기본 30) 후 재시도
      if (code == 503 && attempt < _maxRetries) {
        attempt++;
        final retryAfter = _retryAfterFrom(res.data);
        await Future.delayed(retryAfter);
        continue;
      }

      // 409: 입력 변경 → 사건 재조회
      if (code == 409 && attempt < _maxRetries) {
        attempt++;
        continue;
      }

      // 503 재시도 소진 → 생성 중 예외
      if (code == 503) {
        throw MapImagePendingException();
      }

      // 422: 유효 GPS 없음 → 위치 정보 없음
      if (code == 422) {
        return AccidentMapImage.none;
      }

      // 404(알 수 없는 사건) 등 그 외 → 제공 불가
      return const AccidentMapImage(
        imageUrl: null,
        hasRoute: false,
        status: 'unavailable',
      );
    }
  }

  // 503 응답 본문의 retry_after_seconds 를 읽는다(없으면 기본 30초).
  Duration _retryAfterFrom(dynamic data) {
    try {
      if (data is Map) {
        final sec = data['retry_after_seconds'];
        if (sec is num && sec > 0) {
          return Duration(seconds: sec.toInt());
        }
      }
    } catch (_) {}
    return _retryDelay;
  }
}

// ── Provider ──────────────────────────────────────────────
final mapServiceProvider = Provider<MapService>((ref) => MapService());
