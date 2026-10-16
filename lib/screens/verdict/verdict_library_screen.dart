// lib/screens/verdict/verdict_library_screen.dart
// 테슬라 미니멀 스타일

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/accident_model.dart';
import '../../services/verdict_search_service.dart';
import '../../services/law_analysis_service.dart';
import '../../utils/theme.dart';

// ── 판례 검색 상태 ────────────────────────────────────────
class VerdictSearchState {
  final List<VerdictModel> results;
  final bool isLoading;
  final String query;

  const VerdictSearchState({
    this.results = const [],
    this.isLoading = false,
    this.query = '',
  });

  VerdictSearchState copyWith({
    List<VerdictModel>? results,
    bool? isLoading,
    String? query,
  }) =>
      VerdictSearchState(
        results: results ?? this.results,
        isLoading: isLoading ?? this.isLoading,
        query: query ?? this.query,
      );
}

class VerdictSearchNotifier extends StateNotifier<VerdictSearchState> {
  VerdictSearchNotifier() : super(const VerdictSearchState()) {
    _loadInitial();
  }

  final _searchService = VerdictSearchService();

  final List<VerdictModel> _mockVerdicts = [
    VerdictModel(
      id: '1',
      caseNumber: '대법원 2023다12345',
      court: '대법원',
      decidedAt: DateTime(2023, 5, 15),
      summary: '교차로 직진 차량과 우회전 차량 충돌 사고에서 신호 위반 차량의 과실이 더 높다고 판시.',
      tags: ['#교차로', '#직진우선', '#신호위반'],
      faultRatioPlaintiff: 0.3,
      faultRatioDefendant: 0.7,
      similarityScore: '94%',
    ),
    VerdictModel(
      id: '2',
      caseNumber: '서울지법 2022가단5678',
      court: '서울지방법원',
      decidedAt: DateTime(2022, 11, 3),
      summary: '어린이보호구역 내 제한속도 초과 차량의 과실 비율을 80%로 인정.',
      tags: ['#어린이보호구역', '#과속', '#스쿨존'],
      faultRatioPlaintiff: 0.2,
      faultRatioDefendant: 0.8,
      similarityScore: '87%',
    ),
    VerdictModel(
      id: '3',
      caseNumber: '부산지법 2023나9999',
      court: '부산지방법원',
      decidedAt: DateTime(2023, 2, 22),
      summary: '야간 무신호 교차로에서 우선도로 진행 차량에 우선권이 있음을 인정.',
      tags: ['#야간주행', '#무신호교차로', '#우선도로'],
      faultRatioPlaintiff: 0.4,
      faultRatioDefendant: 0.6,
      similarityScore: '79%',
    ),
  ];

  // 검색된 판례를 VerdictModel로 변환
  VerdictModel _toVerdictModel(SearchedVerdict s, int index) {
    // 과실비율 텍스트 "30:70" 파싱
    double? p, d;
    if (s.faultRatioText != null && s.faultRatioText!.contains(':')) {
      final parts = s.faultRatioText!.split(':');
      p = (double.tryParse(parts[0].trim()) ?? 50) / 100;
      d = (double.tryParse(parts[1].trim()) ?? 50) / 100;
    }
    return VerdictModel(
      id: 'search_$index',
      caseNumber: s.caseNumber.isEmpty ? s.judgmentName : s.caseNumber,
      court: s.court.isEmpty ? '법원' : s.court,
      decidedAt: DateTime.tryParse(s.decisionDate ?? '') ?? DateTime.now(),
      summary: s.summary.isEmpty ? s.judgmentName : s.summary,
      tags: s.matchedKeywords.map((k) => '#$k').toList(),
      faultRatioPlaintiff: p,
      faultRatioDefendant: d,
      similarityScore: null,
    );
  }

  Future<void> _loadInitial() async {
    state = state.copyWith(isLoading: true);
    // 초기엔 Mock 표시 (검색 전)
    await Future.delayed(const Duration(milliseconds: 300));
    state = state.copyWith(isLoading: false, results: _mockVerdicts);
  }

