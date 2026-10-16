import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../data/models/vehicle_showroom.dart';
import 'widgets/luxe_vehicle_hero.dart' show LuxeScooterArt;
import 'widgets/vehicle_showroom.dart';

/// Full-screen luxe showroom for one vehicle model: large stage (2.5D tilt,
/// 360° spin when enough angles exist, pinch zoom), colour swatches, key
/// figures and the photo credit.
class VehicleShowroomScreen extends StatefulWidget {
  const VehicleShowroomScreen({
    super.key,
    required this.title,
    required this.showroom,
    this.eyebrow,
    this.batteryLevel,
    this.figures = const [],
  });

  final String title;
  final String? eyebrow;
  final VehicleShowroomData? showroom;

  /// 0..1, only used by the line-art fallback.
  final double? batteryLevel;

  /// (label, value) pairs shown under the stage, e.g. ('Pin', '3,5 kWh').
  final List<(String, String)> figures;

  static Future<void> open(
    BuildContext context, {
    required String title,
    required VehicleShowroomData? showroom,
    String? eyebrow,
    double? batteryLevel,
    List<(String, String)> figures = const [],
  }) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => VehicleShowroomScreen(
        title: title,
        showroom: showroom,
        eyebrow: eyebrow,
        batteryLevel: batteryLevel,
        figures: figures,
      ),
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: LuxeMotion.enter,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );

  @override
  State<VehicleShowroomScreen> createState() => _VehicleShowroomScreenState();
}

class _VehicleShowroomScreenState extends State<VehicleShowroomScreen> {
  late String? _colorId = widget.showroom?.defaultColor.id;

  ShowroomColor? get _color {
    final data = widget.showroom;
    if (data == null) return null;
    return data.colors.firstWhere(
      (c) => c.id == _colorId,
      orElse: () => data.defaultColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.showroom;
    final color = _color;
    final credit = color?.angles.first.credit;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final fallback = LuxeScooterArt(level: widget.batteryLevel ?? 0.6);
    return Theme(
      data: LuxeTheme.of(context),
      child: Scaffold(
        backgroundColor: LuxeColors.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const LuxeBackdrop(),
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  LuxeReveal(
                    child: LuxePageHeader(
                      eyebrow: widget.eyebrow ?? 'Phòng trưng bày',
                      title: widget.title,
                      caption: color == null
                          ? null
                          : color.canSpin
                          ? 'Kéo ngang để xoay 360° · chụm hai ngón để phóng to'
                          : 'Kéo để ngắm xe · chụm hai ngón để phóng to',
                    ),
                  ),
                  const SizedBox(height: 14),
                  LuxeReveal(
                    index: 1,
                    child: AspectRatio(
                      aspectRatio: 1.15,
                      child: AnimatedSwitcher(
                        duration: reduced
                            ? Duration.zero
                            : const Duration(milliseconds: 420),
                        switchInCurve: LuxeMotion.enter,
                        child: VehicleShowroomView(
                          key: ValueKey(color?.id ?? 'none'),
                          color: color,
                          zoomable: true,
                          fallback: fallback,
                        ),
                      ),
                    ),
                  ),
                  if (data != null && data.colors.length > 1) ...[
                    const SizedBox(height: 18),
                    LuxeReveal(
                      index: 2,
                      child: _Swatches(
                        colors: data.colors,
                        selectedId: color!.id,
                        onSelect: (id) {
                          HapticFeedback.selectionClick();
                          setState(() => _colorId = id);
                        },
                      ),
                    ),
                  ],
                  if (color != null && data!.colors.length > 1) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        child: Text(
                          color.name,
                          key: ValueKey(color.id),
                          style: LuxeText.item,
                        ),
                      ),
                    ),
                  ],
                  if (data == null) ...[
                    const SizedBox(height: 16),
                    LuxeReveal(
                      index: 2,
                      child: LuxeGlass(
                        radius: 18,
                        padding: const EdgeInsets.all(14),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.photo_camera_back_outlined,
                              color: LuxeColors.platinumMid,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Mẫu xe này chưa có ảnh chính thức. Quản trị viên có thể thêm ảnh trong Danh mục xe trên web.',
                                style: LuxeText.caption,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (widget.figures.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    LuxeReveal(
                      index: 3,
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final (label, value) in widget.figures)
                            _Figure(label: label, value: value),
                        ],
                      ),
                    ),
                  ],
                  if (credit != null) ...[
                    const SizedBox(height: 22),
                    Text(
                      'Ảnh: $credit',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: LuxeColors.dim,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({
    required this.colors,
    required this.selectedId,
    required this.onSelect,
  });
  final List<ShowroomColor> colors;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final c in colors)
        Semantics(
          button: true,
          selected: c.id == selectedId,
          label: 'Màu ${c.name}',
          excludeSemantics: true,
          child: InkResponse(
            onTap: () => onSelect(c.id),
            radius: 28,
            child: SizedBox.square(
              dimension: 48,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: LuxeMotion.enter,
                  width: c.id == selectedId ? 36 : 30,
                  height: c.id == selectedId ? 36 : 30,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c.id == selectedId
                          ? LuxeColors.platinumHi
                          : LuxeColors.hairlineStrong,
                      width: c.id == selectedId ? 1.6 : 1,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(c.swatch, Colors.white, 0.25)!,
                          c.swatch,
                          Color.lerp(c.swatch, Colors.black, 0.35)!,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => LuxeGlass(
    radius: 16,
    padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: LuxeColors.platinumHi,
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: LuxeText.label.copyWith(fontSize: 11.5)),
      ],
    ),
  );
}
