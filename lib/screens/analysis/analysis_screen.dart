import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/blackbox_video_service.dart';
import '../../services/device_service.dart';
import '../../services/model_analysis_service.dart';
import '../../services/pdf_report_service.dart';
import '../../utils/theme.dart';
import '../../widgets/road_question_widget.dart';

enum AnalysisPhase { resolving, ready }

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({
    super.key,
    required this.accidentId,
    this.analysisService,
    this.roadDebounce = const Duration(milliseconds: 300),
  });

  final String accidentId;
  final ModelAnalysisService? analysisService;
  final Duration roadDebounce;

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  late final ModelAnalysisService _analysisService;
  final LatestRequestTracker _requestTracker = LatestRequestTracker();

  AnalysisPhase _phase = AnalysisPhase.resolving;
  ModelAnalysisReport? _report;
  String? _caseId;
  String? _errorMessage;
  int? _selectedPlace;
  String? _selectedAction;
  String? _automaticRoadStatus;
  bool _roadWasUserSelected = false;
  bool _isAnalyzing = false;
  bool _reportIsPrevious = false;
  bool _isExportingPdf = false;
  bool _extrasExpanded = false;
  Timer? _roadDebounceTimer;

  final Map<String, bool> _userFeedback = {
    '상대 깜빡이 미점등': false,
    '내 깜빡이 점등': false,
    '상대 신호위반': false,
    '상대 과속': false,
    '빗길·악천후': false,
    '야간': false,
    '어린이보호구역': false,
  };

  @override
  void initState() {
    super.initState();
    _analysisService = widget.analysisService ??
        ModelAnalysisService(
          dio: Dio(BaseOptions(
            baseUrl: kApiBaseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            headers: {'Content-Type': 'application/json'},
          )),
          accessToken: () => ref.read(authProvider.notifier).validAccessToken(),
        );
    _initialize();
  }

  @override
  void didUpdateWidget(covariant AnalysisScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accidentId == widget.accidentId) return;

    _roadDebounceTimer?.cancel();
    _roadDebounceTimer = null;
    _requestTracker.begin();
    _phase = AnalysisPhase.resolving;
    _report = null;
    _caseId = null;
    _errorMessage = null;
    _selectedPlace = null;
    _selectedAction = null;
    _automaticRoadStatus = null;
    _roadWasUserSelected = false;
    _isAnalyzing = false;
    _reportIsPrevious = false;
    _isExportingPdf = false;
    _extrasExpanded = false;
    _userFeedback.updateAll((_, __) => false);
    _initialize();
  }

  @override
  void dispose() {
    _roadDebounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    final request = _requestTracker.begin();
    try {
      final directCase =
          ModelAnalysisService.isBackendCaseId(widget.accidentId);
      final savedDevice = directCase
          ? null
          : await ref.read(deviceServiceProvider).savedDevice();
      final selectedEvent =
          directCase ? null : ref.read(blackboxVideoProvider).event;
      final caseId = await _analysisService.resolveCaseId(
        accidentId: widget.accidentId,
        registeredDeviceId: savedDevice?.deviceId,
        selectedHardwareEventId: selectedEvent?.eventId,
      );
      final road = await _analysisService.loadRoad(caseId);
      if (!mounted || !_requestTracker.isLatest(request)) return;
      setState(() {
        _caseId = caseId;
        _selectedPlace = road.place;
        _selectedAction = road.otherAction;
        _automaticRoadStatus = road.automaticStatus;
        _roadWasUserSelected = road.isUserSelected;
        _phase = AnalysisPhase.ready;
        _isAnalyzing = true;
      });

      final report = await _analysisService.requestAnalysis(caseId: caseId);
      if (!mounted || !_requestTracker.isLatest(request)) return;
      setState(() {
        _report = report;
        _reportIsPrevious = false;
        _errorMessage = null;
        _isAnalyzing = false;
      });
    } on Object catch (error) {
      if (!mounted || !_requestTracker.isLatest(request)) return;
      setState(() {
        _phase = AnalysisPhase.ready;
        _errorMessage = _displayError(error);
        _isAnalyzing = false;
      });
    }
  }

  String _displayError(Object error) {
    if (error is ModelAnalysisException) return error.message;
    return '분석 정보를 불러오지 못했습니다. 네트워크 상태를 확인해 주세요.';
  }

  void _changeRoad(int place, String? action) {
    setState(() {
      _selectedPlace = place;
      _selectedAction = place == 1 || place == 6 ? action : null;
      _roadWasUserSelected = true;
      _reportIsPrevious = _report != null;
    });
    _roadDebounceTimer?.cancel();
    _roadDebounceTimer = Timer(widget.roadDebounce, _reanalyze);
  }

  ({Map<String, bool> facts, List<String> keywords}) _feedbackPayload() {
    final facts = <String, bool>{};
    final keywords = <String>[];
    for (final item in _userFeedback.entries.where((entry) => entry.value)) {
      switch (item.key) {
        case '상대 깜빡이 미점등':
          facts['opponent_lane_change'] = true;
          keywords.addAll(const ['진로변경', '방향지시등 불이행']);
        case '내 깜빡이 점등':
          keywords.add('방향지시등 점등');
        case '상대 신호위반':
          facts['opponent_signal_violation'] = true;
          keywords.add('신호위반');
        case '상대 과속':
          facts['opponent_speeding_suspected'] = true;
          keywords.add('과속');
        case '빗길·악천후':
          facts['bad_weather'] = true;
          keywords.add('빗길');
        case '야간':
          keywords.add('야간');
        case '어린이보호구역':
          facts['school_zone'] = true;
          keywords.add('어린이보호구역');
      }
    }
    return (facts: facts, keywords: keywords);
  }

  Future<void> _reanalyze() async {
    final caseId = _caseId;
    final place = _selectedPlace;
    if (_isAnalyzing) return;
    if (caseId == null) {
      _showMessage('연결된 분석 케이스가 없어 재분석할 수 없습니다.');
      return;
    }
    if (place == null) {
      _showMessage('도로유형을 선택해 주세요.');
      return;
    }

    final request = _requestTracker.begin();
    final feedback = _feedbackPayload();
    setState(() {
      _isAnalyzing = true;
      _reportIsPrevious = _report != null;
      _errorMessage = null;
    });
    try {
      final report = await _analysisService.requestAnalysis(
        caseId: caseId,
        place: place,
        otherAction: _selectedAction,
        facts: feedback.facts,
        keywords: feedback.keywords,
      );
      if (!mounted || !_requestTracker.isLatest(request)) return;
      setState(() {
        _report = report;
        _reportIsPrevious = false;
        _isAnalyzing = false;
      });
      _showMessage(
          report.hasRates ? '실제 모델 재분석이 완료되었습니다.' : '재분석 결과를 확인해 주세요.');
    } on Object catch (error) {
      if (!mounted || !_requestTracker.isLatest(request)) return;
      setState(() {
        _errorMessage = _displayError(error);
        _isAnalyzing = false;
      });
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: AppTheme.surfaceDark,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _exportPdf() async {
    final report = _report;
    final caseId = _caseId;
    if (!_canExportPdf || report == null || caseId == null) {
      _showMessage(
        '현재 도로 입력으로 완료된 실제 모델 분석만 PDF로 저장할 수 있습니다.',
      );
      return;
    }
    if (_isExportingPdf) return;
    setState(() => _isExportingPdf = true);
    try {
      final data = ReportData(
        accidentId: caseId,
        analyzedAt: report.createdAt,
        address: '-',
        accidentTypeText: report.analyzedPlace == null
            ? ''
            : roadLabels[report.analyzedPlace!],
        weatherText: '',
        rateBPct: report.rateB!,
        rateAPct: report.rateA!,
        sourceLabel: '백엔드 실제 모델 분석',
        confidencePct: null,
        summary: report.text,
        caveat: 'Party B와 Party A의 실제 모델 출력이며 운전자 역할을 임의로 해석하지 않습니다.',
        appliedLaws: const [],
        precedents: const [],
        lawAvailable: report.lawAvailable,
      );
      await PdfReportService.saveToLocal(data);
      await PdfReportService.generateAndShare(data);
    } on Object catch (error) {
      _showMessage('PDF 생성 오류: $error');
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  bool get _canExportPdf {
    final report = _report;
    return _phase == AnalysisPhase.ready &&
        !_isAnalyzing &&
        !_reportIsPrevious &&
        _roadDebounceTimer?.isActive != true &&
        report != null &&
        report.hasRates &&
        _caseId == report.caseId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgBlack,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '뒤로',
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
        title: const Text('과실 분석'),
        actions: [
          IconButton(
            tooltip: 'PDF 리포트 저장',
            onPressed: _isExportingPdf || !_canExportPdf ? null : _exportPdf,
            icon: _isExportingPdf
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_rounded, size: 20),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _phase == AnalysisPhase.resolving
            ? const Center(child: CircularProgressIndicator())
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final chipFontFamily = Theme.of(context).textTheme.labelLarge?.fontFamily;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildReport(),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            _statusBox(
              icon: Icons.error_outline_rounded,
              text: _errorMessage!,
              color: AppTheme.errorRed,
            ),
          ],
          const SizedBox(height: 36),
          const Text('도로유형', style: AppTheme.label),
          const SizedBox(height: 6),
          Text(
            _roadStatusText(),
            style: const TextStyle(color: AppTheme.textHint, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Theme(
            data: Theme.of(context).copyWith(
              chipTheme: Theme.of(context).chipTheme.copyWith(
                    backgroundColor: AppTheme.cardDark,
                    selectedColor: Colors.white,
                    disabledColor: AppTheme.cardDark,
                    labelStyle: TextStyle(
                      color: AppTheme.textSub,
                      fontFamily: chipFontFamily,
                    ),
                    secondaryLabelStyle: TextStyle(
                      color: Colors.black,
                      fontFamily: chipFontFamily,
                    ),
                    side: const BorderSide(color: AppTheme.divider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
            ),
            child: RoadQuestionWidget(
              selectedPlace: _selectedPlace,
              selectedAction: _selectedAction,
              isBusy: _isAnalyzing,
              onChanged: _changeRoad,
            ),
          ),
          const SizedBox(height: 32),
          const Text('영상에 안 나온 정황', style: AppTheme.label),
          const SizedBox(height: 12),
          _buildExtras(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isAnalyzing ? null : _reanalyze,
              icon: _isAnalyzing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(_isAnalyzing ? '모델 분석 중' : '추가 정황 반영하여 재분석'),
            ),
          ),
        ],
      ),
    );
  }

  String _roadStatusText() {
    if (_roadWasUserSelected) return '저장된 사용자 선택을 불러왔습니다.';
    return switch (_automaticRoadStatus) {
      'estimated' => 'GPS 기반 자동 추정값입니다. 필요하면 수정해 주세요.',
      'needs_confirmation' => 'GPS만으로 도로유형을 확정하지 못했습니다. 직접 선택해 주세요.',
      'unavailable' => '도로 자동 추정을 사용할 수 없습니다. 직접 선택해 주세요.',
      _ => '사고 당시 도로 형태를 선택해 주세요.',
    };
  }

  Widget _buildReport() {
    final report = _report;
    if (_isAnalyzing && report == null) {
      return _statusBox(
        icon: Icons.auto_awesome_rounded,
        text: '백엔드 실제 모델이 사고 영상을 분석하고 있습니다.',
        color: Colors.white,
      );
    }
    if (report == null) {
      return _statusBox(
        icon: Icons.info_outline_rounded,
        text: '표시할 모델 분석 결과가 없습니다. 도로유형을 선택해 재분석해 주세요.',
        color: AppTheme.textSub,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_reportIsPrevious) ...[
          _statusBox(
            icon: Icons.history_rounded,
            text: '이전 분석 결과',
            color: AppTheme.warningOrange,
          ),
          const SizedBox(height: 16),
        ],
        if (report.hasRates) ...[
          Row(
            children: [
              _rateSide('B측 과실', report.rateB!),
              Container(width: 1, height: 70, color: AppTheme.divider),
              _rateSide('A측 과실', report.rateA!),
            ],
          ),
          const SizedBox(height: 30),
        ] else
          _statusBox(
            icon: Icons.info_outline_rounded,
            text: _modelUnavailableText(report),
            color: AppTheme.warningOrange,
          ),
        const SizedBox(height: 24),
        if (report.gpsIsAssumed) ...[
          _statusBox(
            icon: Icons.location_on_outlined,
            text: 'GPS 기반 도로유형 가정값이 사용되었습니다.',
            color: AppTheme.warningOrange,
          ),
          const SizedBox(height: 24),
        ],
        const Text('모델 보고서', style: AppTheme.label),
        const SizedBox(height: 10),
        Text(
          report.text.isEmpty ? '모델 보고서 본문이 없습니다.' : report.text,
          style: const TextStyle(
            color: AppTheme.textSub,
            fontSize: 14,
            height: 1.65,
          ),
        ),
        const SizedBox(height: 20),
        _statusBox(
          icon: Icons.gavel_rounded,
          text: report.lawAvailable ? 'LAW 근거 사용 가능' : 'LAW 사용 불가',
          color: report.lawAvailable
              ? AppTheme.successGreen
              : AppTheme.warningOrange,
        ),
      ],
    );
  }

  String _modelUnavailableText(ModelAnalysisReport report) {
    return switch (report.reason) {
      'place_required' => '도로유형 입력이 필요합니다.',
      'no_original_video' => '원본 사고 영상이 없어 모델 분석을 실행할 수 없습니다.',
      'unsupported_input' => '모델이 지원하지 않는 영상 형식입니다.',
      'decode_failed' => '사고 영상을 해석하지 못했습니다.',
      'clip_too_short' => '분석할 사고 영상 구간이 너무 짧습니다.',
      _ => report.status == ModelReportStatus.incomplete
          ? '모델 분석에 필요한 입력이 아직 완전하지 않습니다.'
          : '모델 분석을 사용할 수 없습니다.',
    };
  }

  Widget _rateSide(String label, int rate) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(color: AppTheme.textSub, fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            '$rate%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 46,
              fontWeight: FontWeight.w200,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBox({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        border: Border.all(color: AppTheme.divider),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTheme.textSub, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtras() {
    final count = _userFeedback.values.where((value) => value).length;
    return Column(
      children: [
        InkWell(
          onTap: _isAnalyzing
              ? null
              : () => setState(() => _extrasExpanded = !_extrasExpanded),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              border: Border.all(color: AppTheme.divider),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(count == 0 ? '추가 정황 선택' : '$count개 선택됨'),
                ),
                Icon(_extrasExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded),
              ],
            ),
          ),
        ),
        if (_extrasExpanded) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              border: Border.all(color: AppTheme.divider),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              children: _userFeedback.entries.map((entry) {
                return CheckboxListTile(
                  dense: true,
                  value: entry.value,
                  title: Text(entry.key),
                  onChanged: _isAnalyzing
                      ? null
                      : (value) => setState(
                            () => _userFeedback[entry.key] = value ?? false,
                          ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}
