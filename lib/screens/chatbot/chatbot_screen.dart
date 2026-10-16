// lib/screens/chatbot/chatbot_screen.dart
// Groq API 연동 + 트렌디 UI
// - ChatbotScreen : 전체화면 버전 (기존)
// - ChatbotSheet  : 플로팅 바텀시트 버전 (신규, 모든 화면 공용)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../utils/theme.dart';

// ── API 키 설정 ───────────────────────────────────────────
// 보안을 위해 실제 키는 저장소에 올리지 않음. 실행 전 본인 Groq 키로 교체.
const String _groqApiKey = 'YOUR_GROQ_API_KEY';

// ── 시스템 프롬프트 ───────────────────────────────────────
const String _systemPrompt = '''
You must always respond in Korean (한국어) only. Never use Chinese characters (한자) or Japanese characters. Use only Korean Hangul characters.

당신은 교통사고 전문 AI 어시스턴트 "문처리"입니다.
다음 원칙을 따라 대화하세요:

1. 반드시 한국어(한글)로만 답변하세요. 한자나 일본어를 절대 사용하지 마세요.
2. 교통사고 관련 질문에 친절하고 명확하게 답변하세요
3. 과실 비율, 보험 처리, 법적 절차에 대한 정보를 제공하세요
4. 사고 직후 초동 대처 방법을 단계별로 안내하세요
5. 법적 조언 시 반드시 "전문 변호사 상담을 권장합니다"라고 언급하세요
6. 한국 교통법규와 손해보험협회 기준을 참고하세요
7. 답변은 간결하고 이해하기 쉽게 작성하세요
8. 마크다운 형식으로 답변하세요 (굵게, 목록 등 활용)
''';

// ── 채팅 메시지 모델 ─────────────────────────────────────
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isLoading;

  const ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isLoading = false,
  });
}

// ── 챗봇 상태 ────────────────────────────────────────────
class ChatbotState {
  final List<ChatMessage> messages;
  final bool isTyping;

  const ChatbotState({
    this.messages = const [],
    this.isTyping = false,
  });

  ChatbotState copyWith({
    List<ChatMessage>? messages,
    bool? isTyping,
  }) =>
      ChatbotState(
        messages: messages ?? this.messages,
        isTyping: isTyping ?? this.isTyping,
      );
}

class ChatbotNotifier extends StateNotifier<ChatbotState> {
  ChatbotNotifier({this.screenContext}) : super(const ChatbotState()) {
    _initGreeting();
  }

  final String? screenContext;
  final List<Map<String, String>> _history = [];

  void _initGreeting() {
    final greeting = _getContextualGreeting();
    state = state.copyWith(
      messages: [
        ChatMessage(
          text: greeting,
          isUser: false,
          timestamp: DateTime.now(),
        ),
      ],
    );
  }

  String _getContextualGreeting() {
    switch (screenContext) {
      case 'accident':
        return '🚨 **당황하지 마세요!**\n\n저 문처리가 도와드릴게요. 지금 어떤 상황인지 말씀해 주시면 단계별로 안내해 드리겠습니다.\n\n현재 다친 분이 계신가요?';
      case 'analysis':
        return '📊 AI 과실 분석이 완료되었습니다.\n\n결과에 궁금한 점이나 이의가 있으신가요? **법적 근거**나 **유사 판례**에 대해 자세히 설명해 드릴 수 있습니다.';
      default:
        return '안녕하세요! 저는 교통사고 전문 AI 어시스턴트 **문처리**입니다. ✨\n\n교통사고 관련 궁금한 점이 있으시면 무엇이든 물어보세요!';
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    _history.add({'role': 'user', 'content': text});

    final userMsg = ChatMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );
    final loadingMsg = ChatMessage(
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
      isLoading: true,
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg, loadingMsg],
      isTyping: true,
    );

    try {
      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_groqApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'openai/gpt-oss-120b',
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            ..._history,
          ],
          'max_tokens': 1024,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final reply = data['choices'][0]['message']['content'] as String;

        _history.add({'role': 'assistant', 'content': reply});

        final msgs = state.messages.where((m) => !m.isLoading).toList();
        state = state.copyWith(
          messages: [
            ...msgs,
            ChatMessage(
              text: reply,
              isUser: false,
              timestamp: DateTime.now(),
            ),
          ],
          isTyping: false,
        );
      } else {
        throw Exception('API ${response.statusCode}');
      }
    } catch (e) {
      _history.removeLast();
      final msgs = state.messages.where((m) => !m.isLoading).toList();
      state = state.copyWith(
        messages: [
          ...msgs,
          ChatMessage(
            text: '죄송합니다. 일시적인 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        ],
        isTyping: false,
      );
    }
  }
}

final chatbotProvider =
StateNotifierProvider.family<ChatbotNotifier, ChatbotState, String?>(
      (ref, context) => ChatbotNotifier(screenContext: context),
);

