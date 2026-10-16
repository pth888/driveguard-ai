// lib/screens/mypage/mypage_screen.dart
// 테슬라 미니멀 스타일

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../services/device_service.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../utils/theme.dart';

class MypageScreen extends ConsumerStatefulWidget {
  const MypageScreen({super.key});

  @override
  ConsumerState<MypageScreen> createState() => _MypageScreenState();
}

class _MypageScreenState extends ConsumerState<MypageScreen> {
  final _licenseController = TextEditingController();
  final _plateController = TextEditingController();
  final _insuranceController = TextEditingController();
  final _policyNumberController = TextEditingController();
  final _insurancePhoneController = TextEditingController();

  String _selectedVehicleType = '경차';
  bool _isOcrLoading = false;
  bool _isSaving = false;

  // 블랙박스 기기 등록 상태
  String? _registeredDeviceId;
  String? _registeredDeviceName;
  bool _isRegisteringDevice = false;

  // 서버 연결 상태 (null=확인 중, true=연결됨, false=서버 꺼짐)
  bool? _serverOnline;

  final _storage = const FlutterSecureStorage();
  final _imagePicker = ImagePicker();

  final List<String> _vehicleTypes = [
    '경차', 'SUV', '세단', '대형 화물차', '승합차', '기타'
  ];

