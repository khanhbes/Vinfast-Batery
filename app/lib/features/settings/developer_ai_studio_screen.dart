import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/theme/app_ui_colors.dart';
import '../../core/theme/cockpit_design_system.dart';
import '../../core/widgets/responsive_card_grid.dart';
import '../../core/widgets/settings_reveal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/widgets/app_popup.dart';
import '../../data/services/server_smart_charger_service.dart';

class DeveloperAiStudioScreen extends StatefulWidget {
  const DeveloperAiStudioScreen({super.key, this.service});

  final ServerSmartChargerService? service;

  @override
  State<DeveloperAiStudioScreen> createState() =>
      _DeveloperAiStudioScreenState();
}

class _DeveloperAiStudioScreenState extends State<DeveloperAiStudioScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  AppUiColors get _ui => AppUiColors.of(context);
  late final _service = widget.service ?? ServerSmartChargerService();

  bool _loading = true;
  String? _errorMessage;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _records = [];

  // Server health state
  bool _isServerOnline = false;
  int? _serverLatencyMs;

  // Fine-tune hyperparameters
  double _learningRate = 0.08;
  int _nEstimators = 120;
  int _maxDepth = 3;
  double _testSplit = 0.20;
  bool _tuning = false;
  Map<String, dynamic>? _lastTuningResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDataset();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkServerHealth() async {
    try {
      final res = await _service.pingServer();
      if (!mounted) return;
      setState(() {
        _isServerOnline = res['online'] == true;
        _serverLatencyMs = res['latencyMs'] as int?;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isServerOnline = false;
        _serverLatencyMs = null;
      });
    }
  }

  Map<String, dynamic> _computeStats(List<Map<String, dynamic>> records) {
    final total = records.length;
    final confirmed = records
        .where((r) => r['is_user_confirmed'] == true)
        .length;
    final excluded = records
        .where((r) => r['training_excluded'] == true)
        .length;
    final eligible = records
        .where(
          (r) =>
              r['training_eligible'] != false && r['training_excluded'] != true,
        )
        .length;
    return {
      'totalRecords': total,
      'confirmedRecords': confirmed,
      'eligibleRecords': eligible,
      'excludedRecords': excluded,
      'eligiblePct': total > 0 ? ((eligible / total) * 100).round() : 0,
    };
  }

  Future<void> _loadDataset() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    await _checkServerHealth();

    // 1. Thử tải dữ liệu thời gian thực từ máy chủ
    try {
      final res = await _service.getAiDataset();
      final recordsRaw = res['records'];
      final statsRaw = res['stats'];
      if (recordsRaw is List) {
        final records = recordsRaw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final stats = (statsRaw is Map)
            ? Map<String, dynamic>.from(statsRaw)
            : _computeStats(records);
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'cached_ai_dataset_records',
            jsonEncode(records),
          );
        } catch (_) {}

        if (!mounted) return;
        setState(() {
          _records = records;
          _stats = stats;
          _loading = false;
          _isServerOnline = true;
        });
        return;
      }
    } catch (_) {}

    // 2. Nếu máy chủ chưa phản hồi, tải bộ đệm cục bộ hoặc 6 mẫu seed chuẩn
    List<Map<String, dynamic>> fallbackRecords = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('cached_ai_dataset_records');
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final decoded = jsonDecode(cachedJson);
        if (decoded is List && decoded.isNotEmpty) {
          fallbackRecords = decoded
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _records = fallbackRecords;
      _stats = _computeStats(fallbackRecords);
      _loading = false;
      _isServerOnline = false;
      _errorMessage =
          'Máy chủ ngoại tuyến (${AppConstants.apiBaseUrl}). Đang dùng bộ đệm dữ liệu cục bộ.';
    });
  }

  Future<void> _editRecord(Map<String, dynamic> record) async {
    if (!_isServerOnline) {
      AppPopup.showWarning(
        'Đang xem bộ đệm. Cần kết nối máy chủ để sửa dữ liệu.',
      );
      return;
    }
    final sessionId = record['session_id']?.toString() ?? '';
    final startSocCtl = TextEditingController(
      text: '${record['start_soc'] ?? 20}',
    );
    final actualEndSocCtl = TextEditingController(
      text: '${record['actual_end_soc'] ?? 100}',
    );
    final durationMinCtl = TextEditingController(
      text: '${((record['duration_seconds'] as num? ?? 3600) / 60).round()}',
    );
    final energyWhCtl = TextEditingController(
      text: '${record['energy_wh'] ?? 2500}',
    );
    final tempCtl = TextEditingController(
      text: '${record['ambient_temp_c'] ?? 30}',
    );
    final noteCtl = TextEditingController(
      text: '${record['developer_note'] ?? ''}',
    );
    bool excluded = record['training_excluded'] == true;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _ui.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _ui.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.edit_note_rounded, color: _ui.primary),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Chỉnh sửa mẫu: $sessionId',
                        style: TextStyle(
                          color: _ui.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  'Thay đổi sẽ được tự động lưu trực tiếp vào file charging_time_dataset.json',
                  style: TextStyle(color: _ui.muted, fontSize: 12),
                ),
                SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _inputField(
                        label: 'SOC đầu (%)',
                        controller: startSocCtl,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _inputField(
                        label: 'SOC cuối thực tế (%)',
                        controller: actualEndSocCtl,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _inputField(
                        label: 'Thời gian sạc (phút)',
                        controller: durationMinCtl,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _inputField(
                        label: 'Nhiệt độ (°C)',
                        controller: tempCtl,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14),
                _inputField(
                  label: 'Năng lượng nạp (Wh)',
                  controller: energyWhCtl,
                  keyboardType: TextInputType.number,
                ),
                SizedBox(height: 14),
                _inputField(
                  label: 'Ghi chú Developer',
                  controller: noteCtl,
                  keyboardType: TextInputType.text,
                ),
                SizedBox(height: 14),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _ui.elevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _ui.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Loại trừ khỏi Train',
                              style: TextStyle(
                                color: _ui.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Bỏ qua mẫu này khi chạy fine-tune',
                              style: TextStyle(color: _ui.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: excluded,
                        activeThumbColor: _ui.warning,
                        activeTrackColor: _ui.warningSurface,
                        inactiveTrackColor: _ui.elevated,
                        onChanged: (val) => setSheetState(() => excluded = val),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _ui.primary,
                      foregroundColor: _ui.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      'Lưu vào File Dataset',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved == true && mounted) {
      final start = double.tryParse(startSocCtl.text.trim()) ?? 20.0;
      final end = double.tryParse(actualEndSocCtl.text.trim()) ?? 100.0;
      final durMin = double.tryParse(durationMinCtl.text.trim()) ?? 60.0;
      final energy = double.tryParse(energyWhCtl.text.trim()) ?? 2500.0;
      final temp = double.tryParse(tempCtl.text.trim()) ?? 30.0;

      final updates = {
        'start_soc': start,
        'actual_end_soc': end,
        'duration_seconds': durMin * 60.0,
        'energy_wh': energy,
        'ambient_temp_c': temp,
        'training_excluded': excluded,
        'developer_note': noteCtl.text.trim(),
      };

      try {
        await _service.updateAiDatasetRecord(sessionId, updates);
        if (!mounted) return;
        await _loadDataset();
        AppPopup.showSuccess('Máy chủ đã ghi nhận cập nhật dataset.');
      } catch (_) {
        AppPopup.showError(
          'Chưa lưu được thay đổi. Dữ liệu máy chủ chưa được cập nhật; hãy thử lại.',
        );
      }
    }
  }

  Future<void> _addTestSample() async {
    if (!_isServerOnline) {
      AppPopup.showWarning('Cần kết nối máy chủ để thêm mẫu.');
      return;
    }
    final startCtl = TextEditingController(text: '20');
    final endCtl = TextEditingController(text: '95');
    final durCtl = TextEditingController(text: '160');
    final energyCtl = TextEditingController(text: '2400');
    final tempCtl = TextEditingController(text: '29');
    final noteCtl = TextEditingController(text: 'Mẫu kiểm thử thủ công');

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _ui.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Thêm mẫu sạc thử nghiệm',
          style: TextStyle(color: _ui.text, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _inputField(
                label: 'SOC đầu (%)',
                controller: startCtl,
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 10),
              _inputField(
                label: 'SOC cuối thực tế (%)',
                controller: endCtl,
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 10),
              _inputField(
                label: 'Thời gian (phút)',
                controller: durCtl,
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 10),
              _inputField(
                label: 'Năng lượng (Wh)',
                controller: energyCtl,
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 10),
              _inputField(
                label: 'Nhiệt độ (°C)',
                controller: tempCtl,
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 10),
              _inputField(
                label: 'Ghi chú',
                controller: noteCtl,
                keyboardType: TextInputType.text,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Hủy', style: TextStyle(color: _ui.muted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _ui.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Thêm mẫu',
              style: TextStyle(
                color: _ui.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (added == true && mounted) {
      final sampleId = 'sample-dev-${DateTime.now().microsecondsSinceEpoch}';
      final newRecord = {
        'session_id': sampleId,
        'vehicle_id': 'developer-test-only',
        'start_soc': double.tryParse(startCtl.text.trim()) ?? 20.0,
        'target_soc': 100.0,
        'actual_end_soc': double.tryParse(endCtl.text.trim()) ?? 95.0,
        'duration_seconds':
            (double.tryParse(durCtl.text.trim()) ?? 160.0) * 60.0,
        'energy_wh': double.tryParse(energyCtl.text.trim()) ?? 2400.0,
        'ambient_temp_c': double.tryParse(tempCtl.text.trim()) ?? 29.0,
        'is_user_confirmed': false,
        'training_eligible': false,
        'training_excluded': true,
        'developer_note': noteCtl.text.trim(),
        'confirmed_at': DateTime.now().toIso8601String(),
      };

      try {
        await _service.addAiDatasetRecord(newRecord);
        if (!mounted) return;
        await _loadDataset();
        AppPopup.showSuccess(
          'Máy chủ đã ghi nhận mẫu thử nghiệm (loại khỏi huấn luyện).',
        );
      } catch (_) {
        AppPopup.showError('Chưa thêm được mẫu trên máy chủ. Hãy thử lại.');
      }
    }
  }

  Future<void> _triggerFineTune() async {
    if (_tuning || !_isServerOnline) return;
    setState(() => _tuning = true);
    try {
      final res = await _service.triggerChargingTimeFineTune(
        learningRate: _learningRate,
        nEstimators: _nEstimators,
        maxDepth: _maxDepth,
        testSplit: _testSplit,
      );
      if (!mounted) return;
      if (res['success'] != true) {
        AppPopup.showError(
          'Fine-tune thất bại. Không có kết quả mới được ghi nhận.',
        );
        return;
      }
      final data = res['data'] is Map ? res['data'] as Map : res;
      setState(() => _lastTuningResult = Map<String, dynamic>.from(data));
      AppPopup.showSuccess('Máy chủ đã hoàn tất fine-tune.');
    } catch (_) {
      if (mounted) {
        AppPopup.showError('Không nhận được kết quả fine-tune từ máy chủ.');
      }
    } finally {
      if (mounted) setState(() => _tuning = false);
    }
  }

  Widget _inputField({
    required String label,
    required TextEditingController controller,
    required TextInputType keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _ui.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 5),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(
            color: _ui.text,
            fontSize: 14,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            filled: true,
            fillColor: _ui.elevated,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _ui.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _ui.primary),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ui.background,
      appBar: AppBar(
        toolbarHeight: 24 + MediaQuery.textScalerOf(context).scale(34),
        backgroundColor: _ui.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: _ui.text,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Developer AI Studio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _ui.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'Dữ liệu & huấn luyện model',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _ui.primary, fontSize: 12),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            height: 44,
            decoration: BoxDecoration(
              color: _ui.surface,
              borderRadius: BorderRadius.circular(CockpitRadius.medium),
              border: Border.all(color: _ui.border),
            ),
            child: TabBar(
              isScrollable: false,
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: CockpitColors.emerald.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(CockpitRadius.small),
                border: Border.all(
                  color: CockpitColors.emerald.withValues(alpha: 0.4),
                  width: 1.2,
                ),
              ),
              dividerColor: Colors.transparent,
              labelColor: CockpitColors.emeraldStrong,
              unselectedLabelColor: _ui.muted,
              labelStyle: CockpitTypography.label(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: CockpitTypography.label(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.dataset_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('Tập dữ liệu'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.model_training_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('Huấn luyện AI'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _ui.primary))
          : Column(
              children: [
                _buildServerStatusHeader(),
                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: _ui.warning.withValues(alpha: 0.15),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: _ui.warning,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: _ui.warning,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      SettingsReveal(child: _buildDatasetTab()),
                      SettingsReveal(child: _buildFineTuneTab()),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildServerStatusHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: _ui.elevated,
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isServerOnline ? _ui.primary : _ui.warning,
              boxShadow: [
                BoxShadow(
                  color: (_isServerOnline ? _ui.primary : _ui.warning)
                      .withValues(alpha: 0.6),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isServerOnline
                      ? 'MÁY CHỦ TRỰC TUYẾN (${_serverLatencyMs ?? 0}ms)'
                      : 'MÁY CHỦ NGOẠI TUYẾN (BỘ ĐỆM CỤC BỘ)',
                  style: TextStyle(
                    color: _isServerOnline ? _ui.primary : _ui.warning,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  AppConstants.apiBaseUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _ui.muted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 6),
          IconButton(
            onPressed: _loadDataset,
            icon: Icon(Icons.refresh_rounded, size: 18, color: _ui.muted),
            tooltip: 'Tải lại',
            constraints: BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
          SizedBox(width: 4),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _ui.elevated,
              foregroundColor: _ui.primary,
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _showServerConfigDialog,
            icon: Icon(Icons.tune_rounded, size: 13),
            label: Text(
              'Đổi IP',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showServerConfigDialog() async {
    final controller = TextEditingController(text: AppConstants.apiBaseUrl);
    String? pingResult;
    bool pinging = false;
    bool pingSuccess = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            backgroundColor: _ui.elevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: _ui.border),
            ),
            title: Row(
              children: [
                Icon(Icons.router_rounded, color: _ui.primary, size: 22),
                SizedBox(width: 10),
                Text(
                  'Cấu hình Server IP',
                  style: TextStyle(
                    color: _ui.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chọn preset hoặc nhập IP của laptop/server (cùng mạng WiFi hoặc Tailscale):',
                    style: TextStyle(color: _ui.muted, fontSize: 12),
                  ),
                  SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _presetChip(
                        'Tailscale Funnel',
                        'https://khanhbes.tailaafca5.ts.net',
                        controller,
                        setDlgState,
                      ),
                      _presetChip(
                        'WiFi LAN (5000)',
                        'http://192.168.1.15:5000',
                        controller,
                        setDlgState,
                      ),
                      _presetChip(
                        'Emulator (10.0.2.2)',
                        'http://10.0.2.2:5000',
                        controller,
                        setDlgState,
                      ),
                      _presetChip(
                        'Localhost (5000)',
                        'http://127.0.0.1:5000',
                        controller,
                        setDlgState,
                      ),
                    ],
                  ),
                  SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    style: TextStyle(
                      color: _ui.text,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      labelText: 'Server URL',
                      labelStyle: TextStyle(color: _ui.primary, fontSize: 12),
                      hintText: 'https://... hoặc http://...',
                      hintStyle: TextStyle(color: _ui.muted, fontSize: 12),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: _ui.background,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _ui.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _ui.primary),
                      ),
                    ),
                  ),
                  if (pingResult != null) ...[
                    SizedBox(height: 10),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: pingSuccess
                            ? _ui.primary.withValues(alpha: 0.15)
                            : _ui.danger.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: pingSuccess
                              ? _ui.primary.withValues(alpha: 0.4)
                              : _ui.danger.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            pingSuccess
                                ? Icons.check_circle_rounded
                                : Icons.error_outline_rounded,
                            size: 16,
                            color: pingSuccess ? _ui.primary : _ui.danger,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              pingResult!,
                              style: TextStyle(
                                color: pingSuccess ? _ui.primary : _ui.danger,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _ui.primary,
                        side: BorderSide(color: _ui.primary),
                      ),
                      onPressed: pinging
                          ? null
                          : () async {
                              setDlgState(() {
                                pinging = true;
                                pingResult = 'Đang kiểm tra kết nối...';
                              });
                              final res = await _service.pingServer(
                                customUrl: controller.text.trim(),
                              );
                              setDlgState(() {
                                pinging = false;
                                pingSuccess = res['online'] == true;
                                if (pingSuccess) {
                                  pingResult =
                                      'Kết nối tốt! Latency: ${res['latencyMs']}ms (HTTP ${res['status']})';
                                } else {
                                  pingResult =
                                      'Không phản hồi: ${res['error'] ?? 'Server offline'}';
                                }
                              });
                            },
                      icon: pinging
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _ui.primary,
                              ),
                            )
                          : Icon(Icons.network_check_rounded, size: 16),
                      label: Text('Kiểm tra kết nối (Ping /api/health)'),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Đóng', style: TextStyle(color: _ui.muted)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _ui.primary),
                onPressed: () async {
                  final newUrl = controller.text.trim();
                  AppConstants.setCustomApiBaseUrl(newUrl);
                  try {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('custom_api_base_url', newUrl);
                  } catch (_) {}
                  if (ctx.mounted) Navigator.pop(ctx);
                  AppPopup.showSuccess('Đã áp dụng Server: $newUrl');
                  _loadDataset();
                },
                child: Text(
                  'Lưu & Áp dụng',
                  style: TextStyle(
                    color: _ui.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _presetChip(
    String label,
    String url,
    TextEditingController ctl,
    void Function(void Function()) setDlgState,
  ) {
    final isSelected = ctl.text.trim() == url;
    return InkWell(
      onTap: () {
        setDlgState(() {
          ctl.text = url;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? _ui.primary.withValues(alpha: 0.2) : _ui.elevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? _ui.primary : _ui.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? _ui.primary : _ui.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // TAB 1: DATASET MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildDatasetTab() {
    final total = _stats['totalRecords'] ?? _records.length;
    final confirmed = _stats['confirmedRecords'] ?? 0;
    final eligible = _stats['eligibleRecords'] ?? 0;

    return RefreshIndicator(
      color: _ui.primary,
      backgroundColor: _ui.surface,
      onRefresh: _loadDataset,
      child: ListView(
        key: PageStorageKey('studio-dataset'),
        padding: EdgeInsets.all(16),
        children: [
          // Stat cards
          ResponsiveCardGrid(
            maxColumns: 3,
            minCardWidth: 100,
            children: [
              _metricPill(
                'Tổng mẫu',
                '$total',
                Icons.storage_rounded,
                _ui.text,
              ),
              _metricPill(
                'Đã xác nhận',
                '$confirmed',
                Icons.verified_rounded,
                _ui.primary,
              ),
              _metricPill(
                'Đủ điều kiện',
                '$eligible',
                Icons.task_alt_rounded,
                _ui.primary,
              ),
            ],
          ),
          SizedBox(height: 16),

          // Action bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Danh sách mẫu trong file',
                  style: TextStyle(
                    color: _ui.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Thêm mẫu thử nghiệm',
                    icon: Icon(
                      Icons.add_circle_outline_rounded,
                      color: _ui.primary,
                    ),
                    onPressed: _addTestSample,
                  ),
                  IconButton(
                    tooltip: 'Làm mới',
                    icon: Icon(Icons.refresh_rounded, color: _ui.muted),
                    onPressed: _loadDataset,
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 8),

          if (_records.isEmpty)
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _ui.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _ui.border),
              ),
              child: Center(
                child: Text(
                  'Chưa có mẫu nào trong file dataset.',
                  style: TextStyle(color: _ui.muted),
                ),
              ),
            )
          else
            ..._records.map(_buildRecordCard),
        ],
      ),
    );
  }

  Widget _metricPill(String title, String val, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: _ui.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _ui.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: _ui.muted, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            val,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> record) {
    final sessionId = record['session_id']?.toString() ?? '';
    final vehicleId = record['vehicle_id']?.toString() ?? 'VF_FELIZ_2025';
    final startSoc = (record['start_soc'] as num? ?? 0).toDouble();
    final endSoc = (record['actual_end_soc'] as num? ?? 100).toDouble();
    final delta = (record['delta_soc'] as num? ?? (endSoc - startSoc))
        .toDouble();
    final durationSeconds = (record['duration_seconds'] as num? ?? 0)
        .toDouble();
    final durationMin = (durationSeconds / 60).round();
    final energyWh = (record['energy_wh'] as num? ?? 0).toDouble();
    final temp = (record['ambient_temp_c'] as num? ?? 30).toDouble();
    final confirmed = record['is_user_confirmed'] == true;
    final excluded = record['training_excluded'] == true;
    final note = record['developer_note']?.toString() ?? '';

    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _ui.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: excluded
              ? _ui.warning.withValues(alpha: 0.4)
              : confirmed
              ? _ui.primary.withValues(alpha: 0.3)
              : _ui.border,
        ),
      ),
      child: InkWell(
        onTap: () => _editRecord(record),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _ui.elevated,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _ui.border),
                  ),
                  child: Text(
                    vehicleId,
                    style: TextStyle(
                      color: _ui.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  sessionId,
                  style: TextStyle(
                    color: _ui.muted,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (confirmed)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _ui.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Thực tế',
                      style: TextStyle(
                        color: _ui.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (excluded)
                  Container(
                    margin: EdgeInsets.only(left: 4),
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _ui.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Loại trừ',
                      style: TextStyle(
                        color: _ui.warning,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                SizedBox(width: 6),
                Icon(Icons.edit_rounded, size: 16, color: _ui.muted),
              ],
            ),
            SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  '${startSoc.toStringAsFixed(0)}% ➔ ${endSoc.toStringAsFixed(0)}% (+${delta.toStringAsFixed(0)}%)',
                  style: TextStyle(
                    color: _ui.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  '$durationMin phút',
                  style: TextStyle(
                    color: _ui.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  'Nạp: ${energyWh.toStringAsFixed(0)} Wh · Nhiệt độ: ${temp.toStringAsFixed(1)}°C',
                  style: TextStyle(color: _ui.muted, fontSize: 11),
                ),
                Text(
                  'Nhấn để sửa ➜',
                  style: TextStyle(
                    color: _ui.primary.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            if (note.isNotEmpty) ...[
              SizedBox(height: 6),
              Text(
                '📝 $note',
                style: TextStyle(
                  color: _ui.muted,
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // TAB 2: DEEP FINE-TUNE STUDIO
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildFineTuneTab() {
    return ListView(
      key: PageStorageKey('studio-training'),
      padding: EdgeInsets.all(16),
      children: [
        // Smart Charger Telemetry & Hardware Connection Diagnostic
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _ui.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _ui.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.ev_station_rounded,
                        color: _ui.primary,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Kết nối máy chủ AI',
                          style: TextStyle(
                            color: _ui.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _isServerOnline
                          ? _ui.primary.withValues(alpha: 0.15)
                          : _ui.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _isServerOnline ? _ui.primary : _ui.warning,
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      _isServerOnline ? 'CONNECTED' : 'STANDBY / OFFLINE',
                      style: TextStyle(
                        color: _isServerOnline ? _ui.primary : _ui.warning,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _miniMetric(
                      'Cổng kết nối Sạc',
                      'Chưa xác minh Shelly',
                      Icons.power_rounded,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: _miniMetric(
                      'Công suất nạp',
                      'Chưa có số đo',
                      Icons.bolt_rounded,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ui.primary,
                    side: BorderSide(color: _ui.border),
                  ),
                  onPressed: () async {
                    AppPopup.showSuccess('Đang kiểm tra máy chủ...');
                    final res = await _service.pingServer();
                    if (res['online'] == true) {
                      AppPopup.showSuccess(
                        'Máy chủ phản hồi (${res['latencyMs']}ms). Chưa xác minh kết nối Shelly.',
                      );
                    } else {
                      AppPopup.showWarning(
                        'Không thấy phản hồi từ cổng sạc. Vui lòng kiểm tra server.',
                      );
                    }
                  },
                  icon: Icon(Icons.refresh_rounded, size: 16),
                  label: Text('Kiểm tra máy chủ', textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),

        // Architecture card
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _ui.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _ui.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.hub_rounded, color: _ui.primary, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Feature Matrix Architecture',
                      style: TextStyle(
                        color: _ui.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Text(
                'Vector đặc trưng đầu vào X (6 features):',
                style: TextStyle(color: _ui.muted, fontSize: 12),
              ),
              SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _ui.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _ui.border),
                ),
                child: Text(
                  '[start_soc, end_soc, delta_soc, ambient_temp_c, avg_charge_rate, temp_deviation]\n'
                  '➔ Ground Truth Y: [duration_seconds]',
                  style: TextStyle(
                    color: _ui.primary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),

        // Hyperparameters Card
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _ui.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _ui.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tune_rounded, color: _ui.primary, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cấu hình Siêu Tham Số (Hyperparameters)',
                      style: TextStyle(
                        color: _ui.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14),

              // Learning rate slider
              _sliderRow(
                label: 'Learning Rate (Tốc độ học)',
                valueStr: _learningRate.toStringAsFixed(2),
                min: 0.01,
                max: 0.20,
                divisions: 19,
                current: _learningRate,
                onChanged: (v) => setState(() => _learningRate = v),
              ),
              Divider(color: _ui.border, height: 20),

              // N Estimators
              _sliderRow(
                label: 'N Estimators (Số cây Boosting)',
                valueStr: '$_nEstimators cây',
                min: 30,
                max: 300,
                divisions: 27,
                current: _nEstimators.toDouble(),
                onChanged: (v) => setState(() => _nEstimators = v.round()),
              ),
              Divider(color: _ui.border, height: 20),

              // Max depth
              _sliderRow(
                label: 'Max Depth (Độ sâu tối đa)',
                valueStr: '$_maxDepth tầng',
                min: 2,
                max: 6,
                divisions: 4,
                current: _maxDepth.toDouble(),
                onChanged: (v) => setState(() => _maxDepth = v.round()),
              ),
              Divider(color: _ui.border, height: 20),

              // Test Split
              _sliderRow(
                label: 'Tỉ lệ Test Split',
                valueStr: '${(_testSplit * 100).round()}%',
                min: 0.10,
                max: 0.30,
                divisions: 4,
                current: _testSplit,
                onChanged: (v) => setState(() => _testSplit = v),
              ),
            ],
          ),
        ),
        SizedBox(height: 20),

        // Run button
        ConstrainedBox(
          constraints: BoxConstraints(minWidth: double.infinity, minHeight: 52),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _ui.primary,
              foregroundColor: _ui.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 4,
            ),
            onPressed: _tuning || !_isServerOnline ? null : _triggerFineTune,
            icon: _tuning
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _ui.onPrimary,
                    ),
                  )
                : Icon(Icons.flash_on_rounded, size: 22),
            label: Text(
              _tuning
                  ? 'Đang Fine-tune Model...'
                  : '⚡ Kích Hoạt Fine-Tune Ngay',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ),
        ),
        SizedBox(height: 20),

        // Evaluation card
        if (_lastTuningResult != null) _buildEvaluationCard(_lastTuningResult!),
      ],
    );
  }

  Widget _sliderRow({
    required String label,
    required String valueStr,
    required double min,
    required double max,
    required int divisions,
    required double current,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(label, style: TextStyle(color: _ui.muted, fontSize: 13)),
            Text(
              valueStr,
              style: TextStyle(
                color: _ui.text,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: _ui.primary,
            inactiveTrackColor: _ui.border,
            thumbColor: _ui.text,
            overlayColor: _ui.primary.withValues(alpha: 0.2),
            trackHeight: 4,
          ),
          child: Slider(
            value: current,
            min: min,
            max: max,
            divisions: divisions,
            label: valueStr,
            onChanged: _tuning ? null : onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildEvaluationCard(Map<String, dynamic> result) {
    final metrics = (result['metrics'] is Map)
        ? Map<String, dynamic>.from(result['metrics'] as Map)
        : {};
    final version = result['version']?.toString() ?? 'charging_time_latest';
    final mape = (metrics['mape'] as num? ?? 0).toDouble();
    final maeSec = (metrics['maeSeconds'] as num? ?? 0).toDouble();
    final rmseSec = (metrics['rmseSeconds'] as num? ?? 0).toDouble();
    final r2 = (metrics['r2'] as num? ?? 0).toDouble();
    final accuracy = (metrics['accuracyPct'] as num? ?? (100.0 - mape))
        .toDouble();

    return Container(
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _ui.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _ui.primary.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Icon(Icons.check_circle_rounded, color: _ui.primary),
              Text(
                'Kết Quả Đánh Giá Fine-Tune',
                style: TextStyle(
                  color: _ui.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _ui.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Độ chính xác: ${accuracy.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: _ui.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            'Phiên bản model mới: $version',
            style: TextStyle(
              color: _ui.primary,
              fontSize: 12,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 14),
          ResponsiveCardGrid(
            maxColumns: 3,
            minCardWidth: 100,
            children: [
              _metricPill(
                'MAPE (%)',
                '${mape.toStringAsFixed(1)}%',
                Icons.percent_rounded,
                _ui.text,
              ),
              _metricPill(
                'MAE',
                '${(maeSec / 60).toStringAsFixed(1)}p',
                Icons.timer_outlined,
                _ui.primary,
              ),
              _metricPill(
                'R² Score',
                r2.toStringAsFixed(3),
                Icons.auto_graph_rounded,
                _ui.primary,
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            'RMSE: ${rmseSec.toStringAsFixed(1)}s (~${(rmseSec / 60).toStringAsFixed(1)} phút sai số bình phương). Kết quả đánh giá không đồng nghĩa model đã được triển khai.',
            style: TextStyle(color: _ui.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _miniMetric(String label, String value, IconData icon) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _ui.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _ui.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _ui.primary),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: _ui.muted, fontSize: 10)),
                Text(
                  value,
                  style: TextStyle(
                    color: _ui.text,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
