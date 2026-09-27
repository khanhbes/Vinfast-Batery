import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/providers/app_providers.dart';
import 'package:vinfast_battery/core/utils/battery_bot_faq.dart';
import 'package:vinfast_battery/features/settings/battery_bot_screen.dart';

class _TestUser implements User {
  _TestUser(this.uid);
  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestAuth implements FirebaseAuth {
  _TestAuth([String? uid]) : currentUser = uid == null ? null : _TestUser(uid);

  final changes = StreamController<User?>.broadcast();
  @override
  User? currentUser;

  @override
  Stream<User?> userChanges() => changes.stream;

  void switchUser(String uid) {
    currentUser = _TestUser(uid);
    changes.add(currentUser);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingStorage implements FlutterSecureStorage {
  _FailingStorage({this.failRead = false});
  final bool failRead;
  int writes = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #read) {
      return failRead
          ? Future<String?>.error(StateError('Storage unavailable'))
          : Future<String?>.value(null);
    }
    if (invocation.memberName == #write) {
      writes++;
      return Future<void>.error(StateError('Storage unavailable'));
    }
    return super.noSuchMethod(invocation);
  }
}

Widget _app({
  required Widget home,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) => ProviderScope(
  child: MaterialApp(
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(brightness: brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: true,
      ),
      child: child!,
    ),
    home: home,
  ),
);

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byTooltip('Gửi'));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final brightness in Brightness.values) {
    testWidgets('suggestions fit 320dp / font 1.5 / $brightness with IME', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final auth = _TestAuth();
      addTearDown(auth.changes.close);
      await tester.pumpWidget(
        _app(
          home: BatteryBotScreen(auth: auth),
          textScale: 1.5,
          brightness: brightness,
        ),
      );
      await tester.pump();
      for (final prompt in BatteryBotFaq.suggestions) {
        await tester.scrollUntilVisible(
          find.text(prompt),
          100,
          scrollable: find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pump();
        final chip = find.ancestor(
          of: find.text(prompt),
          matching: find.byType(ActionChip),
        );
        expect(tester.getSize(chip).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(chip).width, lessThanOrEqualTo(288));
      }
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text(BatteryBotFaq.suggestions.last),
        100,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pump();
      expect(tester.getBottomRight(find.byType(TextField)).dy, lessThan(420));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('accented question opens a visible tab and removes Bot route', (
    tester,
  ) async {
    final auth = _TestAuth();
    addTearDown(auth.changes.close);
    await tester.pumpWidget(
      _app(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Column(
              children: [
                Text('Tab ${ref.watch(currentTabProvider)}'),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BatteryBotScreen(auth: auth),
                    ),
                  ),
                  child: const Text('Help'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();
    await _send(tester, 'Mở lịch sử');
    await tester.tap(find.text('Mở lịch sử').last);
    await tester.pumpAndSettle();
    expect(find.text('Tab 2'), findsOneWidget);
    expect(find.byType(BatteryBotScreen), findsNothing);
    expect(Navigator.of(tester.element(find.text('Tab 2'))).canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced motion jumps to new reply and preserves 50-message limit',
    (tester) async {
      final history = List.generate(
        49,
        (index) => {
          'text': 'Tin nhắn cũ $index',
          'fromBot': true,
          'action': null,
        },
      );
      FlutterSecureStorage.setMockInitialValues({
        'battery_bot_history_v1_test-user': jsonEncode(history),
      });
      final auth = _TestAuth('test-user');
      addTearDown(auth.changes.close);
      await tester.pumpWidget(_app(home: BatteryBotScreen(auth: auth)));
      await tester.pump();
      await _send(tester, 'Làm sao dừng sạc?');
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(position.isScrollingNotifier.value, isFalse);
      expect(position.pixels, position.maxScrollExtent);
      expect(find.text('Mở Sạc pin'), findsOneWidget);
      final saved =
          jsonDecode(
                (await const FlutterSecureStorage().read(
                  key: 'battery_bot_history_v1_test-user',
                ))!,
              )
              as List;
      expect(saved, hasLength(50));
      expect(saved.last['action'], 'guideCharging');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history remains UID-scoped and private input stays redacted', (
    tester,
  ) async {
    final auth = _TestAuth('first-user');
    addTearDown(auth.changes.close);
    await tester.pumpWidget(_app(home: BatteryBotScreen(auth: auth)));
    await tester.pump();
    const secret = 'api_key=private-test-key';
    await _send(tester, secret);
    expect(find.text(secret), findsNothing);
    expect(find.text('Nội dung riêng tư đã được ẩn'), findsOneWidget);
    final firstHistory = await const FlutterSecureStorage().read(
      key: 'battery_bot_history_v1_first-user',
    );
    expect(firstHistory, isNot(contains(secret)));
    await tester.enterText(find.byType(TextField), 'Bản nháp của tài khoản cũ');
    auth.switchUser('second-user');
    await tester.pump();
    await tester.pump();
    expect(find.text('Nội dung riêng tư đã được ẩn'), findsNothing);
    expect(find.text('Bản nháp của tài khoản cũ'), findsNothing);
    await _send(tester, 'Xem pin ở đâu?');
    final secondHistory = await const FlutterSecureStorage().read(
      key: 'battery_bot_history_v1_second-user',
    );
    expect(secondHistory, contains('Xem pin ở đâu?'));
    expect(secondHistory, isNot(contains('Nội dung riêng tư đã được ẩn')));
    expect(
      await const FlutterSecureStorage().read(
        key: 'battery_bot_history_v1_first-user',
      ),
      firstHistory,
    );
    expect(tester.takeException(), isNull);
  });

  for (final failRead in [true, false]) {
    testWidgets('storage failure does not block FAQ: failRead=$failRead', (
      tester,
    ) async {
      final auth = _TestAuth('test-user');
      final storage = _FailingStorage(failRead: failRead);
      addTearDown(auth.changes.close);
      await tester.pumpWidget(
        _app(
          home: BatteryBotScreen(auth: auth, storage: storage),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await _send(tester, 'Làm sao dừng sạc Shelly?');
      expect(find.text('Mở Sạc pin'), findsOneWidget);
      expect(
        find.textContaining('Lịch sử trò chuyện tạm thời'),
        findsOneWidget,
      );
      expect(storage.writes, failRead ? 0 : 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed history clear does not claim success', (tester) async {
    final auth = _TestAuth('test-user');
    addTearDown(auth.changes.close);
    await tester.pumpWidget(
      _app(
        home: BatteryBotScreen(auth: auth, storage: _FailingStorage()),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Xóa trò chuyện'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xóa'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Chưa xóa được lịch sử đã lưu'), findsOneWidget);
    expect(find.textContaining('Mình đã xóa cuộc trò chuyện.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clear conversation requires confirmation and can be cancelled', (
    tester,
  ) async {
    final auth = _TestAuth('test-user');
    addTearDown(auth.changes.close);
    await tester.pumpWidget(_app(home: BatteryBotScreen(auth: auth)));
    await tester.pump();
    await _send(tester, 'Xem pin ở đâu?');
    await tester.tap(find.byTooltip('Xóa trò chuyện'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(find.text('Xem pin ở đâu?'), findsOneWidget);
    await tester.tap(find.byTooltip('Xóa trò chuyện'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xóa'));
    await tester.pumpAndSettle();
    expect(
      find.text('Mình đã xóa cuộc trò chuyện. Bạn cần giúp gì tiếp theo?'),
      findsOneWidget,
    );
    final saved =
        jsonDecode(
              (await const FlutterSecureStorage().read(
                key: 'battery_bot_history_v1_test-user',
              ))!,
            )
            as List;
    expect(saved, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
