import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/account_reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  AccountReminder reminder(String id) => AccountReminder(
    id: id,
    uid: 'qa-a',
    vehicleId: 'qa-vehicle',
    title: 'Bảo dưỡng phanh',
    kind: 'maintenance',
    dueDate: DateTime(2026, 11, 20),
  );
  test(
    'offline creation persists across service restart and UID switch',
    () async {
      String? uid = 'qa-a';
      AccountReminderService service() => AccountReminderService(
        uidResolver: () => uid,
        scheduleNotification: (_) async => false,
        cancelNotification: (_) async {},
      );
      final original = service();
      final saved = await original.save(reminder('operation-1'));
      expect(saved.pendingSync, true);
      expect(saved.notificationsEnabled, false);
      final restored = service();
      expect(
        (await restored.list('qa-vehicle')).single.title,
        'Bảo dưỡng phanh',
      );
      uid = 'qa-b';
      expect(await restored.list('qa-vehicle'), isEmpty);
      uid = 'qa-a';
      expect((await restored.list('qa-vehicle')).length, 1);
      expect(restored.remoteVerified, false);
    },
  );
  test(
    'same operation is idempotent and does not reschedule notifications',
    () async {
      var scheduled = 0;
      final service = AccountReminderService(
        uidResolver: () => 'qa-a',
        scheduleNotification: (_) async {
          scheduled++;
          return false;
        },
        cancelNotification: (_) async {},
      );
      await service.save(reminder('operation-1'));
      await service.save(reminder('operation-1'));
      expect((await service.list('qa-vehicle')).length, 1);
      expect(scheduled, 1);
    },
  );
  test('a queued save cannot write after UID changes', () async {
    String? uid = 'qa-a';
    final service = AccountReminderService(
      uidResolver: () => uid,
      scheduleNotification: (_) async => false,
      cancelNotification: (_) async {},
    );
    final pending = service.save(reminder('operation-1'));
    uid = 'qa-b';
    await expectLater(pending, throwsStateError);
    expect(await service.list('qa-vehicle'), isEmpty);
  });

  AccountReminderService service({
    Future<void> Function(AccountReminder)? upload,
    Future<bool> Function(AccountReminder)? schedule,
    Future<void> Function(AccountReminder)? cancel,
    String? Function()? uid,
  }) => AccountReminderService(
    uidResolver: uid ?? () => 'qa-a',
    uploadReminder: upload ?? (_) async {},
    scheduleNotification: schedule ?? (_) async => true,
    cancelNotification: cancel ?? (_) async {},
  );

  test(
    'edit persists new revision and same operation retry does not reschedule',
    () async {
      var scheduled = 0, cancelled = 0, uploaded = 0;
      final subject = service(
        upload: (_) async {
          uploaded++;
        },
        schedule: (_) async {
          scheduled++;
          return true;
        },
        cancel: (_) async {
          cancelled++;
        },
      );
      await subject.save(reminder('original'));
      final updated = await subject.revise(
        vehicleId: 'qa-vehicle',
        reminderId: 'original',
        expectedRevision: 1,
        operationId: 'edit-1',
        dueDate: DateTime(2027, 1, 10),
      );
      expect(updated.revision, 2);
      expect(updated.pendingSync, false);
      expect(updated.dueDate, DateTime(2027, 1, 10));
      await subject.revise(
        vehicleId: 'qa-vehicle',
        reminderId: 'original',
        expectedRevision: 1,
        operationId: 'edit-1',
        dueDate: DateTime(2027, 1, 10),
      );
      expect(uploaded, 2);
      expect(scheduled, 2);
      expect(cancelled, 1);
    },
  );

  test(
    'cancel is a durable tombstone and never schedules another notification',
    () async {
      var scheduled = 0, cancelled = 0;
      final subject = service(
        schedule: (_) async {
          scheduled++;
          return true;
        },
        cancel: (_) async {
          cancelled++;
        },
      );
      await subject.save(reminder('original'));
      final saved = await subject.revise(
        vehicleId: 'qa-vehicle',
        reminderId: 'original',
        expectedRevision: 1,
        operationId: 'cancel-1',
        cancel: true,
      );
      expect(saved.cancelled, true);
      expect(saved.notificationsEnabled, false);
      expect(await subject.list('qa-vehicle'), isEmpty);
      expect(
        (await service().list(
          'qa-vehicle',
          includeCancelled: true,
        )).single.cancelled,
        true,
      );
      expect(scheduled, 1);
      expect(cancelled, 1);
      await expectLater(
        subject.revise(
          vehicleId: 'qa-vehicle',
          reminderId: 'original',
          expectedRevision: 2,
          operationId: 'resurrect',
          dueDate: DateTime(2027, 1, 1),
        ),
        throwsA(isA<ReminderConflictException>()),
      );
    },
  );

  test('offline edit remains durable; a second edit waits for sync', () async {
    var offline = false;
    final subject = service(
      upload: (_) async {
        if (offline) throw StateError('offline');
      },
    );
    await subject.save(reminder('original'));
    offline = true;
    final saved = await subject.revise(
      vehicleId: 'qa-vehicle',
      reminderId: 'original',
      expectedRevision: 1,
      operationId: 'edit-1',
      dueDate: DateTime(2027, 1, 10),
    );
    expect(saved.pendingSync, true);
    expect(
      (await service().list('qa-vehicle')).single.dueDate,
      DateTime(2027, 1, 10),
    );
    await expectLater(
      subject.revise(
        vehicleId: 'qa-vehicle',
        reminderId: 'original',
        expectedRevision: 2,
        operationId: 'edit-2',
        dueDate: DateTime(2027, 2, 10),
      ),
      throwsA(isA<ReminderConflictException>()),
    );
  });

  test(
    'remote conflict retains local proposal but cancels notifications',
    () async {
      var conflict = false, scheduled = 0;
      final subject = service(
        upload: (_) async {
          if (conflict) throw const ReminderConflictException();
        },
        schedule: (_) async {
          scheduled++;
          return true;
        },
      );
      await subject.save(reminder('original'));
      conflict = true;
      final saved = await subject.revise(
        vehicleId: 'qa-vehicle',
        reminderId: 'original',
        expectedRevision: 1,
        operationId: 'edit-1',
        dueDate: DateTime(2027, 1, 10),
      );
      expect(saved.syncConflict, true);
      expect(saved.notificationsEnabled, false);
      expect(saved.pendingSync, true);
      expect(scheduled, 1);
      expect((await service().list('qa-vehicle')).single.syncConflict, true);
    },
  );

  test('stale revision, foreign vehicle and foreign UID cannot edit', () async {
    String? uid = 'qa-a';
    final subject = service(uid: () => uid);
    await subject.save(reminder('original'));
    for (final entry in [('qa-vehicle', 7), ('foreign-vehicle', 1)]) {
      await expectLater(
        subject.revise(
          vehicleId: entry.$1,
          reminderId: 'original',
          expectedRevision: entry.$2,
          operationId: 'edit',
          cancel: true,
        ),
        throwsA(isA<ReminderConflictException>()),
      );
    }
    final pending = subject.revise(
      vehicleId: 'qa-vehicle',
      reminderId: 'original',
      expectedRevision: 1,
      operationId: 'edit',
      cancel: true,
    );
    uid = 'qa-b';
    await expectLater(pending, throwsStateError);
    expect(await subject.list('qa-vehicle'), isEmpty);
  });

  test('same create operation with different contents is a conflict', () async {
    final subject = service();
    await subject.save(reminder('original'));
    await expectLater(
      subject.save(
        AccountReminder(
          id: 'original',
          uid: 'qa-a',
          vehicleId: 'qa-vehicle',
          title: 'Khác',
          kind: 'maintenance',
          dueDate: DateTime(2027, 1, 1),
        ),
      ),
      throwsA(isA<ReminderConflictException>()),
    );
  });

  test('legacy reminder migrates without losing content', () {
    final json = reminder('original').toJson()
      ..remove('state')
      ..remove('operationId')
      ..remove('syncConflict');
    final restored = AccountReminder.fromJson(json);
    expect(restored.cancelled, false);
    expect(restored.operationId, 'original');
    expect(restored.title, 'Bảo dưỡng phanh');
    expect(restored.cloudData.containsKey('syncConflict'), false);
  });

  test(
    'transaction receipt tolerates lost response, not a competing revision',
    () {
      final original = reminder('original');
      expect(original.requiresCloudWrite(null), true);
      expect(original.requiresCloudWrite(original.cloudData), false);
      final edit = original.revised(
        operation: 'edit-1',
        date: DateTime(2027, 1, 1),
        cancel: false,
      );
      expect(edit.requiresCloudWrite(original.cloudData), true);
      expect(edit.requiresCloudWrite(edit.cloudData), false);
      final competing = original.revised(
        operation: 'edit-2',
        date: DateTime(2027, 2, 1),
        cancel: false,
      );
      expect(
        () => edit.requiresCloudWrite(competing.cloudData),
        throwsA(isA<ReminderConflictException>()),
      );
      expect(
        () => edit.requiresCloudWrite(null),
        throwsA(isA<ReminderConflictException>()),
      );
      final cancelled = original.revised(operation: 'cancel-1', cancel: true);
      final resurrect = cancelled.revised(
        operation: 'edit-3',
        date: DateTime(2027, 3, 1),
        cancel: false,
      );
      expect(
        () => resurrect.requiresCloudWrite(cancelled.cloudData),
        throwsA(isA<ReminderConflictException>()),
      );
      expect(
        () => edit.requiresCloudWrite({...original.cloudData, 'uid': 'qa-b'}),
        throwsA(isA<ReminderConflictException>()),
      );
    },
  );

  test('OS cancellation error is not reported as success', () async {
    final subject = service(
      cancel: (_) async {
        throw StateError('OS cleanup failed');
      },
    );
    await subject.save(reminder('original'));
    await expectLater(
      subject.revise(
        vehicleId: 'qa-vehicle',
        reminderId: 'original',
        expectedRevision: 1,
        operationId: 'cancel-1',
        cancel: true,
      ),
      throwsStateError,
    );
    final pending = (await subject.list(
      'qa-vehicle',
      includeCancelled: true,
    )).single;
    expect(pending.cancelled, true);
    expect(pending.pendingSync, true);
  });

  test(
    'mutation selection requires explicit valid dates and a unique reminder',
    () {
      final items = [reminder('original')];
      final selection = ReminderChatSelection.parse(
        'đổi lịch bảo dưỡng ngày 20/11/2026 sang 25/11/2026',
        items,
        cancel: false,
        now: DateTime(2026, 10, 7),
      );
      expect(selection!.newDate, DateTime(2026, 11, 25));
      expect(
        ReminderChatSelection.parse(
          'hủy lịch bảo dưỡng ngày 20/11/2026',
          items,
          cancel: true,
        )!.item.id,
        'original',
      );
      expect(
        ReminderChatSelection.parse('hủy lịch bảo dưỡng ngày 20/11/2026', [
          ...items,
          reminder('second'),
        ], cancel: true),
        isNull,
      );
      for (final text in [
        'đổi lịch bảo dưỡng sang thứ sáu',
        'đổi lịch bảo dưỡng ngày 31/11/2026 sang 25/12/2026',
        'đổi lịch bảo dưỡng ngày 20/11/2026 sang 01/01/2020',
        'đổi lịch bảo hành ngày 20/11/2026 sang 25/12/2026',
      ]) {
        expect(
          ReminderChatSelection.parse(text, items, cancel: false),
          isNull,
          reason: text,
        );
      }
    },
  );
}
