import 'package:flutter/material.dart';

/// Rarity drives the medal metal, the points and the ceremony intensity.
enum AchievementRarity {
  bronze('Đồng', 10, [Color(0xFFF6D3AE), Color(0xFFC98A55), Color(0xFF6E4021)]),
  silver('Bạc', 25, [Color(0xFFF6F7F9), Color(0xFFBFC3C9), Color(0xFF686D74)]),
  gold('Vàng', 50, [Color(0xFFFFF0BF), Color(0xFFE2B654), Color(0xFF7E5A18)]),
  platinum('Bạch kim', 100, [
    Color(0xFFFFFFFF),
    Color(0xFFCDD5DE),
    Color(0xFF768392),
  ]),
  emerald('Ngọc lục bảo', 250, [
    Color(0xFFD5FBEA),
    Color(0xFF34D399),
    Color(0xFF065F46),
  ]);

  const AchievementRarity(this.label, this.points, this.metal);
  final String label;
  final int points;

  /// Highlight → body → shadow.
  final List<Color> metal;

  Color get accent => metal[1];
}

enum AchievementCategory {
  energy('Năng lượng', Icons.bolt_rounded),
  sessions('Phiên sạc', Icons.ev_station_rounded),
  ai('Sạc AI', Icons.auto_awesome_rounded),
  care('Chăm pin', Icons.favorite_rounded),
  timing('Giờ sạc', Icons.schedule_rounded),
  streak('Chuỗi', Icons.local_fire_department_rounded),
  eco('Sống xanh', Icons.eco_rounded),
  explore('Khám phá', Icons.explore_rounded),
  secret('Bí mật', Icons.lock_rounded);

  const AchievementCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// What an achievement measures; values come from [AchievementStats].
enum AchievementMetric {
  kwh,
  sessions,
  aiSessions,
  timedSessions,
  care80,
  goldenStart,
  balanceMonths,
  offPeak,
  morning,
  weekend,
  weekStreak,
  activeMonths,
  dayStreak,
  co2Kg,
  km,
  number88,
  nightOwl,
  lightning,
  patience,
  newYear,
  earthDay,
  event,
}

/// App events counted by the explore family (recorded by the features).
abstract final class AchievementEvents {
  static const shellyLinked = 'shelly_linked';
  static const safetyVerified = 'safety_verified';
  static const botCharge = 'bot_charge';
  static const aiPreview = 'ai_preview';
  static const collectionOpened = 'collection_opened';
  static const historyViewed = 'history_viewed';
}

class AchievementDef {
  const AchievementDef({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.rarity,
    required this.icon,
    required this.metric,
    required this.target,
    this.unit = '',
    this.event,
  });

  final String id;
  final String title;

  /// How to unlock it, written as an invitation.
  final String description;
  final AchievementCategory category;
  final AchievementRarity rarity;
  final IconData icon;
  final AchievementMetric metric;
  final double target;
  final String unit;

  /// For [AchievementMetric.event]: the event name.
  final String? event;

  bool get secret => category == AchievementCategory.secret;
  int get points => rarity.points;
}

/// User rank from the sum of unlocked points.
class AchievementRank {
  const AchievementRank(this.name, this.minPoints, this.rarity);
  final String name;
  final int minPoints;
  final AchievementRarity rarity;

  static const all = [
    AchievementRank('Hạng Đồng', 0, AchievementRarity.bronze),
    AchievementRank('Hạng Bạc', 150, AchievementRarity.silver),
    AchievementRank('Hạng Vàng', 500, AchievementRarity.gold),
    AchievementRank('Hạng Bạch kim', 1200, AchievementRarity.platinum),
    AchievementRank('Hạng Ngọc lục bảo', 2400, AchievementRarity.emerald),
  ];

  static AchievementRank forPoints(int points) =>
      all.lastWhere((r) => points >= r.minPoints);

