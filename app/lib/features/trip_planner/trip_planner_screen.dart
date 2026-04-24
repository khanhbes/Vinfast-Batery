import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/trip_prediction_model.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/services/trip_prediction_service.dart';

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
  final _formKey = GlobalKey<FormState>();
  final _destinationController = TextEditingController();
  final _distanceController = TextEditingController();
  final _weightController = TextEditingController(text: '70');
  final _tempController = TextEditingController(text: '25');
  
  String _selectedWeather = 'sunny';
  bool _isLoading = false;
  TripPredictionModel? _prediction;
  String? _error;

  final List<Map<String, dynamic>> _weatherOptions = [
    {'value': 'sunny', 'label': 'Nắng', 'icon': '☀️'},
    {'value': 'cloudy', 'label': 'Nhiều mây', 'icon': '☁️'},
    {'value': 'rain', 'label': 'Mưa', 'icon': '🌧️'},
  ];

  @override
  void dispose() {
    _destinationController.dispose();
    _distanceController.dispose();
    _weightController.dispose();
    _tempController.dispose();
    super.dispose();
  }

  Future<void> _predictTrip() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _prediction = null;
    });

    try {
      final prediction = await TripPredictionService.predictTrip(
        vehicleId: widget.vehicle.vehicleId,
        from: 'Vị trí hiện tại',
        to: _destinationController.text,
        distance: double.parse(_distanceController.text),
        vehicle: widget.vehicle,
        weather: _selectedWeather == 'sunny' ? 1.0 : 
                _selectedWeather == 'cloudy' ? 0.5 : 0.1,
        temperature: double.parse(_tempController.text),
        riderWeight: double.parse(_weightController.text),
      );

      setState(() {
        _prediction = prediction;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lên kế hoạch chuyến đi'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Vehicle Info Card
              _buildVehicleInfoCard(),
              const SizedBox(height: 24),
              
              // Trip Planning Form
              _buildTripForm(),
              const SizedBox(height: 24),
              
              // Error Message
              if (_error != null) ...[
                Card(
                  color: Colors.red[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
                        IconButton(onPressed: _predictTrip, icon: const Icon(Icons.refresh)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Loading Indicator
              if (_isLoading) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 16),
              ],
              
              // Prediction Result
              if (_prediction != null) ...[
                _buildPredictionResult(),
                const SizedBox(height: 24),
              ],
              
              // Predict Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _predictTrip,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('Đang dự đoán...'),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.route),
                            SizedBox(width: 8),
                            Text('Dự đoán chuyến đi'),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVehicleInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.electric_car,
                  color: Colors.blue,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Thông tin xe',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Pin hiện tại:'),
                Text(
                  '${widget.vehicle.currentBattery}%',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Sức khỏe pin:'),
                Text(
                  '${widget.vehicle.stateOfHealth.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: widget.vehicle.stateOfHealth >= 80 
                        ? Colors.green 
                        : widget.vehicle.stateOfHealth >= 60 
                            ? Colors.orange 
                            : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tầm hoạt động:'),
                Text(
                  '${(widget.vehicle.currentBattery * widget.vehicle.defaultEfficiency).toStringAsFixed(1)} km',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.map,
                  color: Colors.blue,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Thông tin chuyến đi',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Destination
            TextFormField(
              controller: _destinationController,
              decoration: const InputDecoration(
                labelText: 'Điểm đến',
                hintText: 'Nhập điểm đến của bạn',
                prefixIcon: Icon(Icons.location_on),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Vui lòng nhập điểm đến';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Distance
            TextFormField(
              controller: _distanceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quãng đường (km)',
                hintText: 'Nhập quãng đường',
                prefixIcon: Icon(Icons.straighten),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Vui lòng nhập quãng đường';
                }
                if (double.tryParse(value) == null || double.parse(value) <= 0) {
                  return 'Quãng đường phải lớn hơn 0';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Weather Selection
            Text(
              'Thời tiết',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: _weatherOptions.map((weather) {
                final isSelected = _selectedWeather == weather['value'];
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedWeather = weather['value'] as String;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue : Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? Colors.blue : Colors.grey[300]!,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            weather['icon'] as String,
                            style: const TextStyle(fontSize: 24),
                          ),
                          Text(
                            weather['label'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? Colors.white : Colors.black,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
            
            // Advanced Settings
            ExpansionTile(
              title: const Text('Cài đặt nâng cao'),
              children: [
                TextFormField(
                  controller: _weightController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cân nặng người lái (kg)',
                    hintText: 'Nhập cân nặng',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Vui lòng nhập cân nặng';
                    }
                    if (double.tryParse(value) == null || double.parse(value) <= 0) {
                      return 'Cân nặng phải lớn hơn 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _tempController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Nhiệt độ (°C)',
                    hintText: 'Nhập nhiệt độ',
                    prefixIcon: Icon(Icons.thermostat),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Vui lòng nhập nhiệt độ';
                    }
                    if (double.tryParse(value) == null) {
                      return 'Nhiệt độ không hợp lệ';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPredictionResult() {
    return Card(
      color: _prediction!.isSafe ? Colors.green[50] : Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _prediction!.isSafe ? Icons.check_circle : Icons.warning,
                  color: _prediction!.isSafe ? Colors.green : Colors.red,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Kết quả dự đoán',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _prediction!.isSafe ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Consumption
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tiêu hao pin dự kiến',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${_prediction!.consumption.toStringAsFixed(1)}%',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Còn ${_prediction!.endBattery.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 14,
                          color: _prediction!.isSafe ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Trip Details
            _buildDetailRow('Thời gian dự kiến', '${_prediction!.duration} phút'),
            _buildDetailRow('Tốc độ trung bình', '${(_prediction!.distance / _prediction!.duration * 60).toStringAsFixed(1)} km/h'),
            _buildDetailRow('Độ tin cậy', '${(_prediction!.confidence * 100).toStringAsFixed(0)}%'),
            
            if (_prediction!.reasoningText != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phân tích AI',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.blue[600],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _prediction!.reasoningText!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _prediction!.isSafe ? () {
                      // TODO: Start trip navigation
                    } : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _prediction!.isSafe ? Colors.blue : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Bắt đầu chuyến đi'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _prediction = null;
                      });
                    },
                    child: const Text('Dự đoán lại'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
