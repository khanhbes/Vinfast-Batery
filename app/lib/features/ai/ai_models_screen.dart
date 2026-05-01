import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers/app_state_providers.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_colors.dart';
import 'ai_charging_predictor_screen.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchModels();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Auto-refresh khi app trở lại foreground
    if (state == AppLifecycleState.resumed) {
      _fetchModels();
    }
  }

  Future<void> _fetchModels() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      // Try API first
      final res = await ApiService().getUserAiModels();
      if (res['success'] == true) {
        final typesList = (res['data']?['types'] as List?) ?? [];

        final results = typesList.map((t) {
          // Backend /api/user/ai/models trả về flat fields (PLAN):
          // runtimeStatus: 'loaded' | 'not_loaded' | 'error'
          // isLoaded, isPredictable: bool
          // activeVersion, featureCount, lastLoadAt, lastError, runMode
          final runtimeStatus = t['runtimeStatus'] as String? ?? 'not_loaded';
          final isLoaded = t['isLoaded'] == true;
          final isPredictable = t['isPredictable'] == true;
          final activeVersion = t['activeVersion'] as String?;
          final featureCount = t['featureCount'] as int?;
          final lastLoadAt = t['lastLoadAt'] as String?;
          final lastError = t['lastError'] as String? ?? t['validationError'] as String?;
          final versionsCount = t['versionsCount'] as int? ?? 0;
          final runMode = t['runMode'] as String? ?? 'none';
          final mobileCompatible = t['mobileCompatible'] == true;

          // Tính isLoaded chính xác cho cả server-only model:
          // nếu backend báo runtimeStatus=='loaded' hoặc có activeVersion
          // thì coi là ĐÃ LOAD (vì server-only không cần local file).
          final effectiveLoaded = isLoaded ||
              runtimeStatus == 'loaded' ||
              (runMode == 'server_only' && activeVersion != null);

          return _ModelInfo(
            key: t['key'] as String? ?? '',
            label: t['label'] as String? ?? '',
            shortName: t['shortName'] as String? ?? '',
            phase: t['phase'] as String? ?? '',
            registryStatus: t['status'] as String? ?? 'planned',
            isLoaded: effectiveLoaded,
            isPredictable: isPredictable || effectiveLoaded,
            activeVersion: activeVersion,
            lastLoadAt: lastLoadAt,
            lastError: lastError,
            featureCount: featureCount,
            availableVersions: versionsCount,
            icon: t['icon'] as String? ?? 'BrainCircuit',
            description: t['description'] as String? ?? '',
            runMode: runMode,
            mobileCompatible: mobileCompatible,
            downloadUrl: t['downloadUrl'] as String?,
          );
        }).toList();

        if (results.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _models = results;
            _loading = false;
            _lastFetchedAt = DateTime.now();
          });
          return;
        }
      }

      // Fallback: read from Firestore AiModelDeployments
      await _fetchModelsFromFirestore();
    } catch (e) {
      // API failed — try Firestore fallback
      debugPrint('[AiModels] API error: $e, falling back to Firestore');
      try {
        await _fetchModelsFromFirestore();
      } catch (e2) {
        setState(() { _error = e.toString(); _loading = false; });
      }
    }
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
        final versionStr = activeVersion['version'] as String? ?? d['latestVersion'] as String?;
        final isDeployed = d['status'] == 'deployed' || activeVersion.isNotEmpty;

        return _ModelInfo(
          key: doc.id,
          label: d['label'] as String? ?? d['name'] as String? ?? doc.id,
          shortName: d['shortName'] as String? ?? '',
          phase: d['phase'] as String? ?? (isDeployed ? 'production' : 'planned'),
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
        setState(() { _error = 'Chưa có model nào được deploy'; _loading = false; });
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
      setState(() { _error = 'Không thể tải models: $e'; _loading = false; });
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Title
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AI Models',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Cores and Intelligence Engine',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Auto-sync indicator (pull-to-refresh để reload, không còn nút manual)
                    _buildSyncIndicator(),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
            ),

            // AI Assistant summary card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _buildAiAssistantCard(),
              ),
            ),

            // Error state
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.error.withAlpha(51)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.wifi_off_rounded, color: AppColors.error, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Không kết nối được server', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700, fontSize: 13)),
                              Text(AppConstants.apiBaseUrl, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Loading skeletons
            if (_loading)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Container(
                      height: 90,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                    ),
                  ),
                  childCount: 3,
                ),
              ),

            // Real model cards
            if (!_loading)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final m = _models[i];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: _buildModelCard(
                        context: context,
                        model: m,
                        onTap: m.key == 'charging_time'
                            ? () => _navigateToChargingPredictor(context)
                            : null,
                      ).animate().fadeIn(delay: Duration(milliseconds: i * 80), duration: 400.ms).slideY(begin: 0.1),
                    );
                  },
                  childCount: _models.length,
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildAiAssistantCard() {
    final loadedCount = _models.where((m) => m.isLoaded).length;
    final totalCount = _models.isEmpty ? '...' : '${_models.length}';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.psychology_rounded, color: AppColors.primary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TRỢ LÝ THÔNG MINH',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _loading ? 'Đang tải...' : '$loadedCount/${_models.length} mô hình đang hoạt động',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$totalCount MÔ HÌNH',
              style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.1);
  }

  Widget _buildModelCard({
    required BuildContext context,
    required _ModelInfo model,
    VoidCallback? onTap,
  }) {
    // Map icon name to Flutter icon
    IconData iconData;
    switch (model.icon) {
      case 'Timer': iconData = Icons.timer_rounded; break;
      case 'Navigation': iconData = Icons.navigation_rounded; break;
      case 'Cpu': iconData = Icons.memory_rounded; break;
      case 'BatteryCharging': iconData = Icons.battery_charging_full_rounded; break;
      default: iconData = Icons.psychology_rounded;
    }

    final Color badgeColor = model.isLoaded && model.isPredictable
        ? AppColors.success
        : model.activeVersion != null
        ? AppColors.warning
        : AppColors.textTertiary;

    final String badgeText = model.isLoaded && model.isPredictable
        ? 'ĐÃ LOAD'
        : model.activeVersion != null
        ? 'CHƯA LOAD'
        : 'CHƯA CÓ MODEL';

    // Format load time
    String? loadInfo;
    if (model.lastLoadAt != null) {
      try {
        final dt = DateTime.parse(model.lastLoadAt!).toLocal();
        loadInfo = 'Load: ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')} ${dt.day}/${dt.month}/${dt.year}';
      } catch (_) {
        loadInfo = 'Load: ${model.lastLoadAt}';
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: model.isLoaded ? AppColors.primary.withAlpha(51) : AppColors.glassBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: model.isLoaded ? AppColors.primaryContainer : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(iconData, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.label,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        model.shortName.toUpperCase(),
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (model.activeVersion != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      model.activeVersion!,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: badgeColor.withAlpha(26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),

            // Load info row
            if (loadInfo != null || model.featureCount != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (loadInfo != null) ...[
                    Icon(Icons.bolt, color: AppColors.textTertiary, size: 14),
                    const SizedBox(width: 4),
                    Text(loadInfo, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ],
                  if (model.featureCount != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.settings_input_component, color: AppColors.textTertiary, size: 14),
                    const SizedBox(width: 4),
                    Text('Features: ${model.featureCount}', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ],
                  const Spacer(),
                  if (onTap != null)
                    Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 20),
                ],
              ),
            ],

            // Error
            if (model.lastError != null && !model.isLoaded) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: AppColors.error, size: 13),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      model.lastError!,
                      style: TextStyle(color: AppColors.error, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Indicator trạng thái sync (không còn nút refresh manual).
  Widget _buildSyncIndicator() {
    final last = _lastFetchedAt;
    String label;
    if (_loading) {
      label = 'Đang đồng bộ...';
    } else if (last == null) {
      label = 'Chưa đồng bộ';
    } else {
      final h = last.hour.toString().padLeft(2, '0');
      final m = last.minute.toString().padLeft(2, '0');
      label = 'Cập nhật $h:$m';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_loading)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            )
          else
            Icon(
              Icons.cloud_done_rounded,
              color: AppColors.primary,
              size: 14,
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToChargingPredictor(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AiChargingPredictorScreen()),
    );
  }
}
