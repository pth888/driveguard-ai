// lib/screens/accident/first_response_screen.dart
// 테슬라 미니멀 스타일 - 색 최소화, 통일감

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/audio_recording_service.dart';
import '../../services/blackbox_video_service.dart';
import '../../widgets/blackbox_video_player_widget.dart';
import '../../widgets/accident_location_map.dart';
import '../../utils/theme.dart';

class FirstResponseScreen extends ConsumerStatefulWidget {
  final String accidentId;
  const FirstResponseScreen({super.key, required this.accidentId});

  @override
  ConsumerState<FirstResponseScreen> createState() =>
      _FirstResponseScreenState();
}

class _FirstResponseScreenState extends ConsumerState<FirstResponseScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<String> _photoPaths = [];
  int _currentStep = 0;
  bool _inlineMapOpen = false; // 방식 3: 인라인 지도 펼침 여부

  final _storage = const FlutterSecureStorage();
  String _insuranceCompany = '보험사 미등록';
  String _insurancePhone = '';

  @override
  void initState() {
    super.initState();
    _loadInsuranceInfo();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(blackboxVideoProvider.notifier)
          .fetchAndDownload(widget.accidentId);
    });
  }

  Future<void> _loadInsuranceInfo() async {
    final company = await _storage.read(key: 'insurance_company');
    final phone = await _storage.read(key: 'insurance_phone');
    if (!mounted) return;
    setState(() {
      _insuranceCompany =
          (company == null || company.isEmpty) ? '보험사 미등록' : company;
      _insurancePhone = phone ?? '';
    });
  }

  // 단계 정보 (색 없이 통일)
  final List<_Step> _steps = const [
    _Step(
      icon: Icons.shield_outlined,
      title: '안전 확보',
      subtitle: '2차 사고 방지가 최우선입니다',
      desc: '비상등을 켜고 차량을 안전한 곳으로 이동하세요. 부상자가 있다면 함부로 이동시키지 마세요.',
    ),
    _Step(
      icon: Icons.phone_outlined,
      title: '신고하기',
      subtitle: '경찰·구급대에 즉시 신고하세요',
      desc: '인명 피해가 있다면 119를 먼저 호출하세요. 신고 전 절대 합의하거나 서명하지 마세요.',
    ),
    _Step(
      icon: Icons.camera_alt_outlined,
      title: '현장 촬영',
      subtitle: '모든 각도에서 촬영하세요',
      desc: '차량 위치, 바퀴 방향, 파손 부위, 번호판을 촬영하세요. 신호등, 차선, 도로 상황도 포함하세요.',
    ),
    _Step(
      icon: Icons.videocam_outlined,
      title: '블랙박스 영상 확인',
      subtitle: '자동으로 전송된 영상입니다',
      desc: '사고 충격 감지와 동시에 블랙박스 영상이 서버로 자동 전송되었습니다. 아래에서 사고 순간의 영상을 확인하세요.',
    ),
    _Step(
      icon: Icons.mic_none_outlined,
      title: '음성 녹취',
      subtitle: '대화 내용을 녹음하세요',
      desc: '상대방의 과실 인정 발언이 중요한 증거입니다. 녹음 파일에는 위변조 방지를 위한 디지털 타임스탬프가 자동 적용됩니다.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final audioState = ref.watch(audioRecordingProvider);
    final step = _steps[_currentStep];

    return Scaffold(
      backgroundColor: AppTheme.bgBlack,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildStepIndicator(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStepHeader(step),
                    const SizedBox(height: 28),
                    _buildActionArea(audioState),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            _buildLocationButtons(),
            _buildBottomButton(audioState),
          ],
        ),
      ),
    );
  }

  // ── 사고 위치 보기 (펼치기) ──────────────────────────────
  // "블랙박스 영상 확인"(step 3) 단계에서만 표시
  Widget _buildLocationButtons() {
    if (_currentStep != 3) return const SizedBox.shrink();

    final event = ref.watch(blackboxVideoProvider).event;
    // 지도 PNG 는 device_id + event_id 로 서버에서 조회한다.
    // event_id 가 없으면(영상 미수신) 버튼 자체를 숨긴다.
    final deviceId = event?.deviceId ?? '';
    final eventId = event?.eventId ?? '';
    if (eventId.isEmpty) return const SizedBox.shrink();

    final lat = event?.lat;
    final lon = event?.lon;
    final at = event?.triggerKst;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 펼치기 버튼
          GestureDetector(
            onTap: () => setState(() => _inlineMapOpen = !_inlineMapOpen),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.divider),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  const Text(
                    '사고 위치 보기',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _inlineMapOpen
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppTheme.textSub,
                  ),
                ],
              ),
            ),
          ),
          // 펼친 지도 (서버 생성 PNG)
          if (_inlineMapOpen) ...[
            const SizedBox(height: 14),
            AccidentLocationMap(
              deviceId: deviceId,
              eventId: eventId,
              latitude: lat,
              longitude: lon,
              capturedAtLabel: at,
              prefetchedUrl: event?.mapImageUrl,
              prefetchedHasRoute: event?.mapImageHasRoute ?? false,
              prefetchedStatus: event?.mapImageStatus,
            ),
          ],
        ],
      ),
    );
  }

  // ── 헤더 ─────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (_currentStep > 0) {
                setState(() => _currentStep--);
                return;
              }
              if (ref.read(audioRecordingProvider).isRecording) {
                ref.read(audioRecordingProvider.notifier).cancelRecording();
              }
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 20, color: Colors.white),
          ),
          const Spacer(),
          const Text(
            '초동 대처',
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 13,
              fontWeight: FontWeight.w400,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 20),
        ],
      ),
    );
  }

  // ── 스텝 인디케이터 (얇은 점) ────────────────────────────
  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Row(
        children: List.generate(_steps.length, (i) {
          final isDone = i < _currentStep;
          final isCurrent = i == _currentStep;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < _steps.length - 1 ? 6 : 0),
              height: 3,
              decoration: BoxDecoration(
                color: isDone || isCurrent
                    ? AppTheme.teslaRed
                    : AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── 단계 헤더 (큰 제목) ──────────────────────────────────
  Widget _buildStepHeader(_Step step) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '0${_currentStep + 1}',
              style: const TextStyle(
                color: AppTheme.teslaRed,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '/ 0${_steps.length}',
              style: const TextStyle(
                color: AppTheme.textHint,
                fontSize: 13,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(step.title, style: AppTheme.h1),
        const SizedBox(height: 8),
        Text(
          step.subtitle,
          style: const TextStyle(
            color: AppTheme.textSub,
            fontSize: 14,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          step.desc,
          style: const TextStyle(
            color: AppTheme.textSub,
            fontSize: 14,
            fontWeight: FontWeight.w300,
            height: 1.7,
          ),
        ),
      ],
    );
  }

  // ── 단계별 액션 ──────────────────────────────────────────
  Widget _buildActionArea(AudioRecordingState audioState) {
    switch (_currentStep) {
      case 0:
        return _buildChecklist([
          '비상등 점등',
          '차량을 갓길로 이동',
          '안전삼각대 설치',
          '부상자 이동 금지',
        ]);
      case 1:
        return _buildCallSection();
      case 2:
        return _buildPhotoSection();
      case 3:
        return _buildVideoSection();
      case 4:
        return _buildRecordingSection(audioState);
      default:
        return const SizedBox.shrink();
    }
  }

  // ── 체크리스트 (미니멀) ──────────────────────────────────
  Widget _buildChecklist(List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('체크리스트', style: AppTheme.label),
        const SizedBox(height: 16),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: AppTheme.teslaRed, size: 20),
                  const SizedBox(width: 14),
                  Text(
                    item,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  // ── 신고 섹션 (통일된 리스트) ────────────────────────────
  Widget _buildCallSection() {
    return Column(
      children: [
        _buildCallRow(
          icon: Icons.local_hospital_outlined,
          label: '구급대',
          number: '119',
          phone: '119',
        ),
        _buildDivider(),
        _buildCallRow(
          icon: Icons.local_police_outlined,
          label: '경찰',
          number: '112',
          phone: '112',
        ),
        _buildDivider(),
        _buildCallRow(
          icon: Icons.shield_outlined,
          label: '보험사',
          number: _insuranceCompany,
          phone: _insurancePhone,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                color: AppTheme.textHint, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '신고 전 절대 합의하거나 서명하지 마세요',
                style: TextStyle(
                  color: AppTheme.textHint,
                  fontSize: 12,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCallRow({
    required IconData icon,
    required String label,
    required String number,
    required String phone,
  }) {
    return GestureDetector(
      onTap: () => _callPhone(phone),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    number,
                    style: const TextStyle(
                      color: AppTheme.textHint,
                      fontSize: 13,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.call_outlined,
                color: AppTheme.teslaRed, size: 20),
          ],
        ),
      ),
    );
  }

  // ── 사진 촬영 섹션 ───────────────────────────────────────
  Widget _buildPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _takePhoto,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              children: [
                const Icon(Icons.camera_alt_outlined,
                    color: Colors.white, size: 24),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    '사진 촬영',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                Text(
                  '${_photoPaths.length}장',
                  style: const TextStyle(
                    color: AppTheme.textHint,
                    fontSize: 13,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.add,
                    color: AppTheme.teslaRed, size: 20),
              ],
            ),
          ),
        ),
        if (_photoPaths.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 84,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _photoPaths.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(_photoPaths[i]),
                    width: 84,
                    height: 84,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── 블랙박스 영상 섹션 ───────────────────────────────────
  Widget _buildVideoSection() {
    final videoState = ref.watch(blackboxVideoProvider);

    switch (videoState.status) {
      case VideoStatus.waiting:
        return _buildVideoStatus(
          icon: Icons.cloud_queue_rounded,
          title: '영상 수신 대기 중',
          subtitle: '블랙박스에서 영상을 전송하고 있습니다',
          showRetry: true,
        );
      case VideoStatus.fetching:
        return _buildVideoStatus(
          icon: Icons.search_rounded,
          title: '영상 확인 중',
          subtitle: '블랙박스 영상을 찾고 있습니다',
          showLoading: true,
        );
      case VideoStatus.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('다운로드 중', style: AppTheme.label),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: videoState.downloadProgress,
                minHeight: 3,
                backgroundColor: AppTheme.divider,
                color: AppTheme.teslaRed,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              videoState.progressPercent,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w200,
              ),
            ),
          ],
        );
      case VideoStatus.ready:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded,
                    color: AppTheme.successGreen, size: 18),
                const SizedBox(width: 8),
                Text(
                  '영상 수신 완료',
                  style: const TextStyle(
                    color: AppTheme.successGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            BlackboxVideoPlayerWidget(localPath: videoState.localPath!),
          ],
        );
      case VideoStatus.error:
        return _buildVideoStatus(
          icon: Icons.error_outline_rounded,
          title: '영상을 불러올 수 없습니다',
          subtitle: videoState.errorMessage ?? '다시 시도해 주세요',
          showRetry: true,
        );
    }
  }

  Widget _buildVideoStatus({
    required IconData icon,
    required String title,
    required String subtitle,
    bool showLoading = false,
    bool showRetry = false,
  }) {
    return Column(
      children: [
        const SizedBox(height: 20),
        SizedBox(
          width: 56,
          height: 56,
          child: showLoading
              ? const CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.teslaRed)
              : Icon(icon, color: AppTheme.textSub, size: 48),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.textHint,
            fontSize: 12,
            fontWeight: FontWeight.w300,
          ),
        ),
        if (showRetry) ...[
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => ref
                .read(blackboxVideoProvider.notifier)
                .retry(widget.accidentId),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF3A3A3E)),
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Text(
                '다시 확인',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── 음성 녹취 섹션 ───────────────────────────────────────
  Widget _buildRecordingSection(AudioRecordingState audioState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: GestureDetector(
            onTap:
                audioState.isRecording ? _stopRecording : _startRecording,
            child: Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: audioState.isRecording
                          ? AppTheme.teslaRed
                          : const Color(0xFF3A3A3E),
                      width: 1.5,
                    ),
                    color: audioState.isRecording
                        ? AppTheme.teslaRed.withOpacity(0.1)
                        : Colors.transparent,
                  ),
                  child: Icon(
                    audioState.isRecording
                        ? Icons.stop_rounded
                        : Icons.mic_none_rounded,
                    color: audioState.isRecording
                        ? AppTheme.teslaRed
                        : Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  audioState.isRecording
                      ? audioState.elapsedFormatted
                      : '탭하여 녹음 시작',
                  style: TextStyle(
                    color: audioState.isRecording
                        ? Colors.white
                        : AppTheme.textSub,
                    fontSize: audioState.isRecording ? 26 : 14,
                    fontWeight: audioState.isRecording
                        ? FontWeight.w200
                        : FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (audioState.sha256Hash != null) ...[
          const SizedBox(height: 32),
          _buildDivider(),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.verified_outlined,
                  color: AppTheme.successGreen, size: 16),
              const SizedBox(width: 8),
              Text(
                '디지털 타임스탬프 생성됨',
                style: const TextStyle(
                  color: AppTheme.successGreen,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow('녹음 길이', audioState.elapsedFormatted),
          _buildInfoRow('파일 크기', audioState.fileSizeFormatted),
          const SizedBox(height: 12),
          const Text('SHA-256', style: AppTheme.label),
          const SizedBox(height: 6),
          Text(
            audioState.sha256Hash!,
            style: const TextStyle(
              color: AppTheme.textSub,
              fontSize: 11,
              fontWeight: FontWeight.w300,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textHint,
              fontSize: 13,
              fontWeight: FontWeight.w300,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(height: 0.5, color: AppTheme.divider);
  }

  // ── 하단 버튼 (알약형) ───────────────────────────────────
  Widget _buildBottomButton(AudioRecordingState audioState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      child: GestureDetector(
        onTap: () {
          if (audioState.isRecording) {
            _stopRecording();
            return;
          }
          if (_currentStep < _steps.length - 1) {
            setState(() => _currentStep++);
          } else {
            _startAnalysis();
          }
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: AppTheme.pointWhite,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Center(
            child: Text(
              audioState.isRecording
                  ? '녹음 중지'
                  : _currentStep < _steps.length - 1
                      ? '다음 단계'
                      : 'AI 과실 분석 시작',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 기능 메서드 ──────────────────────────────────────────
  Future<void> _takePhoto() async {
    final photo =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (photo != null) setState(() => _photoPaths.add(photo.path));
  }

  Future<void> _startRecording() async {
    await ref
        .read(audioRecordingProvider.notifier)
        .startRecording(widget.accidentId);
  }

  Future<void> _stopRecording() async {
    final hash =
        await ref.read(audioRecordingProvider.notifier).stopRecording();
    if (hash != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('녹음 완료 · 디지털 타임스탬프가 생성되었습니다'),
          backgroundColor: AppTheme.surfaceDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _callPhone(String number) async {
    if (number.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('마이페이지에서 보험사 전화번호를 먼저 등록해 주세요.'),
            backgroundColor: AppTheme.surfaceDark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      return;
    }
    final cleanNumber = number.replaceAll('-', '').replaceAll(' ', '');
    final uri = Uri(scheme: 'tel', path: cleanNumber);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('전화 연결 실패 ($number)\n에뮬레이터에서는 제한됩니다.'),
            backgroundColor: AppTheme.surfaceDark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  void _startAnalysis() {
    context.goNamed('analysis', extra: widget.accidentId);
  }
}

class _Step {
  final IconData icon;
  final String title;
  final String subtitle;
  final String desc;
  const _Step({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.desc,
  });
}
