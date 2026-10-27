import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers/app_providers.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/utils/app_error_formatter.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import 'smart_charging_control_screen.dart';
import '../../core/widgets/app_popup.dart';

String _catalogLabel(String key, String fallback) =>
    key == 'charging_time' ? 'Smart Charge' : fallback;

String _catalogShortName(String key, String fallback) =>
    key == 'charging_time' ? 'Smart Charge' : fallback;

class _ModelInfo {
  final String key;
  final String label;
  final String shortName;
  final String phase;
  final String registryStatus;
  final bool isLoaded;
  final bool isPredictable;
  final String? activeVersion;
  final String? lastLoadAt;
  final String? lastError;
  final int? featureCount;
  final int availableVersions;
  final String icon;
  final String description;
  final String runMode;
  final bool mobileCompatible;
  final String? downloadUrl;

  const _ModelInfo({
    required this.key,
    required this.label,
    required this.shortName,
    required this.phase,
    required this.registryStatus,
    required this.isLoaded,
    required this.isPredictable,
    this.activeVersion,
    this.lastLoadAt,
    this.lastError,
    this.featureCount,
    this.availableVersions = 0,
    required this.icon,
    required this.description,
    this.runMode = 'none',
    this.mobileCompatible = false,
    this.downloadUrl,
  });
}

class AiModelsScreen extends ConsumerStatefulWidget {
  const AiModelsScreen({super.key});

  @override
  ConsumerState<AiModelsScreen> createState() => _AiModelsScreenState();
}

