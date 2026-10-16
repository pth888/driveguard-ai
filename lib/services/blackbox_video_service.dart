// lib/services/blackbox_video_service.dart
//
// 블랙박스 영상 다운로드 및 재생 (project-box.life)
//   - GET /api/events 로 이벤트 목록 조회
//   - video_file_url 로 영상 다운로드
//   - model_analysis_file_url 로 AI 분석 결과 조회

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

// ── 하드웨어 서버 설정 ────────────────────────────────────
// 보안을 위해 실제 토큰은 저장소에 올리지 않음. 실행 전 본인 토큰으로 교체.
const String _hardwareBaseUrl = 'https://project-box.life';
const String _hardwareToken = 'YOUR_HARDWARE_TOKEN';

// ── 블랙박스 이벤트 모델 ─────────────────────────────────
class BlackboxEvent {
  final String deviceId;
  final String eventId;
  final DateTime? triggerUtc;
  final String? triggerKst;
  final double? lat;
  final double? lon;
  final String videoFileUrl;
  final String? webVideoFileUrl;
  final String? metadataFileUrl;
  final String? modelAnalysisUrl;
  // 서버가 /api/events 응답에 함께 내려주는 경로 PNG 정보
  // (JSON 이 영상보다 늦으면 null 일 수 있어, 그 경우 map_service 로 재조회)
  final String? mapImageUrl;
  final bool mapImageHasRoute;
  final String? mapImageStatus;

  BlackboxEvent({
    required this.deviceId,
    required this.eventId,
    this.triggerUtc,
    this.triggerKst,
    this.lat,
    this.lon,
    required this.videoFileUrl,
    this.webVideoFileUrl,
    this.metadataFileUrl,
    this.modelAnalysisUrl,
    this.mapImageUrl,
    this.mapImageHasRoute = false,
    this.mapImageStatus,
  });

  factory BlackboxEvent.fromJson(Map<String, dynamic> json) {
    final gps = json['gps'] as Map<String, dynamic>?;
    final rawMapUrl = json['map_image_url'] as String?;
    return BlackboxEvent(
      deviceId: (json['device_id'] ?? '') as String,
      eventId: (json['event_id'] ?? '') as String,
      triggerUtc: json['trigger_utc'] != null
          ? DateTime.tryParse(json['trigger_utc'] as String)
          : null,
      triggerKst: json['trigger_kst'] as String?,
      lat: (gps?['lat'] as num?)?.toDouble(),
      lon: (gps?['lon'] as num?)?.toDouble(),
      videoFileUrl: (json['video_file_url'] ?? '') as String,
      webVideoFileUrl: json['web_video_file_url'] as String?,
      metadataFileUrl: json['metadata_file_url'] as String?,
      modelAnalysisUrl: json['model_analysis_file_url'] as String?,
      mapImageUrl: (rawMapUrl == null || rawMapUrl.isEmpty) ? null : rawMapUrl,
      mapImageHasRoute: json['map_image_has_route'] == true,
      mapImageStatus: json['map_image_status'] as String?,
    );
  }
}

// ── 영상 상태 ────────────────────────────────────────────
enum VideoStatus { waiting, fetching, downloading, ready, error }

class BlackboxVideoState {
  final VideoStatus status;
  final BlackboxEvent? event;
  final String? localPath;
  final double downloadProgress;
  final String? errorMessage;

  const BlackboxVideoState({
    this.status = VideoStatus.waiting,
    this.event,
    this.localPath,
    this.downloadProgress = 0.0,
    this.errorMessage,
  });

  BlackboxVideoState copyWith({
    VideoStatus? status,
    BlackboxEvent? event,
    String? localPath,
    double? downloadProgress,
    String? errorMessage,
  }) =>
      BlackboxVideoState(
        status: status ?? this.status,
        event: event ?? this.event,
        localPath: localPath ?? this.localPath,
        downloadProgress: downloadProgress ?? this.downloadProgress,
        errorMessage: errorMessage,
      );

  String get progressPercent => '${(downloadProgress * 100).toInt()}%';
}

