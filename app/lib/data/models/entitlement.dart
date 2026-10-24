/// Pinova Premium (QA 135). Mirrors `web/billing/features.py` for display;
/// the server decides every gate.
enum PlanTier {
  free('free', 'Free'),
  pro('pro', 'Pro'),
  ultra('ultra', 'Ultra');

  const PlanTier(this.id, this.label);
  final String id;
  final String label;

  static PlanTier parse(Object? value) => PlanTier.values.firstWhere(
    (t) => t.id == value?.toString().toLowerCase(),
    orElse: () => PlanTier.free,
  );

  bool covers(PlanTier other) => index >= other.index;
}

enum PlanPeriod {
  month('month', 'Tháng'),
  year('year', 'Năm');

  const PlanPeriod(this.id, this.label);
  final String id;
  final String label;
}

/// Premium features (server ids). Safety and the core are not listed: they
/// are free on every plan.
enum PremiumFeature {
  targetCharging('target_charging', PlanTier.pro, 'Sạc đến % tự ngắt'),
  targetEdit('target_edit', PlanTier.pro, 'Sửa mục tiêu khi đang sạc'),
  progressPush('progress_push', PlanTier.pro, 'Thông báo tiến độ sạc'),
  batteryHealth('battery_health', PlanTier.pro, '% pin chai'),
  appearance('appearance', PlanTier.pro, 'Giao diện tùy chọn'),
  historyExport('history_export', PlanTier.pro, 'Xuất lịch sử CSV'),
  widget('widget', PlanTier.pro, 'Widget màn hình chính'),
  learningTrain('learning_train', PlanTier.ultra, 'AI cá nhân'),
  tripEstimate('trip_estimate', PlanTier.ultra, 'Dự đoán pin theo lộ trình'),
  costAdvanced('cost_advanced', PlanTier.ultra, 'Thống kê chi phí nâng cao'),
  nightCharging('night_charging', PlanTier.ultra, 'Sạc đêm an toàn'),
  offpeakSchedule('offpeak_schedule', PlanTier.ultra, 'Sạc giờ điện rẻ'),
  shareVehicle('share_vehicle', PlanTier.ultra, 'Chia sẻ xe với người nhà'),
  monthlyReport('monthly_report', PlanTier.ultra, 'Báo cáo pin hằng tháng');

  const PremiumFeature(this.id, this.tier, this.label);
  final String id;
  final PlanTier tier;
  final String label;
}

abstract final class PlanTable {
  static const prices = {
    PlanTier.pro: {PlanPeriod.month: 29000, PlanPeriod.year: 249000},
    PlanTier.ultra: {PlanPeriod.month: 49000, PlanPeriod.year: 449000},
  };

  static const assistantDaily = {
    PlanTier.free: 10,
    PlanTier.pro: 30,
    PlanTier.ultra: 100,
  };
  static const scanAiDaily = {
    PlanTier.free: 5,
    PlanTier.pro: 30,
    PlanTier.ultra: 100,
  };
  static const historyDays = {
    PlanTier.free: 30,
    PlanTier.pro: null,
    PlanTier.ultra: null,
  };
  static const maxVehicles = {
    PlanTier.free: 1,
    PlanTier.pro: 2,
    PlanTier.ultra: 10,
  };

  static int price(PlanTier tier, PlanPeriod period) =>
      prices[tier]?[period] ?? 0;

  /// What a yearly plan saves against twelve months.
  static int yearlySavingPct(PlanTier tier) {
    final month = price(tier, PlanPeriod.month) * 12;
    if (month == 0) return 0;
    return ((month - price(tier, PlanPeriod.year)) * 100 / month).round();
  }
}

/// A promo code checked by the server: prices after the discount for the
/// plans/periods it applies to.
class PromoQuote {
  const PromoQuote({
    required this.code,
    required this.percentOff,
    required this.validTo,
    required this.finalPrices,
  });

  final String code;
  final int percentOff;
  final DateTime? validTo;
  final Map<PlanTier, Map<PlanPeriod, int>> finalPrices;

  int? finalPrice(PlanTier tier, PlanPeriod period) =>
      finalPrices[tier]?[period];

