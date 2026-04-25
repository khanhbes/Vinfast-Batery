import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/sync_service.dart';
import '../../data/models/trip_prediction_model.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/services/trip_prediction_service.dart';

// =============================================================================
// Trip Planner Screen V4 — Modern Design
// Target Destination input, Recent Expeditions list
// =============================================================================

class TripPlannerScreen extends ConsumerStatefulWidget {
  final VehicleModel vehicle;

  const TripPlannerScreen({
    super.key,
    required this.vehicle,
  });

  @override
  ConsumerState<TripPlannerScreen> createState() => _TripPlannerScreenState();
}

class _TripPlannerScreenState extends ConsumerState<TripPlannerScreen> {
  final _fromController = TextEditingController(text: 'Current Location');
  final _toController = TextEditingController();
  final _distanceController = TextEditingController();
  final _riderWeightController = TextEditingController(text: '70');

  String _selectedWeather = 'sunny';
  double _temperature = 25.0;
  bool _isPredicting = false;
  TripPredictionModel? _prediction;
  List<TripPredictionModel> _recentPredictions = [];

  final List<Map<String, dynamic>> _weatherOptions = [
    {'value': 'sunny', 'label': 'Nắng', 'icon': Icons.wb_sunny_outlined, 'color': Colors.orange},
    {'value': 'cloudy', 'label': 'Mây', 'icon': Icons.wb_cloudy_outlined, 'color': Colors.grey},
    {'value': 'rain', 'label': 'Mưa', 'icon': Icons.water_drop_outlined, 'color': Colors.blue},
  ];

  @override
  void initState() {
    super.initState();
    _loadRecentPredictions();
  }

  Future<void> _loadRecentPredictions() async {
    final predictions = await TripPredictionService.getPredictionHistory(
      vehicleId: widget.vehicle.vehicleId,
      limit: 5,
    );
    setState(() => _recentPredictions = predictions);
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _distanceController.dispose();
    _riderWeightController.dispose();
    super.dispose();
  }

  Future<void> _predictTrip() async {
    if (_toController.text.isEmpty || _distanceController.text.isEmpty) {
      _showError('Please enter destination and distance');
      return;
    }

    setState(() => _isPredicting = true);

    try {
      final prediction = await TripPredictionService.predictTrip(
        vehicleId: widget.vehicle.vehicleId,
        from: _fromController.text,
        to: _toController.text,
        distance: double.parse(_distanceController.text),
        vehicle: widget.vehicle,
        weather: _weatherValueToDouble(_selectedWeather),
        temperature: _temperature,
        riderWeight: double.tryParse(_riderWeightController.text) ?? 70,
      );

      // Sync to web
      await SyncService().syncTripPredictionToWeb(prediction.id);

      setState(() {
        _prediction = prediction;
        _isPredicting = false;
      });

      _showPredictionResult(prediction);
    } catch (e) {
      setState(() => _isPredicting = false);
      _showError('Prediction failed: $e');
    }
  }

