import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/features/ai/assistant_sheet.dart';
import 'package:vinfast_battery/features/ai/models/function_call_action.dart';
import 'package:vinfast_battery/features/ai/services/chat_api_service.dart';
import 'package:vinfast_battery/features/ai/services/suggestion_service.dart';

class _QuietSuggestions extends SuggestionService {
  @override
  Future<bool> canShowProactiveBubble() async => false;
}

class _FakeChat extends ChatApiService {
  final replies = <StreamController<String>>[];
  @override
  ChatStreamResponse streamChat({
    required String message,
    String? sessionId,
    String? userId,
    Map<String, dynamic>? vehicleContext,
    Map<String, dynamic>? behaviorProfile,
    void Function(FunctionCallAction)? onFunctionCall,
    void Function(Map<String, dynamic>)? onToolCall,
    void Function(Map<String, dynamic>)? onToolResult,
    void Function(Map<String, dynamic>)? onRichCard,
    void Function(String)? onTextReplace,
  }) {
    final stream = StreamController<String>();
    replies.add(stream);
    return ChatStreamResponse(
      stream: stream.stream,
      messageIdCompleter: Completer<String>()..complete('server-message'),
      sessionIdCompleter: Completer<String>()..complete(sessionId ?? 'session'),
      functionCallCompleter: Completer<FunctionCallAction?>()..complete(null),
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  Future<void> open(
    WidgetTester tester,
    _FakeChat api, {
    double width = 390,
    double scale = 1,
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatApiServiceProvider.overrideWithValue(api),
          suggestionServiceProvider.overrideWithValue(_QuietSuggestions()),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: const Scaffold(body: InteractiveAssistantSheet()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets(
    'stream error remains visible after done, new chat rejects old callback',
    (tester) async {
      final api = _FakeChat();
      await open(tester, api);
      await tester.enterText(
        find.byKey(const Key('assistant_input_field')),
        'Xin chào',
      );
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pump();
      expect(api.replies, hasLength(1));
      api.replies.first.addError(
        const ChatApiException(
          'offline',
          'Chưa nhận được câu trả lời. Hãy thử lại.',
        ),
      );
      await api.replies.first.close();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Thử lại câu trả lời'), findsOneWidget);
      await tester.tap(find.byKey(const Key('assistant_new_chat_button')));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Thử lại câu trả lời'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('credential is neither shown nor sent to service', (
    tester,
  ) async {
    final api = _FakeChat();
    await open(tester, api);
    await tester.enterText(
      find.byKey(const Key('assistant_input_field')),
      'password: mock-private-value',
    );
    await tester.tap(find.byKey(const Key('assistant_send_button')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(api.replies, isEmpty);
    expect(find.textContaining('mock-private-value'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('broken history shows retry, not an empty success state', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'vinfast_chat_sessions_index_v2_guest': 'broken',
    });
    await open(tester, _FakeChat());
    await tester.tap(find.byKey(const Key('assistant_history_button')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Chưa tải được lịch sử trò chuyện.'), findsOneWidget);
    expect(find.text('Chưa có lịch sử hội thoại nào.'), findsNothing);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('double tap history creates only one modal', (tester) async {
    await open(tester, _FakeChat());
    // Keep the real button callback to simulate a second queued pointer action
    // even if the first opens the modal before another hit test can run.
    final historyAction = tester
        .widget<IconButton>(find.byKey(const Key('assistant_history_button')))
        .onPressed;
    expect(historyAction, isNotNull);
    await tester.tap(find.byKey(const Key('assistant_history_button')));
    historyAction!();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Lịch sử trò chuyện'), findsOneWidget);
    expect(find.text('Lịch sử lưu trên máy này.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [320.0, 390.0, 412.0]) {
    testWidgets('actual sheet fits $width dp, font 1.5 and keyboard', (
      tester,
    ) async {
      await open(tester, _FakeChat(), width: width, scale: 1.5, keyboard: 300);
      expect(find.byKey(const Key('assistant_send_button')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
