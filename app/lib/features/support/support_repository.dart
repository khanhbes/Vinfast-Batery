import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/pinova_api.dart';

/// What the owner asks about (server ids, `web/support/tickets.py`).
enum SupportCategory {
  charging('charging', 'Sạc pin'),
  shelly('shelly', 'Ổ sạc Shelly'),
  scan('scan', 'Quét đồng hồ'),
  battery('battery', 'Pin & quãng đường'),
  billing('billing', 'Gói Premium'),
  account('account', 'Tài khoản'),
  app('app', 'Lỗi ứng dụng'),
  other('other', 'Khác');

  const SupportCategory(this.id, this.label);
  final String id;
  final String label;

  static SupportCategory parse(Object? value) => SupportCategory.values
      .firstWhere((c) => c.id == value, orElse: () => SupportCategory.other);
}

class SupportReply {
  const SupportReply({
    required this.at,
    required this.fromAdmin,
    required this.text,
  });
  final DateTime? at;
  final bool fromAdmin;
  final String text;
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.subject,
    required this.category,
    required this.message,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.replies,
    required this.unread,
  });

  final String id;
  final String subject;
  final SupportCategory category;
  final String message;

  /// open | answered | closed.
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<SupportReply> replies;

  /// The team answered and the owner has not opened it yet.
  final bool unread;

  String get statusLabel => switch (status) {
    'answered' => 'Đã trả lời',
    'closed' => 'Đã đóng',
    _ => 'Đang chờ',
  };

  static SupportTicket fromMap(Map<String, dynamic> map) => SupportTicket(
    id: map['id']?.toString() ?? '',
    subject: map['subject']?.toString() ?? '',
    category: SupportCategory.parse(map['category']),
    message: map['message']?.toString() ?? '',
    status: map['status']?.toString() ?? 'open',
    createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? ''),
    updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? ''),
    replies: [
      for (final r in (map['replies'] as List? ?? const []))
        if (r is Map)
          SupportReply(
            at: DateTime.tryParse(r['at']?.toString() ?? ''),
            fromAdmin: r['by'] == 'admin',
            text: r['text']?.toString() ?? '',
          ),
    ],
    unread: map['unread'] == true,
  );
}

/// `/api/support/*` (QA 135).
class SupportRepository {
  SupportRepository({PinovaApi? api}) : _api = api ?? PinovaApi();
  final PinovaApi _api;

  Future<SupportTicket> create({
    required SupportCategory category,
    required String subject,
    required String message,
    Map<String, Object?>? diagnostics,
  }) async => SupportTicket.fromMap(
    await _api.post('/api/support/tickets', {
      'category': category.id,
      'subject': subject,
      'message': message,
      'diagnostics': ?diagnostics,
    }),
  );

  Future<List<SupportTicket>> mine() async {
    final data = await _api.get('/api/support/tickets');
    return [
      for (final item in (data['items'] as List? ?? const []))
        if (item is Map) SupportTicket.fromMap(Map<String, dynamic>.from(item)),
    ];
  }

  Future<SupportTicket> get(String id) async => SupportTicket.fromMap(
    await _api.get('/api/support/tickets/${Uri.encodeComponent(id)}'),
  );

  Future<SupportTicket> reply(String id, String text) async =>
      SupportTicket.fromMap(
        await _api.post(
          '/api/support/tickets/${Uri.encodeComponent(id)}/replies',
          {'text': text},
        ),
      );
}

final supportRepositoryProvider = Provider<SupportRepository>(
  (ref) => SupportRepository(),
);

final supportTicketsProvider = FutureProvider.autoDispose<List<SupportTicket>>(
  (ref) => ref.watch(supportRepositoryProvider).mine(),
);
