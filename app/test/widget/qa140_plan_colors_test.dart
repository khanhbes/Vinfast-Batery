import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/theme/plan_style.dart';
import 'package:vinfast_battery/data/models/entitlement.dart';

/// QA 140 (item 4): every highlight follows the plan; emerald stays only
/// where it means a real status (verified, charging, connected, done). The
/// files below may keep at most the listed count; any other file must take
/// the plan's colour (`context.planAccent` / `PlanStyle`).
const _emeraldAllowed = <String, int>{
  // The palette and its legacy alias.
  'core/theme/plan_style.dart': 2,
  'core/theme/cockpit_design_system.dart': 4,
  // Status: success toast, saved, charging pill, brand mark.
  'core/widgets/app_popup.dart': 1,
  'core/widgets/luxe_submit_button.dart': 2,
  'core/widgets/global_charging_pill.dart': 2,
  'core/widgets/pinova_brand.dart': 2,
  // Status: model ready, reading locked, session outcome, confirmed card,
  // live charging, command steps, done states, charging dial.
  'features/achievements/models/achievement.dart': 1,
  'features/ai/ai_models_screen.dart': 3,
  'features/ai/dashboard_scan_screen.dart': 4, // + locked zones (QA 149)
  'features/ai/smart_charge_history_screen.dart': 2,
  'features/ai/smart_charging_control_screen.dart': 1,
  'features/ai/widgets/action_confirmation_card.dart': 2,
  'features/ai/widgets/active_charging_card_v2.dart': 8,
  'features/ai/widgets/command_progress_strip.dart': 3,
  'features/ai/widgets/charge_edit_controls.dart': 3, // done strip
  'features/ai/widgets/history_luxe_widgets.dart': 2,
  'features/ai/widgets/luxe_soc_dial.dart': 5,
  'features/ai/widgets/recent_sessions_section_v2.dart': 2,
  'features/ai/widgets/session_soc_summary.dart': 1,
  'features/maintenance/maintenance_screen.dart': 1,
  'features/more/more_screen.dart': 2, // + charging bolt (QA 149)
  'features/more/widgets/luxe_tile_grid.dart': 1,
  'features/notifications/notification_center_screen.dart': 1,
  'features/settings/widgets/training_result_sheet.dart': 1,
  'features/smart_charging/shelly_connect_screen.dart': 1,
  'features/smart_charging/smart_charger_setup_hub_screen.dart': 14,
  'features/support/help_center_screen.dart': 3,
};

void main() {
  test('emerald only where it means a status', () {
    final emerald = RegExp(r'LuxeColors\.emerald');
    final problems = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path
          .replaceAll(r'\', '/')
          .replaceFirst(RegExp(r'^lib/'), '');
      if (rel == 'core/theme/luxe_theme.dart') continue; // defines it
      final count = emerald.allMatches(entity.readAsStringSync()).length;
      final allowed = _emeraldAllowed[rel] ?? 0;
      if (count > allowed) problems.add('$rel: $count (allowed $allowed)');
    }
    expect(problems, isEmpty, reason: 'use context.planAccent for highlights');
  });

  test('QA 143: no hard-coded emerald hex outside the palette', () {
    // `Color(0x2234D399)` slipped past the rule above (selected glass,
    // bot glow, chips): the hex is emerald all the same.
    final hex = RegExp(r'0x[0-9A-Fa-f]{2}34D399', caseSensitive: false);
    final problems = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path
          .replaceAll(r'\', '/')
          .replaceFirst(RegExp(r'^lib/'), '');
      if (rel.startsWith('core/theme/')) continue;
      if (hex.hasMatch(entity.readAsStringSync())) problems.add(rel);
    }
    expect(problems, isEmpty, reason: 'use context.planAccent');
  });

  testWidgets('the accent follows the plan; status colours do not', (
    tester,
  ) async {
    final seen = <PlanTier, Color>{};
    for (final tier in PlanTier.values) {
      late Color accent;
      // Theme, not MaterialApp.theme: the app animates a theme change, and
      // the first frame would still show the previous plan.
      await tester.pumpWidget(
        Theme(
          data: LuxeTheme.data(tier: tier),
          child: Builder(
            builder: (context) {
              accent = context.planAccent;
              return const SizedBox();
            },
          ),
        ),
      );
      seen[tier] = accent;
      expect(accent, PlanStyle.forTier(tier).accent);
    }
    expect(seen.values.toSet(), hasLength(PlanTier.values.length));
    expect(seen.values, isNot(contains(LuxeColors.emerald)));
  });
}
