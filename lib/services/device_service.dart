// lib/services/device_service.dart
//
// 블랙박스 기기 연결 (데모: 주소 + device_id 연결 방식)
//
// 하드웨어팀 안내:
//   - 수집 서버: https://project-box.life
//   - 기기 식별자: 전방 violet-dashcam-1 / 후방 violet-dashcam-2
//   - 계정 서버에서 account_id + server_url + device_id 를 연결한다.
//     (MAC 이나 event_id 로 연결하는 방식이 아니다. event_id 는 개별 사고 ID.)
//   - 사용자가 Pi 통신용 토큰을 따로 입력할 필요는 없다.
//   - 단, device_id 자체는 소유권 증명 수단이 아니므로
//     계정 연결 권한은 앱 백엔드에서 확인해야 한다.
//
// 구현 방침(데모):
//   - 연결 정보(server_url + device_id + 전/후방 + 이름)를 secure_storage 에 저장한다.
//     이 저장값만으로 영상/지도 조회가 동작한다(백엔드 없이도).
//   - 앱 백엔드에 계정-기기 연결을 등록 시도하되, 엔드포인트가 아직 없거나
//     실패하더라도 조용히 넘어간다(데모 안정성). 백엔드 스펙이 확정되면
//     _registerOnBackend 본문만 채우면 자동 연동된다.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_service.dart';

// 수집 서버 주소
const String kCollectorServerUrl = 'https://project-box.life';

// 전/후방 기기 식별자
const String kDeviceIdFront = 'violet-dashcam-1';
const String kDeviceIdRear = 'violet-dashcam-2';

// 전/후방 구분
enum DevicePosition { front, rear }

extension DevicePositionX on DevicePosition {
  String get deviceId =>
      this == DevicePosition.front ? kDeviceIdFront : kDeviceIdRear;
  String get label => this == DevicePosition.front ? '전방' : '후방';
  String get code => this == DevicePosition.front ? 'front' : 'rear';

  static DevicePosition fromDeviceId(String id) =>
      id == kDeviceIdRear ? DevicePosition.rear : DevicePosition.front;
  static DevicePosition fromCode(String? code) =>
      code == 'rear' ? DevicePosition.rear : DevicePosition.front;
}

// secure_storage 키
const _kDeviceIdKey = 'registered_device_id';
const _kDeviceNameKey = 'registered_device_name';
const _kServerUrlKey = 'registered_server_url';
const _kPositionKey = 'registered_device_position'; // 'front' | 'rear'

// 저장된 기기 연결 정보
class ConnectedDevice {
  final String deviceId; // violet-dashcam-1 / -2
  final String deviceName; // 사용자가 붙인 이름
  final String serverUrl; // https://project-box.life
  final DevicePosition position;

  const ConnectedDevice({
    required this.deviceId,
    required this.deviceName,
    required this.serverUrl,
    required this.position,
  });
}

class DeviceService {
  DeviceService(this._ref) {
    _dio = Dio(BaseOptions(
      baseUrl: kApiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
      validateStatus: (code) => code != null && code < 600,
    ));
  }

  final Ref _ref;
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  // ── 저장된(연결된) 기기 조회 ────────────────────────────
  Future<ConnectedDevice?> savedDevice() async {
    try {
      final id = await _storage.read(key: _kDeviceIdKey);
      if (id == null || id.isEmpty) return null;
      final name = await _storage.read(key: _kDeviceNameKey) ?? '내 블랙박스';
      final server =
          await _storage.read(key: _kServerUrlKey) ?? kCollectorServerUrl;
      final pos =
          await _storage.read(key: _kPositionKey);
      return ConnectedDevice(
        deviceId: id,
        deviceName: name,
        serverUrl: server,
        position: DevicePositionX.fromCode(pos),
      );
    } catch (_) {
      return null;
    }
  }

  // ── 기기 연결 (주소 + device_id) ─────────────────────────
  // position(전/후방)으로 device_id 를 결정하고 연결 정보를 로컬에 저장한다.
  // 백엔드 계정-기기 연결은 시도하되 실패해도 저장은 유지한다.
  Future<ConnectedDevice?> connectDevice({
    required String name,
    required DevicePosition position,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    final deviceId = position.deviceId;

    // 1) 로컬 저장 (이게 메인 — 영상/지도 조회가 이 값으로 동작)
    try {
      await _storage.write(key: _kDeviceIdKey, value: deviceId);
      await _storage.write(key: _kDeviceNameKey, value: trimmed);
      await _storage.write(key: _kServerUrlKey, value: kCollectorServerUrl);
      await _storage.write(key: _kPositionKey, value: position.code);
    } catch (_) {
      return null; // 로컬 저장조차 실패하면 연결 실패로 간주
    }

    // 2) 앱 백엔드에 계정-기기 연결 등록 (보조 — 실패해도 무시)
    await _registerOnBackend(
      deviceId: deviceId,
      serverUrl: kCollectorServerUrl,
      position: position,
    );

    return ConnectedDevice(
      deviceId: deviceId,
      deviceName: trimmed,
      serverUrl: kCollectorServerUrl,
      position: position,
    );
  }

  // ── 앱 백엔드 계정-기기 연결 등록 (보조) ─────────────────
  // 백엔드가 account_id + server_url + device_id 를 받는 엔드포인트가
  // 확정되면 이 본문을 그에 맞게 채운다. 지금은 시도 후 실패를 무시한다.
  Future<void> _registerOnBackend({
    required String deviceId,
    required String serverUrl,
    required DevicePosition position,
  }) async {
    try {
      final access =
          await _ref.read(authProvider.notifier).validAccessToken();
      if (access == null) return;

      // NOTE: 백엔드 엔드포인트/바디 스펙 확정 시 교체.
      //   account_id 는 토큰에서 서버가 식별(앱이 보낼 필요 없음).
      await _dio.post(
        '/api/v1/devices/link',
        data: {
          'server_url': serverUrl,
          'device_id': deviceId,
          'position': position.code, // front | rear
        },
        options: Options(headers: {'Authorization': 'Bearer $access'}),
      );
      // 응답 코드 검사 없음 — 데모에서는 로컬 저장을 신뢰한다.
    } catch (_) {
      // 엔드포인트 미구현/네트워크 오류 → 무시 (로컬 연결은 유효)
    }
  }

  // ── 연결 해제 ────────────────────────────────────────────
  Future<void> unregister() async {
    await clearLocal();
    // 백엔드 연결 해제 엔드포인트가 확정되면 여기서 호출.
  }

  Future<void> clearLocal() async {
    try {
      await _storage.delete(key: _kDeviceIdKey);
      await _storage.delete(key: _kDeviceNameKey);
      await _storage.delete(key: _kServerUrlKey);
      await _storage.delete(key: _kPositionKey);
    } catch (_) {}
  }
}

// ── Provider ──────────────────────────────────────────────
final deviceServiceProvider =
    Provider<DeviceService>((ref) => DeviceService(ref));
