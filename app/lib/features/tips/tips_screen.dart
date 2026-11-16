import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/theme/plan_style.dart';
import '../../core/widgets/battery_bot_mascot.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../data/models/vehicle_model.dart';
import '../ai/assistant_sheet.dart';
import '../../core/utils/battery_bot_faq.dart';
import '../battery_monitor/battery_health_screen.dart';
import '../maintenance/maintenance_screen.dart';
import '../smart_charging/night_charging_screen.dart';
import '../trip_planner/trip_planner_wrapper.dart';
import 'tip.dart';
import 'tip_library.dart';

/// "Mẹo nhỏ" (QA 163, Tiện ích): every tip for riding and charging an
/// electric scooter, in groups, searchable, with its source; the ones that
/// do not fit the selected vehicle's battery are left out. The same list
/// Pinova Bot tells one of each day.
class TipsScreen extends ConsumerStatefulWidget {
  const TipsScreen({super.key, this.highlightId, this.library});

  /// The tip to show on top (opened from Pinova Bot's bubble).
  final String? highlightId;

  /// Tests.
  final TipLibrary? library;

  @override
  ConsumerState<TipsScreen> createState() => _TipsScreenState();
}

class _TipsScreenState extends ConsumerState<TipsScreen> {
  late final TipLibrary _library = widget.library ?? TipLibrary.instance;
  final _search = TextEditingController();
  final _open = <String>{};
  String _filter = 'all';
  int _shuffle = 0;

  @override
  void initState() {
    super.initState();
    _library.addListener(_changed);
    _library.load();
    final id = widget.highlightId;
    if (id != null) {
      _open.add(id);
      _library.markSeen(id);
    }
  }