  @override
  void initState() {
    super.initState();
    // 첫 프레임 이후에 provider 접근/비동기 로드를 수행해 렌더 중 예외를 방지
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadSavedData();
      _loadBackendProfile();
      _loadRegisteredDevice();
      _checkServer();
    });
  }

  // 서버 연결 상태 확인 (계정 카드 배지에 반영)
  Future<void> _checkServer() async {
    final online = await ref.read(profileServiceProvider).pingServer();
    if (!mounted) return;
    setState(() => _serverOnline = online);
  }

  // 등록된 블랙박스 정보 불러오기
  Future<void> _loadRegisteredDevice() async {
    try {
      final dev = await ref.read(deviceServiceProvider).savedDevice();
      if (!mounted) return;
      setState(() {
        _registeredDeviceId = dev?.deviceId;
        _registeredDeviceName = dev?.deviceName;
      });
    } catch (_) {
      // 로드 실패해도 화면은 유지
    }
  }

  Future<void> _loadSavedData() async {
    final license = await _storage.read(key: 'license_number');
    final plate = await _storage.read(key: 'license_plate');
    final insurance = await _storage.read(key: 'insurance_company');
    final policy = await _storage.read(key: 'policy_number');
    final phone = await _storage.read(key: 'insurance_phone');
    final vehicleType = await _storage.read(key: 'vehicle_type');
    if (!mounted) return;
    setState(() {
      _licenseController.text = license ?? '';
      _plateController.text = plate ?? '';
      _insuranceController.text = insurance ?? '';
      _policyNumberController.text = policy ?? '';
      _insurancePhoneController.text = phone ?? '';
      if (vehicleType != null) _selectedVehicleType = vehicleType;
    });
  }

  // 백엔드 프로필 조회: 서버에 저장된 전화번호가 있으면 반영
  // (로컬 입력이 비어 있을 때만 덮어써서 로컬 입력을 우선 존중)
  Future<void> _loadBackendProfile() async {
    try {
      final profile =
          await ref.read(profileServiceProvider).fetchProfile();
      if (!mounted || profile == null) return;
      if (_insurancePhoneController.text.trim().isEmpty &&
          (profile.phone ?? '').isNotEmpty) {
        setState(() => _insurancePhoneController.text = profile.phone!);
      }
    } catch (_) {
      // 서버 연결 실패해도 화면은 유지
    }
  }

  Future<void> _scanLicense() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (picked == null) return;
    setState(() => _isOcrLoading = true);

    try {
      final inputImage = InputImage.fromFilePath(picked.path);
      final recognizer =
      TextRecognizer(script: TextRecognitionScript.korean);
      final recognized = await recognizer.processImage(inputImage);
      await recognizer.close();

      final licenseRegex = RegExp(r'\d{2}-\d{6}-\d{2}');
      final match = licenseRegex.firstMatch(recognized.text);

      if (match != null) {
        setState(() => _licenseController.text = match.group(0)!);
        _showSnackbar('면허증 인식 완료', isError: false);
      } else {
        _showSnackbar('OCR 인식 실패. 직접 입력해 주세요.', isError: true);
      }
    } catch (e) {
      _showSnackbar('인식 중 오류 발생', isError: true);
    } finally {
      if (mounted) setState(() => _isOcrLoading = false);
    }
  }

  Future<void> _saveData() async {
    setState(() => _isSaving = true);

    // 1) 로컬 저장 (면허/차량/보험 상세 — 백엔드에 없는 항목 포함)
    await _storage.write(key: 'license_number', value: _licenseController.text);
    await _storage.write(key: 'license_plate', value: _plateController.text);
    await _storage.write(
        key: 'insurance_company', value: _insuranceController.text);
    await _storage.write(
        key: 'policy_number', value: _policyNumberController.text);
    await _storage.write(
        key: 'insurance_phone', value: _insurancePhoneController.text);
    await _storage.write(key: 'vehicle_type', value: _selectedVehicleType);

    // 2) 백엔드 프로필 동기화 (display_name=계정 이름, phone=보험사 전화)
    //    백엔드는 display_name/phone 두 필드만 저장한다.
    final auth = ref.read(authProvider);
    final displayName = (auth.name ?? '').trim();
    bool backendOk = true;
    if (displayName.isNotEmpty) {
      final saved = await ref.read(profileServiceProvider).saveProfile(
            displayName: displayName,
            phone: _insurancePhoneController.text,
          );
      backendOk = saved != null;
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    _showSnackbar(
      backendOk ? '저장 완료' : '저장됨 (서버 동기화 실패 — 오프라인 저장)',
      isError: !backendOk,
    );
  }

  void _showSnackbar(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.surfaceDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgBlack,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('내 정보', style: AppTheme.h1),
                    const SizedBox(height: 8),
                    const Text(
                      '사고 발생 시 자동으로 사용됩니다',
                      style: TextStyle(
                        color: AppTheme.textSub,
                        fontSize: 14,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── 로그인 계정 ──────────────────────────
                    _buildAccountCard(),

                    const SizedBox(height: 36),

                    // ── 블랙박스 기기 ────────────────────────
                    _buildSectionLabel('블랙박스'),
                    const SizedBox(height: 16),
                    _buildDeviceCard(),

                    const SizedBox(height: 40),

                    // ── 운전면허 ────────────────────────────
                    _buildSectionLabel('운전면허'),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _isOcrLoading ? null : _scanLicense,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            _isOcrLoading
                                ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                                : const Icon(Icons.camera_alt_outlined,
                                color: Colors.white, size: 22),
                            const SizedBox(width: 14),
                            Text(
                              _isOcrLoading ? '인식 중...' : '면허증 촬영으로 자동 입력',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildField('면허번호', _licenseController, '00-000000-00'),

                    const SizedBox(height: 40),

                    // ── 차량 정보 ────────────────────────────
                    _buildSectionLabel('차량 정보'),
                    const SizedBox(height: 20),
                    _buildField('차량 번호', _plateController, '12가 3456'),
                    const SizedBox(height: 24),
                    _buildVehicleTypeSelector(),

                    const SizedBox(height: 40),

                    // ── 보험 정보 ────────────────────────────
                    _buildSectionLabel('보험 정보'),
                    const SizedBox(height: 20),
                    _buildField('보험사', _insuranceController, '삼성화재'),
                    const SizedBox(height: 24),
                    _buildField('증권번호', _policyNumberController, '선택 입력'),
                    const SizedBox(height: 24),
                    _buildField(
                        '보험사 전화', _insurancePhoneController, '1588-0000'),

                    const SizedBox(height: 48),

                    // ── 저장 버튼 ────────────────────────────
                    GestureDetector(
                      onTap: _isSaving ? null : _saveData,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: AppTheme.pointWhite,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Center(
                          child: Text(
                            _isSaving ? '저장 중...' : '저장하기',
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
                    const SizedBox(height: 12),

                    // ── 로그아웃 버튼 ─────────────────────────
                    GestureDetector(
                      onTap: () async {
                        await ref.read(authProvider.notifier).logout();
                        // 라우터 redirect 가 자동으로 로그인 화면으로 보냄
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF3A3A3E)),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: const Center(
                          child: Text(
                            '로그아웃',
                            style: TextStyle(
                              color: AppTheme.textSub,
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
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
            'MY',
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

  // ── 로그인 계정 카드 (백엔드 인증 연동) ──────────────────
  Widget _buildAccountCard() {
    final auth = ref.watch(authProvider);
    final name = (auth.name ?? '').trim();
    final email = (auth.email ?? '').trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.divider, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.surfaceDark,
            ),
            child: const Icon(Icons.person_outline_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? '로그인 사용자' : name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email.isEmpty ? '-' : email,
                  style: const TextStyle(
                    color: AppTheme.textHint,
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
          _buildServerBadge(),
        ],
      ),
    );
  }

  // 서버 연결 상태 배지 (실제 /health/live 핑 결과 반영)
  Widget _buildServerBadge() {
    final String label;
    final Color color;
    if (_serverOnline == null) {
      label = '확인 중';
      color = AppTheme.textHint;
    } else if (_serverOnline == true) {
      label = '연결됨';
      color = AppTheme.textSub;
    } else {
      label = '서버 꺼짐';
      color = AppTheme.errorRed;
    }
    return GestureDetector(
      // 서버 꺼짐일 때 탭하면 다시 확인
      onTap: _serverOnline == false
          ? () {
              setState(() => _serverOnline = null);
              _checkServer();
            }
          : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // ── 블랙박스 기기 카드 ───────────────────────────────────
  Widget _buildDeviceCard() {
    final registered = _registeredDeviceId != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.divider, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.surfaceDark,
            ),
            child: Icon(
              registered
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_outlined,
              color: registered ? Colors.white : AppTheme.textHint,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  registered
                      ? (_registeredDeviceName ?? '등록된 블랙박스')
                      : '등록된 블랙박스 없음',
                  style: TextStyle(
                    color: registered ? Colors.white : AppTheme.textSub,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  registered
                      ? '사고 영상이 이 기기에서 수집됩니다'
                      : '블랙박스를 등록해 사고 영상을 연동하세요',
                  style: const TextStyle(
                    color: AppTheme.textHint,
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _isRegisteringDevice ? null : _startDeviceRegistration,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: registered ? Colors.transparent : AppTheme.pointWhite,
                border: Border.all(
                  color: registered ? AppTheme.divider : AppTheme.pointWhite,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(100),
              ),
              child: _isRegisteringDevice
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      registered ? '재등록' : '등록',
                      style: TextStyle(
                        color: registered ? AppTheme.textSub : Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // 등록 시작: 이름 입력 + 전/후방 선택 다이얼로그
  Future<void> _startDeviceRegistration() async {
    final nameController =
        TextEditingController(text: _registeredDeviceName ?? '내 블랙박스');
    DevicePosition position = DevicePosition.front;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: AppTheme.surfaceDark,
          title: const Text('블랙박스 연결',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '기기 이름을 입력하세요',
                style: TextStyle(color: AppTheme.textSub, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: '예: 내 차 블랙박스',
                  hintStyle: TextStyle(color: AppTheme.textHint),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.divider),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '설치 위치',
                style: TextStyle(color: AppTheme.textSub, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _positionChip(
                    label: '전방',
                    sub: kDeviceIdFront,
                    selected: position == DevicePosition.front,
                    onTap: () =>
                        setDialog(() => position = DevicePosition.front),
                  ),
                  const SizedBox(width: 10),
                  _positionChip(
                    label: '후방',
                    sub: kDeviceIdRear,
                    selected: position == DevicePosition.rear,
                    onTap: () =>
                        setDialog(() => position = DevicePosition.rear),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '수집 서버 · $kCollectorServerUrl',
                style: const TextStyle(
                    color: AppTheme.textHint, fontSize: 11, height: 1.4),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('취소', style: TextStyle(color: AppTheme.textSub)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('연결', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isRegisteringDevice = true);
    final result = await ref
        .read(deviceServiceProvider)
        .connectDevice(name: name, position: position);
    if (!mounted) return;
    setState(() {
      _isRegisteringDevice = false;
      if (result != null) {
        _registeredDeviceId = result.deviceId;
        _registeredDeviceName = result.deviceName;
      }
    });

    if (result == null) {
      _showSnackbar('연결 실패 — 다시 시도해 주세요', isError: true);
      return;
    }
    _showSnackbar(
      '${result.position.label} 블랙박스(${result.deviceId})가 연결되었습니다',
      isError: false,
    );
  }

  // 전/후방 선택 칩
  Widget _positionChip({
    required String label,
    required String sub,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.pointWhite : Colors.transparent,
            border: Border.all(
              color: selected ? AppTheme.pointWhite : AppTheme.divider,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: TextStyle(
                  color: selected ? Colors.black54 : AppTheme.textHint,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(text.toUpperCase(), style: AppTheme.label);
  }

  Widget _buildField(
      String label, TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSub,
            fontSize: 13,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w300,
          ),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: AppTheme.textHint,
              fontSize: 16,
              fontWeight: FontWeight.w300,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.only(bottom: 10),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.divider),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.divider),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '차종',
          style: TextStyle(
            color: AppTheme.textSub,
            fontSize: 13,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _vehicleTypes.map((type) {
            final selected = _selectedVehicleType == type;
            return GestureDetector(
              onTap: () => setState(() => _selectedVehicleType = type),
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? AppTheme.pointWhite : Colors.transparent,
                  border: Border.all(
                    color: selected ? AppTheme.pointWhite : AppTheme.divider,
                  ),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  type,
                  style: TextStyle(
                    color: selected ? Colors.black : AppTheme.textSub,
                    fontSize: 13,
                    fontWeight:
                    selected ? FontWeight.w500 : FontWeight.w300,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _licenseController.dispose();
    _plateController.dispose();
    _insuranceController.dispose();
    _policyNumberController.dispose();
    _insurancePhoneController.dispose();
    super.dispose();
  }
}