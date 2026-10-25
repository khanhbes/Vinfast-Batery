import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/luxe_theme.dart';
import '../../core/utils/number_text.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/services/pinova_api.dart';
import '../../data/services/dashboard_ai_reader.dart';
import '../../data/services/dashboard_layout_parser.dart';
import '../../data/services/dashboard_reader.dart';
import '../../data/services/seven_segment_reader.dart';
import '../../core/services/guide_registry.dart';
import '../../core/services/screen_tour.dart';

/// Reads the dashboard the quickest way (QA 131): the live scanner, which
/// can hand over to a gallery photo. `null` when the owner cancelled or
/// chose to type. [lastOdoKm] (last known ODO) rules out misreads.
Future<DashboardReading?> scanDashboard(
  BuildContext context, {
  double? lastOdoKm,
}) async {
  final prior = lastOdoKm != null && lastOdoKm > 0 ? lastOdoKm : null;
  final scan = await DashboardScanScreen.open(context, lastOdoKm: prior);
  if (scan == null) return null;
  if (!scan.wantsGallery) return scan.reading;
  return DashboardReader().read(camera: false, lastOdoKm: prior);
}

/// What the scanner hands back to the reading sheet.
class DashboardScanResult {
  const DashboardScanResult({this.reading, this.wantsGallery = false});

  final DashboardReading? reading;

  /// The owner chose "Chọn ảnh" instead.
  final bool wantsGallery;
}

/// Live dashboard scanner (QA 131): point the phone at the cluster and the
/// battery % and ODO lock on their own once several frames agree — no
/// shutter, no crop. Frames are read on the phone and never stored.
class DashboardScanScreen extends StatefulWidget {
  const DashboardScanScreen({
    super.key,
    this.lastOdoKm,
    this.loadCameras = availableCameras,
  });

  final double? lastOdoKm;
  final Future<List<CameraDescription>> Function() loadCameras;

  static Future<DashboardScanResult?> open(
    BuildContext context, {
    double? lastOdoKm,
  }) => Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<DashboardScanResult>(
      fullscreenDialog: true,
      builder: (_) => DashboardScanScreen(lastOdoKm: lastOdoKm),
    ),
  );

  @override
  State<DashboardScanScreen> createState() => _DashboardScanScreenState();
}

enum _CameraProblem { none, denied, unavailable }

