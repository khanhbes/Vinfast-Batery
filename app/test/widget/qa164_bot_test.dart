import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/services/guide_registry.dart';
import 'package:vinfast_battery/core/services/voice_bridge.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/widgets/app_popup.dart';
import 'package:vinfast_battery/features/ai/assistant_settings_screen.dart';
import 'package:vinfast_battery/features/ai/assistant_sheet.dart';
import 'package:vinfast_battery/features/ai/models/chat_message.dart';
import 'package:vinfast_battery/features/ai/models/function_call_action.dart';
import 'package:vinfast_battery/features/ai/services/assistant_api.dart';
import 'package:vinfast_battery/features/ai/services/chat_api_service.dart';
import 'package:vinfast_battery/features/ai/services/chat_history_storage.dart';
import 'package:vinfast_battery/features/ai/services/hybrid_assistant_engine.dart';
import 'package:vinfast_battery/features/ai/services/local_chat_engine.dart';
import 'package:vinfast_battery/features/ai/services/suggestion_service.dart';
import 'package:vinfast_battery/features/ai/widgets/chat_history_sheet.dart';

/// QA 164 (17/11/2026, owner: Pinova Bot's interface, logic, history, voice
/// and photos): the answer as it is written, one greeting, named tools,
/// history with search, days, rename and undo, an old chat is the context
/// again, a new chat starts clean, voice on Android, photos for Pro/Ultra.
class _QuietSuggestions extends SuggestionService {
  @override
  Future<bool> canShowProactiveBubble() async => false;
}

class _FakeChat extends ChatApiService {
  final replies = <StreamController<String>>[];
  final conversations = <List<ChatMessage>>[];

