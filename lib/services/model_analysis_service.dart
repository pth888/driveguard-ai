import 'package:dio/dio.dart';

typedef AccessTokenProvider = Future<String?> Function();

final RegExp _backendCaseIdPattern = RegExp(r'^case_[0-9a-f]{32}$');
const _providerStates = {'absent', 'mock', 'real', 'unavailable'};
const _reportStatuses = {'complete', 'incomplete', 'unavailable'};

enum ModelReportStatus { complete, incomplete, unavailable }

class CaseRoadSelection {
  const CaseRoadSelection({
    required this.place,
    required this.otherAction,
    required this.isUserSelected,
    required this.automaticStatus,
    required this.raw,
  });

  final int? place;
  final String? otherAction;
  final bool isUserSelected;
  final String? automaticStatus;
  final Map<String, dynamic> raw;
}

class ModelAnalysisReport {
  const ModelAnalysisReport({
    required this.status,
    required this.rateB,
    required this.rateA,
    required this.text,
    required this.lawAvailable,
    required this.reason,
    required this.caseId,
    required this.createdAt,
    required this.analyzedPlace,
    required this.analysis,
    required this.report,
  });

  final ModelReportStatus status;
  final int? rateB;
  final int? rateA;
  final String text;
  final bool lawAvailable;
  final String? reason;
  final String caseId;
  final DateTime createdAt;
  final int? analyzedPlace;
  final Map<String, dynamic> analysis;
  final Map<String, dynamic> report;

  bool get hasRates => rateB != null && rateA != null;

  bool get gpsIsAssumed {
    final provenance = _mapOrNull(analysis['provenance']);
    final modelInput = _mapOrNull(analysis['model_input']);
    return provenance?['gps_is_assumed'] == true ||
        modelInput?['gps_is_assumed'] == true;
  }

  factory ModelAnalysisReport.fromReport(
    Map<String, dynamic> report, {
    String? expectedCaseId,
  }) {
    final caseId = report['case_id'];
    final createdAtRaw = report['created_at'];
    final createdAt = createdAtRaw is String
        ? DateTime.tryParse(createdAtRaw)?.toUtc()
        : null;
    final analysis = _mapOrNull(report['analysis']);
    final providers = _mapOrNull(analysis?['providers']);
    final model = _mapOrNull(analysis?['model']);
    final prediction = _mapOrNull(model?['prediction']);
    final statusValue = analysis?['status'];
    final validProviders = providers != null &&
        const ['model', 'law', 'context', 'llm'].every(
          (name) => _providerStates.contains(providers[name]),
        );
    if (caseId is! String ||
        !_backendCaseIdPattern.hasMatch(caseId) ||
        expectedCaseId != null && caseId != expectedCaseId ||
        createdAt == null ||
        analysis == null ||
        providers == null ||
        model == null ||
        !_reportStatuses.contains(statusValue) ||
        statusValue == 'complete' && prediction == null ||
        !validProviders) {
      throw const ModelAnalysisException('분석 보고서 응답 형식이 올바르지 않습니다.');
    }
    final status = switch (statusValue) {
      'complete' => ModelReportStatus.complete,
      'unavailable' => ModelReportStatus.unavailable,
      _ => ModelReportStatus.incomplete,
    };
    final rateB = prediction?['rateB'];
    final rateA = prediction?['rateA'];
    final validRates = status == ModelReportStatus.complete &&
        providers['model'] == 'real' &&
        prediction?['ego_party'] == 'B' &&
        rateB is int &&
        rateA is int &&
        rateB >= 0 &&
        rateB <= 100 &&
        rateA >= 0 &&
        rateA <= 100 &&
        rateB + rateA == 100;
    final modelInput = _mapOrNull(analysis['model_input']);
    final inputPlace = modelInput?['place'];
    final predictionPlace = prediction?['place_used'];
    final analyzedPlace = inputPlace is int &&
            inputPlace >= 0 &&
            inputPlace <= 7
        ? inputPlace
        : predictionPlace is int && predictionPlace >= 0 && predictionPlace <= 7
            ? predictionPlace
            : null;

    return ModelAnalysisReport(
      status: status,
      rateB: validRates ? rateB : null,
      rateA: validRates ? rateA : null,
      text: report['text'] is String ? report['text'] as String : '',
      lawAvailable: providers['law'] == 'real',
      reason: model['reason'] is String ? model['reason'] as String : null,
      caseId: caseId,
      createdAt: createdAt,
      analyzedPlace: analyzedPlace,
      analysis: analysis,
      report: report,
    );
  }
}

class ModelAnalysisException implements Exception {
  const ModelAnalysisException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MissingCaseMappingException extends ModelAnalysisException {
  const MissingCaseMappingException(super.message);
}

class LatestRequestTracker {
  int _latest = 0;

  int begin() => ++_latest;

  bool isLatest(int request) => request == _latest;
}

class ModelAnalysisService {
  ModelAnalysisService({
    required Dio dio,
    required AccessTokenProvider accessToken,
    this.pollInterval = const Duration(seconds: 1),
    this.maxPollAttempts = 120,
  })  : _dio = dio,
        _accessToken = accessToken;

  final Dio _dio;
  final AccessTokenProvider _accessToken;
  final Duration pollInterval;
  final int maxPollAttempts;

  static bool isBackendCaseId(String value) =>
      _backendCaseIdPattern.hasMatch(value);

