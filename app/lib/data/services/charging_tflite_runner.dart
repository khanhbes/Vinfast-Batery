import 'dart:io';
import 'dart:isolate';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../../core/services/model_sync_service.dart';

typedef ChargingLocalInference =
    Future<double> Function(String modelPath, List<double> features);

/// Runs the legacy six-feature, float32 charging model. Missing or invalid
/// models return null; a physics estimate must never be labelled as AI.
class ChargingTfliteRunner {
  ChargingTfliteRunner({
    ModelSyncService? modelSyncService,
    String? Function()? modelPathResolver,
    ChargingLocalInference? inference,
  }) : _syncService = modelSyncService ?? ModelSyncService(),
       _modelPathResolver = modelPathResolver,
       _inference = inference ?? _runOffMainThread;

  final ModelSyncService _syncService;
  final String? Function()? _modelPathResolver;
  final ChargingLocalInference _inference;

  String? get _path => _modelPathResolver != null
      ? _modelPathResolver()
      : _syncService.getLocalModelPath('charging_time');

  bool hasLocalModel() {
    if (_modelPathResolver == null &&
        !_syncService.hasVerifiedMobileContract('charging_time')) {
      return false;
    }
    final path = _path;
    if (path == null) return false;
    RandomAccessFile? handle;
    try {
      handle = File(path).openSync();
      if (handle.lengthSync() < 16) return false;
      final header = handle.readSync(8);
      return header[4] == 84 &&
          header[5] == 70 &&
          header[6] == 76 &&
          header[7] == 51;
    } on Object {
      return false;
    } finally {
      handle?.closeSync();
    }
  }

  String getLocalVersion() =>
      _syncService.getLocalModelVersion('charging_time') ?? 'local_unversioned';

  Future<int?> predictDurationSeconds({
    required double startSoc,
    required double targetSoc,
    double ambientTempC = 30,
    double? nominalCapacityWh,
  }) async {
    if (!startSoc.isFinite ||
        !targetSoc.isFinite ||
        !ambientTempC.isFinite ||
        startSoc < 0 ||
        startSoc > 100 ||
        targetSoc < 0 ||
        targetSoc > 100) {
      return null;
    }
    final delta = targetSoc - startSoc;
    if (delta <= 0) return 0;
    final path = _path;
    if (path == null || !hasLocalModel()) return null;
    try {
      final seconds = await _inference(path, [
        startSoc,
        targetSoc,
        delta,
        ambientTempC,
        22.5,
        (ambientTempC - 27).abs(),
      ]);
      if (!seconds.isFinite || seconds < 1 || seconds > 36000) return null;
      return seconds.round();
    } on Object {
      return null;
    }
  }

  static Future<double> _runOffMainThread(String path, List<double> features) =>
      Isolate.run(() {
        final interpreter = Interpreter.fromFile(File(path));
        try {
          final inputs = interpreter.getInputTensors();
          final outputs = interpreter.getOutputTensors();
          bool shapeIs(List<int> shape, int width) =>
              shape.length == 2 && shape[0] == 1 && shape[1] == width;
          if (inputs.length != 1 ||
              outputs.length != 1 ||
              inputs.single.type != TensorType.float32 ||
              outputs.single.type != TensorType.float32 ||
              !shapeIs(inputs.single.shape, 6) ||
              !shapeIs(outputs.single.shape, 1)) {
            throw StateError('Unsupported charging model contract');
          }
          final output = <List<double>>[
            [0],
          ];
          interpreter.run(<List<double>>[features], output);
          return output.single.single;
        } finally {
          interpreter.close();
        }
      });
}