  @override
  void startConversation(List<ChatMessage> messages) =>
      conversations.add(List.of(messages));

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

class _Api extends AssistantApi {}

class _Local implements LocalChatEngine {
  @override
  Future<LocalChatReply> reply(String message) async => LocalChatReply(message);
  @override
  Future<Map<String, dynamic>> confirm(String callId, bool confirmed) async =>
      const {};
  @override
  void cancel() {}
  @override
  void dispose() {}
}

class _Host implements AssistantActionHost {
  @override
  Map<String, dynamic> context() => const {};
  @override
  Future<bool> navigate(String screen, {String? sessionId}) async => true;
  @override
  Future<bool> prepare(String name, Map<String, dynamic> args) async => true;
  @override
  Future<AssistantUndo?> apply(String name, Map<String, dynamic> args) async =>
      null;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      AssistantSettingsScreen.introSeenKey: true,
    });
    FlutterSecureStorage.setMockInitialValues({});
    AppPopup.resetForTesting();
    AssistantSignals.clearLive();
    VoiceBridge.supportedOverride = false;
  });
  tearDown(() {
    AppPopup.resetForTesting();
    VoiceBridge.supportedOverride = null;
  });

  Future<void> open(
    WidgetTester tester,
    _FakeChat api, {
    double width = 320,
    double scale = 1,
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
          navigatorKey: AppPopup.navigatorKey,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              textScaler: TextScaler.linear(scale),
            ),
            child: const Scaffold(body: InteractiveAssistantSheet()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('one greeting, named tools, nothing overflows at x$scale', (
      tester,
    ) async {
      await open(tester, _FakeChat(), scale: scale);
      expect(tester.takeException(), isNull);
      // The greeting once (no second copy as a message under it).
      expect(
        find.text(
          'Chào bạn, mình hỗ trợ về xe, pin, sạc và Shelly. Bạn muốn xem gì?',
        ),
        findsOneWidget,
      );
      expect(find.text('Lịch sử'), findsOneWidget);
      expect(find.text('Chat mới'), findsOneWidget);
      expect(find.text('Cài đặt'), findsOneWidget);
      // Battery data is muted, never the caution colour.
      final battery = tester.widget<Text>(
        find.byKey(const Key('assistant_battery_source')),
      );
      expect(battery.style?.color, isNot(LuxeColors.champagne));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('the answer shows as it is written, then the final one', (
    tester,
  ) async {
    final api = _FakeChat();
    await open(tester, api, width: 390);
    await tester.enterText(
      find.byKey(const Key('assistant_input_field')),
      'Pin còn bao nhiêu?',
    );
    await tester.tap(find.byKey(const Key('assistant_send_button')));
    await tester.pump();
    expect(find.text('Đang suy nghĩ…'), findsOneWidget);
    AssistantSignals.liveStatus.value = 'Đang xem ổ Shelly…';
    await tester.pump();
    expect(find.text('Đang xem ổ Shelly…'), findsOneWidget);
    AssistantSignals.liveText.value = 'Pin còn ';
    await tester.pump();
    expect(find.textContaining('Pin còn'), findsWidgets);
    expect(find.text('Đang xem ổ Shelly…'), findsNothing);
    // The checked answer replaces the streamed text (not added to it).
    api.replies.single.add('Pin còn 40%.');
    await api.replies.single.close();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Pin còn 40%.'), findsOneWidget);
    expect(find.textContaining('Pin còn Pin còn'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a new chat starts Pinova Bot without the old turns', (
    tester,
  ) async {
    final api = _FakeChat();
    await open(tester, api, width: 390);
    api.conversations.clear();
    await tester.tap(find.byKey(const Key('assistant_new_chat_button')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.conversations, [isEmpty]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('photos and the scan share one button; mic only when it works', (
    tester,
  ) async {
    await open(tester, _FakeChat(), width: 390);
    expect(find.byKey(const Key('assistant_voice_button')), findsNothing);
    await tester.tap(find.byKey(GuideRegistry.keyBotScan));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('attach-scan')), findsOneWidget);
    expect(find.byKey(const ValueKey('attach-camera')), findsOneWidget);
    expect(find.byKey(const ValueKey('attach-gallery')), findsOneWidget);
    expect(
      find.text('Ảnh chỉ gửi kèm câu hỏi, không được lưu'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the mic shows on Android', (tester) async {
    VoiceBridge.supportedOverride = true;
    await open(tester, _FakeChat(), width: 390);
    expect(find.byKey(const Key('assistant_voice_button')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('read aloud without Markdown marks', () {
    expect(
      VoiceBridge.plain('**Pin còn 40%**\n\n- Sạc lên [80%](x) mất `1 giờ`.'),
      'Pin còn 40%\nSạc lên 80% mất 1 giờ.',
    );
  });

  test('an old conversation is the context again; a new one is empty', () {
    final engine = HybridAssistantEngine(
      api: _Api(),
      local: _Local(),
      host: _Host(),
      uidResolver: () => 'u1',
    );
    engine.startConversation([
      ('user', 'Pin còn bao nhiêu?'),
      ('assistant', 'Pin còn 40%.'),
    ]);
    expect(engine.historyForTest, [
      {'role': 'user', 'text': 'Pin còn bao nhiêu?'},
      {'role': 'assistant', 'text': 'Pin còn 40%.'},
    ]);
    engine.startConversation(const []);
    expect(engine.historyForTest, isEmpty);
  });

  group('history sheet', () {
    final now = DateTime(2026, 11, 17, 12);

    Future<ChatHistoryStorage> seeded() async {
      final storage = ChatHistoryStorage();
      for (final (id, text) in [
        ('s1', 'Sạc lên 80% mất bao lâu?'),
        ('s2', 'Đi Hà Nam được không?'),
        ('s3', 'Bảo dưỡng lần tới khi nào?'),
        ('s4', 'Ổ Shelly báo lỗi'),
      ]) {
        await storage.saveSessionMessages(id, [
          ChatMessage(
            id: '$id-u',
            role: ChatRole.user,
            content: text,
            timestamp: now,
          ),
          ChatMessage(
            id: '$id-b',
            role: ChatRole.model,
            content: 'Trả lời cho $text',
            timestamp: now,
          ),
        ]);
      }
      return storage;
    }

    Future<void> pumpSheet(
      WidgetTester tester,
      ChatHistoryStorage storage, {
      double scale = 1,
    }) async {
      final sessions = await storage.listSessions();
      await tester.binding.setSurfaceSize(Size(320, scale == 1 ? 900 : 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: AppPopup.navigatorKey,
          theme: LuxeTheme.data(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: ChatHistorySheet(
              sessions: sessions,
              storage: storage,
              currentId: 's1',
              onOpen: (_) {},
              onNewChat: () {},
              onDeleted: (_) {},
              now: now,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets('search, day groups and the last line at x$scale', (
        tester,
      ) async {
        final storage = await tester.runAsync(seeded);
        await tester.runAsync(() => pumpSheet(tester, storage!, scale: scale));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('HÔM NAY'), findsOneWidget);
        expect(find.text('Trả lời cho Ổ Shelly báo lỗi'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('history-search')),
          'shelly',
        );
        await tester.pump();
        expect(find.text('Ổ Shelly báo lỗi'), findsOneWidget);
        expect(find.text('Đi Hà Nam được không?'), findsNothing);
        await tester.enterText(
          find.byKey(const ValueKey('history-search')),
          'khong co',
        );
        await tester.pump();
        expect(find.byKey(const ValueKey('history-none')), findsOneWidget);
      });
    }

    testWidgets('rename keeps the name on later saves', (tester) async {
      final storage = await tester.runAsync(seeded);
      await tester.runAsync(() => pumpSheet(tester, storage!));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('history-menu-s2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đổi tên'));
      // The field's cursor blinks: fixed pumps, not pumpAndSettle.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
        find.byKey(const ValueKey('history-rename-field')),
        'Chuyến đi Hà Nam',
      );
      await tester.tap(find.byKey(const ValueKey('history-rename-save')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Chuyến đi Hà Nam'), findsOneWidget);
    });

    test('a renamed conversation keeps its name on later saves', () async {
      final storage = await seeded();
      await storage.renameSession('s2', 'Chuyến đi Hà Nam');
      final messages = await storage.loadSessionMessages('s2');
      await storage.saveSessionMessages('s2', messages);
      final sessions = await storage.listSessions();
      final s2 = sessions.firstWhere((s) => s.id == 's2');
      expect(s2.title, 'Chuyến đi Hà Nam');
      expect(s2.renamed, isTrue);
    });
  });
}