  double _weatherValueToDouble(String weather) {
    switch (weather) {
      case 'rain': return 0.0;
      case 'cloudy': return 0.5;
      case 'sunny': return 1.0;
      default: return 0.5;
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showPredictionResult(TripPredictionModel prediction) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _PredictionResultSheet(prediction: prediction),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // App Bar
            SliverToBoxAdapter(
              child: _buildAppBar(),
            ),

            // Title Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trip Planner',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'AI-powered range prediction',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1),
            ),

            // Trip Form Card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildTripFormCard(),
              ),
            ),

            // Predict Button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: _AnimatedPredictButton(
                  isLoading: _isPredicting,
                  onTap: _predictTrip,
                ),
              ),
            ),

            // Recent Predictions Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'RECENT EXPEDITIONS',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                    if (_recentPredictions.isNotEmpty)
                      GestureDetector(
                        onTap: _loadRecentPredictions,
                        child: Text(
                          'Refresh',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ).animate().fadeIn(delay: 200.ms),
            ),

            // Recent Predictions List
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: _recentPredictions.isEmpty
                ? SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No recent trips',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final prediction = _recentPredictions[index];
                        return _buildPredictionCard(prediction, index);
                      },
                      childCount: _recentPredictions.length,
                    ),
                  ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          _AnimatedBackButton(onTap: () => Navigator.pop(context)),
          const SizedBox(width: 12),
          const Text(
            'Trip Planner',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          _AnimatedIconButton(
            icon: Icons.more_vert,
            onTap: () {
              // Show options menu
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTripFormCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // From field
          _buildInputField(
            label: 'FROM',
            icon: Icons.my_location_outlined,
            controller: _fromController,
            hint: 'Current Location',
          ),
          const SizedBox(height: 16),
          
          // To field
          _buildInputField(
            label: 'TO',
            icon: Icons.location_on_outlined,
            controller: _toController,
            hint: 'Destination',
          ),
          const SizedBox(height: 16),
          
          // Distance field
          _buildInputField(
            label: 'DISTANCE (KM)',
            icon: Icons.straighten_outlined,
            controller: _distanceController,
            hint: 'Enter distance',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 20),
          
          // Weather selection
          Text(
            'WEATHER CONDITIONS',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: _weatherOptions.map((weather) {
              final isSelected = _selectedWeather == weather['value'];
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedWeather = weather['value'] as String),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? (weather['color'] as Color).withOpacity(0.2) : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? weather['color'] as Color : AppColors.glassBorder,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          weather['icon'] as IconData,
                          color: isSelected ? weather['color'] as Color : AppColors.textSecondary,
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          weather['label'] as String,
                          style: TextStyle(
                            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          
          // Temperature slider
          Row(
            children: [
              Icon(Icons.thermostat_outlined, color: AppColors.textSecondary, size: 18),
              const SizedBox(width: 8),
              Text(
                'Temperature: ${_temperature.toInt()}°C',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              Expanded(
                child: Slider(
                  value: _temperature,
                  min: 0,
                  max: 45,
                  activeColor: AppColors.primary,
                  inactiveColor: AppColors.surfaceVariant,
                  onChanged: (value) => setState(() => _temperature = value),
                ),
              ),
            ],
          ),
          
          // Rider weight
          _buildInputField(
            label: 'RIDER WEIGHT (KG)',
            icon: Icons.person_outline,
            controller: _riderWeightController,
            hint: '70',
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildInputField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPredictionCard(TripPredictionModel prediction, int index) {
    final batteryUsed = prediction.startBattery - prediction.endBattery;
    
    return GestureDetector(
      onTap: () => _showPredictionResult(prediction),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
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
                color: prediction.isSafe ? AppColors.success.withOpacity(0.15) : AppColors.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                prediction.isSafe ? Icons.check_circle_outlined : Icons.warning_outlined,
                color: prediction.isSafe ? AppColors.success : AppColors.warning,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${prediction.from} → ${prediction.to}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${prediction.distance.toStringAsFixed(1)} km • ${prediction.duration} mins',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${batteryUsed.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  prediction.endBattery.toStringAsFixed(0) + '% left',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: (300 + index * 100).ms).slideX(begin: 0.1);
  }
}

// =============================================================================
// Animated Widgets
// =============================================================================

class _AnimatedBackButton extends StatefulWidget {
  final VoidCallback onTap;

  const _AnimatedBackButton({required this.onTap});

  @override
  State<_AnimatedBackButton> createState() => _AnimatedBackButtonState();
}

class _AnimatedBackButtonState extends State<_AnimatedBackButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _AnimatedIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _AnimatedIconButton({required this.icon, required this.onTap});

  @override
  State<_AnimatedIconButton> createState() => _AnimatedIconButtonState();
}

class _AnimatedIconButtonState extends State<_AnimatedIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Icon(widget.icon, color: AppColors.textPrimary, size: 20),
        ),
      ),
    );
  }
}

class _AnimatedPredictButton extends StatefulWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _AnimatedPredictButton({required this.isLoading, required this.onTap});

  @override
  State<_AnimatedPredictButton> createState() => _AnimatedPredictButtonState();
}

class _AnimatedPredictButtonState extends State<_AnimatedPredictButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.isLoading ? null : (_) => _controller.forward(),
      onTapUp: widget.isLoading ? null : (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: widget.isLoading ? null : () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: widget.isLoading ? 1.0 : _scaleAnimation.value,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.isLoading) ...[
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ] else ...[
                    const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    widget.isLoading ? 'AI Predicting...' : 'AI Predict Trip',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).animate().fadeIn(delay: 300.ms).scale(begin: const Offset(0.9, 0.9));
  }
}

class _PredictionResultSheet extends StatelessWidget {
  final TripPredictionModel prediction;

  const _PredictionResultSheet({required this.prediction});

  @override
  Widget build(BuildContext context) {
    final batteryUsed = prediction.startBattery - prediction.endBattery;
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textTertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: prediction.isSafe ? AppColors.success.withOpacity(0.15) : AppColors.error.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  prediction.isSafe ? Icons.check_circle_outlined : Icons.warning_outlined,
                  color: prediction.isSafe ? AppColors.success : AppColors.error,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prediction.isSafe ? 'Trip is Safe' : 'Caution Required',
                      style: TextStyle(
                        color: prediction.isSafe ? AppColors.success : AppColors.error,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'AI Confidence: ${(prediction.confidence * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildResultRow('From', prediction.from, Icons.location_on_outlined),
          _buildResultRow('To', prediction.to, Icons.flag_outlined),
          _buildResultRow('Distance', '${prediction.distance.toStringAsFixed(1)} km', Icons.straighten_outlined),
          _buildResultRow('Duration', '${prediction.duration} mins', Icons.schedule_outlined),
          _buildResultRow('Battery Start', '${prediction.startBattery.toStringAsFixed(0)}%', Icons.battery_full_outlined),
          _buildResultRow('Battery End', '${prediction.endBattery.toStringAsFixed(1)}%', Icons.battery_alert_outlined),
          _buildResultRow('Consumption', '${batteryUsed.toStringAsFixed(1)}%', Icons.bolt_outlined),
          const SizedBox(height: 24),
          _AnimatedButton(
            label: 'Close',
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildResultRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 18),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _AnimatedButton({required this.label, required this.onTap});

  @override
  State<_AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<_AnimatedButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