class _AiModelsScreenState extends ConsumerState<AiModelsScreen>
    with WidgetsBindingObserver {
  List<_ModelInfo> _models = [];
  bool _loading = true;
  String? _error;
  DateTime? _lastFetchedAt;
  bool _fromCache = false; // true khi đang hiển thị dữ liệu cache
  int _retryCount = 0;
  static const _cacheKey = 'ai_models_catalog_v3';
  static const _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Load cache ngay để hiển thị nhanh, rồi fetch mới ở background
    _loadFromCache().then((_) => _fetchModels());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _retryCount = 0;
      _fetchModels();
    }
  }

  // ── Cache helpers ────────────────────────────────────────────────

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((m) => _fromCacheMap(m as Map<String, dynamic>))
          .toList();
      if (list.isNotEmpty && mounted) {
        setState(() {
          _models = list;
          _loading = false; // Hiển thị cache ngay, không spinner
          _fromCache = true;
        });
      }
    } catch (e) {
      debugPrint('[AiModels] Cache read error: $e');
    }
  }

  Future<void> _saveToCache(List<_ModelInfo> models) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(models.map(_toCacheMap).toList());
      await prefs.setString(_cacheKey, raw);
    } catch (e) {
      debugPrint('[AiModels] Cache write error: $e');
    }
  }

  Map<String, dynamic> _toCacheMap(_ModelInfo m) => {
    'key': m.key,
    'label': m.label,
    'shortName': m.shortName,
    'phase': m.phase,
    'registryStatus': m.registryStatus,
    'isLoaded': m.isLoaded,
    'isPredictable': m.isPredictable,
    'activeVersion': m.activeVersion,
    'lastLoadAt': m.lastLoadAt,
    'lastError': m.lastError,
    'featureCount': m.featureCount,
    'availableVersions': m.availableVersions,
    'icon': m.icon,
    'description': m.description,
    'runMode': m.runMode,
    'mobileCompatible': m.mobileCompatible,
    'downloadUrl': m.downloadUrl,
  };

  _ModelInfo _fromCacheMap(Map<String, dynamic> m) => _ModelInfo(
    key: m['key'] as String? ?? '',
    label: m['label'] as String? ?? '',
    shortName: m['shortName'] as String? ?? '',
    phase: m['phase'] as String? ?? '',
    registryStatus: m['registryStatus'] as String? ?? 'planned',
    isLoaded: m['isLoaded'] as bool? ?? false,
    isPredictable: m['isPredictable'] as bool? ?? false,
    activeVersion: m['activeVersion'] as String?,
    lastLoadAt: m['lastLoadAt'] as String?,
    lastError: m['lastError'] as String?,
    featureCount: m['featureCount'] as int?,
    availableVersions: m['availableVersions'] as int? ?? 0,
    icon: m['icon'] as String? ?? 'BrainCircuit',
    description: m['description'] as String? ?? '',
    runMode: m['runMode'] as String? ?? 'none',
    mobileCompatible: m['mobileCompatible'] as bool? ?? false,
    downloadUrl: m['downloadUrl'] as String?,
  );

  static String? _stringOrNull(dynamic value) {
    if (value == null) return null;
    final str = value.toString().trim();
    return str.isEmpty ? null : str;
  }

  static int? _intOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool _boolValue(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  // ── Cập nhật cache khi predict thành công (mark model là loaded) ──
  void markModelPredictSuccess(String modelKey) {
    final updated = _models.map((m) {
      if (m.key == modelKey && !m.isLoaded) {
        return _ModelInfo(
          key: m.key,
          label: m.label,
          shortName: m.shortName,
          phase: m.phase,
          registryStatus: m.registryStatus,
          isLoaded: true,
          isPredictable: true,
          activeVersion: m.activeVersion,
          lastLoadAt: m.lastLoadAt,
          lastError: null,
          featureCount: m.featureCount,
          availableVersions: m.availableVersions,
          icon: m.icon,
          description: m.description,
          runMode: m.runMode,
          mobileCompatible: m.mobileCompatible,
          downloadUrl: m.downloadUrl,
        );
      }
      return m;
    }).toList();
    if (mounted) setState(() => _models = updated);
    _saveToCache(updated);
  }

  Future<void> _fetchModels() async {
    if (!mounted) return;
    // Nếu đã có dữ liệu (cache hoặc fresh), chỉ refresh loading nhẹ
    final hasCurrent = _models.isNotEmpty;
    if (!hasCurrent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final res = await ApiService().getUserAiModels();
      if (res['success'] == true) {
        final typesList = (res['data']?['types'] as List?) ?? [];

        final results = typesList.map((raw) {
          final t = Map<String, dynamic>.from(raw as Map);
          // Backend /api/user/ai/models trả về flat fields (PLAN):
          // runtimeStatus: 'loaded' | 'not_loaded' | 'error'
          // isLoaded, isPredictable: bool
          // activeVersion, featureCount, lastLoadAt, lastError, runMode
          final runtimeStatus =
              _stringOrNull(t['runtimeStatus']) ??
              _stringOrNull(t['runtimeHealth']) ??
              'not_loaded';
          final activeVersion =
              _stringOrNull(t['activeVersion']) ??
              _stringOrNull(t['deploymentVersion']) ??
              _stringOrNull(t['latestUploadedVersion']);
          final lastLoadAt =
              _stringOrNull(t['lastLoadAt']) ?? _stringOrNull(t['deployedAt']);
          final lastError =
              _stringOrNull(t['lastError']) ??
              _stringOrNull(t['validationError']);
          final runMode = _stringOrNull(t['runMode']) ?? 'none';
          final deploymentStatus =
              _stringOrNull(t['deploymentStatus']) ??
              _stringOrNull(t['status']) ??
              'planned';
          final mobileCompatible = _boolValue(t['mobileCompatible']);
          final isLoaded = _boolValue(t['isLoaded']);
          final isPredictable = _boolValue(t['isPredictable']);

          // Server-only model (.keras/.pkl) vẫn chạy qua backend predict.
          // Có active/deployed version và không có lỗi runtime thì coi là đã triển khai.
          final hasDeployedVersion =
              activeVersion != null ||
              deploymentStatus == 'deployed' ||
              runtimeStatus == 'loaded';
          final effectiveLoaded =
              lastError == null &&
              (isLoaded ||
                  isPredictable ||
                  runtimeStatus == 'loaded' ||
                  runtimeStatus == 'deployed' ||
                  (runMode == 'server_only' && hasDeployedVersion) ||
                  hasDeployedVersion);

          return _ModelInfo(
            key: _stringOrNull(t['key']) ?? '',
            label: _catalogLabel(
              _stringOrNull(t['key']) ?? '',
              _stringOrNull(t['label']) ?? '',
            ),
            shortName: _catalogShortName(
              _stringOrNull(t['key']) ?? '',
              _stringOrNull(t['shortName']) ?? '',
            ),
            phase: _stringOrNull(t['phase']) ?? '',
            registryStatus: deploymentStatus,
            isLoaded: effectiveLoaded,
            isPredictable: isPredictable || effectiveLoaded,
            activeVersion: activeVersion,
            lastLoadAt: lastLoadAt,
            lastError: lastError,
            featureCount: _intOrNull(t['featureCount']),
            availableVersions: _intOrNull(t['versionsCount']) ?? 0,
            icon: _stringOrNull(t['icon']) ?? 'BrainCircuit',
            description: _stringOrNull(t['description']) ?? '',
            runMode: runMode,
            mobileCompatible: mobileCompatible,
            downloadUrl: _stringOrNull(t['downloadUrl']),
          );
        }).toList();

        if (results.isNotEmpty) {
          if (!mounted) return;
          _retryCount = 0;
          await _saveToCache(results);
          setState(() {
            _models = results;
            _loading = false;
            _fromCache = false;
            _error = null;
            _lastFetchedAt = DateTime.now();
          });
          return;
        }
      }

      // API trả success=false hoặc list rỗng → fallback Firestore
      await _fetchModelsFromFirestore();
    } catch (e) {
      debugPrint('[AiModels] API error: $e');
      // Còn cache → giữ nguyên, hiển thị error nhẹ, retry
      if (_models.isNotEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _fromCache = true;
            _error = null; // không show full-page error khi có cache
          });
        }
        _scheduleRetry();
        return;
      }
      // Không có cache → thử Firestore
      try {
        await _fetchModelsFromFirestore();
      } catch (e2) {
        if (mounted) {
          setState(() {
            _error =
                'Chưa thể tải danh sách tính năng AI. Vui lòng thử lại sau.';
            _loading = false;
          });
        }
      }
    }
  }

  void _scheduleRetry() {
    if (_retryCount >= _maxRetries) return;
    _retryCount++;
    final delay = Duration(seconds: 2 << _retryCount); // 4s, 8s, 16s
    debugPrint('[AiModels] Retry #$_retryCount in ${delay.inSeconds}s');
    Future.delayed(delay, () {
      if (mounted) _fetchModels();
    });
  }

  /// Fallback: read deployed models from Firestore collection
  Future<void> _fetchModelsFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('AiModelDeployments')
          .get();

      final results = snapshot.docs.map((doc) {
        final d = doc.data();
        final activeVersion = d['activeVersion'] as Map<String, dynamic>? ?? {};
        final versionStr =
            activeVersion['version'] as String? ??
            d['latestVersion'] as String?;
        final isDeployed =
            d['status'] == 'deployed' || activeVersion.isNotEmpty;

        return _ModelInfo(
          key: doc.id,
          label: _catalogLabel(
            doc.id,
            d['label'] as String? ?? d['name'] as String? ?? doc.id,
          ),
          shortName: _catalogShortName(doc.id, d['shortName'] as String? ?? ''),
          phase:
              d['phase'] as String? ?? (isDeployed ? 'production' : 'planned'),
          registryStatus: d['status'] as String? ?? 'planned',
          isLoaded: isDeployed,
          isPredictable: isDeployed,
          activeVersion: versionStr,
          lastLoadAt: activeVersion['deployedAt'] as String?,
          lastError: d['error'] as String?,
          icon: d['icon'] as String? ?? 'BrainCircuit',
          description: d['description'] as String? ?? '',
          runMode: d['runMode'] as String? ?? 'server',
          mobileCompatible: d['mobileCompatible'] == true,
          downloadUrl: d['downloadUrl'] as String?,
        );
      }).toList();

      if (!mounted) return;
      if (results.isEmpty) {
        setState(() {
          _error = 'Chưa có model nào được deploy';
          _loading = false;
        });
      } else {
        setState(() {
          _models = results;
          _loading = false;
          _error = null;
          _lastFetchedAt = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('[AiModels] Firestore fallback error: $e');
      setState(() {
        _error = 'Không thể tải models: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-refetch khi user chuyển sang AI tab (index 1)
    ref.listen<int>(currentTabProvider, (prev, next) {
      if (next == 1 && prev != 1) {
        _fetchModels();
      }
    });
    // Auto-refetch khi global pull-to-refresh được kích hoạt
    ref.listen<DateTime?>(lastRefreshTimeProvider, (prev, next) {
      if (next != null && next != prev) {
        _fetchModels();
      }
    });

    return LuxeScaffold(
      appBar: Navigator.canPop(context) ? const LuxeAppBar() : null,
      body: SafeArea(
        top: !Navigator.canPop(context),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: LuxeReveal(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const LuxePageHeaderText(
                        eyebrow: 'Trí tuệ nhân tạo',
                        title: 'Dự báo cho xe',
                        caption: 'Kết quả dự kiến từ dữ liệu của xe',
                      ),
                      const SizedBox(height: 12),
                      // Auto-sync indicator (pull-to-refresh để reload).
                      _buildSyncIndicator(),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: LuxeReveal(index: 1, child: _buildAiAssistantCard()),
              ),
            ),
            if (_error != null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: LuxeNotice(
                    icon: Icons.wifi_off_rounded,
                    color: LuxeColors.danger,
                    message:
                        'Chưa tải được dự báo. Kiểm tra kết nối rồi thử lại.',
                  ),
                ),
              ),
            if (_fromCache && _error == null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: LuxeNotice(
                    icon: Icons.history_rounded,
                    color: LuxeColors.champagne,
                    message: 'Dữ liệu cache — đang kiểm tra server…',
                  ),
                ),
              ),
            if (_models.isNotEmpty || _loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: LuxeSectionLabel('Mô hình'),
                ),
              ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: LoadingSkeleton(layout: SkeletonLayout.list),
                ),
              ),
            if (!_loading)
              SliverList(
                delegate: SliverChildBuilderDelegate((ctx, i) {
                  final m = _models[i];
                  final card = _buildModelCard(
                    context: context,
                    model: m,
                    onTap: m.key == 'charging_time'
                        ? () => _navigateToChargingPredictor(context)
                        : null,
                  );
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: i < 8 ? LuxeReveal(index: i + 2, child: card) : card,
                  );
                }, childCount: _models.length),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildAiAssistantCard() {
    final loadedCount = _models.where((m) => m.isLoaded).length;
    final total = _models.length;
    return LuxeGlass(
      radius: 24,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          LuxeRing(
            value: total == 0 ? 0 : loadedCount / total,
            size: 80,
            stroke: 6,
            semanticLabel: '$loadedCount trên $total mô hình đang hoạt động',
            child: ExcludeSemantics(
              child: Text(
                total == 0 ? '…' : '$loadedCount/$total',
                style: const TextStyle(
                  color: LuxeColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TRỢ LÝ THÔNG MINH', style: LuxeText.eyebrow),
                const SizedBox(height: 6),
                Text(
                  _loading
                      ? 'Đang tải…'
                      : '$loadedCount/$total mô hình đang hoạt động',
                  style: LuxeText.item.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  '${total == 0 ? '…' : '$total'} mô hình trong danh mục',
                  style: LuxeText.caption.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelCard({
    required BuildContext context,
    required _ModelInfo model,
    VoidCallback? onTap,
  }) {
    final iconData = switch (model.icon) {
      'Timer' => Icons.timer_rounded,
      'Navigation' => Icons.navigation_rounded,
      'Cpu' => Icons.memory_rounded,
      'BatteryCharging' => Icons.battery_charging_full_rounded,
      _ => Icons.psychology_rounded,
    };

    final hasUsableModel =
        model.isLoaded ||
        model.isPredictable ||
        (model.activeVersion != null && model.lastError == null);

    final Color badgeColor = hasUsableModel
        ? LuxeColors.emerald
        : model.lastError != null
        ? LuxeColors.danger
        : LuxeColors.platinumMid;

    final String badgeText = hasUsableModel
        ? 'Đã triển khai'
        : model.lastError != null
        ? 'Lỗi model'
        : 'Chưa có model';

    String? loadInfo;
    if (model.lastLoadAt != null) {
      try {
        final dt = DateTime.parse(model.lastLoadAt!).toLocal();
        loadInfo =
            'Load ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${dt.day}/${dt.month}/${dt.year}';
      } catch (_) {
        loadInfo = 'Load ${model.lastLoadAt}';
      }
    }

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: LuxeGlass(
          selected: model.isLoaded,
          radius: 22,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  LuxeMedallion(
                    icon: iconData,
                    accent: hasUsableModel ? LuxeColors.emerald : null,
                    size: 44,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.label,
                          style: LuxeText.item.copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          model.shortName.toUpperCase(),
                          style: LuxeText.label.copyWith(
                            fontSize: 10.5,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onTap != null)
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: LuxeColors.dim,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  LuxeTag(badgeText, color: badgeColor),
                  if (model.activeVersion != null)
                    LuxeTag(model.activeVersion!),
                  if (loadInfo != null)
                    LuxeTag(loadInfo, color: LuxeColors.steel),
                  if (model.featureCount != null)
                    LuxeTag('Features ${model.featureCount}'),
                ],
              ),
              if (model.lastError != null && !model.isLoaded) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: LuxeColors.danger,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        AppErrorFormatter.format(model.lastError),
                        style: const TextStyle(
                          color: LuxeColors.danger,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Indicator trạng thái sync (không còn nút refresh manual).
  Widget _buildSyncIndicator() {
    final last = _lastFetchedAt;
    String label;
    if (_loading) {
      label = 'Đang đồng bộ…';
    } else if (last == null) {
      label = 'Chưa đồng bộ';
    } else {
      final h = last.hour.toString().padLeft(2, '0');
      final m = last.minute.toString().padLeft(2, '0');
      label = 'Cập nhật $h:$m';
    }
    return LuxeTag(
      label,
      color: last == null && !_loading
          ? LuxeColors.platinumMid
          : LuxeColors.emerald,
    );
  }

  void _navigateToChargingPredictor(BuildContext context) {
    final vehicleId = ref.read(selectedVehicleIdProvider);
    final vehicle = vehicleId.isEmpty
        ? null
        : ref.read(vehicleProvider(vehicleId)).value;
    if (vehicle == null || vehicleId.isEmpty) {
      AppPopup.showMessage(
        'Hãy chọn một xe trước khi mở Smart Charge.',
        kind: AppNoticeKind.warning,
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SmartChargingControlScreen(
          vehicleId: vehicleId,
          currentSoc: vehicle.currentBattery.toDouble(),
        ),
      ),
    );
  }
}
