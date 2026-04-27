import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import 'api_service.dart';

/// Model deployment info từ server
class DeployedModelInfo {
  final String key;
  final String label;
  final String? shortName;
  final String? description;
  final String? group;
  final String? deploymentVersion;
  final String? deployedAt;
  final String? runtimeHealth;
  final bool mobileCompatible;
  final String? artifactExt;
  final String? downloadUrl;

  DeployedModelInfo({
    required this.key,
    required this.label,
    this.shortName,
    this.description,
    this.group,
    this.deploymentVersion,
    this.deployedAt,
    this.runtimeHealth,
    this.mobileCompatible = false,
    this.artifactExt,
    this.downloadUrl,
  });

  factory DeployedModelInfo.fromJson(Map<String, dynamic> json) {
    return DeployedModelInfo(
      key: json['key'] ?? '',
      label: json['label'] ?? '',
      shortName: json['shortName'],
      description: json['description'],
      group: json['group'],
      deploymentVersion: json['deploymentVersion'],
      deployedAt: json['deployedAt'],
      runtimeHealth: json['runtimeHealth'],
      mobileCompatible: json['mobileCompatible'] ?? false,
      artifactExt: json['artifactExt'],
      downloadUrl: json['downloadUrl'],
    );
  }

  String get uniqueKey => '${key}_$deploymentVersion';
}

/// Manifest của model đã tải về local
class LocalModelManifest {
  final String key;
  final String version;
  final String localPath;
  final String artifactExt;
  final DateTime downloadedAt;
  final int fileSize;

  LocalModelManifest({
    required this.key,
    required this.version,
    required this.localPath,
    required this.artifactExt,
    required this.downloadedAt,
    required this.fileSize,
  });

  Map<String, dynamic> toJson() => {
    'key': key,
    'version': version,
    'localPath': localPath,
    'artifactExt': artifactExt,
    'downloadedAt': downloadedAt.toIso8601String(),
    'fileSize': fileSize,
  };

  factory LocalModelManifest.fromJson(Map<String, dynamic> json) {
    return LocalModelManifest(
      key: json['key'] ?? '',
      version: json['version'] ?? '',
      localPath: json['localPath'] ?? '',
      artifactExt: json['artifactExt'] ?? '.tflite',
      downloadedAt: DateTime.tryParse(json['downloadedAt'] ?? '') ?? DateTime.now(),
      fileSize: json['fileSize'] ?? 0,
    );
  }
}

/// Callback khi có model update
typedef OnModelUpdate = void Function(List<DeployedModelInfo> newModels, List<DeployedModelInfo> updatedModels);

/// Service đồng bộ model từ server về app
class ModelSyncService {
  static final ModelSyncService _instance = ModelSyncService._internal();
  factory ModelSyncService() => _instance;
  ModelSyncService._internal();

  static const _manifestKey = 'model_sync_manifest';
  static const _lastSyncKey = 'model_sync_last_check';

  Map<String, LocalModelManifest> _localManifest = {};
  List<DeployedModelInfo> _lastDeployedModels = [];

  OnModelUpdate? onModelUpdate;

  /// Khởi tạo service, load manifest local
  Future<void> initialize() async {
    await _loadManifest();
    debugPrint('[ModelSync] Initialized with ${_localManifest.length} local models');
  }

