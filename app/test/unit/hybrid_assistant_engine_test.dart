import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/ai/models/function_call_action.dart';
import 'package:vinfast_battery/features/ai/services/assistant_api.dart';
import 'package:vinfast_battery/features/ai/services/hybrid_assistant_engine.dart';
import 'package:vinfast_battery/features/ai/services/local_chat_engine.dart';

class _Api extends AssistantApi {
  _Api(this.turns);
  final List<Object> turns;
  final sent = <Map<String, dynamic>>[];

  @override
  Future<AssistantTurn> chat({
    required String message,
    required List<Map<String, String>> history,
    required Map<String, dynamic> context,
  }) async {
    sent.add({'message': message, 'history': history, 'context': context});
    final next = turns.removeAt(0);
    if (next is AssistantUnavailable) throw next;
    return next as AssistantTurn;
  }
}

class _Local implements LocalChatEngine {
  final asked = <String>[];
  final confirmed = <String>[];
  @override
  Future<LocalChatReply> reply(String message) async {
    asked.add(message);
    if (message.startsWith('bật sạc')) {
      return LocalChatReply(
        'local proposal',
        action: FunctionCallAction(
          callId: 'local-1',
          toolName: 'start_timed_charging',
          args: const {},
          cardData: ActionConfirmationCardData(
            title: 'Bật sạc',
            description: 'x',
          ),
        ),
      );
    }
    return const LocalChatReply('FAQ answer');
  }

  @override
  Future<Map<String, dynamic>> confirm(String callId, bool confirmed) async {
    this.confirmed.add(callId);
    return {'success': true, 'status': 'verified'};
  }

  @override
  void cancel() {}
  @override
  void dispose() {}
}

class _Host implements AssistantActionHost {
  final List<(String, Map<String, dynamic>)> prepared = [];

  @override
  Future<bool> prepare(String name, Map<String, dynamic> args) async {
    prepared.add((name, args));
    return true;
  }

  final navigated = <String>[];
  final applied = <String>[];
  int battery = 40;

  @override
  Map<String, dynamic> context() => {'vehicleId': 'v1'};

  @override
  Future<bool> navigate(String screen, {String? sessionId}) async {
    navigated.add(screen);
    return true;
  }

  @override
  Future<AssistantUndo?> apply(String name, Map<String, dynamic> args) async {
    applied.add(name);
    if (name == 'update_odometer') {
      throw const AssistantActionError('ODO mới nhỏ hơn ODO hiện tại');
    }
    final previous = battery;
    battery = (args['percent'] as num).toInt();
    return AssistantUndo(
      'mức pin về $previous%',
      () async => battery = previous,
    );
  }
}

