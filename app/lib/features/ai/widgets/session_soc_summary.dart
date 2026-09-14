import 'package:flutter/material.dart';
import '../../../core/theme/cockpit_design_system.dart';
import '../../../data/models/smart_charging_session.dart';

/// Session SOC summary that adapts to compact phones and large text.
class SessionSocSummary extends StatelessWidget {
  const SessionSocSummary({super.key, required this.session});
  final SmartChargingSession session;

  String _soc(double? value) => value != null && value.isFinite && value >= 0 && value <= 100 ? '${value.round()}%' : '\u2014';

  @override
  Widget build(BuildContext context) {
    final confirmed = session.actualEndSoc;
    final estimated = session.estimatedSoc;
    final actualValid = confirmed != null && confirmed.isFinite && confirmed >= 0 && confirmed <= 100;
    final startSoc = session.startSoc >= 0 && session.startSoc <= 100 ? session.startSoc : 0.0;
    // A stored estimate is already the server's reconciled value. Older
    // sessions do not carry a quality field, so do not hide a valid estimate
    // merely because that optional metadata is absent.
    final estimatedValid = estimated != null && estimated.isFinite && estimated >= 0 && estimated <= 100;
    final double? endSoc = actualValid ? confirmed : (estimatedValid ? estimated : null);
    final gain = endSoc == null ? 0.0 : (endSoc - startSoc).clamp(-100.0, 100.0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: CockpitColors.surface, borderRadius: BorderRadius.circular(CockpitRadius.large), border: Border.all(color: CockpitColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: CockpitColors.emerald.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.battery_charging_full_rounded, size: 20, color: CockpitColors.emeraldStrong)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ti\u1EBFn tr\u00ecnh s\u1EA1c pin (SOC)', style: CockpitTypography.heading(fontSize: 15, fontWeight: FontWeight.w700, color: CockpitColors.text)),
            Text(actualValid ? 'Cu\u1ED1i phi\u00ean \u00b7 \u0111\u00e3 x\u00e1c nh\u1EADn' : (session.state.isTerminal ? '\u01AF\u1EDBc t\u00ednh k\u1EBFt th\u00fac' : '\u0110ang ti\u1EBFp t\u1EE5c n\u1EA1p'), style: CockpitTypography.label(fontSize: 11, color: actualValid ? CockpitColors.emeraldStrong : CockpitColors.muted)),
          ])),
          if (gain > 0) Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: CockpitColors.emerald.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999), border: Border.all(color: CockpitColors.emerald.withValues(alpha: 0.3))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.trending_up_rounded, size: 14, color: CockpitColors.emeraldStrong),
              const SizedBox(width: 4),
              Text('+${gain.round()}% pin', style: CockpitTypography.numbers(fontSize: 12, fontWeight: FontWeight.w700, color: CockpitColors.emeraldStrong)),
            ]),
          ),
        ]),
        const SizedBox(height: 20),
        LayoutBuilder(builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final narrow = constraints.maxWidth < 420 || scale > 1.3;
          final start = _SocBox(label: 'B\u1EAFt \u0111\u1EA7u', value: _soc(startSoc), color: CockpitColors.muted);
          final end = _SocBox(label: actualValid ? 'Th\u1EF1c t\u1EBF cu\u1ED1i' : (estimatedValid ? 'SOC \u01B0\u1EDBc t\u00ednh' : (session.state.isTerminal ? '\u01AF\u1EDBc t\u00ednh cu\u1ED1i' : 'Hi\u1EC7n t\u1EA1i')), value: endSoc == null ? 'Ch\u01B0a c\u00f3 d\u1EEF li\u1EC7u' : _soc(endSoc), color: CockpitColors.emeraldStrong, isHighlighted: true);
          final target = _SocBox(label: 'M\u1EE5c ti\u00eau \u0111\u1EB7t tr\u01B0\u1EDBc: ${_soc(session.targetSoc)}', value: '\u2014', color: CockpitColors.info);
          if (narrow) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              start,
              const SizedBox(height: 8),
              const Center(child: Icon(Icons.arrow_downward_rounded, size: 18, color: CockpitColors.dim)),
              const SizedBox(height: 8),
              end,
              const SizedBox(height: 8),
              const Center(child: Icon(Icons.arrow_downward_rounded, size: 18, color: CockpitColors.dim)),
              const SizedBox(height: 8),
              target,
            ]);
          }
          return Row(children: [
            Expanded(child: start),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.arrow_forward_rounded, size: 18, color: CockpitColors.dim)),
            Expanded(child: end),
            const SizedBox(width: 12),
            Expanded(child: target),
          ]);
        }),
        const SizedBox(height: 18),
        Stack(children: [
          Container(height: 10, decoration: BoxDecoration(color: CockpitColors.surfaceSoft, borderRadius: BorderRadius.circular(999))),
          FractionallySizedBox(widthFactor: ((endSoc ?? startSoc) / 100.0).clamp(0.0, 1.0), child: Container(height: 10, decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), gradient: const LinearGradient(colors: [Color(0xFF059669), CockpitColors.emeraldStrong, Color(0xFF34D399)]), boxShadow: [BoxShadow(color: CockpitColors.emeraldStrong.withValues(alpha: 0.3), blurRadius: 6, offset: Offset(0, 1))]))),
        ]),
        const SizedBox(height: 12),
        Text(actualValid ? '\u2713 SOC cu\u1ED1i \u0111\u01B0\u1EE3c ghi nh\u1EADn theo th\u00f4ng s\u1ED1 ng\u01B0\u1EDDi d\u00f9ng x\u00e1c nh\u1EADn.' : '\u2022 S\u1ED1 \u0111o SOC \u01B0\u1EDBc t\u00ednh d\u1EF1a tr\u00ean c\u00f4ng su\u1EA5t n\u1EA1p l\u01B0\u1EDBi v\u00e0 dung l\u01B0\u1EE3ng xe.', style: CockpitTypography.label(fontSize: 11, color: CockpitColors.dim)),
      ]),
    );
  }
}

class _SocBox extends StatelessWidget {
  const _SocBox({required this.label, required this.value, required this.color, this.isHighlighted = false});
  final String label;
  final String value;
  final Color color;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: BoxDecoration(color: isHighlighted ? color.withValues(alpha: 0.08) : CockpitColors.surfaceSoft.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(CockpitRadius.medium), border: Border.all(color: isHighlighted ? color.withValues(alpha: 0.35) : CockpitColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: CockpitTypography.label(fontSize: 10, color: CockpitColors.muted)),
      const SizedBox(height: 4),
      Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: CockpitTypography.numbers(fontSize: 18, fontWeight: FontWeight.w800, color: isHighlighted ? color : CockpitColors.text)),
    ]),
  );
}