  /// Đồng bộ model từ server - gọi khi app mở/resume
  Future<ModelSyncResult> sync({bool force = false}) async {
    try {
      // Check throttle (6 giờ)
      if (!force) {
        final prefs = await SharedPreferences.getInstance();
        final lastSync = prefs.getInt(_lastSyncKey) ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        final hoursSince = (now - lastSync) / (1000 * 60 * 60);
        if (hoursSince < 6) {
          return ModelSyncResult.skipped('Throttled: ${hoursSince.toStringAsFixed(1)}h since last sync');
        }
      }

      // Fetch deployed models
      final response = await ApiService().get('/api/user/ai/models/deployed');
      if (response['success'] != true) {
        return ModelSyncResult.failed(response['error'] ?? 'API error');
      }

      final data = response['data'] ?? {};
      final types = (data['types'] as List<dynamic>? ?? []);
      
      final deployedModels = types
          .map((t) => DeployedModelInfo.fromJson(t as Map<String, dynamic>))
          .toList();

      _lastDeployedModels = deployedModels;

      // So sánh với local manifest
      final newModels = <DeployedModelInfo>[];
      final updatedModels = <DeployedModelInfo>[];

      for (final model in deployedModels) {
        if (!model.mobileCompatible || model.downloadUrl == null) continue;

        final local = _localManifest[model.key];
        if (local == null) {
          // Model mới chưa có local
          newModels.add(model);
        } else if (local.version != model.deploymentVersion) {
          // Có version mới
          updatedModels.add(model);
        }
      }

      // Tải model mới/cập nhật
      final downloaded = <DeployedModelInfo>[];
      final failed = <String>[];

      for (final model in [...newModels, ...updatedModels]) {
        final success = await _downloadModel(model);
        if (success) {
          downloaded.add(model);
        } else {
          failed.add(model.key);
        }
      }

      // Cập nhật timestamp
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);

      // Callback
      if (onModelUpdate != null && (newModels.isNotEmpty || updatedModels.isNotEmpty)) {
        onModelUpdate!(newModels, updatedModels);
      }

      return ModelSyncResult.success(
        checked: deployedModels.length,
        newModels: newModels.length,
        updatedModels: updatedModels.length,
        downloaded: downloaded.length,
        failed: failed,
      );

    } catch (e, stack) {
      debugPrint('[ModelSync] Error: $e\n$stack');
      return ModelSyncResult.failed(e.toString());
    }
  }

  /// Tải model từ server
  Future<bool> _downloadModel(DeployedModelInfo model) async {
    if (model.downloadUrl == null) return false;

    try {
      final url = '${AppConstants.apiBaseUrl}${model.downloadUrl}';
      final response = await http.get(Uri.parse(url), headers: await ApiService().getHeaders());

      if (response.statusCode != 200) {
        debugPrint('[ModelSync] Download failed for ${model.key}: ${response.statusCode}');
        return false;
      }

      // Lưu file
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${appDir.path}/models');
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }

      final ext = model.artifactExt ?? '.tflite';
      final fileName = '${model.key}_v${model.deploymentVersion}$ext';
      final filePath = '${modelDir.path}/$fileName';

      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      // Cập nhật manifest
      final manifest = LocalModelManifest(
        key: model.key,
        version: model.deploymentVersion!,
        localPath: filePath,
        artifactExt: ext,
        downloadedAt: DateTime.now(),
        fileSize: response.bodyBytes.length,
      );

      _localManifest[model.key] = manifest;
      await _saveManifest();

      debugPrint('[ModelSync] Downloaded ${model.key} v${model.deploymentVersion} (${response.bodyBytes.length} bytes)');
      return true;

    } catch (e) {
      debugPrint('[ModelSync] Download error for ${model.key}: $e');
      return false;
    }
  }

  /// Lấy đường dẫn local của model nếu có
  String? getLocalModelPath(String key) {
    final manifest = _localManifest[key];
    if (manifest == null) return null;

    final file = File(manifest.localPath);
    if (!file.existsSync()) return null;

    return manifest.localPath;
  }

  /// Kiểm tra model có sẵn local không
  bool isModelAvailable(String key, {String? requiredVersion}) {
    final manifest = _localManifest[key];
    if (manifest == null) return false;

    if (requiredVersion != null && manifest.version != requiredVersion) {
      return false;
    }

    final file = File(manifest.localPath);
    return file.existsSync();
  }

  /// Xóa model local
  Future<bool> deleteLocalModel(String key) async {
    final manifest = _localManifest[key];
    if (manifest == null) return false;

    try {
      final file = File(manifest.localPath);
      if (await file.exists()) {
        await file.delete();
      }
      _localManifest.remove(key);
      await _saveManifest();
      return true;
    } catch (e) {
      debugPrint('[ModelSync] Delete error: $e');
      return false;
    }
  }

  /// Load manifest từ SharedPreferences
  Future<void> _loadManifest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_manifestKey);
      if (jsonStr != null) {
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        _localManifest = data.map((key, value) => MapEntry(
          key,
          LocalModelManifest.fromJson(value as Map<String, dynamic>),
        ));
      }
    } catch (e) {
      debugPrint('[ModelSync] Load manifest error: $e');
      _localManifest = {};
    }
  }

  /// Save manifest vào SharedPreferences
  Future<void> _saveManifest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _localManifest.map((key, value) => MapEntry(key, value.toJson()));
      await prefs.setString(_manifestKey, jsonEncode(data));
    } catch (e) {
      debugPrint('[ModelSync] Save manifest error: $e');
    }
  }

  /// Lấy danh sách models đã deploy từ lần sync cuối
  List<DeployedModelInfo> get lastDeployedModels => List.unmodifiable(_lastDeployedModels);

  /// Lấy danh sách local manifests
  List<LocalModelManifest> get localManifests => List.unmodifiable(_localManifest.values);
}

/// Kết quả đồng bộ model
class ModelSyncResult {
  final bool success;
  final String message;
  final int? checked;
  final int? newModels;
  final int? updatedModels;
  final int? downloaded;
  final List<String>? failed;

  ModelSyncResult({
    required this.success,
    required this.message,
    this.checked,
    this.newModels,
    this.updatedModels,
    this.downloaded,
    this.failed,
  });

  factory ModelSyncResult.success({
    required int checked,
    required int newModels,
    required int updatedModels,
    required int downloaded,
    List<String>? failed,
  }) {
    return ModelSyncResult(
      success: true,
      message: 'Đồng bộ thành công: $downloaded model mới/cập nhật',
      checked: checked,
      newModels: newModels,
      updatedModels: updatedModels,
      downloaded: downloaded,
      failed: failed,
    );
  }

  factory ModelSyncResult.failed(String error) {
    return ModelSyncResult(
      success: false,
      message: 'Lỗi: $error',
    );
  }

  factory ModelSyncResult.skipped(String reason) {
    return ModelSyncResult(
      success: true,
      message: 'Bỏ qua: $reason',
    );
  }
}
