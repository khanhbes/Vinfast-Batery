/// Overview hero (QA 131): the owner picks how the Tổng quan tab looks.
enum DashboardStyle {
  luxe('luxe', 'Luxe', 'Ảnh xe trên sân khấu, % pin lớn'),
  lcd('lcd', 'Đồng hồ xe', 'Số 7 đoạn như màn hình Feliz'),
  compact('compact', 'Gọn', 'Lưới số liệu, không ảnh lớn'),
  minimal('minimal', 'Tối giản', 'Chỉ vòng % pin và nút Sạc');

  const DashboardStyle(this.id, this.label, this.caption);

  final String id;
  final String label;
  final String caption;

  static DashboardStyle parse(Object? raw) =>
      values.firstWhere((v) => v.id == raw, orElse: () => luxe);
}

/// Charge tab layout (QA 131).
enum ChargeStyle {
  dial('dial', 'Vòng dial Luxe', 'Kéo núm trên vòng tròn'),
  bar('bar', 'Thanh ngang', 'Thanh pin ngang tối giản'),
  lcd('lcd', 'Đồng hồ LCD', 'Số 7 đoạn: %, W, phút còn lại'),
  detail('detail', 'Số liệu chi tiết', 'W, V, A, Wh, nhiệt độ ổ cắm');

  const ChargeStyle(this.id, this.label, this.caption);

  final String id;
  final String label;
  final String caption;

  static ChargeStyle parse(Object? raw) =>
      values.firstWhere((v) => v.id == raw, orElse: () => dial);
}

/// How switching the charger ON is confirmed (QA 131). Stopping is always
/// a plain button.
enum ChargeConfirmStyle {
  slide('slide', 'Vuốt để sạc', 'Kéo núm hết thanh mới bật — khó bấm nhầm'),
  hold('hold', 'Giữ để xác nhận', 'Nhấn giữ khoảng 1 giây'),
  tap('tap', 'Bấm 1 lần', 'Nhanh nhất, nhưng dễ bật nhầm hơn');

  const ChargeConfirmStyle(this.id, this.label, this.caption);

  final String id;
  final String label;
  final String caption;

  static ChargeConfirmStyle parse(Object? raw) =>
      values.firstWhere((v) => v.id == raw, orElse: () => slide);
}

/// The owner's appearance choices, saved per account.
class AppAppearance {
  const AppAppearance({
    this.dashboard = DashboardStyle.luxe,
    this.charge = ChargeStyle.dial,
    this.confirm = ChargeConfirmStyle.slide,
  });

  final DashboardStyle dashboard;
  final ChargeStyle charge;
  final ChargeConfirmStyle confirm;

  AppAppearance copyWith({
    DashboardStyle? dashboard,
    ChargeStyle? charge,
    ChargeConfirmStyle? confirm,
  }) => AppAppearance(
    dashboard: dashboard ?? this.dashboard,
    charge: charge ?? this.charge,
    confirm: confirm ?? this.confirm,
  );

  Map<String, Object> toMap() => {
    'dashboardStyle': dashboard.id,
    'chargeStyle': charge.id,
    'confirmStyle': confirm.id,
  };

  factory AppAppearance.fromMap(Map<String, dynamic>? map) => AppAppearance(
    dashboard: DashboardStyle.parse(map?['dashboardStyle']),
    charge: ChargeStyle.parse(map?['chargeStyle']),
    confirm: ChargeConfirmStyle.parse(map?['confirmStyle']),
  );

  @override
  bool operator ==(Object other) =>
      other is AppAppearance &&
      other.dashboard == dashboard &&
      other.charge == charge &&
      other.confirm == confirm;

  @override
  int get hashCode => Object.hash(dashboard, charge, confirm);
}
