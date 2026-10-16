// lib/services/verdict_search_service.dart
//
// 백엔드 판례 검색 (GET /law/search?q=검색어)
//
// 사용 패키지: dio: ^5.9.2

import 'package:dio/dio.dart';

// ── 서버 주소 (law_analysis_service와 동일하게 맞추세요) ──
// 에뮬레이터: http://10.0.2.2:9000
// Cloudflare: https://xxxx.trycloudflare.com
const String _searchServerUrl = 'http://10.0.2.2:9000';

// ── 검색된 판례 모델 ─────────────────────────────────────
class SearchedVerdict {
  final String judgmentName;   // 판결명
  final String caseNumber;     // 사건번호
  final String court;          // 법원
  final String? decisionDate;  // 선고일
  final String summary;        // 요약
  final String? faultRatioText; // 과실비율 텍스트
  final List<String> matchedKeywords;
  final String? sourceUrl;

  SearchedVerdict({
    required this.judgmentName,
    required this.caseNumber,
    required this.court,
    this.decisionDate,
    required this.summary,
    this.faultRatioText,
    this.matchedKeywords = const [],
    this.sourceUrl,
  });

  factory SearchedVerdict.fromJson(Map<String, dynamic> json) {
    return SearchedVerdict(
      judgmentName: (json['judgment_name'] ?? json['case_name'] ?? '') as String,
      caseNumber: (json['case_number'] ?? '') as String,
      court: (json['court'] ?? '') as String,
      decisionDate: json['decision_date'] as String?,
      summary: (json['summary'] ?? '') as String,
      faultRatioText: json['extracted_fault_ratio_text'] as String?,
      matchedKeywords:
      (json['matched_keywords'] as List?)?.cast<String>() ?? [],
      sourceUrl: json['source_url'] as String?,
    );
  }
}

// ── 검색 서비스 ──────────────────────────────────────────
class VerdictSearchService {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _searchServerUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  // GET /law/search?q=검색어&limit=10
  Future<List<SearchedVerdict>> search(String query, {int limit = 10}) async {
    final response = await _dio.get(
      '/law/search',
      queryParameters: {
        'q': query,
        'limit': limit,
      },
    );

    final data = response.data;
    final results = (data['results'] as List?) ?? [];
    return results
        .map((e) => SearchedVerdict.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}