// ── Notifier ─────────────────────────────────────────────
class BlackboxVideoNotifier extends StateNotifier<BlackboxVideoState> {
  BlackboxVideoNotifier() : super(const BlackboxVideoState());

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _hardwareBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Authorization': 'Bearer $_hardwareToken',
        'User-Agent': 'Blackbox-Collector/1.0',
      },
    ),
  );

  // ── 최신 이벤트 조회 + 영상 다운로드 ────────────────────
  Future<void> fetchAndDownload(String accidentId) async {
    state = state.copyWith(status: VideoStatus.fetching);

    try {
      // ① 이벤트 목록 조회
      final response = await _dio.get('/api/events');
      final data = response.data as Map<String, dynamic>;

      if (data['ok'] != true) {
        throw Exception('서버 응답 오류');
      }

      // ② 최신 이벤트 추출
      final event = _extractLatestEvent(data);
      if (event == null) {
        state = state.copyWith(
          status: VideoStatus.waiting,
          errorMessage: '아직 전송된 블랙박스 영상이 없습니다.',
        );
        return;
      }

      // ③ 영상 다운로드
      await _downloadVideo(event);
    } on DioException catch (e) {
      state = state.copyWith(
        status: VideoStatus.error,
        errorMessage: '영상 조회 실패: ${e.message}',
      );
    } catch (e) {
      state = state.copyWith(
        status: VideoStatus.error,
        errorMessage: '오류가 발생했습니다: $e',
      );
    }
  }

  // ── 응답에서 최신 이벤트 추출 (중첩 구조 평탄화) ────────
  BlackboxEvent? _extractLatestEvent(Map<String, dynamic> data) {
    final events = data['events'] as Map<String, dynamic>?;
    if (events == null || events.isEmpty) return null;

    final allEvents = <BlackboxEvent>[];
    events.forEach((deviceId, deviceEvents) {
      if (deviceEvents is Map<String, dynamic>) {
        deviceEvents.forEach((eventId, eventData) {
          if (eventData is Map<String, dynamic>) {
            allEvents.add(BlackboxEvent.fromJson(eventData));
          }
        });
      }
    });

    if (allEvents.isEmpty) return null;

    allEvents.sort((a, b) {
      final at = a.triggerUtc ?? DateTime(2000);
      final bt = b.triggerUtc ?? DateTime(2000);
      return bt.compareTo(at);
    });

    return allEvents.first;
  }

  // ── 영상 파일 다운로드 ───────────────────────────────────
  Future<void> _downloadVideo(BlackboxEvent event) async {
    state = state.copyWith(
      status: VideoStatus.downloading,
      event: event,
      downloadProgress: 0.0,
    );

    try {
      final dir = await getApplicationDocumentsDirectory();
      final safeId = event.eventId.isEmpty
          ? 'demo'
          : event.eventId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final savePath = '${dir.path}/blackbox_$safeId.mp4';

      // 웹용 720p 우선 (용량 작음), 없으면 원본
      final videoPath = event.webVideoFileUrl ?? event.videoFileUrl;
      final fullUrl = videoPath.startsWith('http')
          ? videoPath
          : '$_hardwareBaseUrl$videoPath';

      await _dio.download(
        fullUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            state = state.copyWith(downloadProgress: received / total);
          }
        },
      );

      state = state.copyWith(
        status: VideoStatus.ready,
        localPath: savePath,
        downloadProgress: 1.0,
      );
    } catch (e) {
      state = state.copyWith(
        status: VideoStatus.error,
        errorMessage: '영상 다운로드 실패: $e',
      );
    }
  }

  // ── AI 분석 결과 조회 (facts 추출용) ────────────────────
  // 이벤트 목록만 조회해서 최신 이벤트를 state 에 저장 (영상 다운로드 없음)
  Future<void> _fetchLatestEventOnly() async {
    try {
      final response = await _dio.get('/api/events');
      final data = response.data as Map<String, dynamic>?;
      if (data == null || data['ok'] != true) return;
      final event = _extractLatestEvent(data);
      if (event != null) {
        state = state.copyWith(event: event);
      }
    } catch (_) {
      // 실패 시 그대로 (분석은 null 반환됨)
    }
  }

  Future<Map<String, dynamic>?> fetchAnalysis() async {
    // 이벤트가 아직 없으면 하드웨어 서버에서 먼저 가져옴(영상 다운로드는 생략)
    if (state.event == null) {
      await _fetchLatestEventOnly();
    }
    final event = state.event;
    if (event?.modelAnalysisUrl == null) return null;
    try {
      final url = event!.modelAnalysisUrl!;
      final fullUrl = url.startsWith('http') ? url : '$_hardwareBaseUrl$url';
      final response = await _dio.get(fullUrl);
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }

  // ── AI 분석 결과에서 과실 정보 추출 ─────────────────────
  // model_analysis.json → 앱이 쓸 수 있는 과실 데이터로 변환
  Future<VideoAnalysisResult?> fetchAnalysisResult() async {
    final raw = await fetchAnalysis();
    if (raw == null) return null;

    try {
      final analysis = raw['analysis'] as Map<String, dynamic>?;
      if (analysis == null) return null;

      final std = analysis['standardized_prediction']
      as Map<String, dynamic>?;
      final crossRef = (analysis['violation_analysis']
      as Map<String, dynamic>?)?['negligence_cross_reference']
      as Map<String, dynamic>?;
      final situation = analysis['situation_context']
      as Map<String, dynamic>?;

      // 내 차(ego) 과실 비율 (cross_reference가 우선)
      int myFault = 50;
      if (crossRef != null &&
          crossRef['estimated_ratio_percent_for_suggested_ego_party'] !=
              null) {
        myFault = (crossRef[
        'estimated_ratio_percent_for_suggested_ego_party'] as num)
            .toInt();
      } else if (std != null) {
        // fallback: rateB를 내 과실로 (ego가 후행 추정인 경우가 많음)
        myFault = (std['accident_negligence_rateB'] as num?)?.toInt() ?? 50;
      }

      // 사고 유형
      final accidentType =
      (std?['traffic_accident_type'] ?? 'unknown') as String;
      final accidentObject =
      (std?['accident_object'] ?? '') as String;

      // 장면 설명
      final sceneSummary =
      (situation?['scene_summary_text'] ?? '') as String;

      // 법률 쿼리 (판례 검색용 키워드)
      final legalQueries = <String>[];
      final queries = analysis['violation_analysis']
      as Map<String, dynamic>?;
      if (queries?['legal_queries'] is List) {
        for (final q in queries!['legal_queries'] as List) {
          if (q is Map && q['query_ko'] != null) {
            legalQueries.add(q['query_ko'] as String);
          }
        }
      }

      return VideoAnalysisResult(
        myFaultRatio: myFault / 100,
        opponentFaultRatio: (100 - myFault) / 100,
        accidentType: accidentType,
        accidentObject: accidentObject,
        sceneSummary: sceneSummary,
        legalQueries: legalQueries,
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> retry(String accidentId) async {
    await fetchAndDownload(accidentId);
  }

  void reset() {
    state = const BlackboxVideoState();
  }
}

// ── AI 영상 분석 결과 (과실 정보) ────────────────────────
class VideoAnalysisResult {
  final double myFaultRatio;
  final double opponentFaultRatio;
  final String accidentType;    // sudden_stop 등
  final String accidentObject;  // pedestrian 등
  final String sceneSummary;    // 장면 설명
  final List<String> legalQueries; // 판례 검색 키워드

  VideoAnalysisResult({
    required this.myFaultRatio,
    required this.opponentFaultRatio,
    required this.accidentType,
    required this.accidentObject,
    required this.sceneSummary,
    required this.legalQueries,
  });

  // 사고 유형 한글 변환
  String get accidentTypeKo {
    switch (accidentType) {
      case 'sudden_stop':
        return '급정거 추돌';
      case 'rear_end_collision':
      case 'rear_end':
        return '후방 추돌';
      case 'intersection':
        return '교차로 사고';
      case 'side_collision':
        return '측면 충돌';
      case 'lane_change':
        return '차로 변경 사고';
      case 'head_on':
        return '정면 충돌';
      case 'pedestrian':
        return '보행자 사고';
      default:
        return accidentType;
    }
  }

  // 사고 대상 한글 변환
  String get accidentObjectKo {
    switch (accidentObject) {
      case 'pedestrian':
        return '보행자';
      case 'vehicle':
        return '차량';
      case 'motorcycle':
        return '이륜차';
      case 'bicycle':
        return '자전거';
      case 'object':
        return '고정물';
      default:
        return accidentObject;
    }
  }
}

// ── Provider ─────────────────────────────────────────────
final blackboxVideoProvider =
StateNotifierProvider<BlackboxVideoNotifier, BlackboxVideoState>(
      (ref) => BlackboxVideoNotifier(),
);