  AchievementRank? get next {
    final i = all.indexOf(this);
    return i + 1 < all.length ? all[i + 1] : null;
  }
}

const _b = AchievementRarity.bronze;
const _s = AchievementRarity.silver;
const _g = AchievementRarity.gold;
const _p = AchievementRarity.platinum;
const _e = AchievementRarity.emerald;

AchievementDef _def(
  String id,
  String title,
  String description,
  AchievementCategory category,
  AchievementRarity rarity,
  IconData icon,
  AchievementMetric metric,
  double target, {
  String unit = '',
  String? event,
}) => AchievementDef(
  id: id,
  title: title,
  description: description,
  category: category,
  rarity: rarity,
  icon: icon,
  metric: metric,
  target: target,
  unit: unit,
  event: event,
);

/// The full collection. Thresholds suit an electric scooter (~2–3 kWh per
/// charge): the first medals arrive in the first week, emerald ones are
/// for long-time riders.
final List<AchievementDef> achievementCatalog = [
  // ── Năng lượng (kWh tích lũy) ──
  _def(
    'kwh_1',
    'Giọt năng lượng',
    'Nạp tổng cộng 1 kWh qua Smart Charge.',
    AchievementCategory.energy,
    _b,
    Icons.water_drop_rounded,
    AchievementMetric.kwh,
    1,
    unit: 'kWh',
  ),
  _def(
    'kwh_10',
    'Dòng điện nhỏ',
    'Nạp tổng cộng 10 kWh.',
    AchievementCategory.energy,
    _b,
    Icons.electrical_services_rounded,
    AchievementMetric.kwh,
    10,
    unit: 'kWh',
  ),
  _def(
    'kwh_25',
    'Mạch năng lượng',
    'Nạp tổng cộng 25 kWh.',
    AchievementCategory.energy,
    _s,
    Icons.cable_rounded,
    AchievementMetric.kwh,
    25,
    unit: 'kWh',
  ),
  _def(
    'kwh_50',
    'Trạm tích điện',
    'Nạp tổng cộng 50 kWh.',
    AchievementCategory.energy,
    _s,
    Icons.battery_charging_full_rounded,
    AchievementMetric.kwh,
    50,
    unit: 'kWh',
  ),
  _def(
    'kwh_100',
    'Trăm số điện',
    'Nạp tổng cộng 100 kWh.',
    AchievementCategory.energy,
    _g,
    Icons.flash_on_rounded,
    AchievementMetric.kwh,
    100,
    unit: 'kWh',
  ),
  _def(
    'kwh_250',
    'Nhà máy mini',
    'Nạp tổng cộng 250 kWh.',
    AchievementCategory.energy,
    _g,
    Icons.factory_rounded,
    AchievementMetric.kwh,
    250,
    unit: 'kWh',
  ),
  _def(
    'kwh_500',
    'Lưới điện riêng',
    'Nạp tổng cộng 500 kWh.',
    AchievementCategory.energy,
    _p,
    Icons.hub_rounded,
    AchievementMetric.kwh,
    500,
    unit: 'kWh',
  ),
  _def(
    'kwh_1000',
    'Megawatt huyền thoại',
    'Nạp tổng cộng 1.000 kWh — một megawatt-giờ.',
    AchievementCategory.energy,
    _e,
    Icons.wb_sunny_rounded,
    AchievementMetric.kwh,
    1000,
    unit: 'kWh',
  ),

  // ── Phiên sạc ──
  _def(
    'ses_1',
    'Lần sạc đầu tiên',
    'Hoàn tất phiên sạc đầu tiên.',
    AchievementCategory.sessions,
    _b,
    Icons.power_rounded,
    AchievementMetric.sessions,
    1,
    unit: 'phiên',
  ),
  _def(
    'ses_5',
    'Bắt nhịp',
    'Hoàn tất 5 phiên sạc.',
    AchievementCategory.sessions,
    _b,
    Icons.repeat_rounded,
    AchievementMetric.sessions,
    5,
    unit: 'phiên',
  ),
  _def(
    'ses_10',
    'Thói quen tốt',
    'Hoàn tất 10 phiên sạc.',
    AchievementCategory.sessions,
    _s,
    Icons.check_circle_rounded,
    AchievementMetric.sessions,
    10,
    unit: 'phiên',
  ),
  _def(
    'ses_25',
    'Người sạc chăm chỉ',
    'Hoàn tất 25 phiên sạc.',
    AchievementCategory.sessions,
    _s,
    Icons.military_tech_rounded,
    AchievementMetric.sessions,
    25,
    unit: 'phiên',
  ),
  _def(
    'ses_50',
    'Nửa trăm',
    'Hoàn tất 50 phiên sạc.',
    AchievementCategory.sessions,
    _g,
    Icons.workspace_premium_rounded,
    AchievementMetric.sessions,
    50,
    unit: 'phiên',
  ),
  _def(
    'ses_100',
    'Bách phiên',
    'Hoàn tất 100 phiên sạc.',
    AchievementCategory.sessions,
    _g,
    Icons.emoji_events_rounded,
    AchievementMetric.sessions,
    100,
    unit: 'phiên',
  ),
  _def(
    'ses_200',
    'Bậc thầy sạc',
    'Hoàn tất 200 phiên sạc.',
    AchievementCategory.sessions,
    _p,
    Icons.stars_rounded,
    AchievementMetric.sessions,
    200,
    unit: 'phiên',
  ),
  _def(
    'ses_365',
    'Trọn vòng năm',
    'Hoàn tất 365 phiên sạc.',
    AchievementCategory.sessions,
    _e,
    Icons.all_inclusive_rounded,
    AchievementMetric.sessions,
    365,
    unit: 'phiên',
  ),

  // ── Sạc AI ──
  _def(
    'ai_preview',
    'Hỏi ý AI',
    'Lập kế hoạch sạc đầu tiên bằng AI.',
    AchievementCategory.ai,
    _b,
    Icons.psychology_rounded,
    AchievementMetric.event,
    1,
    event: AchievementEvents.aiPreview,
  ),
  _def(
    'ai_1',
    'Tin tưởng AI',
    'Hoàn tất một phiên Sạc AI.',
    AchievementCategory.ai,
    _b,
    Icons.auto_awesome_rounded,
    AchievementMetric.aiSessions,
    1,
    unit: 'phiên',
  ),
  _def(
    'ai_5',
    'Cộng sự thông minh',
    'Hoàn tất 5 phiên Sạc AI.',
    AchievementCategory.ai,
    _s,
    Icons.smart_toy_rounded,
    AchievementMetric.aiSessions,
    5,
    unit: 'phiên',
  ),
  _def(
    'ai_15',
    'Nhịp sạc cá nhân',
    'Hoàn tất 15 phiên Sạc AI — AI hiểu thói quen của bạn hơn.',
    AchievementCategory.ai,
    _g,
    Icons.insights_rounded,
    AchievementMetric.aiSessions,
    15,
    unit: 'phiên',
  ),
  _def(
    'ai_40',
    'Đồng điệu với AI',
    'Hoàn tất 40 phiên Sạc AI.',
    AchievementCategory.ai,
    _p,
    Icons.hub_rounded,
    AchievementMetric.aiSessions,
    40,
    unit: 'phiên',
  ),

  // ── Hẹn giờ ──
  _def(
    'timed_1',
    'Đặt hẹn giờ',
    'Hoàn tất một phiên Sạc hẹn giờ.',
    AchievementCategory.sessions,
    _b,
    Icons.timer_rounded,
    AchievementMetric.timedSessions,
    1,
    unit: 'phiên',
  ),
  _def(
    'timed_10',
    'Đúng giờ đúng hẹn',
    'Hoàn tất 10 phiên Sạc hẹn giờ.',
    AchievementCategory.sessions,
    _s,
    Icons.alarm_on_rounded,
    AchievementMetric.timedSessions,
    10,
    unit: 'phiên',
  ),
  _def(
    'timed_30',
    'Người giữ nhịp',
    'Hoàn tất 30 phiên Sạc hẹn giờ.',
    AchievementCategory.sessions,
    _g,
    Icons.av_timer_rounded,
    AchievementMetric.timedSessions,
    30,
    unit: 'phiên',
  ),

  // ── Chăm pin ──
  _def(
    'care80_5',
    'Người giữ 80',
    'Sạc AI với mục tiêu tối đa 80% trong 5 phiên.',
    AchievementCategory.care,
    _b,
    Icons.shield_rounded,
    AchievementMetric.care80,
    5,
    unit: 'phiên',
  ),
  _def(
    'care80_20',
    'Bảo vệ cell pin',
    'Mục tiêu tối đa 80% trong 20 phiên.',
    AchievementCategory.care,
    _s,
    Icons.health_and_safety_rounded,
    AchievementMetric.care80,
    20,
    unit: 'phiên',
  ),
  _def(
    'care80_50',
    'Pin bền bỉ',
    'Mục tiêu tối đa 80% trong 50 phiên.',
    AchievementCategory.care,
    _g,
    Icons.verified_user_rounded,
    AchievementMetric.care80,
    50,
    unit: 'phiên',
  ),
  _def(
    'care80_100',
    'Thầy thuốc của pin',
    'Mục tiêu tối đa 80% trong 100 phiên.',
    AchievementCategory.care,
    _p,
    Icons.medical_services_rounded,
    AchievementMetric.care80,
    100,
    unit: 'phiên',
  ),
  _def(
    'golden_5',
    'Vùng vàng',
    'Bắt đầu sạc khi pin còn 20–40% trong 5 phiên.',
    AchievementCategory.care,
    _b,
    Icons.tonality_rounded,
    AchievementMetric.goldenStart,
    5,
    unit: 'phiên',
  ),
  _def(
    'golden_20',
    'Nhịp sạc lý tưởng',
    'Bắt đầu sạc ở 20–40% trong 20 phiên.',
    AchievementCategory.care,
    _s,
    Icons.balance_rounded,
    AchievementMetric.goldenStart,
    20,
    unit: 'phiên',
  ),
  _def(
    'golden_50',
    'Chuẩn mực vàng',
    'Bắt đầu sạc ở 20–40% trong 50 phiên.',
    AchievementCategory.care,
    _g,
    Icons.diamond_rounded,
    AchievementMetric.goldenStart,
    50,
    unit: 'phiên',
  ),
  _def(
    'balance_1',
    'Cân bằng cell',
    'Sạc đầy 100% một lần trong tháng để cân bằng cell.',
    AchievementCategory.care,
    _b,
    Icons.battery_full_rounded,
    AchievementMetric.balanceMonths,
    1,
    unit: 'tháng',
  ),
  _def(
    'balance_3',
    'Bảo dưỡng định kỳ',
    'Sạc cân bằng 100% trong 3 tháng khác nhau.',
    AchievementCategory.care,
    _s,
    Icons.event_repeat_rounded,
    AchievementMetric.balanceMonths,
    3,
    unit: 'tháng',
  ),
  _def(
    'balance_6',
    'Kỷ luật pin',
    'Sạc cân bằng 100% trong 6 tháng khác nhau.',
    AchievementCategory.care,
    _g,
    Icons.calendar_month_rounded,
    AchievementMetric.balanceMonths,
    6,
    unit: 'tháng',
  ),

  // ── Giờ sạc ──
  _def(
    'offpeak_1',
    'Giờ thấp điểm',
    'Bắt đầu sạc trong giờ thấp điểm 22:00–04:00.',
    AchievementCategory.timing,
    _b,
    Icons.nightlight_round,
    AchievementMetric.offPeak,
    1,
    unit: 'phiên',
  ),
  _def(
    'offpeak_10',
    'Tiết kiệm thông thái',
    'Sạc giờ thấp điểm 10 lần.',
    AchievementCategory.timing,
    _s,
    Icons.savings_rounded,
    AchievementMetric.offPeak,
    10,
    unit: 'phiên',
  ),
  _def(
    'offpeak_30',
    'Bậc thầy giờ thấp điểm',
    'Sạc giờ thấp điểm 30 lần.',
    AchievementCategory.timing,
    _g,
    Icons.dark_mode_rounded,
    AchievementMetric.offPeak,
    30,
    unit: 'phiên',
  ),
  _def(
    'offpeak_100',
    'Người của đêm xanh',
    'Sạc giờ thấp điểm 100 lần.',
    AchievementCategory.timing,
    _p,
    Icons.bedtime_rounded,
    AchievementMetric.offPeak,
    100,
    unit: 'phiên',
  ),
  _def(
    'morning_5',
    'Bình minh',
    'Bắt đầu sạc từ 05:00–08:00 trong 5 phiên.',
    AchievementCategory.timing,
    _s,
    Icons.wb_twilight_rounded,
    AchievementMetric.morning,
    5,
    unit: 'phiên',
  ),
  _def(
    'weekend_10',
    'Cuối tuần năng động',
    'Sạc vào thứ Bảy hoặc Chủ nhật 10 lần.',
    AchievementCategory.timing,
    _s,
    Icons.weekend_rounded,
    AchievementMetric.weekend,
    10,
    unit: 'phiên',
  ),

  // ── Chuỗi ──
  _def(
    'week_2',
    'Hai tuần liền',
    'Sạc ít nhất một lần mỗi tuần, 2 tuần liên tiếp.',
    AchievementCategory.streak,
    _b,
    Icons.local_fire_department_rounded,
    AchievementMetric.weekStreak,
    2,
    unit: 'tuần',
  ),
  _def(
    'week_4',
    'Tròn một tháng',
    'Duy trì chuỗi 4 tuần liên tiếp.',
    AchievementCategory.streak,
    _s,
    Icons.whatshot_rounded,
    AchievementMetric.weekStreak,
    4,
    unit: 'tuần',
  ),
  _def(
    'week_8',
    'Bền bỉ',
    'Duy trì chuỗi 8 tuần liên tiếp.',
    AchievementCategory.streak,
    _g,
    Icons.trending_up_rounded,
    AchievementMetric.weekStreak,
    8,
    unit: 'tuần',
  ),
  _def(
    'week_16',
    'Không ngừng nghỉ',
    'Duy trì chuỗi 16 tuần liên tiếp.',
    AchievementCategory.streak,
    _p,
    Icons.rocket_launch_rounded,
    AchievementMetric.weekStreak,
    16,
    unit: 'tuần',
  ),
  _def(
    'week_52',
    'Một năm trọn vẹn',
    'Duy trì chuỗi 52 tuần liên tiếp.',
    AchievementCategory.streak,
    _e,
    Icons.cake_rounded,
    AchievementMetric.weekStreak,
    52,
    unit: 'tuần',
  ),
  _def(
    'months_3',
    'Ba mùa sạc',
    'Sạc trong 3 tháng khác nhau.',
    AchievementCategory.streak,
    _s,
    Icons.filter_3_rounded,
    AchievementMetric.activeMonths,
    3,
    unit: 'tháng',
  ),
  _def(
    'months_12',
    'Mười hai mùa trăng',
    'Sạc trong 12 tháng khác nhau.',
    AchievementCategory.streak,
    _g,
    Icons.brightness_3_rounded,
    AchievementMetric.activeMonths,
    12,
    unit: 'tháng',
  ),

  // ── Sống xanh ──
  _def(
    'co2_5',
    'Hơi thở trong lành',
    'Giảm 5 kg CO₂ so với xe xăng.',
    AchievementCategory.eco,
    _b,
    Icons.air_rounded,
    AchievementMetric.co2Kg,
    5,
    unit: 'kg',
  ),
  _def(
    'co2_25',
    'Một góc phố xanh',
    'Giảm 25 kg CO₂.',
    AchievementCategory.eco,
    _s,
    Icons.park_rounded,
    AchievementMetric.co2Kg,
    25,
    unit: 'kg',
  ),
  _def(
    'co2_100',
    'Khu rừng nhỏ',
    'Giảm 100 kg CO₂ — bằng 5 cây xanh hấp thụ trong một năm.',
    AchievementCategory.eco,
    _g,
    Icons.forest_rounded,
    AchievementMetric.co2Kg,
    100,
    unit: 'kg',
  ),
  _def(
    'co2_250',
    'Người giữ bầu trời',
    'Giảm 250 kg CO₂.',
    AchievementCategory.eco,
    _p,
    Icons.cloud_done_rounded,
    AchievementMetric.co2Kg,
    250,
    unit: 'kg',
  ),
  _def(
    'km_1000',
    'Nghìn cây số xanh',
    'Nạp đủ năng lượng cho 1.000 km.',
    AchievementCategory.eco,
    _s,
    Icons.route_rounded,
    AchievementMetric.km,
    1000,
    unit: 'km',
  ),
  _def(
    'km_10000',
    'Vòng quanh đất nước',
    'Nạp đủ năng lượng cho 10.000 km.',
    AchievementCategory.eco,
    _p,
    Icons.public_rounded,
    AchievementMetric.km,
    10000,
    unit: 'km',
  ),

  // ── Khám phá ──
  _def(
    'explore_shelly',
    'Kết nối thông minh',
    'Liên kết ổ cắm Shelly với ứng dụng.',
    AchievementCategory.explore,
    _b,
    Icons.power_rounded,
    AchievementMetric.event,
    1,
    event: AchievementEvents.shellyLinked,
  ),
  _def(
    'explore_safety',
    'An toàn là trên hết',
    'Hoàn tất kiểm tra an toàn không tải cho Shelly.',
    AchievementCategory.explore,
    _s,
    Icons.verified_rounded,
    AchievementMetric.event,
    1,
    event: AchievementEvents.safetyVerified,
  ),
  _def(
    'explore_bot',
    'Điều khiển bằng lời',
    'Bật sạc qua Pinova Bot và xác nhận.',
    AchievementCategory.explore,
    _s,
    Icons.record_voice_over_rounded,
    AchievementMetric.event,
    1,
    event: AchievementEvents.botCharge,
  ),
  _def(
    'explore_collection',
    'Nhà sưu tầm',
    'Mở bộ sưu tập Thành tựu.',
    AchievementCategory.explore,
    _b,
    Icons.collections_bookmark_rounded,
    AchievementMetric.event,
    1,
    event: AchievementEvents.collectionOpened,
  ),
  _def(
    'explore_history',
    'Nhìn lại hành trình',
    'Xem toàn bộ lịch sử sạc.',
    AchievementCategory.explore,
    _b,
    Icons.history_rounded,
    AchievementMetric.event,
    1,
    event: AchievementEvents.historyViewed,
  ),

  // ── Bí mật ──
  _def(
    'secret_88',
    'Số phát lộc',
    'Đặt mục tiêu sạc đúng 88%.',
    AchievementCategory.secret,
    _s,
    Icons.casino_rounded,
    AchievementMetric.number88,
    1,
  ),
  _def(
    'secret_night',
    'Cú đêm',
    'Bắt đầu sạc trong khoảng 00:00–03:00.',
    AchievementCategory.secret,
    _s,
    Icons.nights_stay_rounded,
    AchievementMetric.nightOwl,
    1,
  ),
  _def(
    'secret_lightning',
    'Tia chớp',
    'Hoàn tất một phiên sạc dưới 20 phút.',
    AchievementCategory.secret,
    _s,
    Icons.electric_bolt_rounded,
    AchievementMetric.lightning,
    1,
  ),
  _def(
    'secret_patience',
    'Kiên nhẫn',
    'Một phiên sạc kéo dài từ 5 giờ trở lên.',
    AchievementCategory.secret,
    _g,
    Icons.hourglass_bottom_rounded,
    AchievementMetric.patience,
    1,
  ),
  _def(
    'secret_newyear',
    'Năng lượng năm mới',
    'Sạc vào ngày 1 tháng 1.',
    AchievementCategory.secret,
    _g,
    Icons.celebration_rounded,
    AchievementMetric.newYear,
    1,
  ),
  _def(
    'secret_earth',
    'Ngày Trái Đất',
    'Sạc vào ngày 22 tháng 4.',
    AchievementCategory.secret,
    _g,
    Icons.public_rounded,
    AchievementMetric.earthDay,
    1,
  ),
  _def(
    'secret_week',
    'Bảy ngày liên tiếp',
    'Sạc mỗi ngày trong 7 ngày liền.',
    AchievementCategory.secret,
    _p,
    Icons.calendar_view_week_rounded,
    AchievementMetric.dayStreak,
    7,
    unit: 'ngày',
  ),
];
