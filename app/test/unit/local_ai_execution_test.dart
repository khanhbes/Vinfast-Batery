import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:vinfast_battery/data/services/charging_tflite_runner.dart';
import 'package:vinfast_battery/features/ai/services/chat_api_service.dart';
import 'package:vinfast_battery/features/ai/services/chat_history_storage.dart';
import 'package:vinfast_battery/features/ai/services/behavior_sync_service.dart';

void main() {
  test('local chat never calls network or generates relay actions', () async {
    final service = ChatApiService(
      localOnly: true,
      uidResolver: () => 'qa',
      tokenResolver: () async => throw StateError('Token requested'),
      client: MockClient((_) async => throw StateError('Network requested')),
    );
    addTearDown(service.dispose);
    final response = service.streamChat(message: 'Bắt đầu sạc Shelly');
    final text = await response.stream.join();
    expect(text, contains('không tự bật'));
    expect(await response.functionCallCompleter.future, isNull);
    expect(await service.getSessions(), isEmpty);
    final action = await service.confirmAction(
      sessionId: 's',
      callId: 'c',
      toolName: 'start_smart_charging',
      args: {},
      confirmed: true,
    );
    expect(action['success'], isFalse);
    expect(
      await service.sendFeedback(
        sessionId: 's',
        messageId: 'm',
        rating: 'like',
      ),
      isTrue,
    );
  });

  test(
    'local response is dropped when account changes before emission',
    () async {
      var uid = 'qa-a';
      final service = ChatApiService(localOnly: true, uidResolver: () => uid);
      addTearDown(service.dispose);
      final response = service.streamChat(message: 'Xem pin');
      uid = 'qa-b';
      expect(await response.stream.toList(), isEmpty);
    },
  );

  test(
    'local history and behavior cannot upload or fetch cloud data',
    () async {
      final client = MockClient(
        (_) async => throw StateError('Network requested'),
      );
      final storage = ChatHistoryStorage(localOnly: true, client: client);
      final behavior = BehaviorSyncService(localOnly: true, client: client);
      addTearDown(storage.dispose);
      addTearDown(behavior.dispose);
      expect(await storage.backupToCloud('s', []), isFalse);
      behavior.scheduleSync();
      expect(await behavior.syncNow(), isFalse);
      expect(await behavior.fetchRemoteProfile('qa'), isNull);
    },
  );

  test('missing and fake models never become physics-labelled AI', () async {
    final dir = Directory.systemTemp.createTempSync('charging-runner-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/fake.tflite');
    file.writeAsBytesSync('TFL3version:fake'.codeUnits);
    final runner = ChargingTfliteRunner(modelPathResolver: () => file.path);
    expect(runner.hasLocalModel(), isFalse);
    expect(
      await runner.predictDurationSeconds(startSoc: 20, targetSoc: 80),
      isNull,
    );
  });

  test(
    'inference uses seconds, six features, and rejects invalid output',
    () async {
      final dir = Directory.systemTemp.createTempSync('charging-contract-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/header.tflite');
      // Only a wrapper fixture, not a valid native model or quality evidence.
      file.writeAsBytesSync([0, 0, 0, 0, 84, 70, 76, 51, ...List.filled(8, 0)]);
      var value = 1800.0;
      final runner = ChargingTfliteRunner(
        modelPathResolver: () => file.path,
        inference: (path, features) async {
          expect(features, [20, 80, 60, 30, 22.5, 3]);
          return value;
        },
      );
      expect(
        await runner.predictDurationSeconds(startSoc: 20, targetSoc: 80),
        1800,
      );
      value = double.nan;
      expect(
        await runner.predictDurationSeconds(startSoc: 20, targetSoc: 80),
        isNull,
      );
      expect(
        await runner.predictDurationSeconds(
          startSoc: double.nan,
          targetSoc: 80,
        ),
        isNull,
      );
    },
  );
}
