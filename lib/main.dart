// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

import 'router/app_router.dart';
import 'services/sensor_service.dart';
import 'services/push_service.dart';
import 'services/auth_service.dart';
import 'utils/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 초기화 (FCM 푸시 알림)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 백그라운드/종료 상태 FCM 메시지 핸들러 등록 (최상위 함수)
  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

  runApp(
    // ProviderScope: Riverpod 전역 상태 컨테이너
    const ProviderScope(
      child: BlackboxApp(),
    ),
  );
}

class BlackboxApp extends ConsumerStatefulWidget {
  const BlackboxApp({super.key});

  @override
  ConsumerState<BlackboxApp> createState() => _BlackboxAppState();
}

class _BlackboxAppState extends ConsumerState<BlackboxApp> {
  bool _pushWired = false;

  @override
  void initState() {
    super.initState();

    // 사고 푸시 수신 → 블박(외부) 트리거로 사고 동작 연결
    final push = ref.read(pushServiceProvider);
    push.onAccidentPush = (accident) {
      ref.read(sensorProvider.notifier).triggerFromExternal(
            lat: accident.lat,
            lon: accident.lon,
            gForce: accident.gForce,
          );
    };
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    // 로그인(authenticated) 되면 FCM 초기화 + 토큰 등록을 1회 수행.
    // (로그인 전에는 백엔드 토큰 등록이 거부되므로 인증 후에 등록한다.)
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.status == AuthStatus.authenticated && !_pushWired) {
        _pushWired = true;
        ref.read(pushServiceProvider).initialize();
      }
      // 로그아웃 시 다음 로그인에서 다시 등록되도록 플래그 해제
      if (next.status == AuthStatus.unauthenticated) {
        _pushWired = false;
      }
    });

    return MaterialApp.router(
      title: 'DriveGuard AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      //darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