  Future<void> search(String query) async {
    state = state.copyWith(isLoading: true, query: query);

    if (query.isEmpty) {
      state = state.copyWith(isLoading: false, results: _mockVerdicts);
      return;
    }

    try {
      // 백엔드 실제 검색
      final searched = await _searchService.search(query, limit: 10);
      if (searched.isEmpty) {
        // 결과 없으면 Mock 필터링
        final filtered = _mockVerdicts
            .where((v) =>
        v.summary.contains(query) ||
            v.tags.any((t) => t.contains(query)))
            .toList();
        state = state.copyWith(isLoading: false, results: filtered);
      } else {
        final models = <VerdictModel>[];
        for (var i = 0; i < searched.length; i++) {
          models.add(_toVerdictModel(searched[i], i));
        }
        state = state.copyWith(isLoading: false, results: models);
      }
    } catch (e) {
      // 서버 실패 시 Mock으로 fallback
      final filtered = _mockVerdicts
          .where((v) =>
      v.summary.contains(query) ||
          v.tags.any((t) => t.contains(query)))
          .toList();
      state = state.copyWith(
        isLoading: false,
        results: filtered.isEmpty ? _mockVerdicts : filtered,
      );
    }
  }
}

final verdictSearchProvider =
StateNotifierProvider<VerdictSearchNotifier, VerdictSearchState>(
      (ref) => VerdictSearchNotifier(),
);

// ── 판결 도서관 화면 ──────────────────────────────────────
class VerdictLibraryScreen extends ConsumerStatefulWidget {
  final String? initialQuery; // 분석 화면에서 넘어온 자동 검색어
  const VerdictLibraryScreen({super.key, this.initialQuery});

  @override
  ConsumerState<VerdictLibraryScreen> createState() =>
      _VerdictLibraryScreenState();
}

class _VerdictLibraryScreenState extends ConsumerState<VerdictLibraryScreen> {
  final _searchController = TextEditingController();
  final List<String> _suggestions = ['신호위반', '스쿨존', '야간주행', '과속', '교차로'];