  static PromoQuote? fromMap(Object? raw) {
    if (raw is! Map || raw['code'] is! String) return null;
    final prices = <PlanTier, Map<PlanPeriod, int>>{};
    final source = raw['prices'];
    if (source is Map) {
      for (final tier in [PlanTier.pro, PlanTier.ultra]) {
        final byPeriod = source[tier.id];
        if (byPeriod is! Map) continue;
        for (final period in PlanPeriod.values) {
          final entry = byPeriod[period.id];
          final value = entry is Map ? entry['final'] : null;
          if (value is num) {
            (prices[tier] ??= {})[period] = value.toInt();
          }
        }
      }
    }
    return PromoQuote(
      code: raw['code'] as String,
      percentOff: (raw['percentOff'] as num?)?.toInt() ?? 0,
      validTo: DateTime.tryParse(raw['validTo']?.toString() ?? ''),
      finalPrices: prices,
    );
  }

  Map<String, Object?> toMap() => {
    'code': code,
    'percentOff': percentOff,
    'validTo': validTo?.toIso8601String(),
    'prices': {
      for (final tier in finalPrices.keys)
        tier.id: {
          for (final e in finalPrices[tier]!.entries)
            e.key.id: {'final': e.value},
        },
    },
  };
}

/// The account's plan as the server reported it.
class Entitlement {
  const Entitlement({
    this.tier = PlanTier.free,
    this.status = 'none',
    this.expiresAt,
    this.trialAvailable = false,
    this.trialDays = 7,
    this.features = const {},
    this.limits = const {},
    this.pendingPromo,
    this.enforced = true,
    this.known = false,
    this.serverSupportsBilling = true,
  });

  final PlanTier tier;

  /// none | trial | active | expired | revoked.
  final String status;
  final DateTime? expiresAt;
  final bool trialAvailable;
  final int trialDays;

  /// Gate answers from the server (`target_charging: true`, ...).
  final Map<String, bool> features;
  final Map<String, int?> limits;
  final PromoQuote? pendingPromo;
  final bool enforced;

  /// False until the server (or the phone's cache) answered once.
  final bool known;

  /// False when the server predates QA 135 (no billing yet): nothing is
  /// gated then, exactly like before.
  final bool serverSupportsBilling;

  static const legacyServer = Entitlement(
    known: true,
    serverSupportsBilling: false,
    enforced: false,
  );

  bool get isTrial => status == 'trial';
  bool get isPremium => tier != PlanTier.free;

  /// Display answer. Before the first server reply nothing shows a lock
  /// (the server rejects what the plan does not include anyway).
  bool allows(PremiumFeature feature) {
    if (!known || !serverSupportsBilling || !enforced) return true;
    final answer = features[feature.id];
    if (answer != null) return answer;
    return tier.covers(feature.tier);
  }

  int? limit(String name, Map<PlanTier, int?> table) =>
      limits.containsKey(name) ? limits[name] : table[tier];

  int get assistantDaily =>
      limit('assistant_daily', PlanTable.assistantDaily) ?? 100;
  int get maxVehicles => limit('max_vehicles', PlanTable.maxVehicles) ?? 10;
  int? get historyDays => known && serverSupportsBilling && enforced
      ? limit('history_days', PlanTable.historyDays)
      : null;

  /// Days left on a trial or plan (rounded up), null when it never ends.
  int? daysLeft(DateTime now) {
    final end = expiresAt;
    if (end == null || !isPremium) return null;
    final hours = end.difference(now).inHours;
    return hours <= 0 ? 0 : (hours / 24).ceil();
  }

  static Entitlement fromMap(Map<String, dynamic> map) {
    final rawFeatures = map['features'];
    final rawLimits = map['limits'];
    return Entitlement(
      tier: PlanTier.parse(map['tier']),
      status: map['status']?.toString() ?? 'none',
      expiresAt: DateTime.tryParse(map['expiresAt']?.toString() ?? ''),
      trialAvailable: map['trialAvailable'] == true,
      trialDays: (map['trialDays'] as num?)?.toInt() ?? 7,
      features: {
        if (rawFeatures is Map)
          for (final e in rawFeatures.entries)
            if (e.value is bool) e.key.toString(): e.value as bool,
      },
      limits: {
        if (rawLimits is Map)
          for (final e in rawLimits.entries)
            e.key.toString(): (e.value as num?)?.toInt(),
      },
      pendingPromo: PromoQuote.fromMap(map['pendingPromo']),
      enforced: map['enforced'] != false,
      known: true,
    );
  }

  Map<String, Object?> toMap() => {
    'tier': tier.id,
    'status': status,
    'expiresAt': expiresAt?.toIso8601String(),
    'trialAvailable': trialAvailable,
    'trialDays': trialDays,
    'features': features,
    'limits': limits,
    'pendingPromo': pendingPromo?.toMap(),
    'enforced': enforced,
  };
}
