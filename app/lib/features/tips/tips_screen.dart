import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/theme/plan_style.dart';
import '../../core/utils/battery_bot_faq.dart';
import '../../core/widgets/battery_bot_mascot.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../data/models/vehicle_model.dart';
import '../ai/assistant_sheet.dart';
import '../battery_monitor/battery_health_screen.dart';
import '../maintenance/maintenance_screen.dart';
import '../smart_charging/night_charging_screen.dart';
import '../trip_planner/trip_planner_wrapper.dart';
import 'tip.dart';
import 'tip_library.dart';

/// The icon of each group of "Mẹo nhỏ" (QA 164: one per group, no colour of
/// its own; the plan accent marks what is selected).
IconData tipCategoryIcon(String category) => switch (category) {
  'drive' => Icons.two_wheeler_rounded,
  'charge' => Icons.bolt_rounded,
  'battery' => Icons.battery_saver_rounded,
  'weather' => Icons.thunderstorm_rounded,
  'storage' => Icons.home_rounded,
  'safety' => Icons.health_and_safety_rounded,
  'app' => Icons.smartphone_rounded,
  _ => Icons.lightbulb_rounded,
};

/// "Mẹo nhỏ" (QA 163, Tiện ích): every tip for riding and charging an
/// electric scooter, searchable, with its source; the ones that do not fit
/// the selected vehicle's battery are left out. The same list Pinova Bot
/// tells one of each day.
///
/// QA 164 (owner: more professional, consistent and friendly): Pinova Bot
/// says the tip of the day in its own words, one row of group filters with
/// icons, tips under their group with a two-line preview, a dot on the ones
/// not read yet and how many have been read.
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
    final leadAcid = _leadAcid(vehicle);
    final percent = vehicle?.hasBatteryData == true
        ? vehicle!.currentBattery
        : null;
    // QA 164: the same tip of the day as Pinova Bot's bubble and chat;
    // "Mẹo khác" walks on from it without changing it.
    if (_shuffle == 0) {
      return _library.today(
        now: DateTime.now(),
        leadAcid: leadAcid,
        batteryPercent: percent,
      );
    }
    return TipPicker.pick(
      tips,
      now: DateTime.now().add(Duration(days: _shuffle)),
      seen: _library.seen,
      leadAcid: leadAcid,
      batteryPercent: percent,
    );
  }

  bool _matches(Tip tip, String query) =>
      query.isEmpty ||
      BatteryBotFaq.normalize(
        '${tip.title} ${tip.body} ${tip.tags.join(' ')}',
      ).contains(query);

  List<Tip> _shown(List<Tip> tips) {
    final query = BatteryBotFaq.normalize(_search.text);
    return [
      for (final tip in tips)
        if ((_filter == 'all' ||
                (_filter == 'saved' && _library.saved.contains(tip.id)) ||
                tip.category == _filter) &&
            _matches(tip, query))
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

  Widget _card(Tip tip) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: _TipCard(
      key: ValueKey('tip-${tip.id}'),
      tip: tip,
      open: _open.contains(tip.id),
      saved: _library.saved.contains(tip.id),
      unread: !_library.seen.contains(tip.id),
      actionLabel: actionLabel(tip.action),
      onToggle: () {
        setState(() {
          _open.contains(tip.id) ? _open.remove(tip.id) : _open.add(tip.id);
        });
        _library.markSeen(tip.id);
      },
      onSave: () => _library.toggleSaved(tip.id),
      onAction: () => _openAction(tip),
    ),
  );

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
    final read = fitting.where((t) => _library.seen.contains(t.id)).length;
    final filters = <(String, String, IconData)>[
      ('all', 'Tất cả', Icons.apps_rounded),
      if (_library.saved.isNotEmpty)
        ('saved', 'Đã lưu', Icons.bookmark_rounded),
      for (final (id, label) in tipCategories) (id, label, tipCategoryIcon(id)),
    ];
    // Grouped when browsing everything; a flat list for one group, the
    // saved ones or a search.
    final grouped = _filter == 'all' && _search.text.trim().isEmpty;
    return LuxeScaffold(
      title: 'Mẹo nhỏ',
      body: !_library.loaded
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 128),
              children: [
                if (today != null)
                  _TodayCard(
                    tip: today,
                    read: read,
                    total: fitting.length,
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
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(
                    color: LuxeColors.text,
                    fontSize: 15.5,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Tìm mẹo: sạc, mưa, tiết kiệm…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            key: const ValueKey('tips-search-clear'),
                            tooltip: 'Xóa tìm kiếm',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(_search.clear),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                // One row of groups; every pill is built (a short list).
                SingleChildScrollView(
                  key: const ValueKey('tips-filters'),
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Row(
                    children: [
                      for (final (id, label, icon) in filters) ...[
                        _FilterPill(
                          key: ValueKey('tips-filter-$id'),
                          label: label,
                          icon: icon,
                          selected: _filter == id,
                          onTap: () => setState(() => _filter = id),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (shown.isEmpty)
                  const LuxeNotice(
                    key: ValueKey('tips-none'),
                    icon: Icons.search_off_rounded,
                    message:
                        'Chưa có mẹo nào khớp. Thử từ khác hoặc chọn Tất cả.',
                  )
                else if (grouped)
                  for (final (id, label) in tipCategories)
                    if (shown.where((t) => t.category == id).toList()
                        case final group when group.isNotEmpty) ...[
                      _GroupHeader(
                        key: ValueKey('tips-group-$id'),
                        icon: tipCategoryIcon(id),
                        label: label,
                        count: group.length,
                      ),
                      for (final tip in group) _card(tip),
                      const SizedBox(height: 8),
                    ] else
                      const SizedBox.shrink()
                else
                  for (final tip in shown) _card(tip),
                const SizedBox(height: 8),
                Text(
                  'Mẹo tổng hợp từ báo, diễn đàn xe điện và dữ liệu sạc, chuyến '
                  'đi trong Pinova. Con số là ước tính; luôn ưu tiên sổ hướng '
                  'dẫn của xe.',
                  key: const ValueKey('tips-footer'),
                  style: LuxeText.caption,
                ),
              ],
            ),
    );
  }
}

/// Pinova Bot says the tip of the day, like a message in the chat.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.tip,
    required this.read,
    required this.total,
    required this.onAnother,
    required this.onAsk,
  });

  final Tip tip;
  final int read;
  final int total;
  final VoidCallback onAnother;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) => LuxeGlass(
    key: const ValueKey('tips-today'),
    raised: true,
    radius: 24,
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox.square(
              dimension: 40,
              child: BatteryBotMascot(
                displayMode: BatteryBotDisplayMode.avatar,
                size: BatteryBotSize.avatar,
                customWidth: 40,
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
                  const SizedBox(height: 2),
                  Text('Pinova Bot gợi ý cho bạn', style: LuxeText.caption),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // The bubble: what Pinova Bot says.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: LuxeColors.glass,
            border: Border.all(color: LuxeColors.hairline),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      tipCategoryIcon(tip.category),
                      size: 18,
                      color: context.planAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tip.title, style: LuxeText.item)),
                ],
              ),
              const SizedBox(height: 6),
              Text(tip.body, style: LuxeText.body),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            if (total > 0)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  'Đã đọc $read/$total mẹo',
                  key: const ValueKey('tips-read-count'),
                  style: LuxeText.caption,
                ),
              ),
            Wrap(
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
      ],
    ),
  );
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    label: '$label, $count mẹo',
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: LuxeColors.glass,
              border: Border.all(color: LuxeColors.hairline),
            ),
            child: Icon(icon, size: 17, color: LuxeColors.platinum),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label.toUpperCase(), style: LuxeText.eyebrow)),
          Text('$count mẹo', style: LuxeText.caption),
        ],
      ),
    ),
  );
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
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
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? context.planAccent : LuxeColors.muted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: LuxeText.label.copyWith(
                    color: selected ? LuxeColors.text : LuxeColors.muted,
                    fontSize: 13,
                  ),
                ),
              ],
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
    required this.unread,
    required this.onToggle,
    required this.onSave,
    required this.onAction,
    this.actionLabel,
  });

  final Tip tip;
  final bool open;
  final bool saved;
  final bool unread;
  final String? actionLabel;
  final VoidCallback onToggle;
  final VoidCallback onSave;
  final VoidCallback onAction;

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
            crossAxisAlignment: CrossAxisAlignment.start,
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
                        padding: const EdgeInsets.fromLTRB(16, 14, 4, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (unread)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 7,
                                      right: 8,
                                    ),
                                    child: Semantics(
                                      label: 'Chưa đọc',
                                      child: Container(
                                        key: ValueKey('tip-unread-${tip.id}'),
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: context.planAccent,
                                        ),
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Text(tip.title, style: LuxeText.item),
                                ),
                              ],
                            ),
                            if (battery != null) ...[
                              const SizedBox(height: 6),
                              LuxeTag(battery, color: LuxeColors.platinumMid),
                            ],
                            // A preview, so a tip can be read without a tap.
                            if (!open) ...[
                              const SizedBox(height: 6),
                              Text(
                                tip.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: LuxeText.caption,
                              ),
                            ],
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
                                        const Icon(
                                          Icons.link_rounded,
                                          size: 16,
                                          color: LuxeColors.muted,
                                        ),
                                        const SizedBox(width: 6),
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
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              key: ValueKey('tip-action-${tip.id}'),
                              onPressed: onAction,
                              style: OutlinedButton.styleFrom(
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