  @override
  void initState() {
    super.initState();
    // 분석 키워드가 넘어왔으면 진입 시 자동 검색
    final q = widget.initialQuery;
    if (q != null && q.trim().isNotEmpty) {
      _searchController.text = q;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(verdictSearchProvider.notifier).search(q);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(verdictSearchProvider);

    // 내 분석 과실 비율 — "분석 화면에서 넘어온 경우(initialQuery 존재)"에만 사용.
    // 메인에서 그냥 판례도서관에 들어오면 매핑을 띄우지 않는다.
    final cameFromAnalysis =
        widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty;
    final lawState = ref.watch(lawAnalysisProvider);
    int? myFaultPct;
    if (cameFromAnalysis &&
        lawState.status == LawAnalysisStatus.done &&
        lawState.result != null) {
      myFaultPct = lawState.result!.prediction.egoFault;
    }

    return Scaffold(
      backgroundColor: AppTheme.bgBlack,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildSearchBar(searchState),
            if (searchState.query.isEmpty) _buildSuggestions(),
            if (myFaultPct != null) _buildMyFaultBanner(myFaultPct),
            Expanded(
              child: searchState.isLoading
                  ? const Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : searchState.results.isEmpty
                  ? _buildEmpty()
                  : _buildList(searchState.results, myFaultPct),
            ),
          ],
        ),
      ),
    );
  }

  // ── 내 과실 기준 안내 배너 ──────────────────────────────
  Widget _buildMyFaultBanner(int myFaultPct) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_pin_circle_outlined,
              size: 18, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: '내 분석 과실 ',
                    style: TextStyle(
                      color: AppTheme.textSub,
                      fontSize: 13,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  TextSpan(
                    text: '$myFaultPct%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const TextSpan(
                    text: ' 기준으로 각 판례에서 내 입장을 표시합니다',
                    style: TextStyle(
                      color: AppTheme.textSub,
                      fontSize: 13,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
            '판결 도서관',
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

  Widget _buildSearchBar(VerdictSearchState searchState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
      child: Row(
        children: [
          const Icon(Icons.search_rounded,
              color: AppTheme.textSub, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w300,
              ),
              cursorColor: Colors.white,
              decoration: const InputDecoration(
                hintText: '판례 검색',
                hintStyle: TextStyle(
                  color: AppTheme.textHint,
                  fontSize: 16,
                  fontWeight: FontWeight.w300,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (q) =>
                  ref.read(verdictSearchProvider.notifier).search(q),
              onChanged: (q) {
                if (q.isEmpty) {
                  ref.read(verdictSearchProvider.notifier).search('');
                }
              },
            ),
          ),
          if (searchState.query.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                ref.read(verdictSearchProvider.notifier).search('');
              },
              child: const Icon(Icons.close_rounded,
                  color: AppTheme.textSub, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: _suggestions
            .map((kw) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () {
              _searchController.text = kw;
              ref.read(verdictSearchProvider.notifier).search(kw);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.divider),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                kw,
                style: const TextStyle(
                  color: AppTheme.textSub,
                  fontSize: 13,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
          ),
        ))
            .toList(),
      ),
    );
  }

  Widget _buildList(List<VerdictModel> verdicts, int? myFaultPct) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      itemCount: verdicts.length,
      itemBuilder: (_, i) => _buildVerdictItem(verdicts[i], i, myFaultPct),
    );
  }

  Widget _buildVerdictItem(VerdictModel v, int index, int? myFaultPct) {
    final pPct = ((v.faultRatioPlaintiff ?? 0) * 100).toInt();
    final dPct = ((v.faultRatioDefendant ?? 0) * 100).toInt();

    // "내 입장" 판정: 내 분석 과실(%)과 더 가까운 쪽이 내 입장
    // (분석을 했고, 판례에 과실비율이 있을 때만)
    final hasRatio = v.faultRatioPlaintiff != null;
    bool? iAmPlaintiff; // true=원고 입장, false=피고 입장, null=판정불가
    if (myFaultPct != null && hasRatio) {
      final diffPlaintiff = (pPct - myFaultPct).abs();
      final diffDefendant = (dPct - myFaultPct).abs();
      iAmPlaintiff = diffPlaintiff <= diffDefendant;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 0.5, color: AppTheme.divider),
          const SizedBox(height: 24),
          // 순위 + 유사도
          Row(
            children: [
              Text(
                '0${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              if (v.similarityScore != null)
                Text(
                  '유사도 ${v.similarityScore}',
                  style: const TextStyle(
                    color: AppTheme.successGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            v.caseNumber,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            v.court,
            style: const TextStyle(
              color: AppTheme.textHint,
              fontSize: 12,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            v.summary,
            style: const TextStyle(
              color: AppTheme.textSub,
              fontSize: 14,
              fontWeight: FontWeight.w300,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          // 과실 비율 바 + "내 입장" 강조
          if (hasRatio) ...[
            Row(
              children: [
                _ratioLabel('원고', pPct, iAmPlaintiff == true),
                const Spacer(),
                _ratioLabel('피고', dPct, iAmPlaintiff == false),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Row(
                children: [
                  Expanded(
                    flex: pPct == 0 ? 1 : pPct,
                    child: Container(
                      height: 4,
                      color: iAmPlaintiff == true
                          ? AppTheme.pointWhite
                          : AppTheme.divider,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: dPct == 0 ? 1 : dPct,
                    child: Container(
                      height: 4,
                      color: iAmPlaintiff == false
                          ? AppTheme.pointWhite
                          : AppTheme.divider,
                    ),
                  ),
                ],
              ),
            ),
            if (iAmPlaintiff != null) ...[
              const SizedBox(height: 10),
              _myPositionLine(iAmPlaintiff, iAmPlaintiff ? pPct : dPct),
            ],
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: v.tags
                .map((t) => Text(
              t,
              style: const TextStyle(
                color: AppTheme.textHint,
                fontSize: 12,
                fontWeight: FontWeight.w300,
              ),
            ))
                .toList(),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // 원고/피고 라벨 (내 입장이면 흰색 강조)
  Widget _ratioLabel(String side, int pct, bool isMine) {
    return Row(
      children: [
        if (isMine) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(100),
            ),
            child: const Text(
              '나',
              style: TextStyle(
                color: Colors.black,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          '$side $pct%',
          style: TextStyle(
            color: isMine ? Colors.white : AppTheme.textHint,
            fontSize: 12,
            fontWeight: isMine ? FontWeight.w500 : FontWeight.w300,
          ),
        ),
      ],
    );
  }

  // "이 판례에서 나와 같은 입장은 X% 과실" 한 줄 설명
  Widget _myPositionLine(bool iAmPlaintiff, int myPctInCase) {
    final sideName = iAmPlaintiff ? '원고' : '피고';
    return Row(
      children: [
        const Icon(Icons.subdirectory_arrow_right_rounded,
            size: 14, color: AppTheme.textHint),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '이 판례에서 나와 같은 입장($sideName)은 ',
                  style: const TextStyle(
                    color: AppTheme.textSub,
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                TextSpan(
                  text: '$myPctInCase% 과실',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off_rounded,
              color: AppTheme.textHint, size: 40),
          const SizedBox(height: 16),
          const Text(
            '검색 결과가 없습니다',
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 15,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}