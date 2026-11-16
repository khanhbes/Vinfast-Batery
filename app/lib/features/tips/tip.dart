/// QA 163: one tip of "Mẹo nhỏ" (the same list as Pinova Bot's, from
/// `assets/tips/tips_vi.json` or `/api/tips`).
class Tip {
  const Tip({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    this.appliesTo = 'all',
    this.tags = const [],
    this.when = 'any',
    this.action,
    this.sourceName,
    this.sourceUrl,
  });

  final String id;

  /// drive | charge | battery | weather | storage | safety | app
  final String category;
  final String title;
  final String body;

  /// all | lithium | leadAcid
  final String appliesTo;
  final List<String> tags;

  /// morning | afterCharge | lowBattery | rain | any
  final String when;

  /// A screen Pinova Bot can open too (`navigate`): charge, trip_planner…
  final String? action;
  final String? sourceName;
  final String? sourceUrl;

  static Tip? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], title = raw['title'], body = raw['body'];
    if (id is! String || title is! String || body is! String) return null;
    final source = raw['source'] is Map ? raw['source'] as Map : const {};
    final url = source['url'];
    return Tip(
      id: id,
      category: raw['category']?.toString() ?? 'app',
      title: title,
      body: body,
      appliesTo: raw['appliesTo']?.toString() ?? 'all',
      tags: [for (final t in (raw['tags'] as List? ?? const [])) '$t'],
      when: raw['when']?.toString() ?? 'any',
      action: raw['action']?.toString(),
      sourceName: source['name']?.toString(),
      sourceUrl: url is String && url.startsWith('https://') ? url : null,
    );
  }

  /// Fits a battery: [leadAcid] null when the vehicle's type is unknown
  /// (then both kinds are shown).
  bool fits({bool? leadAcid}) => switch (appliesTo) {
    'lithium' => leadAcid != true,
    'leadAcid' => leadAcid != false,
    _ => true,
  };

  /// "Pin lithium" / "Ắc quy chì" when the tip is for one kind only.
  String? get batteryLabel => switch (appliesTo) {
    'lithium' => 'Pin lithium',
    'leadAcid' => 'Ắc quy chì',
    _ => null,
  };
}

/// The groups of "Mẹo nhỏ", in screen order.
const tipCategories = <(String, String)>[
  ('drive', 'Lái xe'),
  ('charge', 'Sạc pin'),
  ('battery', 'Giữ pin bền'),
  ('weather', 'Mưa & nắng'),
  ('storage', 'Cất xe'),
  ('safety', 'An toàn'),
  ('app', 'Dùng app'),
];

/// QA 163: which tip Pinova Bot tells today. Pure, so it is tested alone.
abstract final class TipPicker {
  /// A tip for this moment that fits the battery, unseen ones first; the
  /// choice is stable for the day (same tip on every open). Null when none.
  static Tip? pick(
    List<Tip> tips, {
    required DateTime now,
    Set<String> seen = const {},
    bool? leadAcid,
    int? batteryPercent,
    bool charging = false,
  }) {
    final fitting = [
      for (final tip in tips)
        if (tip.fits(leadAcid: leadAcid)) tip,
    ];
    if (fitting.isEmpty) return null;
    final moments = <String>{
      if (now.hour >= 5 && now.hour < 10) 'morning',
      if (batteryPercent != null && batteryPercent < 30 && !charging)
        'lowBattery',
      if (charging || (batteryPercent != null && batteryPercent >= 80))
        'afterCharge',
      // The rainy season in most of Vietnam.
      if (now.month >= 5 && now.month <= 10) 'rain',
    };
    List<Tip> pool(bool unseenOnly, bool momentOnly) => [
      for (final tip in fitting)
        if ((!unseenOnly || !seen.contains(tip.id)) &&
            (!momentOnly || moments.contains(tip.when)))
          tip,
    ];
    final candidates = [
      pool(true, true),
      pool(true, false),
      pool(false, true),
      fitting,
    ].firstWhere((list) => list.isNotEmpty);
    final day = DateTime(now.year, now.month, now.day);
    final index =
        day.difference(DateTime(2026)).inDays.abs() % candidates.length;
    return candidates[index];
  }
}
