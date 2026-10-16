// lib/services/auth_service.dart
//
// 백엔드 인증 연동 (회원가입 / 로그인 / 토큰 저장 / 자동 갱신)
//   - POST /api/v1/auth/signup   {email, name, password}
//   - POST /api/v1/auth/login    {email, password} -> {access_token, refresh_token}
//   - POST /api/v1/auth/refresh  {refresh_token}    -> 새 토큰쌍
//   - GET  /api/v1/auth/me        (Authorization: Bearer access_token)
//
// 응답은 {"data": {...}, "request_id": "..."} 형태로 감싸져 있음.
//
// 사용 패키지: dio, flutter_secure_storage, flutter_riverpod

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ── 백엔드 API 서버 주소 ──────────────────────────────────
// 로컬 Docker 백엔드: 안드로이드 에뮬레이터에서는 10.0.2.2 로 접근
// (서버 배포 주소가 생기면 이 한 줄만 교체)
const String kApiBaseUrl = 'http://10.0.2.2:8000';

// ── 토큰 저장 키 ──────────────────────────────────────────
const _kAccessKey = 'auth_access_token';
const _kRefreshKey = 'auth_refresh_token';

// ══════════════════════════════════════════════════════════
// 인증 상태
// ══════════════════════════════════════════════════════════
enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? email;
  final String? name;
  final bool isBusy;
  final String? error;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.email,
    this.name,
    this.isBusy = false,
    this.error,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? email,
    String? name,
    bool? isBusy,
    String? error,
  }) =>
      AuthState(
        status: status ?? this.status,
        email: email ?? this.email,
        name: name ?? this.name,
        isBusy: isBusy ?? this.isBusy,
        error: error,
      );
}

// ══════════════════════════════════════════════════════════
// 인증 Notifier
// ══════════════════════════════════════════════════════════
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _dio = Dio(BaseOptions(
      baseUrl: kApiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
      // 4xx 도 예외로 던지지 않고 직접 처리
      validateStatus: (code) => code != null && code < 500,
    ));
    _restoreSession();
  }

  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  String? _accessToken;
  String? _refreshToken;

  String? get accessToken => _accessToken;

  // 저장된 토큰으로 세션 복원 (앱 시작 시)
  Future<void> _restoreSession() async {
    try {
      _accessToken = await _storage.read(key: _kAccessKey);
      _refreshToken = await _storage.read(key: _kRefreshKey);
    } catch (_) {}

    if (_accessToken == null && _refreshToken == null) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }
    // me 조회로 토큰 유효성 확인 (만료면 refresh 시도)
    final ok = await _fetchMe();
    if (!ok) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        await _fetchMe();
      } else {
        await _clearTokens();
        state = state.copyWith(status: AuthStatus.unauthenticated);
      }
    }
  }

  // ── 회원가입 ────────────────────────────────────────────
  Future<bool> signup({
    required String email,
    required String name,
    required String password,
  }) async {
    state = state.copyWith(isBusy: true, error: null);
    try {
      final res = await _dio.post('/api/v1/auth/signup', data: {
        'email': email.trim().toLowerCase(),
        'name': name.trim(),
        'password': password,
      });
      if (res.statusCode == 201) {
        // 가입 성공 → 바로 로그인
        return await login(email: email, password: password);
      }
      state = state.copyWith(
        isBusy: false,
        error: _errorMessage(res, '회원가입에 실패했습니다.'),
      );
      return false;
    } catch (e) {
      state = state.copyWith(isBusy: false, error: '서버에 연결할 수 없습니다.');
      return false;
    }
  }

  // ── 로그인 ──────────────────────────────────────────────
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isBusy: true, error: null);
    try {
      final res = await _dio.post('/api/v1/auth/login', data: {
        'email': email.trim().toLowerCase(),
        'password': password,
      });
      if (res.statusCode == 200) {
        final data = res.data['data'] as Map<String, dynamic>;
        await _saveTokens(
          data['access_token'] as String,
          data['refresh_token'] as String,
        );
        await _fetchMe();
        state = state.copyWith(isBusy: false, error: null);
        return true;
      }
      state = state.copyWith(
        isBusy: false,
        error: _errorMessage(res, '이메일 또는 비밀번호를 확인해 주세요.'),
      );
      return false;
    } catch (e) {
      state = state.copyWith(isBusy: false, error: '서버에 연결할 수 없습니다.');
      return false;
    }
  }

  // ── 로그아웃 ────────────────────────────────────────────
  Future<void> logout() async {
    try {
      if (_refreshToken != null) {
        await _dio.post('/api/v1/auth/logout',
            data: {'refresh_token': _refreshToken});
      }
    } catch (_) {}
    await _clearTokens();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  // ── 내 정보 조회 (토큰 유효성 확인) ──────────────────────
  Future<bool> _fetchMe() async {
    if (_accessToken == null) return false;
    try {
      final res = await _dio.get(
        '/api/v1/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
      );
      if (res.statusCode == 200) {
        final user = res.data['data']['user'] as Map<String, dynamic>;
        state = state.copyWith(
          status: AuthStatus.authenticated,
          email: user['email'] as String?,
          name: user['name'] as String?,
        );
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ── 토큰 갱신 ───────────────────────────────────────────
  Future<bool> _tryRefresh() async {
    if (_refreshToken == null) return false;
    try {
      final res = await _dio.post('/api/v1/auth/refresh',
          data: {'refresh_token': _refreshToken});
      if (res.statusCode == 200) {
        final data = res.data['data'] as Map<String, dynamic>;
        await _saveTokens(
          data['access_token'] as String,
          data['refresh_token'] as String,
        );
        return true;
      }
    } catch (_) {}
    return false;
  }

  // 외부(다른 서비스)에서 인증 요청 보낼 때 쓸 수 있는 헬퍼:
  // 저장된 access token 을 그대로 반환한다.
  //
  // NOTE: 예전에는 여기서 _fetchMe() 를 호출해 토큰을 검증했는데,
  //       _fetchMe() 가 전역 auth 상태(state)를 갱신하면서 라우터 redirect 가
  //       재평가되어 화면(마이페이지 등)이 즉시 튕기는 문제가 있었다.
  //       토큰 유효성은 실제 API 호출이 401 을 받을 때 처리하면 되므로,
  //       여기서는 상태를 건드리지 않고 토큰만 반환한다.
  Future<String?> validAccessToken() async {
    return _accessToken;
  }

  // ── 토큰 저장/삭제 ──────────────────────────────────────
  Future<void> _saveTokens(String access, String refresh) async {
    _accessToken = access;
    _refreshToken = refresh;
    try {
      await _storage.write(key: _kAccessKey, value: access);
      await _storage.write(key: _kRefreshKey, value: refresh);
    } catch (_) {}
  }

  Future<void> _clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    try {
      await _storage.delete(key: _kAccessKey);
      await _storage.delete(key: _kRefreshKey);
    } catch (_) {}
  }

  String _errorMessage(Response res, String fallback) {
    try {
      final err = res.data['error'];
      if (err is Map && err['message'] is String) {
        return err['message'] as String;
      }
      final msg = res.data['message'];
      if (msg is String) return msg;
    } catch (_) {}
    return fallback;
  }
}

// ── Provider ──────────────────────────────────────────────
final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());
