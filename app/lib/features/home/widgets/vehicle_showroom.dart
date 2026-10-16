import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../data/models/vehicle_showroom.dart';

/// Luxe vehicle stage built from approved catalog photos.
///
/// * Any colour: a 2.5D view — drag tilts the vehicle in perspective and it
///   springs back; a mirrored reflection sits on the pedestal.
/// * Colours with ≥ [VehicleShowroomData.spinMinAngles] angles: a 360°
///   turntable — horizontal drag steps through the frames with inertia.
///   Frames are pre-cached (progress ring) before the spin is enabled.
/// * [zoomable]: two-finger pinch zooms (double tap resets).
///
/// With no photo the [fallback] (line-art scooter) is shown on the stage.
class VehicleShowroomView extends StatefulWidget {
  const VehicleShowroomView({
    super.key,
    required this.color,
    required this.fallback,
    this.interactive = true,
    this.zoomable = false,
    this.reflection = true,
    this.showHint = true,
  });

  final ShowroomColor? color;
  final Widget fallback;
  final bool interactive;
  final bool zoomable;
  final bool reflection;
  final bool showHint;

  @override
  State<VehicleShowroomView> createState() => VehicleShowroomViewState();
}

@visibleForTesting
class VehicleShowroomViewState extends State<VehicleShowroomView>
    with TickerProviderStateMixin {
  /// Continuous frame position (0..n), wraps around.
  late final AnimationController _spin = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _tiltBack = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  Offset _tilt = Offset.zero;
  Offset _tiltFrom = Offset.zero;
  double _zoom = 1;
  double _zoomStart = 1;
  int _loaded = 0;
  final Set<int> _failed = {};
  bool _interacted = false;
  int _generation = 0;

  List<ShowroomImage> get _angles => widget.color?.angles ?? const [];
  bool get _spinCapable => widget.color?.canSpin == true;
  bool get spinReady => _spinCapable && _loaded >= _angles.length;

  /// Index of the frame currently shown (skips frames that failed to load).
  int get frameIndex {
    final n = _angles.length;
    if (n == 0) return 0;
    var i = _spin.value.round() % n;
    if (i < 0) i += n;
    for (var k = 0; k < n && _failed.contains(i); k++) {
      i = (i + 1) % n;
    }
    return i;
  }

  @override
  void initState() {
    super.initState();
    _tiltBack.addListener(() {
      final t = Curves.easeOutBack.transform(_tiltBack.value);
      setState(() => _tilt = Offset.lerp(_tiltFrom, Offset.zero, t)!);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precache();
  }

  @override
  void didUpdateWidget(covariant VehicleShowroomView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color?.id != widget.color?.id ||
        oldWidget.color?.angles.length != widget.color?.angles.length) {
      _spin.value = 0;
      _precache();
    }
  }

  @override
  void dispose() {
    _generation++;
    _spin.dispose();
    _tiltBack.dispose();
    super.dispose();
  }

  Future<void> _precache() async {
    final generation = ++_generation;
    _loaded = 0;
    _failed.clear();
    if (!_spinCapable) return;
    final angles = _angles;
    for (var i = 0; i < angles.length; i++) {
      if (!mounted || generation != _generation) return;
      try {
        await precacheImage(
          showroomImageProvider(angles[i].mediumUrl),
          context,
          onError: (_, _) => _failed.add(i),
        );
      } catch (_) {
        _failed.add(i);
      }
      if (!mounted || generation != _generation) return;
      setState(() => _loaded = i + 1);
    }
  }

  void _rotateBy(double frames) {
    _spin.stop();
    _spin.value += frames;
  }

  void _onScaleStart(ScaleStartDetails d) {
    _spin.stop();
    _tiltBack.stop();
    _zoomStart = _zoom;
    if (!_interacted) setState(() => _interacted = true);
  }

  void _onScaleUpdate(ScaleUpdateDetails d, double width) {
    if (d.pointerCount >= 2 && widget.zoomable) {
      setState(() => _zoom = (_zoomStart * d.scale).clamp(1.0, 2.6));
      return;
    }
    final delta = d.focalPointDelta;
    if (spinReady) {
      // One full turn per ~1.4 widths of travel.
      final perFrame = (width * 1.4) / _angles.length;
      setState(() => _spin.value -= delta.dx / perFrame);
    } else {
      setState(() {
        _tilt = Offset(
          (_tilt.dx + delta.dx / width * 0.9).clamp(-0.28, 0.28),
          (_tilt.dy + delta.dy / width * 0.6).clamp(-0.14, 0.14),
        );
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails d, double width) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (spinReady) {
      final perFrame = (width * 1.4) / _angles.length;
      final velocity = -d.velocity.pixelsPerSecond.dx / perFrame;
      if (reduced || velocity.abs() < 0.5) {
        _spin.animateTo(
          _spin.value.roundToDouble(),
          duration: reduced ? Duration.zero : const Duration(milliseconds: 180),
        );
      } else {
        _spin.animateWith(FrictionSimulation(0.12, _spin.value, velocity));
        HapticFeedback.selectionClick();
      }
      return;
    }
    _tiltFrom = _tilt;
    if (reduced) {
      setState(() => _tilt = Offset.zero);
    } else {
      _tiltBack.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final angles = _angles;
    final hasPhoto = angles.isNotEmpty;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth.isFinite ? box.maxWidth : 360.0;
        Widget subject = AnimatedBuilder(
          animation: _spin,
          builder: (context, _) {
            final image = hasPhoto ? angles[spinReady ? frameIndex : 0] : null;
            return _StageImage(
              image: image,
              fallback: widget.fallback,
              reflection: widget.reflection,
            );
          },
        );
        subject = Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0014)
            ..rotateY(_tilt.dx)
            ..rotateX(-_tilt.dy)
            ..scaleByDouble(_zoom, _zoom, 1, 1),
          child: subject,
        );
        final stage = Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: CustomPaint(painter: ShowroomStagePainter()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
              child: subject,
            ),
            if (_spinCapable && !spinReady)
              Positioned(
                left: 10,
                right: 10,
                top: 10,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _LoadRing(loaded: _loaded, total: angles.length),
                ),
              ),
            if (spinReady)
              Positioned(
                right: 12,
                top: 12,
                child: _AngleDial(index: frameIndex, total: angles.length),
              ),
            if (widget.interactive && widget.showHint && hasPhoto)
              Positioned(
                left: 12,
                right: 12,
                bottom: 6,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _interacted ? 0 : 1,
                    duration: const Duration(milliseconds: 400),
                    child: Center(
                      child: _Hint(
                        text: spinReady
                            ? 'Kéo để xoay 360°'
                            : (_spinCapable
                                  ? 'Đang chuẩn bị 360°…'
                                  : 'Kéo để ngắm xe'),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
        if (!widget.interactive || !hasPhoto) return stage;
        final n = angles.length;
        return Semantics(
          label: spinReady
              ? 'Xe màu ${widget.color!.name}, góc ${frameIndex + 1} trên $n. Kéo ngang để xoay.'
              : 'Ảnh xe màu ${widget.color!.name}. Kéo để nghiêng.',
          onIncrease: spinReady ? () => setState(() => _rotateBy(1)) : null,
          onDecrease: spinReady ? () => setState(() => _rotateBy(-1)) : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: (d) => _onScaleUpdate(d, width),
            onScaleEnd: (d) => _onScaleEnd(d, width),
            onDoubleTap: widget.zoomable
                ? () => setState(() => _zoom = _zoom > 1.01 ? 1 : 1.8)
                : null,
            child: stage,
          ),
        );
      },
    );
  }
}

/// Resolves catalog image URLs. Disk-cached in the app (photos stay
/// available offline); tests swap it for an in-memory provider.
ImageProvider Function(String url) showroomImageProvider = (url) =>
    CachedNetworkImageProvider(url);

/// Photo (or fallback art) with a mirrored reflection fading into the floor.
class _StageImage extends StatelessWidget {
  const _StageImage({
    required this.image,
    required this.fallback,
    required this.reflection,
  });
  final ShowroomImage? image;
  final Widget fallback;
  final bool reflection;

  @override
  Widget build(BuildContext context) {
    final url = image?.mediumUrl;
    if (url == null) return fallback;
    Widget photo() => Image(
      image: showroomImageProvider(url),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
        opacity: sync || frame != null ? 1 : 0,
        duration: const Duration(milliseconds: 380),
        child: child,
      ),
      errorBuilder: (_, _, _) => fallback,
    );
    if (!reflection) return photo();
    return Column(
      children: [
        Expanded(flex: 6, child: photo()),
        Expanded(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (b) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x38FFFFFF), Color(0x00FFFFFF)],
                ).createShader(b),
                child: Transform(
                  alignment: Alignment.topCenter,
                  transform: Matrix4.diagonal3Values(1, -1, 1),
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      heightFactor: 0.22,
                      child: AspectRatio(aspectRatio: 1.6, child: photo()),
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
}

/// Brushed-metal pedestal, a soft spotlight and an emerald floor glow.
class ShowroomStagePainter extends CustomPainter {
  const ShowroomStagePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Spotlight cone from above.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -1.1),
          radius: 1.05,
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );
    final floor = Rect.fromCenter(
      center: Offset(w / 2, h * 0.86),
      width: w * 0.86,
      height: h * 0.16,
    );
    canvas.drawOval(
      floor.inflate(10),
      Paint()
        ..color = LuxeColors.emerald.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawOval(
      floor,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF26282C), Color(0xFF0C0D0F)],
        ).createShader(floor),
    );
    canvas.drawOval(
      floor,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = SweepGradient(
          colors: const [
            Color(0x66FFFFFF),
            Color(0x14FFFFFF),
            Color(0x5534D399),
            Color(0x14FFFFFF),
            Color(0x66FFFFFF),
          ],
        ).createShader(floor),
    );
  }

  @override
  bool shouldRepaint(ShowroomStagePainter old) => false;
}