  @override
  void dispose() {
    _library.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool? _leadAcid(VehicleModel? vehicle) {
    final chemistry = vehicle?.batteryType?.trim() ?? '';
    if (chemistry.isEmpty || chemistry.toLowerCase() == 'unknown') return null;
    return isLeadAcidChemistry(chemistry);
  }

  Tip? _today(List<Tip> tips, VehicleModel? vehicle) {
    final id = widget.highlightId;
    if (id != null && _shuffle == 0) {
      final tip = _library.byId(id);
      if (tip != null) return tip;
    }
    return TipPicker.pick(
      tips,
      now: DateTime.now().add(Duration(days: _shuffle)),
      seen: _library.seen,
      leadAcid: _leadAcid(vehicle),
      batteryPercent: vehicle?.hasBatteryData == true
          ? vehicle!.currentBattery
          : null,
    );
  }

  List<Tip> _shown(List<Tip> tips) {
    final query = BatteryBotFaq.normalize(_search.text);
    return [
      for (final tip in tips)
        if ((_filter == 'all' ||
                (_filter == 'saved' && _library.saved.contains(tip.id)) ||
                tip.category == _filter) &&
            (query.isEmpty ||
                BatteryBotFaq.normalize(
                  '${tip.title} ${tip.body} ${tip.tags.join(' ')}',
                ).contains(query)))
          tip,
    ];
  }

  void _openAction(Tip tip) {
    final vehicle = ref.read(vehicleContextProvider).vehicle;
    final id = ref.read(selectedVehicleIdProvider);
    void push(Widget page) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    switch (tip.action) {
      case 'charge':
        Navigator.of(context).popUntil((route) => route.isFirst);
        openChargeControl(ref, ai: true);
      case 'trip_planner':
        push(const TripPlannerWrapper());
      case 'night_charging':
        NightChargingScreen.open(
          context,
          ref,
          vehicleId: id,
          currentSoc: vehicle?.currentBattery.toDouble(),
          currentOdoKm: vehicle?.currentOdo.toDouble(),
        );
      case 'battery_health':
        if (id.isNotEmpty) BatteryHealthScreen.open(context, ref, id);
      case 'maintenance':
        push(const MaintenanceScreen());
    }
  }

  static String? actionLabel(String? action) => switch (action) {
    'charge' => 'Mở Sạc pin',
    'trip_planner' => 'Mở Lộ trình',
    'night_charging' => 'Mở Sạc đêm',
    'battery_health' => 'Mở Sức khỏe pin',
    'maintenance' => 'Mở Bảo dưỡng',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final vehicle = ref.watch(vehicleContextProvider).vehicle;
    final leadAcid = _leadAcid(vehicle);
    final fitting = [
      for (final tip in _library.tips)
        if (tip.fits(leadAcid: leadAcid)) tip,
    ];
    final today = _today(fitting, vehicle);
    final shown = _shown(fitting);
    final filters = <(String, String)>[
      ('all', 'Tất cả'),
      if (_library.saved.isNotEmpty) ('saved', 'Đã lưu'),
      ...tipCategories,
    ];
    return LuxeScaffold(
      title: 'Mẹo nhỏ',
      body: !_library.loaded
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                if (today != null)
                  _TodayCard(
                    tip: today,
                    onAnother: () => setState(() => _shuffle++),
                    onAsk: () {
                      _library.markSeen(today.id);
                      InteractiveAssistantSheet.show(
                        context,
                        initialQuery: 'Giải thích thêm mẹo: ${today.title}',
                      );
                    },
                  ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('tips-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  autofillHints: const <String>[],
                  style: const TextStyle(
                    color: LuxeColors.text,
                    fontSize: 15.5,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Tìm mẹo: sạc, mưa, tiết kiệm…',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                // Every group in view (a new owner sees what there is).
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (id, label) in filters)
                      _FilterPill(
                        key: ValueKey('tips-filter-$id'),
                        label: label,
                        selected: _filter == id,
                        onTap: () => setState(() => _filter = id),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (shown.isEmpty)
                  const LuxeNotice(
                    key: ValueKey('tips-none'),
                    icon: Icons.search_off_rounded,
                    message:
                        'Chưa có mẹo nào khớp. Thử từ khác hoặc chọn Tất cả.',
                  )
                else
                  for (final tip in shown) ...[
                    _TipCard(
                      key: ValueKey('tip-${tip.id}'),
                      tip: tip,
                      open: _open.contains(tip.id),
                      saved: _library.saved.contains(tip.id),
                      actionLabel: actionLabel(tip.action),
                      onToggle: () {
                        setState(() {
                          _open.contains(tip.id)
                              ? _open.remove(tip.id)
                              : _open.add(tip.id);
                        });
                        _library.markSeen(tip.id);
                      },
                      onSave: () => _library.toggleSaved(tip.id),
                      onAction: () => _openAction(tip),
                    ),
                    const SizedBox(height: 10),
                  ],
                const SizedBox(height: 8),
                Text(
                  'Mẹo tổng hợp từ báo, diễn đàn xe điện và dữ liệu sạc, chuyến '
                  'đi trong Pinova. Con số là ước tính; luôn ưu tiên sổ hướng '
                  'dẫn của xe.',
                  style: LuxeText.caption,
                ),
              ],
            ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.tip,
    required this.onAnother,
    required this.onAsk,
  });

  final Tip tip;
  final VoidCallback onAnother;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) => LuxeGlass(
    key: const ValueKey('tips-today'),
    raised: true,
    radius: 24,
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox.square(
              dimension: 44,
              child: BatteryBotMascot(
                displayMode: BatteryBotDisplayMode.avatar,
                size: BatteryBotSize.avatar,
                customWidth: 44,
                mood: BatteryBotMood.happy,
                enableFloating: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('MẸO HÔM NAY', style: LuxeText.eyebrow),
                  const SizedBox(height: 4),
                  Text(tip.title, style: LuxeText.item),
                  const SizedBox(height: 6),
                  Text(tip.body, style: LuxeText.body),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 4,
          children: [
            TextButton.icon(
              key: const ValueKey('tips-another'),
              onPressed: onAnother,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Mẹo khác'),
            ),
            TextButton.icon(
              key: const ValueKey('tips-ask'),
              onPressed: onAsk,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.forum_rounded, size: 18),
              label: const Text('Hỏi Pinova Bot'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected
          ? context.planAccent.withValues(alpha: 0.18)
          : LuxeColors.glass,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? context.planAccent : LuxeColors.hairline,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: LuxeText.label.copyWith(
                  color: selected ? LuxeColors.text : LuxeColors.muted,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    super.key,
    required this.tip,
    required this.open,
    required this.saved,
    required this.onToggle,
    required this.onSave,
    required this.onAction,
    this.actionLabel,
  });

  final Tip tip;
  final bool open;
  final bool saved;
  final String? actionLabel;
  final VoidCallback onToggle;
  final VoidCallback onSave;
  final VoidCallback onAction;

  String get _group =>
      tipCategories.where((c) => c.$1 == tip.category).firstOrNull?.$2 ?? '';

  @override
  Widget build(BuildContext context) {
    final url = tip.sourceUrl;
    final battery = tip.batteryLabel;
    return LuxeGlass(
      quiet: true,
      radius: 20,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  expanded: open,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: onToggle,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [_group, ?battery].join(' · ').toUpperCase(),
                              style: LuxeText.eyebrow,
                            ),
                            const SizedBox(height: 4),
                            Text(tip.title, style: LuxeText.item),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('tip-save-${tip.id}'),
                tooltip: saved ? 'Bỏ lưu mẹo' : 'Lưu mẹo',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: onSave,
                icon: Icon(
                  saved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  color: saved ? context.planAccent : LuxeColors.platinumMid,
                ),
              ),
            ],
          ),
          LuxeFold(
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tip.body, style: LuxeText.body),
                        const SizedBox(height: 8),
                        if (tip.sourceName != null)
                          url == null
                              ? Text(
                                  'Nguồn: ${tip.sourceName}',
                                  style: LuxeText.caption,
                                )
                              : InkWell(
                                  onTap: () => launchUrl(
                                    Uri.parse(url),
                                    mode: LaunchMode.externalApplication,
                                  ),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 48,
                                    ),
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            'Nguồn: ${tip.sourceName}',
                                            style: LuxeText.caption.copyWith(
                                              decoration:
                                                  TextDecoration.underline,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.open_in_new_rounded,
                                          size: 14,
                                          color: LuxeColors.muted,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        if (actionLabel != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              key: ValueKey('tip-action-${tip.id}'),
                              onPressed: onAction,
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 48),
                              ),
                              icon: const Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                              ),
                              label: Text(actionLabel!),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
