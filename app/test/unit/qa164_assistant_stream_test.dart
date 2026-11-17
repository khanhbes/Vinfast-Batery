import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vinfast_battery/core/constants/app_constants.dart';
import 'package:vinfast_battery/features/ai/services/assistant_api.dart';

/// QA 164 (owner's choice): Pinova Bot's answer arrives as it is written.
/// The app reads server-sent events into [AssistantSignals] and takes the
/// final, checked answer from `done`; an older server's JSON still works.
class _Client extends http.BaseClient {
  _Client(this.respond);
  final http.StreamedResponse Function(http.BaseRequest request) respond;
  final requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request as http.Request);
    return respond(request);
  }
}

String _event(String name, Object data) =>
    'event: $name\ndata: ${jsonEncode(data)}\n\n';

void main() {
  setUp(() {
    AppConstants.setCustomApiBaseUrl('https://api.example.test');
    AssistantSignals.clearLive();
  });
  tearDown(() => AppConstants.setCustomApiBaseUrl(''));

  AssistantApi api(_Client client) =>
      AssistantApi(client: client, tokenResolver: () async => 'token');

  test('deltas and status reach the sheet, done gives the turn', () async {
    final controller = StreamController<List<int>>();
    final client = _Client(
      (_) => http.StreamedResponse(
        controller.stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      ),
    );
    final seen = <String>[];
    void listen() => seen.add(AssistantSignals.liveText.value);
    AssistantSignals.liveText.addListener(listen);
    addTearDown(() => AssistantSignals.liveText.removeListener(listen));
    final turn = api(
      client,
    ).chat(message: 'pin', history: const [], context: const {});
    controller.add(utf8.encode(_event('start', {'botVersion': '3.3.0'})));
    controller.add(
      utf8.encode(_event('status', {'text': 'Đang xem ổ Shelly…'})),
    );
    await pumpEventQueue();
    expect(AssistantSignals.liveStatus.value, 'Đang xem ổ Shelly…');
    controller.add(utf8.encode(_event('delta', {'text': 'Pin còn '})));
    controller.add(utf8.encode(_event('delta', {'text': '40%.'})));
    await pumpEventQueue();
    expect(AssistantSignals.liveText.value, 'Pin còn 40%.');
    expect(AssistantSignals.liveStatus.value, isNull);
    controller.add(
      utf8.encode(
        _event('done', {
          'reply': 'Pin còn 40%.',
          'actions': [],
          'followUps': ['Sạc lên 80% mất bao lâu?'],
          'remainingToday': 9,
        }),
      ),
    );
    final result = await turn;
    await controller.close();
    expect(result.reply, 'Pin còn 40%.');
    expect(result.followUps, ['Sạc lên 80% mất bao lâu?']);
    expect(result.remainingToday, 9);
    expect(seen, containsAllInOrder(['Pin còn ', 'Pin còn 40%.']));
    final body = jsonDecode(client.requests.single.body) as Map;
    expect(body['stream'], isTrue);
    expect(
      client.requests.single.headers['Accept'],
      contains('text/event-stream'),
    );
  });

  test('an older server answers JSON and it is read as before', () async {
    final client = _Client(
      (_) => http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'success': true,
              'data': {'reply': 'Chào bạn', 'actions': []},
            }),
          ),
        ),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final turn = await api(
      client,
    ).chat(message: 'chào', history: const [], context: const {});
    expect(turn.reply, 'Chào bạn');
  });

  test('a stream error is the basic mode, not a half answer', () async {
    final client = _Client(
      (_) => http.StreamedResponse(
        Stream.value(
          utf8.encode(
            _event('delta', {'text': 'Pin '}) +
                _event('error', {'code': 'ASSISTANT_UNAVAILABLE'}),
          ),
        ),
        200,
        headers: {'content-type': 'text/event-stream'},
      ),
    );
    await expectLater(
      api(client).chat(message: 'pin', history: const [], context: const {}),
      throwsA(
        isA<AssistantUnavailable>().having(
          (e) => e.code,
          'code',
          'ASSISTANT_UNAVAILABLE',
        ),
      ),
    );
  });

  test('a stream that ends without done is incomplete', () async {
    final client = _Client(
      (_) => http.StreamedResponse(
        Stream.value(utf8.encode(_event('delta', {'text': 'Pin '}))),
        200,
        headers: {'content-type': 'text/event-stream'},
      ),
    );
    await expectLater(
      api(client).chat(message: 'pin', history: const [], context: const {}),
      throwsA(
        isA<AssistantUnavailable>().having((e) => e.code, 'code', 'incomplete'),
      ),
    );
  });

  test('quota over before the model comes back as JSON 429', () async {
    final client = _Client(
      (_) => http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'success': false,
              'error': {'code': 'ASSISTANT_QUOTA', 'message': 'hết lượt'},
            }),
          ),
        ),
        429,
        headers: {'content-type': 'application/json'},
      ),
    );
    await expectLater(
      api(client).chat(message: 'pin', history: const [], context: const {}),
      throwsA(
        isA<AssistantUnavailable>().having((e) => e.quota, 'quota', true),
      ),
    );
  });
}