class _LoadRing extends StatelessWidget {
  const _LoadRing({required this.loaded, required this.total});
  final int loaded;
  final int total;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Đang tải ảnh 360 độ, $loaded trên $total',
    child: Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: const Color(0xCC0B0C0E),
        border: Border.all(color: LuxeColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(
              value: total == 0 ? null : loaded / total,
              strokeWidth: 2,
              color: LuxeColors.emerald,
              backgroundColor: LuxeColors.hairline,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '360° · $loaded/$total',
              maxLines: 1,
              style: const TextStyle(
                color: LuxeColors.platinum,
                fontSize: 11.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Small dial: a dot travels around a ring as the vehicle turns.
class _AngleDial extends StatelessWidget {
  const _AngleDial({required this.index, required this.total});
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: 34,
      child: CustomPaint(
        painter: _DialPainter(total == 0 ? 0 : index / total),
        child: const Center(
          child: Text(
            '360°',
            style: TextStyle(
              color: LuxeColors.platinum,
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ),
  );
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = LuxeColors.hairlineStrong,
    );
    final a = -math.pi / 2 + 2 * math.pi * t;
    canvas.drawCircle(
      c + Offset(math.cos(a), math.sin(a)) * r,
      3,
      Paint()..color = LuxeColors.emerald,
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.t != t;
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(99),
      color: const Color(0xB30B0C0E),
      border: Border.all(color: LuxeColors.hairline),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.swipe_rounded, size: 14, color: LuxeColors.platinum),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: LuxeColors.platinum, fontSize: 11.5),
          ),
        ),
      ],
    ),
  );
}
