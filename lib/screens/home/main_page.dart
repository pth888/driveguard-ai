// lib/screens/home/main_page.dart
// 테슬라 미니멀 스타일

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/sensor_service.dart';
import '../../services/location_service.dart';
import '../../utils/theme.dart';
import '../../widgets/accident_alert_dialog.dart';

class MainPage extends ConsumerStatefulWidget {
  const MainPage({super.key});

  @override
  ConsumerState<MainPage> createState() => _MainPageState();
}

class _MainPageState extends ConsumerState<MainPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(locationProvider.notifier).requestLocationAndFetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sensorState = ref.watch(sensorProvider);

    ref.listen<SensorState>(sensorProvider, (prev, next) {
      if (next.isImpactDetected && !(prev?.isImpactDetected ?? false)) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AccidentAlertDialog(
            gForce: next.currentGForce,
            onAccident: () {
              Navigator.pop(context);
              ref.read(sensorProvider.notifier).dismissAlert();
              context.pushNamed('accident-detected');
            },
            onDismiss: () {
              Navigator.pop(context);
              ref.read(sensorProvider.notifier).dismissAlert();
            },
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.bgBlack,
      body: SafeArea(
        child: Column(
          children: [
            // ── 상단 바 ────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'DRIVEGUARD',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),

            // ── 중앙: 보호 상태 ────────────────────────
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 원형 상태 아이콘
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: sensorState.isMonitoring
                              ? AppTheme.teslaRed
                              : AppTheme.textHint,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        sensorState.isMonitoring
                            ? Icons.shield_outlined
                            : Icons.gpp_bad_outlined,
                        color: sensorState.isMonitoring
                            ? AppTheme.teslaRed
                            : AppTheme.textHint,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 36),
                    Text(
                      sensorState.isMonitoring ? '보호 중' : '대기 중',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      sensorState.isMonitoring
                          ? '사고 감지 대기'
                          : '모니터링이 꺼져 있습니다',
                      style: const TextStyle(
                        color: AppTheme.textHint,
                        fontSize: 12,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── 하단 정보 (2개 수치) ──────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                children: [
                  Container(
                    height: 0.5,
                    color: AppTheme.divider,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildStat(
                        value: sensorState.currentGForce.toStringAsFixed(1),
                        unit: 'G',
                        label: '현재 충격',
                      ),
                      _buildStat(
                        value: '2.5',
                        unit: 'G',
                        label: '감지 임계값',
                        alignRight: false,
                      ),
                      _buildStat(
                        value: sensorState.isMonitoring ? 'ON' : 'OFF',
                        label: '모니터링',
                        alignRight: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── 사고 접수 버튼 (알약형) ────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: GestureDetector(
                onTap: () => context.pushNamed('accident-detected'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: AppTheme.pointWhite,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Center(
                    child: Text(
                      '사고 접수 시작',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── 하단 미니 메뉴 ────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMiniMenu(
                    icon: Icons.gavel_rounded,
                    label: '판례 검색',
                    onTap: () => context.pushNamed('verdict-library'),
                  ),
                  _buildMiniMenu(
                    icon: Icons.description_outlined,
                    label: '과실 분석 기록',
                    onTap: () => context.pushNamed('my-reports'),
                  ),
                  _buildMiniMenu(
                    icon: Icons.person_outline_rounded,
                    label: '내 정보',
                    onTap: () => context.pushNamed('mypage'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 수치 표시 ────────────────────────────────────────────
  Widget _buildStat({
    required String value,
    String? unit,
    required String label,
    bool alignRight = false,
  }) {
    return Column(
      crossAxisAlignment:
      alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w300,
                ),
              ),
              if (unit != null)
                TextSpan(
                  text: unit,
                  style: const TextStyle(
                    color: AppTheme.textSub,
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textHint,
            fontSize: 11,
            fontWeight: FontWeight.w300,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  // ── 미니 메뉴 ────────────────────────────────────────────
  Widget _buildMiniMenu({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.divider, width: 1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSub,
              fontSize: 11,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }
}