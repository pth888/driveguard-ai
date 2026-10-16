// lib/services/profile_service.dart
//
// 백엔드 프로필 / 대시보드 연동
//   - GET /api/v1/profile          내 프로필 조회 (없으면 404)
//   - PUT /api/v1/profile          내 프로필 저장/수정 {display_name, phone?}
//   - GET /api/v1/dashboard        프로필 + 사고(case) 목록
//
// 모든 요청은 로그인 토큰(access_token)이 필요하며,
// auth_service 의 AuthNotifier.validAccessToken() 으로 유효 토큰을 얻어 사용한다.
// 응답은 {"data": {...}, "request_id": "..."} 형태로 감싸져 있다.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';

// ══════════════════════════════════════════════════════════
// 모델
// ══════════════════════════════════════════════════════════
class UserProfile {
  final String? id;
  final String? displayName;
  final String? phone;

  const UserProfile({this.id, this.displayName, this.phone});

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: j['id'] as String?,
        displayName: j['display_name'] as String?,
        phone: j['phone'] as String?,
      );
}

class CaseSummary {
  final String id;
  final String? title;
  final String? status;
  final double? lat;
  final double? lon;
  final String? capturedAt;
  final String? createdAt;

  const CaseSummary({
    required this.id,
    this.title,
    this.status,
    this.lat,
    this.lon,
    this.capturedAt,
    this.createdAt,
  });

  factory CaseSummary.fromJson(Map<String, dynamic> j) => CaseSummary(
        id: j['id'] as String,
        title: j['title'] as String?,
        status: j['status'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
        capturedAt: j['captured_at'] as String?,
        createdAt: j['created_at'] as String?,
      );
}

class DashboardData {
  final UserProfile? profile;
  final List<CaseSummary> cases;

  const DashboardData({this.profile, this.cases = const []});
}

// ══════════════════════════════════════════════════════════
// 서비스
// ══════════════════════════════════════════════════════════
class ProfileService {
  ProfileService(this._ref) {
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

  // ── 서버 연결 확인 (인증 불필요) ─────────────────────────
  // 백엔드 /health/live 는 토큰 없이 항상 열려 있어 연결 상태 확인에 사용.
  // true=서버 응답함, false=서버 꺼짐/네트워크 불가
  Future<bool> pingServer() async {
    try {
      final res = await _dio.get(
        '/health/live',
        options: Options(sendTimeout: const Duration(seconds: 4)),
      );
      return res.statusCode != null && res.statusCode! < 500;
    } catch (_) {
      return false;
    }
  }

  // 로그인 토큰을 Authorization 헤더로 붙인 Options 생성
  Future<Options?> _authOptions() async {
    final token =
        await _ref.read(authProvider.notifier).validAccessToken();
    if (token == null) return null;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // ── 프로필 조회 (없으면 null) ────────────────────────────
  Future<UserProfile?> fetchProfile() async {
    final opts = await _authOptions();
    if (opts == null) return null;
    try {
      final res = await _dio.get('/api/v1/profile', options: opts);
      if (res.statusCode == 200) {
        final p = res.data['data']['profile'] as Map<String, dynamic>;
        return UserProfile.fromJson(p);
      }
      // 404 = 아직 프로필 미생성
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── 프로필 저장/수정 ─────────────────────────────────────
  // display_name 은 필수(공백 불가). phone 은 선택.
  Future<UserProfile?> saveProfile({
    required String displayName,
    String? phone,
  }) async {
    final opts = await _authOptions();
    if (opts == null) return null;
    final name = displayName.trim();
    if (name.isEmpty) return null;
    try {
      final res = await _dio.put(
        '/api/v1/profile',
        data: {
          'display_name': name,
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        },
        options: opts,
      );
      if (res.statusCode == 200) {
        final p = res.data['data']['profile'] as Map<String, dynamic>;
        return UserProfile.fromJson(p);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── 대시보드 (프로필 + 사고 목록) ────────────────────────
  Future<DashboardData> fetchDashboard() async {
    final opts = await _authOptions();
    if (opts == null) return const DashboardData();
    try {
      final res = await _dio.get('/api/v1/dashboard', options: opts);
      if (res.statusCode == 200) {
        final data = res.data['data'] as Map<String, dynamic>;
        final profileJson = data['profile'];
        final casesJson = (data['cases'] as List?) ?? const [];
        return DashboardData(
          profile: profileJson == null
              ? null
              : UserProfile.fromJson(
                  Map<String, dynamic>.from(profileJson as Map)),
          cases: casesJson
              .map((c) => CaseSummary.fromJson(
                  Map<String, dynamic>.from(c as Map)))
              .toList(),
        );
      }
      return const DashboardData();
    } catch (_) {
      return const DashboardData();
    }
  }
}

// ── Provider ──────────────────────────────────────────────
final profileServiceProvider =
    Provider<ProfileService>((ref) => ProfileService(ref));