  Future<String> resolveCaseId({
    required String accidentId,
    required String? registeredDeviceId,
    required String? selectedHardwareEventId,
  }) async {
    if (isBackendCaseId(accidentId)) return accidentId;
    if (registeredDeviceId == null || registeredDeviceId.isEmpty) {
      throw const MissingCaseMappingException(
        '등록된 블랙박스가 없습니다. 기기를 등록한 뒤 다시 시도해 주세요.',
      );
    }
    if (selectedHardwareEventId == null || selectedHardwareEventId.isEmpty) {
      throw const MissingCaseMappingException(
        '선택된 블랙박스 사고 영상이 없습니다. 사고 영상을 선택한 뒤 다시 시도해 주세요.',
      );
    }

    final response = await _authorizedGet(
      '/api/v1/cases/by-event',
      queryParameters: {
        'device_id': registeredDeviceId,
        'event_id': selectedHardwareEventId,
      },
    );
    final caseData = _map(_data(response)['case']);
    final caseId = caseData['id'];
    if (caseId is! String || !_backendCaseIdPattern.hasMatch(caseId)) {
      throw const MissingCaseMappingException(
        '선택한 사고 영상과 연결된 분석 케이스를 찾지 못했습니다.',
      );
    }
    return caseId;
  }

  Future<CaseRoadSelection> loadRoad(String caseId) async {
    final response = await _authorizedGet('/api/v1/cases/$caseId/road');
    final road = _map(_data(response)['road']);
    final selected = _mapOrNull(road['selected']);
    final modelInput = _map(road['model_input']);
    final automatic = _map(road['automatic']);
    final selectedPlace = selected?['place'];
    final effectivePlace =
        selectedPlace is int ? selectedPlace : modelInput['place'];
    final selectedAction = selected?['other_action'];
    final effectiveAction = selectedAction is String
        ? selectedAction
        : modelInput['other_action'] is String
            ? modelInput['other_action'] as String
            : null;

    return CaseRoadSelection(
      place: effectivePlace is int && effectivePlace >= 0 && effectivePlace <= 7
          ? effectivePlace
          : null,
      otherAction: effectiveAction,
      isUserSelected: selected != null,
      automaticStatus:
          automatic['status'] is String ? automatic['status'] as String : null,
      raw: road,
    );
  }

  Future<ModelAnalysisReport> requestAnalysis({
    required String caseId,
    int? place,
    String? otherAction,
    Map<String, bool>? facts,
    List<String>? keywords,
  }) async {
    final body = <String, dynamic>{};
    if (place != null) {
      body['road'] = {
        'place': place,
        'other_action': place == 1 || place == 6 ? otherAction : null,
      };
    }
    if (facts != null) body['facts'] = facts;
    if (keywords != null) body['keywords'] = keywords;

    final response = await _authorizedPost(
      '/api/v1/cases/$caseId/analysis',
      data: body,
    );
    final job = _map(_data(response)['job']);
    final jobId = job['id'];
    if (jobId is! String || jobId.isEmpty) {
      throw const ModelAnalysisException('분석 작업 ID를 받지 못했습니다.');
    }
    return _pollJob(caseId, jobId);
  }

  Future<ModelAnalysisReport> _pollJob(String caseId, String jobId) async {
    for (var attempt = 0; attempt < maxPollAttempts; attempt++) {
      if (attempt > 0 && pollInterval > Duration.zero) {
        await Future<void>.delayed(pollInterval);
      }
      final response =
          await _authorizedGet('/api/v1/cases/$caseId/jobs/$jobId');
      final data = _data(response);
      final job = _map(data['job']);
      if (job['id'] != jobId) {
        throw const ModelAnalysisException('요청한 분석 작업과 응답이 일치하지 않습니다.');
      }
      if (job['case_id'] != caseId) {
        throw const ModelAnalysisException('분석 작업이 요청한 사고 케이스와 일치하지 않습니다.');
      }
      final status = job['status'];
      if (status == 'done') {
        final report = _mapOrNull(data['report']);
        if (report == null) {
          throw const ModelAnalysisException('분석은 완료됐지만 결과 보고서가 없습니다.');
        }
        return ModelAnalysisReport.fromReport(
          report,
          expectedCaseId: caseId,
        );
      }
      if (status == 'failed' || status == 'dead') {
        final code = job['error_code'];
        throw ModelAnalysisException(
          code == 'inputs_changed'
              ? '분석 중 입력이 변경되었습니다. 다시 분석해 주세요.'
              : '모델 분석 작업이 완료되지 못했습니다.',
        );
      }
      if (status is! String || status.isEmpty) {
        throw const ModelAnalysisException('분석 작업 상태를 확인할 수 없습니다.');
      }
    }
    throw const ModelAnalysisException('모델 분석 대기 시간이 초과되었습니다.');
  }

  Future<Response<dynamic>> _authorizedGet(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final token = await _requiredToken();
    try {
      return await _dio.get(
        path,
        queryParameters: queryParameters,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (error) {
      throw ModelAnalysisException(_apiMessage(error));
    }
  }

  Future<Response<dynamic>> _authorizedPost(
    String path, {
    required Map<String, dynamic> data,
  }) async {
    final token = await _requiredToken();
    try {
      return await _dio.post(
        path,
        data: data,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (error) {
      throw ModelAnalysisException(_apiMessage(error));
    }
  }

  Future<String> _requiredToken() async {
    final token = await _accessToken();
    if (token == null || token.isEmpty) {
      throw const ModelAnalysisException('로그인이 필요합니다. 다시 로그인해 주세요.');
    }
    return token;
  }

  static String _apiMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final apiError = data['error'];
      if (apiError is Map && apiError['message'] is String) {
        return apiError['message'] as String;
      }
    }
    return '분석 서버에 연결하지 못했습니다.';
  }

  static Map<String, dynamic> _data(Response<dynamic> response) {
    final envelope = _map(response.data);
    final data = _mapOrNull(envelope['data']);
    if (data == null) {
      throw const ModelAnalysisException('분석 서버 응답 형식이 올바르지 않습니다.');
    }
    return data;
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

Map<String, dynamic>? _mapOrNull(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}