void main() {
  late _Local local;
  late _Host host;
  String? uid = 'u1';

  HybridAssistantEngine build(List<Object> turns) {
    local = _Local();
    host = _Host();
    uid = 'u1';
    return HybridAssistantEngine(
      api: _Api(turns),
      local: local,
      host: host,
      uidResolver: () => uid,
    );
  }

  test('plain answers keep a short history for the next turn', () async {
    final engine = build([
      const AssistantTurn(reply: 'Chào bạn', actions: []),
      const AssistantTurn(reply: 'Lần 2', actions: []),
    ]);
    expect((await engine.reply('xin chào')).text, 'Chào bạn');
    await engine.reply('tiếp');
    final api = engine.api as _Api;
    expect(api.sent.last['history'], [
      {'role': 'user', 'text': 'xin chào'},
      {'role': 'assistant', 'text': 'Chào bạn'},
    ]);
    expect(api.sent.last['context'], {'vehicleId': 'v1'});
  });

  test('navigation runs at once without a card', () async {
    final engine = build([
      const AssistantTurn(
        reply: 'Mở Bảo dưỡng',
        actions: [
          AssistantAction('navigate', {'screen': 'maintenance'}),
        ],
      ),
    ]);
    final reply = await engine.reply('mở bảo dưỡng');
    expect(reply.action, isNull);
    expect(host.navigated, ['maintenance']);
  });

  test(
    'target charging is prepared on the Charge tab, never started',
    () async {
      final engine = build([
        const AssistantTurn(
          reply: 'Mình mở tab Sạc với mục tiêu 80%',
          actions: [
            AssistantAction('prepare_target_charging', {'percent': 80}),
          ],
        ),
      ]);
      final reply = await engine.reply('sạc đến 80%');
      expect(reply.action, isNull); // no relay proposal, no card to confirm
      expect(local.asked, isEmpty);
      expect(host.prepared.single.$1, 'prepare_target_charging');
      expect(host.prepared.single.$2['percent'], 80);
    },
  );

  test('trip estimate card comes back with the answer', () async {
    final engine = build([
      const AssistantTurn(
        reply: 'Không đủ pin, bạn nên sạc lên 80% trước.',
        actions: [
          AssistantAction('plan_trip', {'destination': 'Nội Bài'}),
        ],
        card: {
          'cardType': 'trip_plan',
          'data': {'usePct': 40},
        },
      ),
    ]);
    final reply = await engine.reply('đi Nội Bài được không');
    expect(host.prepared.single.$1, 'plan_trip');
    expect(reply.card?['cardType'], 'trip_plan');
    expect(reply.text, startsWith('Không đủ pin'));
  });

  test('charging goes through the on-device verified proposal', () async {
    final engine = build([
      const AssistantTurn(
        reply: 'Mình chuẩn bị sạc 30 phút',
        actions: [
          AssistantAction('start_timed_charging', {'minutes': 30}),
        ],
      ),
    ]);
    final reply = await engine.reply('sạc 30 phút');
    expect(local.asked, ['bật sạc 30 phút']);
    expect(reply.action!.callId, 'local-1');
    expect(reply.text, 'Mình chuẩn bị sạc 30 phút');
    // Confirmation is owned by the local engine (slide-to-confirm, gateway).
    await engine.confirm('local-1', true);
    expect(local.confirmed, ['local-1']);
    expect(host.applied, isEmpty);
  });

  test('reminder dates are rewritten for the on-device parser', () async {
    final engine = build([
      const AssistantTurn(
        reply: 'ok',
        actions: [
          AssistantAction('create_reminder', {
            'kind': 'maintenance',
            'date': '2026-11-20',
            'note': 'thay dầu phanh',
          }),
        ],
      ),
    ]);
    await engine.reply('đặt lịch');
    expect(local.asked, ['nhắc bảo dưỡng thay dầu phanh ngày 20/11/2026']);
  });

  test(
    'one-tap change needs confirmation, runs once and can be undone',
    () async {
      final engine = build([
        const AssistantTurn(
          reply: 'Cập nhật pin 60%',
          actions: [
            AssistantAction('update_battery_level', {'percent': 60}),
          ],
        ),
      ]);
      final reply = await engine.reply('pin 60%');
      expect(host.applied, isEmpty); // nothing before confirmation
      final id = reply.action!.callId;
      expect(reply.action!.toolName, 'app_update_battery_level');
      final result = await engine.confirm(id, true);
      expect(result['status'], 'verified');
      expect(host.battery, 60);
      expect((await engine.confirm(id, true))['status'], 'expired');
      expect(host.applied, ['update_battery_level']);
      expect((await engine.reply('hoàn tác')).text, contains('mức pin về 40%'));
      expect(host.battery, 40);
    },
  );

  test(
    'refused change reports the reason; cancelled change does nothing',
    () async {
      final engine = build([
        const AssistantTurn(
          reply: 'ODO',
          actions: [
            AssistantAction('update_odometer', {'km': 5}),
          ],
        ),
        const AssistantTurn(
          reply: 'pin',
          actions: [
            AssistantAction('update_battery_level', {'percent': 10}),
          ],
        ),
      ]);
      final odo = await engine.reply('odo 5');
      final refused = await engine.confirm(odo.action!.callId, true);
      expect(refused['status'], 'blocked');
      expect(refused['message'], contains('nhỏ hơn'));
      final pin = await engine.reply('pin 10');
      expect(
        (await engine.confirm(pin.action!.callId, false))['status'],
        'cancelled',
      );
      expect(host.battery, 40);
    },
  );

  test('offline or out of quota falls back to the basic engine', () async {
    final engine = build([
      const AssistantUnavailable('network'),
      const AssistantUnavailable('ASSISTANT_QUOTA'),
    ]);
    final offline = await engine.reply('xem pin ở đâu');
    expect(offline.text, startsWith('Chế độ cơ bản'));
    expect(offline.text, contains('FAQ answer'));
    final quota = await engine.reply('xem pin ở đâu');
    expect(quota.text, contains('hết lượt AI hôm nay'));
  });

  test('a confirmation from a previous account is refused', () async {
    final engine = build([
      const AssistantTurn(
        reply: 'pin',
        actions: [
          AssistantAction('update_battery_level', {'percent': 70}),
        ],
      ),
    ]);
    final reply = await engine.reply('pin 70');
    uid = 'someone-else';
    expect(
      (await engine.confirm(reply.action!.callId, true))['status'],
      'expired',
    );
    expect(host.applied, isEmpty);
  });

  test('app settings use a one-tap card that states the effect', () async {
    final engine = build([
      const AssistantTurn(
        reply: 'Tắt thông báo',
        actions: [
          AssistantAction('set_app_setting', {
            'setting': 'push_notifications',
            'value': 'off',
          }),
        ],
      ),
      const AssistantTurn(
        reply: 'English',
        actions: [
          AssistantAction('set_app_setting', {
            'setting': 'language',
            'value': 'en',
          }),
        ],
      ),
    ]);
    final push = await engine.reply('tắt thông báo');
    expect(push.action!.toolName, 'app_set_app_setting');
    expect(push.action!.cardData!.title, 'Tắt thông báo đẩy');
    expect(push.action!.cardData!.description, contains('máy khác'));
    expect(host.applied, isEmpty);
    await engine.confirm(push.action!.callId, true);
    expect(host.applied, ['set_app_setting']);
    final language = await engine.reply('dùng tiếng anh');
    expect(language.action, isNull);
    expect(language.text, contains('chỉ có tiếng Việt'));
  });
}
