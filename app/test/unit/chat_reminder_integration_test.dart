import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/data/services/account_reminder_service.dart';
import 'package:vinfast_battery/features/ai/services/app_chat_tool_gateway.dart';
import 'package:vinfast_battery/features/ai/services/local_chat_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  late String? uid;
  late AccountReminderService reminders;
  late BatteryBotLocalEngine engine;
  late int writes;
  setUp(() {
    uid = 'qa-a';
    writes = 0;
    reminders = AccountReminderService(
      uidResolver: () => uid,
      uploadReminder: (_) async {
        writes++;
      },
      scheduleNotification: (_) async => false,
      cancelNotification: (_) async {},
    );
    engine = BatteryBotLocalEngine(
      tools: AppChatToolGateway(
        uidResolver: () => uid,
        selectedVehicle: () => VehicleModel(
          vehicleId: 'qa-vehicle',
          ownerUid: uid,
          vehicleName: 'Feliz QA',
          currentOdo: 0,
        ),
        reminders: reminders,
      ),
    );
  });
  tearDown(() {
    engine.dispose();
    reminders.dispose();
  });

  Future<void> create() async {
    final reply = await engine.reply('nhắc bảo dưỡng phanh ngày 20/11/2027');
    expect(reply.action, isNotNull);
    expect(reply.action!.cardData!.safetyNote, isNull);
    expect(writes, 0);
    expect((await engine.confirm(reply.action!.callId, true))['success'], true);
    expect(writes, 1);
  }

  test(
    'real local engine/gateway edits and cancels only after confirmation',
    () async {
      await create();
      final edit = await engine.reply(
        'đổi lịch bảo dưỡng ngày 20/11/2027 sang 25/11/2027',
      );
      expect(edit.action!.cardData!.description, contains('25/11/2027'));
      expect(edit.action!.args, isEmpty);
      expect((await reminders.list('qa-vehicle')).single.revision, 1);
      expect(writes, 1);
      expect(
        (await engine.confirm(edit.action!.callId, true))['success'],
        true,
      );
      expect((await reminders.list('qa-vehicle')).single.revision, 2);
      await engine.confirm(edit.action!.callId, true);
      expect(writes, 2);

      final cancel = await engine.reply('hủy lịch bảo dưỡng ngày 25/11/2027');
      expect((await reminders.list('qa-vehicle')).length, 1);
      expect(
        (await engine.confirm(cancel.action!.callId, true))['success'],
        true,
      );
      expect(await reminders.list('qa-vehicle'), isEmpty);
      expect(writes, 3);
    },
  );

  test('cancelling a proposal leaves the original reminder intact', () async {
    await create();
    final cancel = await engine.reply('hủy lịch bảo dưỡng ngày 20/11/2027');
    await engine.confirm(cancel.action!.callId, false);
    expect((await reminders.list('qa-vehicle')).single.revision, 1);
    expect(writes, 1);
  });

  test(
    'UID change expires edit proposal without a write or cross-account read',
    () async {
      await create();
      final edit = await engine.reply(
        'đổi lịch bảo dưỡng ngày 20/11/2027 sang 25/11/2027',
      );
      uid = 'qa-b';
      expect(
        (await engine.confirm(edit.action!.callId, true))['status'],
        'expired',
      );
      expect(await reminders.list('qa-vehicle'), isEmpty);
      expect(writes, 1);
    },
  );

  test('an old confirmed preview cannot overwrite a new revision', () async {
    await create();
    final a = await engine.reply(
      'đổi lịch bảo dưỡng ngày 20/11/2027 sang 25/11/2027',
    );
    final b = await engine.reply(
      'đổi lịch bảo dưỡng ngày 20/11/2027 sang 30/11/2027',
    );
    await engine.confirm(a.action!.callId, true);
    expect((await engine.confirm(b.action!.callId, true))['status'], 'expired');
    expect((await reminders.list('qa-vehicle')).single.dueDate.day, 25);
    expect(writes, 2);
  });

  test(
    'missing date and duplicate same-day reminder never create a mutation proposal',
    () async {
      await create();
      expect((await engine.reply('hủy lịch bảo dưỡng')).action, isNull);
      final duplicate = await engine.reply(
        'nhắc bảo dưỡng pin ngày 20/11/2027',
      );
      await engine.confirm(duplicate.action!.callId, true);
      expect(
        (await engine.reply('hủy lịch bảo dưỡng ngày 20/11/2027')).action,
        isNull,
      );
      expect((await reminders.list('qa-vehicle')).length, 2);
      expect(writes, 2);
    },
  );
}