// ════════════════════════════════════════════════════════
//  공용 대화 본문 (전체화면 / 바텀시트 둘 다 사용)
// ════════════════════════════════════════════════════════
class _ChatBody extends ConsumerStatefulWidget {
  final String screenCtx;
  final bool isSheet;
  const _ChatBody({required this.screenCtx, this.isSheet = false});

  @override
  ConsumerState<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends ConsumerState<_ChatBody> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<String> _quickQuestions = [
    '과실 비율이 뭔가요?',
    '사고 후 신고 방법',
    '블랙박스 영상 보존',
    '보험사 연락 방법',
  ];

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatbotProvider(widget.screenCtx));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            itemCount: chatState.messages.length,
            itemBuilder: (_, i) => _buildMessage(chatState.messages[i]),
          ),
        ),
        if (chatState.messages.length <= 1) _buildQuickQuestions(),
        _buildInputArea(chatState),
      ],
    );
  }

  Widget _buildMessage(ChatMessage msg) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment:
        isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isUser)
            const Padding(
              padding: EdgeInsets.only(bottom: 8, left: 2),
              child: Text(
                '문처리',
                style: TextStyle(
                  color: AppTheme.textHint,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isUser ? AppTheme.pointWhite : AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(18),
            ),
            child: msg.isLoading
                ? _buildTyping()
                : (isUser
                    ? Text(
                        msg.text,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                          height: 1.5,
                        ),
                      )
                    : MarkdownBody(
                        data: msg.text,
                        styleSheet: MarkdownStyleSheet(
                          p: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w300,
                            height: 1.5,
                          ),
                          strong: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.5,
                          ),
                          listBullet: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      )),
          ),
        ],
      ),
    );
  }

  Widget _buildTyping() {
    return const SizedBox(
      width: 30,
      child: Text(
        '...',
        style: TextStyle(color: AppTheme.textSub, fontSize: 20),
      ),
    );
  }

  Widget _buildQuickQuestions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _quickQuestions
            .map((q) => GestureDetector(
          onTap: () => _send(q),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.north_east_rounded,
                    color: AppTheme.textHint, size: 16),
                const SizedBox(width: 12),
                Text(
                  q,
                  style: const TextStyle(
                    color: AppTheme.textSub,
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
        ))
            .toList(),
      ),
    );
  }

  Widget _buildInputArea(ChatbotState chatState) {
    // 바텀시트일 때 키보드 높이만큼 패딩
    final bottomInset =
        widget.isSheet ? MediaQuery.of(context).viewInsets.bottom : 0.0;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceDark,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: TextField(
                  controller: _msgController,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                  ),
                  cursorColor: Colors.white,
                  decoration: const InputDecoration(
                    hintText: '메시지 입력',
                    hintStyle: TextStyle(
                      color: AppTheme.textHint,
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                  onSubmitted: _send,
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: chatState.isTyping ? null : () => _send(_msgController.text),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: chatState.isTyping
                      ? AppTheme.surfaceDark
                      : AppTheme.pointWhite,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  color: chatState.isTyping ? AppTheme.textHint : Colors.black,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    _msgController.clear();
    ref.read(chatbotProvider(widget.screenCtx).notifier).sendMessage(text);
  }

  @override
  void dispose() {
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

// ════════════════════════════════════════════════════════
//  바텀시트 버전 (플로팅 버튼에서 호출)
// ════════════════════════════════════════════════════════
class ChatbotSheet extends StatelessWidget {
  final String screenContext;
  const ChatbotSheet({super.key, this.screenContext = 'home'});

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.82;
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: AppTheme.bgBlack,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // 드래그 핸들
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.textHint,
              borderRadius: BorderRadius.circular(100),
            ),
          ),
          _buildSheetHeader(context),
          Expanded(
            child: _ChatBody(screenCtx: screenContext, isSheet: true),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '문처리',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                ),
              ),
              Row(
                children: const [
                  _StatusDot(),
                  SizedBox(width: 5),
                  Text(
                    'AI 상담',
                    style: TextStyle(
                      color: AppTheme.textSub,
                      fontSize: 11,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(Icons.close_rounded,
                size: 24, color: AppTheme.textSub),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot();
  @override
  Widget build(BuildContext context) => Container(
        width: 5,
        height: 5,
        decoration: const BoxDecoration(
          color: AppTheme.successGreen,
          shape: BoxShape.circle,
        ),
      );
}

// ════════════════════════════════════════════════════════
//  전체화면 버전 (기존 /chatbot 라우트 유지)
// ════════════════════════════════════════════════════════
class ChatbotScreen extends StatelessWidget {
  final Map<String, dynamic>? initialContext;
  const ChatbotScreen({super.key, this.initialContext});

  @override
  Widget build(BuildContext context) {
    final screenCtx = initialContext?['screen'] ?? 'home';
    return Scaffold(
      backgroundColor: AppTheme.bgBlack,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _ChatBody(screenCtx: screenCtx)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 20, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '문처리',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                ),
              ),
              Row(
                children: const [
                  _StatusDot(),
                  SizedBox(width: 5),
                  Text(
                    'AI 상담',
                    style: TextStyle(
                      color: AppTheme.textSub,
                      fontSize: 11,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
