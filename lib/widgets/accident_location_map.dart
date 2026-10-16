// lib/widgets/accident_location_map.dart
//
// 사고 위치 지도 — 영상 아래에 표시.
// 하드웨어 수집 서버가 생성한 OSM 도로 약도 PNG(map_image_url)를 받아 그대로 보여준다.
// 앱에서 지도를 다시 그리지 않는다(flutter_map 불필요).
//
//   GET /api/map/event?device_id=&event_id=  →  map_image_url (PNG)
//
// device_id + event_id 로 PNG 를 조회하고, 좌표/시각 텍스트와
// 카카오맵·로드뷰 외부 링크를 함께 보여준다.
//
// 사용 패키지: dio(map_service)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/map_service.dart';
import '../utils/theme.dart';

class AccidentLocationMap extends ConsumerStatefulWidget {
  final String deviceId;
  final String eventId;
  final double? latitude; // 좌표 텍스트 표시용(선택)
  final double? longitude;
  final String? capturedAtLabel; // 사고 시각 표시용(선택)
  final double? speedKmh; // 속도(선택)

  // /api/events 응답에 이미 들어온 지도 PNG 정보(있으면 재조회 생략)
  final String? prefetchedUrl;
  final bool prefetchedHasRoute;
  final String? prefetchedStatus;

  const AccidentLocationMap({
    super.key,
    required this.deviceId,
    required this.eventId,
    this.latitude,
    this.longitude,
    this.capturedAtLabel,
    this.speedKmh,
    this.prefetchedUrl,
    this.prefetchedHasRoute = false,
    this.prefetchedStatus,
  });

  @override
  ConsumerState<AccidentLocationMap> createState() =>
      _AccidentLocationMapState();
}

class _AccidentLocationMapState extends ConsumerState<AccidentLocationMap> {
  late Future<AccidentMapImage> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  // 이벤트에 PNG URL 이 이미 있으면 그걸 쓰고, 없으면 서버에서 조회한다.
  Future<AccidentMapImage> _load() {
    final url = widget.prefetchedUrl;
    final status = widget.prefetchedStatus;
    final usable = url != null &&
        url.isNotEmpty &&
        status != 'disabled' &&
        status != 'unavailable' &&
        status != 'no_gps';
    if (usable) {
      return Future.value(AccidentMapImage(
        imageUrl: url,
        hasRoute: widget.prefetchedHasRoute,
        status: status ?? 'available',
      ));
    }
    return ref.read(mapServiceProvider).fetchEventMap(
          deviceId: widget.deviceId,
          eventId: widget.eventId,
        );
  }

  void _reload() {
    setState(() {
      // 재시도는 항상 서버 조회(prefetch 무시)
      _future = ref.read(mapServiceProvider).fetchEventMap(
            deviceId: widget.deviceId,
            eventId: widget.eventId,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 지도 PNG ──────────────────────────────
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 200,
            width: double.infinity,
            child: FutureBuilder<AccidentMapImage>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return _loadingBox();
                }
                if (snap.hasError) {
                  final pending = snap.error is MapImagePendingException;
                  return _messageBox(
                    pending ? '지도 이미지를 생성하는 중입니다' : '지도를 불러올 수 없습니다',
                    showRetry: true,
                  );
                }
                final map = snap.data;
                if (map == null || !map.available) {
                  return _messageBox(
                      map?.unavailableReason ?? '위치 정보가 없습니다');
                }
                return _mapImage(map);
              },
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ── 좌표 / 속도 ────────────────────────────
        if (widget.latitude != null && widget.longitude != null)
          Row(
            children: [
              const Icon(Icons.my_location_rounded,
                  size: 14, color: AppTheme.textSub),
              const SizedBox(width: 6),
              Text(
                '${widget.latitude!.toStringAsFixed(6)}, '
                '${widget.longitude!.toStringAsFixed(6)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const Spacer(),
              if (widget.speedKmh != null)
                Text(
                  '${widget.speedKmh!.toStringAsFixed(1)} km/h',
                  style: const TextStyle(
                    color: AppTheme.textSub,
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                  ),
                ),
            ],
          ),
        if (widget.capturedAtLabel != null) ...[
          const SizedBox(height: 4),
          Text(
            '사고 시각 · ${widget.capturedAtLabel}',
            style: const TextStyle(
              color: AppTheme.textHint,
              fontSize: 11,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ],
    );
  }

  // ── 지도 PNG 이미지 (+ OSM 출처 표기) ────────────────────
  Widget _mapImage(AccidentMapImage map) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          map.imageUrl!,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return _loadingBox();
          },
          errorBuilder: (context, _, __) =>
              _messageBox('지도를 불러올 수 없습니다', showRetry: true),
        ),
        // OSM 저작권 표기 (카카오 캡처가 아닌 OSM 약도이므로 유지)
        Positioned(
          right: 6,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            color: Colors.white70,
            child: const Text(
              '© OpenStreetMap',
              style: TextStyle(fontSize: 9, color: Colors.black54),
            ),
          ),
        ),
        // 경로 포함 뱃지
        if (map.hasRoute)
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '이동 경로 포함',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _loadingBox() {
    return Container(
      color: AppTheme.surfaceDark,
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.teslaRed,
          ),
        ),
      ),
    );
  }

  Widget _messageBox(String msg, {bool showRetry = false}) {
    return Container(
      color: AppTheme.surfaceDark,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, color: AppTheme.textHint, size: 32),
            const SizedBox(height: 10),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSub,
                fontSize: 12,
                fontWeight: FontWeight.w300,
              ),
            ),
            if (showRetry) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _reload,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.divider),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Text(
                    '다시 시도',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
