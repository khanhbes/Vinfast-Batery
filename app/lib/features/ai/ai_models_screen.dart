import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
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

class _AiModelsScreenState extends ConsumerState<AiModelsScreen> {
  List<_ModelInfo> _models = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchModels();
  }

  Future<void> _fetchModels() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().getUserAiModels();
      if (res['success'] != true) throw Exception(res['error'] ?? 'Unknown error');

      final typesList = (res['data']?['types'] as List?) ?? [];

      final results = typesList.map((t) {
        final st = t['runtimeStatus'] as String? ?? 'not_loaded';
        return _ModelInfo(
          key: t['key'] as String? ?? '',
          label: t['label'] as String? ?? '',
          shortName: t['shortName'] as String? ?? '',
          phase: t['phase'] as String? ?? '',
          registryStatus: t['status'] as String? ?? 'planned',
          isLoaded: st == 'loaded',
          isPredictable: st == 'loaded',
          activeVersion: t['activeVersion'] as String?,
          lastLoadAt: t['lastLoadAt'] as String?,
          lastError: t['error'] as String?,
          icon: t['icon'] as String? ?? 'BrainCircuit',
          description: t['description'] as String? ?? '',
          runMode: t['runMode'] as String? ?? 'none',
          mobileCompatible: t['mobileCompatible'] == true,
          downloadUrl: t['downloadUrl'] as String?,
        );
      }).toList();

      setState(() { _models = results; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildFixedHeader(context)),

            // Title
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
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
                    // Refresh button
                    GestureDetector(
                      onTap: _loading ? null : _fetchModels,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _loading
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              )
                            : Icon(Icons.refresh_rounded, color: AppColors.primary, size: 18),
                      ),
                    ),
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

  Widget _buildFixedHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: AppColors.textPrimary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'VinFast Battery',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.notifications_outlined,
                  color: AppColors.textPrimary,
                  size: 20,
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.vinfastRed,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
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

  void _navigateToChargingPredictor(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AiChargingPredictorScreen()),
    );
  }
}