class _DashboardScanScreenState extends State<DashboardScanScreen>
    with WidgetsBindingObserver {
  static const _frameGap = Duration(milliseconds: 150);
  static const _hintAfter = Duration(seconds: 8);

  CameraController? _controller;
  CameraDescription? _camera;
  TextRecognizer? _recognizer;
  final _vote = DashboardScanVote();
  _CameraProblem _problem = _CameraProblem.none;
  bool _starting = false;
  bool _busy = false;
  bool _capturing = false;
  bool _done = false;
  bool _torch = false;
  bool _showHint = false;
  String? _captureNote;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _frames = 0;

  /// Frames in a row without segment digits: then text recognition gets a
  /// turn (dashboards that are not seven-segment LCDs).
  int _noSegments = 0;
  Size? _imageSize;
  Rect? _socBox;
  Rect? _odoBox;
  Timer? _hintTimer;
  final _log = _ScanLog();

  /// The guide window: only this part of the frame is read (QA 135).
  final _guideKey = GuideRegistry.keyScanWindow;
  final _stackKey = GlobalKey();

  /// The image model's turn (QA 135): one crop of the guide window when
  /// the phone has not locked both numbers after [_aiAfter].
  static const _aiAfter = Duration(milliseconds: 2500);
  final _ai = DashboardAiReader();
  _FrameJob? _lastJob;
  Timer? _aiTimer;
  bool _aiAsked = false;
  bool _aiAssisted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _log.open().whenComplete(_start);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hintTimer?.cancel();
    _aiTimer?.cancel();
    _stopCamera();
    _recognizer?.close();
    _log.line(
      'closed frames=$_frames soc=${_vote.socLocked} odo=${_vote.odoLocked}',
    );
    _log.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.inactive) {
      // The permission prompt also makes the app inactive mid-start.
      if (controller == null || !controller.value.isInitialized) return;
      _stopCamera();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && controller == null) {
      _start();
    }
  }

  Future<void> _start() async {
    if (_starting || _done) return;
    _starting = true;
    try {
      final cameras = _camera == null ? await widget.loadCameras() : null;
      _camera ??= cameras!
          .where((c) => c.lensDirection == CameraLensDirection.back)
          .followedBy(cameras)
          .firstOrNull;
      final camera = _camera;
      if (camera == null) {
        if (mounted) setState(() => _problem = _CameraProblem.unavailable);
        return;
      }
      // 1080p: seven-segment digits need pixels; one frame at a time keeps
      // the preview smooth.
      final controller = CameraController(
        camera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
      if (_torch) {
        await controller.setFlashMode(FlashMode.torch).catchError((_) {});
      }
      await controller.startImageStream(_onFrame);
      _log.line(
        'camera ${camera.name} lens=${camera.lensDirection.name} '
        'sensor=${camera.sensorOrientation} preview=${controller.value.previewSize} '
        'prior=${widget.lastOdoKm}',
      );
      setState(() {
        _controller = controller;
        _problem = _CameraProblem.none;
      });
      // QA 135: the first scan explains the window and the capture button.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScreenTour.maybeShow(
            context,
            ScreenTour.scan,
            GuideRegistry.scanTourSteps(),
          );
        }
      });
      _hintTimer?.cancel();
      _hintTimer = Timer(_hintAfter, () {
        if (mounted && !_vote.bothLocked) setState(() => _showHint = true);
      });
    } on CameraException catch (e) {
      _log.line('camera error ${e.code}');
      if (!mounted) return;
      setState(
        () =>
            _problem = e.code.contains('Access') || e.code.contains('ermission')
            ? _CameraProblem.denied
            : _CameraProblem.unavailable,
      );
    } on Object catch (e) {
      _log.line('start failed ${e.runtimeType}');
      if (mounted) setState(() => _problem = _CameraProblem.unavailable);
    } finally {
      _starting = false;
    }
  }

  void _stopCamera() {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    () async {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } on Object {
        // Disposing below stops it anyway.
      }
      await controller.dispose();
    }();
  }

  void _onFrame(CameraImage image) {
    if (_busy || _done || _capturing || !mounted) return;
    final now = DateTime.now();
    if (now.difference(_lastFrameAt) < _frameGap) return;
    final degrees = _rotationDegrees();
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    final ok =
        degrees != null &&
        image.planes.length == 1 &&
        (Platform.isAndroid
            ? format == InputImageFormat.nv21
            : format == InputImageFormat.bgra8888);
    if (!ok) {
      _log.once(
        'skip-format',
        'frame skipped format=${image.format.raw} planes=${image.planes.length}',
      );
      return;
    }
    _log.sample(image, _frames);
    final plane = image.planes.first;
    final quarter = degrees == 90 || degrees == 270;
    _imageSize = quarter
        ? Size(image.height.toDouble(), image.width.toDouble())
        : Size(image.width.toDouble(), image.height.toDouble());
    // The plane is only valid during this callback: copy what the isolate
    // reads (Android: just the luminance rows).
    final job = _FrameJob(
      bytes: Platform.isAndroid
          ? Uint8List.fromList(
              plane.bytes.sublist(0, plane.bytesPerRow * image.height),
            )
          : Uint8List.fromList(plane.bytes),
      width: image.width,
      height: image.height,
      bytesPerRow: plane.bytesPerRow,
      rotation: degrees,
      bgra: Platform.isIOS,
      roi: _guideRoi(_imageSize!),
    );
    _lastJob = job;
    final text = _noSegments >= 4 && _noSegments % 2 == 0
        ? _inputImage(image, degrees, format!)
        : null;
    _busy = true;
    _lastFrameAt = now;
    _process(job, text).whenComplete(() => _busy = false);
  }

  /// The guide window as fractions of the upright frame, with a margin
  /// (the preview is cover-fitted to the screen). Null before layout.
  Rect? _guideRoi(Size upright) {
    final guide = _guideKey.currentContext?.findRenderObject();
    final stack = _stackKey.currentContext?.findRenderObject();
    if (guide is! RenderBox || stack is! RenderBox) return null;
    if (!guide.hasSize || !stack.hasSize) return null;
    final screen = stack.size;
    final window = _GuidePainter.windowFor(
      guide.size,
    ).shift(guide.localToGlobal(Offset.zero, ancestor: stack));
    final scale = math.max(
      screen.width / upright.width,
      screen.height / upright.height,
    );
    final shownW = upright.width * scale, shownH = upright.height * scale;
    final ox = (screen.width - shownW) / 2, oy = (screen.height - shownH) / 2;
    final r = Rect.fromLTRB(
      (window.left - ox) / shownW,
      (window.top - oy) / shownH,
      (window.right - ox) / shownW,
      (window.bottom - oy) / shownH,
    );
    final mx = r.width * 0.12, my = r.height * 0.18;
    final roi = Rect.fromLTRB(
      math.max(0, r.left - mx),
      math.max(0, r.top - my),
      math.min(1, r.right + mx),
      math.min(1, r.bottom + my),
    );
    return roi.width > 0.1 && roi.height > 0.05 ? roi : null;
  }

  int? _rotationDegrees() {
    final camera = _camera;
    final controller = _controller;
    if (camera == null || controller == null) return null;
    if (Platform.isIOS) return camera.sensorOrientation;
    final device = switch (controller.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    return camera.lensDirection == CameraLensDirection.front
        ? (camera.sensorOrientation + device) % 360
        : (camera.sensorOrientation - device + 360) % 360;
  }

  /// ML Kit input (fallback for dashboards that are not seven-segment).
  InputImage? _inputImage(
    CameraImage image,
    int degrees,
    InputImageFormat format,
  ) {
    final rotation = InputImageRotationValue.fromRawValue(degrees);
    if (rotation == null) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _process(_FrameJob job, InputImage? text) async {
    final watch = Stopwatch()..start();
    final frame = await _FrameJob.read(job, widget.lastOdoKm);
    final hasDigits = frame.hasDigits;
    _noSegments = hasDigits ? 0 : _noSegments + 1;
    var reading = frame.reading;
    final recognizer = _recognizer;
    if (!hasDigits && text != null && recognizer != null) {
      try {
        reading = DashboardLayoutParser.parse(
          DashboardOcr.tokensOf(await recognizer.processImage(text)),
          lastOdoKm: widget.lastOdoKm,
        );
      } on Object catch (e) {
        _log.line('ocr failed ${e.runtimeType}');
      }
    }
    if (!mounted || _done) return;
    _frames++;
    // The image model gets one turn if the phone has not locked both
    // numbers after a moment (QA 135).
    _aiTimer ??= Timer(_aiAfter, _askAi);
    _log.line(
      'frame $_frames ${watch.elapsedMilliseconds}ms '
      '${hasDigits ? 'seg' : (text != null ? 'mlkit' : 'none')} '
      'img=${_imageSize?.width.round()}x${_imageSize?.height.round()} '
      'roi=${job.roi} '
      'soc=${reading.soc}${reading.socConfident ? '' : '?'} '
      'odo=${reading.odoKm}${reading.odoConfident ? '' : '?'} '
      'cand=${reading.socCandidates}/${reading.odoCandidates}',
    );
    final socBefore = _vote.socLocked;
    final odoBefore = _vote.odoLocked;
    _vote.add(reading);
    final locked =
        (socBefore == null && _vote.socLocked != null) ||
        (odoBefore == null && _vote.odoLocked != null);
    if (locked) HapticFeedback.selectionClick();
    setState(() {
      _socBox = reading.socBox ?? _socBox;
      _odoBox = (reading.odoConfident ? reading.odoBox : null) ?? _odoBox;
    });
    if (_vote.bothLocked) _finish();
  }

  Future<void> _askAi() async {
    final job = _lastJob;
    if (_aiAsked || _done || _vote.bothLocked || job == null || !mounted) {
      return;
    }
    _aiAsked = true;
    try {
      final png = await Isolate.run(() => _FrameJob.png(job));
      final result = await _ai.read(png, lastOdoKm: widget.lastOdoKm);
      _log.line(
        'ai soc=${result.soc} odo=${result.odoKm} conf=${result.confidence}',
      );
      _mergeAi(result);
    } on PinovaApiException catch (e) {
      _log.line('ai unavailable ${e.code}');
    } on Object catch (e) {
      _log.line('ai failed ${e.runtimeType}');
    }
  }

  /// The model's numbers fill what the frames have not locked; the owner
  /// still checks them on the next sheet.
  void _mergeAi(DashboardAiResult result) {
    if (!mounted || _done || result.isEmpty) return;
    final last = widget.lastOdoKm;
    final odo = result.odoKm;
    final odoOk = odo != null && (last == null || odo >= last - 1);
    setState(() {
      if (_vote.socLocked == null && result.soc != null) {
        _vote.socLocked = result.soc;
        _aiAssisted = true;
      }
      if (_vote.odoLocked == null && odoOk) {
        _vote.odoLocked = odo;
        _aiAssisted = true;
      }
    });
    if (_vote.bothLocked) _finish();
  }

  Future<void> _finish() async {
    if (_done) return;
    setState(() => _done = true);
    _hintTimer?.cancel();
    HapticFeedback.mediumImpact();
    final reading = DashboardReading(
      soc: _vote.socLocked,
      odoKm: _vote.odoLocked,
      socCandidates: [if (_vote.socLocked != null) _vote.socLocked!],
      odoCandidates: [if (_vote.odoLocked != null) _vote.odoLocked!],
      odoFromLabel: _vote.odoLocked != null,
      frames: _vote.needed,
      aiAssisted: _aiAssisted,
    );
    // A beat so the owner sees both values lock before the sheet returns.
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (mounted) {
      Navigator.of(context).pop(DashboardScanResult(reading: reading));
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    final next = !_torch;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torch = next);
    } on Object {
      // No torch on this camera.
    }
  }

  /// Full-resolution still: sharper than a stream frame in poor light.
  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing || _done) return;
    setState(() {
      _capturing = true;
      _captureNote = null;
    });
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final shot = await controller.takePicture();
      await _log.keep(shot.path);
      var read = await DashboardReader.readFile(
        shot.path,
        lastOdoKm: widget.lastOdoKm,
      );
      var ai = false;
      if (read.soc == null || read.odoKm == null) {
        // The photo's turn with the image model (QA 135).
        try {
          final png = await DashboardReader.pngOfFile(shot.path);
          if (png != null) {
            final result = await _ai.read(png, lastOdoKm: widget.lastOdoKm);
            final last = widget.lastOdoKm;
            final odoOk =
                result.odoKm != null &&
                (last == null || result.odoKm! >= last - 1);
            ai =
                (read.soc == null && result.soc != null) ||
                (read.odoKm == null && odoOk);
            read = DashboardReading(
              soc: read.soc ?? result.soc,
              odoKm: read.odoKm ?? (odoOk ? result.odoKm : null),
              socCandidates: read.socCandidates,
              odoCandidates: read.odoCandidates,
              odoFromLabel: read.odoFromLabel,
              rawText: read.rawText,
            );
          }
        } on Object catch (e) {
          _log.line('still ai failed ${e.runtimeType}');
        }
      }
      unawaited(File(shot.path).delete().then((_) {}, onError: (_) {}));
      _log.line(
        'still soc=${read.soc} odo=${read.odoKm} ai=$ai | ${read.rawText.replaceAll('\n', ' / ')}',
      );
      if (!mounted) return;
      final reading = DashboardReading(
        soc: _vote.socLocked ?? read.soc,
        odoKm: _vote.odoLocked ?? read.odoKm,
        socCandidates: read.socCandidates,
        odoCandidates: read.odoCandidates,
        odoFromLabel: read.odoFromLabel,
        rawText: read.rawText,
        aiAssisted: ai || _aiAssisted,
      );
      if (!reading.isEmpty) {
        _done = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(DashboardScanResult(reading: reading));
        return;
      }
      setState(
        () => _captureNote =
            'Ảnh chưa đọc được số nào. Đưa gần hơn và nghiêng nhẹ để tránh lóa.',
      );
    } on Object {
      if (mounted) {
        setState(() => _captureNote = 'Không chụp được. Hãy thử lại.');
      }
    } finally {
      if (mounted && !_done) {
        setState(() => _capturing = false);
        final current = _controller;
        if (current != null && !current.value.isStreamingImages) {
          try {
            await current.startImageStream(_onFrame);
          } on Object {
            // The owner can still capture, pick a photo or type.
          }
        }
      }
    }
  }

  void _usePartial() {
    if (_done || !_vote.anyLocked) return;
    _done = true;
    Navigator.of(context).pop(
      DashboardScanResult(
        reading: DashboardReading(
          soc: _vote.socLocked,
          odoKm: _vote.odoLocked,
          frames: _vote.needed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          key: _stackKey,
          fit: StackFit.expand,
          children: [
            if (ready)
              ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: controller.value.previewSize!.height,
                    height: controller.value.previewSize!.width,
                    child: CameraPreview(
                      controller,
                      child: CustomPaint(
                        painter: _FoundPainter(
                          imageSize: _imageSize,
                          socBox: _socBox,
                          odoBox: _odoBox,
                          socLocked: _vote.socLocked != null,
                          odoLocked: _vote.odoLocked != null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        LuxeCircleButton(
                          icon: Icons.close_rounded,
                          tooltip: 'Đóng',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Expanded(
                          child: Text(
                            'Quét đồng hồ xe',
                            key: ValueKey('scan-title'),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LuxeText.item,
                          ),
                        ),
                        LuxeCircleButton(
                          key: const ValueKey('scan-torch'),
                          icon: _torch
                              ? Icons.flashlight_on_rounded
                              : Icons.flashlight_off_rounded,
                          tooltip: _torch ? 'Tắt đèn' : 'Bật đèn',
                          color: _torch
                              ? LuxeColors.champagne
                              : LuxeColors.text,
                          onPressed: ready ? _toggleTorch : null,
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _problem == _CameraProblem.none
                      ? CustomPaint(
                          key: _guideKey,
                          painter: _GuidePainter(ready: ready),
                          child: const SizedBox.expand(),
                        )
                      : _CameraProblemView(
                          denied: _problem == _CameraProblem.denied,
                        ),
                ),
                DashboardScanPanel(
                  socSeen: _vote.socSeen,
                  socLocked: _vote.socLocked,
                  odoSeen: _vote.odoSeen,
                  odoLocked: _vote.odoLocked,
                  scanning: ready && !_done,
                  capturing: _capturing,
                  note:
                      _captureNote ??
                      (_showHint && !_vote.bothLocked
                          ? 'Chưa đọc rõ. Nghiêng nhẹ điện thoại để tránh lóa, '
                                'đưa gần hơn hoặc bấm Chụp ảnh.'
                          : null),
                  onCapture: ready && !_done ? _capture : null,
                  onUse: _vote.anyLocked && !_vote.bothLocked && !_done
                      ? _usePartial
                      : null,
                  onGallery: () => Navigator.of(
                    context,
                  ).pop(const DashboardScanResult(wantsGallery: true)),
                  onManual: () => Navigator.of(context).pop(),
                  onOpenSettings: _problem == _CameraProblem.denied
                      ? openAppSettings
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraProblemView extends StatelessWidget {
  const _CameraProblemView({required this.denied});

  final bool denied;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            size: 44,
            color: LuxeColors.platinumMid,
          ),
          const SizedBox(height: 14),
          Text(
            denied
                ? 'Cần quyền camera để quét đồng hồ. Bạn vẫn có thể chọn ảnh '
                      'hoặc nhập tay.'
                : 'Không mở được camera. Bạn vẫn có thể chọn ảnh hoặc nhập tay.',
            key: const ValueKey('scan-camera-problem'),
            textAlign: TextAlign.center,
            style: LuxeText.body,
          ),
        ],
      ),
    ),
  );
}

/// Live values and actions under the viewfinder.
class DashboardScanPanel extends StatelessWidget {
  const DashboardScanPanel({
    super.key,
    this.socSeen,
    this.socLocked,
    this.odoSeen,
    this.odoLocked,
    this.scanning = false,
    this.capturing = false,
    this.note,
    this.onCapture,
    this.onUse,
    this.onGallery,
    this.onManual,
    this.onOpenSettings,
  });

  final int? socSeen;
  final int? socLocked;
  final double? odoSeen;
  final double? odoLocked;
  final bool scanning;
  final bool capturing;
  final String? note;
  final VoidCallback? onCapture;
  final VoidCallback? onUse;
  final VoidCallback? onGallery;
  final VoidCallback? onManual;
  final VoidCallback? onOpenSettings;

  static String _km(double km) => km == km.roundToDouble()
      ? groupThousands(km.round())
      : km.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final socValue = socLocked ?? socSeen;
    final odoValue = odoLocked ?? odoSeen;
    // Large text: the panel scrolls instead of pushing the viewfinder away.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: LuxeColors.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: LuxeColors.hairline)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _ScanTile(
                    key: const ValueKey('scan-soc'),
                    label: 'PIN',
                    value: socValue == null ? null : '$socValue',
                    unit: '%',
                    locked: socLocked != null,
                    scanning: scanning,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ScanTile(
                    key: const ValueKey('scan-odo'),
                    label: 'ODO',
                    value: odoValue == null ? null : _km(odoValue),
                    unit: 'km',
                    locked: odoLocked != null,
                    scanning: scanning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (onOpenSettings != null) ...[
              FilledButton.icon(
                key: const ValueKey('scan-settings'),
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Mở cài đặt quyền'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 8),
            ] else if (onUse != null) ...[
              FilledButton.icon(
                key: const ValueKey('scan-use'),
                onPressed: onUse,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Dùng số đã đọc'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (note != null) ...[
              const SizedBox(height: 12),
              LuxeNotice(
                key: const ValueKey('scan-note'),
                icon: Icons.wb_sunny_outlined,
                color: LuxeColors.champagne,
                message: note!,
              ),
            ],
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                if (onCapture != null || capturing)
                  KeyedSubtree(
                    key: GuideRegistry.keyScanCapture,
                    child: TextButton.icon(
                      key: const ValueKey('scan-capture'),
                      onPressed: capturing ? null : onCapture,
                      icon: capturing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_alt_outlined),
                      label: const Text('Chụp ảnh'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                    ),
                  ),
                TextButton.icon(
                  key: const ValueKey('scan-gallery'),
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Chọn ảnh'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
                TextButton.icon(
                  key: const ValueKey('scan-manual'),
                  onPressed: onManual,
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Text('Nhập tay'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanTile extends StatelessWidget {
  const _ScanTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.locked,
    required this.scanning,
  });

  final String label;
  final String? value;
  final String unit;
  final bool locked;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final color = locked
        ? LuxeColors.emerald
        : value != null
        ? LuxeColors.champagne
        : LuxeColors.platinumMid;
    final status = locked
        ? 'Đã khớp'
        : value != null
        ? 'Đang xác nhận…'
        : scanning
        ? 'Đang tìm…'
        : 'Chưa có';
    return Semantics(
      container: true,
      label: '$label ${value == null ? 'chưa có' : '$value $unit'}, $status',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: LuxeMotion.enter,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: color.withValues(alpha: locked ? 0.10 : 0.05),
          border: Border.all(
            color: color.withValues(alpha: locked ? 0.55 : 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LuxeText.eyebrow,
                  ),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: locked
                      ? const Icon(
                          Icons.check_circle_rounded,
                          key: ValueKey('locked'),
                          size: 18,
                          color: LuxeColors.emerald,
                        )
                      : const SizedBox(key: ValueKey('open'), height: 18),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 40,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: value ?? '—'),
                        if (value != null)
                          TextSpan(
                            text: ' $unit',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: LuxeColors.muted,
                            ),
                          ),
                      ],
                    ),
                    key: ValueKey(value),
                    maxLines: 1,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: value == null ? LuxeColors.dim : LuxeColors.text,
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LuxeText.caption.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dims the frame around a cluster-shaped window with platinum corners.
class _GuidePainter extends CustomPainter {
  _GuidePainter({required this.ready});

  final bool ready;

  /// The window the owner aims at (also the part of the frame read).
  static Rect windowFor(Size size) {
    final width = (size.width - 48).clamp(0.0, 420.0).toDouble();
    final height = (width * 0.78)
        .clamp(0.0, math.max(0.0, size.height - 32))
        .toDouble();
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: width,
      height: height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = windowFor(size);
    final width = rect.width;
    if (rect.width <= 0 || rect.height <= 0) return;
    final window = RRect.fromRectAndRadius(rect, const Radius.circular(26));
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(window),
      Paint()..color = Colors.black.withValues(alpha: ready ? 0.45 : 0.0),
    );
    final corner = Paint()
      ..color = LuxeColors.platinum.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const arm = 26.0;
    final r = window.outerRect;
    for (final (x, y, dx, dy) in [
      (r.left, r.top, 1.0, 1.0),
      (r.right, r.top, -1.0, 1.0),
      (r.left, r.bottom, 1.0, -1.0),
      (r.right, r.bottom, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + dy * arm)
          ..lineTo(x, y + dy * 10)
          ..quadraticBezierTo(x, y, x + dx * 10, y)
          ..lineTo(x + dx * arm, y),
        corner,
      );
    }
    final hint = TextPainter(
      text: const TextSpan(
        text: 'Đưa số % pin và ODO vào khung',
        style: TextStyle(color: LuxeColors.platinumHi, fontSize: 14),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: width - 24);
    final below = r.bottom + 12;
    final y = below + hint.height <= size.height
        ? below
        : r.bottom - hint.height - 12;
    hint.paint(canvas, Offset(size.width / 2 - hint.width / 2, y));
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.ready != ready;
}

/// Outlines where the % and ODO were found (image → preview coordinates).
class _FoundPainter extends CustomPainter {
  _FoundPainter({
    required this.imageSize,
    required this.socBox,
    required this.odoBox,
    required this.socLocked,
    required this.odoLocked,
  });

  final Size? imageSize;
  final Rect? socBox;
  final Rect? odoBox;
  final bool socLocked;
  final bool odoLocked;

  @override
  void paint(Canvas canvas, Size size) {
    final image = imageSize;
    if (image == null || image.width <= 0 || image.height <= 0) return;
    final sx = size.width / image.width;
    final sy = size.height / image.height;
    void outline(Rect? box, bool locked) {
      if (box == null) return;
      final rect = Rect.fromLTRB(
        box.left * sx,
        box.top * sy,
        box.right * sx,
        box.bottom * sy,
      ).inflate(6);
      final color = locked ? LuxeColors.emerald : LuxeColors.champagne;
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
      canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.14));
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    outline(socBox, socLocked);
    outline(odoBox, odoLocked);
  }

  @override
  bool shouldRepaint(_FoundPainter old) =>
      old.socBox != socBox ||
      old.odoBox != odoBox ||
      old.socLocked != socLocked ||
      old.odoLocked != odoLocked ||
      old.imageSize != imageSize;
}

/// Profile/debug builds only: what the scanner saw, written to the app's
/// own files folder (`Android/data/<app>/files/ocr`) and pulled with adb
/// while tuning (QA 131). Release builds write nothing.
class _ScanLog {
  IOSink? _sink;
  String? _dir;
  int _samples = 0;
  final _onceKeys = <String>{};

  bool get _enabled => !kReleaseMode && Platform.isAndroid;

  Future<void> open() async {
    if (!_enabled) return;
    try {
      final base = await getExternalStorageDirectory();
      if (base == null) return;
      final dir = Directory('${base.path}/ocr');
      await dir.create(recursive: true);
      _dir = dir.path;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      _sink = File('${dir.path}/scan-$stamp.txt').openWrite();
    } on Object {
      _sink = null;
    }
  }

  void line(String text) {
    try {
      _sink?.writeln('${DateTime.now().toIso8601String()} $text');
    } on Object {
      // Diagnostics never break the scan.
    }
  }

  void once(String key, String text) {
    if (_onceKeys.add(key)) line(text);
  }

  /// Every 15th frame (at most 5): the luminance plane as a PGM image.
  void sample(CameraImage image, int frame) {
    final dir = _dir;
    if (dir == null || _samples >= 5 || frame % 15 != 0) return;
    _samples++;
    final plane = image.planes.first;
    final w = image.width, h = image.height;
    if (plane.bytes.length < w * h) return;
    final header = 'P5\n$w $h\n255\n'.codeUnits;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    File(
      '$dir/frame-$stamp.pgm',
    ).writeAsBytes([...header, ...plane.bytes.sublist(0, w * h)]).ignore();
  }

  /// Keeps a copy of a still capture before it is read and deleted.
  Future<void> keep(String path) async {
    final dir = _dir;
    if (dir == null) return;
    try {
      await File(
        path,
      ).copy('$dir/still-${DateTime.now().millisecondsSinceEpoch}.jpg');
    } on Object {
      // Diagnostics only.
    }
  }

  Future<void> close() async {
    try {
      await _sink?.flush();
      await _sink?.close();
    } on Object {
      // Diagnostics only.
    }
    _sink = null;
  }
}

/// One camera frame handed to the seven-segment reader in an isolate.
class _FrameJob {
  const _FrameJob({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.rotation,
    required this.bgra,
    this.roi,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;
  final int rotation;
  final bool bgra;

  /// The guide window (fractions of the upright frame); null = all of it.
  final Rect? roi;

  GrayCrop _crop({int maxSide = 720}) => GrayImage.crop(
    bytes,
    width: width,
    height: height,
    bytesPerRow: bytesPerRow,
    rotation: rotation,
    bgra: bgra,
    roi: roi ?? const Rect.fromLTRB(0, 0, 1, 1),
    maxSide: roi == null ? 960 : maxSide,
  );

  /// The frame's reading, boxes in upright full-frame coordinates (QA 135:
  /// the guide window at full resolution, several thresholds, consensus).
  static Future<({DashboardLayoutReading reading, bool hasDigits})> read(
    _FrameJob job,
    double? lastOdoKm,
  ) async {
    try {
      return await Isolate.run(() {
        final crop = job._crop();
        final passes = SevenSegmentReader.readPasses(crop.image);
        final hasDigits = passes.any(
          (p) => p.any((t) => RegExp(r'\d').hasMatch(t.text)),
        );
        final r = DashboardLayoutParser.combine([
          for (final p in passes)
            DashboardLayoutParser.parse(p, lastOdoKm: lastOdoKm),
        ]);
        return (
          reading: DashboardLayoutReading(
            soc: r.soc,
            odoKm: r.odoKm,
            socBox: r.socBox == null ? null : crop.toFrame(r.socBox!),
            odoBox: r.odoBox == null ? null : crop.toFrame(r.odoBox!),
            socConfident: r.socConfident,
            odoConfident: r.odoConfident,
            socCandidates: r.socCandidates,
            odoCandidates: r.odoCandidates,
          ),
          hasDigits: hasDigits,
        );
      });
    } on Object {
      return (reading: const DashboardLayoutReading(), hasDigits: false);
    }
  }

  /// The guide window as a small grayscale PNG for the image model.
  static Uint8List png(_FrameJob job) =>
      DashboardAiReader.pngFor(job._crop(maxSide: 768).image);
}
