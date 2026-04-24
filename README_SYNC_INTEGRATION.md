# VinFast Battery - Đồng bộ dữ liệu App và Web Dashboard

## 📋 Tổng quan

Hướng dẫn này mô tả cách tích hợp và đồng bộ dữ liệu giữa ứng dụng Flutter (VinFast Battery App) và Web Dashboard, sử dụng API Server làm trung gian.

## 🏗️ Kiến trúc hệ thống

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Flutter App   │◄──►│  API Server     │◄──►│  Web Dashboard  │
│   (Mobile)      │    │  (Port 5000)    │    │  (Port 3003)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Local Data    │    │   Firebase      │    │   Firebase      │
│   (SQLite)      │    │   Firestore     │    │   Firestore     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🔧 Các thành phần đã phát triển

### 1. Models (Flutter App)
- **BatteryStateModel**: Trạng thái pin đồng bộ
- **TripPredictionModel**: Dự đoán chuyến đi AI
- **VehicleModel**: Thông tin xe (đã có)

### 2. Services (Flutter App)
- **BatteryStateService**: Quản lý trạng thái pin
- **TripPredictionService**: Dự đoán chuyến đi
- **FirebaseService**: Kết nối Firestore

### 3. API Endpoints (Server)
- **SOC AI**: `/api/soc/predict|status|history`
- **Trip Prediction**: `/api/trip/predict|history`
- **Web Sync**: `/api/web/sync/battery-state|trip-prediction`

### 4. Features (Flutter App)
- **TripPlannerScreen**: Lên kế hoạch chuyến đi
- **BatteryMonitorScreen**: Giám sát pin real-time

## 🚀 Triển khai

### Bước 1: Khởi động API Server
```bash
cd "c:\Users\khanh\OneDrive\Desktop\Vinfast Batery\web"
python server.py
```

### Bước 2: Khởi động Web Dashboard
```bash
cd "c:\Users\khanh\OneDrive\Desktop\Vinfast Batery\web\dashboard"
npm run dev
```

### Bước 3: Chạy Flutter App
```bash
cd "c:\Users\khanh\OneDrive\Desktop\Vinfast Batery\app"
flutter run
```

## 📊 Luồng dữ liệu

### 1. Battery State Sync
```
Flutter App → API Server → Firestore → Web Dashboard
```

**Flutter App gửi:**
- currentBattery, temperature, voltage, current
- odometer, timeOfDay, dayOfWeek, avgSpeed
- elevationGain, weatherCondition

**API Server xử lý:**
- Gọi SOC AI model (ev_soc_pipeline.pkl)
- Tính toán time series 24 giờ
- Lưu vào Firestore collection `battery_states`

**Web Dashboard nhận:**
- Real-time battery status
- SOC predictions với visualization
- Battery health monitoring

### 2. Trip Prediction Sync
```
Flutter App → API Server → Firestore → Web Dashboard
```

**Flutter App gửi:**
- from, to, distance, currentBattery
- temperature, riderWeight, weather

**API Server xử lý:**
- Tính toán tiêu hao pin với AI
- Xác định safety level
- Tạo reasoning text
- Lưu vào Firestore collection `trip_predictions`

**Web Dashboard nhận:**
- Trip planning interface
- Prediction history
- Consumption analytics

## 🔌 API Integration

### Flutter App Usage

```dart
// Battery State Service
final batteryState = await BatteryStateService.getCurrentBatteryState(vehicleId);
final socPrediction = await BatteryStateService.predictSOC(...);

// Trip Prediction Service
final tripPrediction = await TripPredictionService.predictTrip(
  vehicleId: vehicleId,
  from: 'Hanoi',
  to: 'Haiphong',
  distance: 120,
  vehicle: vehicle,
  weather: 1.0,
  temperature: 25.0,
  riderWeight: 70.0,
);

// Sync with Web Dashboard
await BatteryStateService.syncWithWebDashboard(vehicleId);
await TripPredictionService.syncWithWebDashboard(vehicleId);
```

### Web Dashboard Usage

```typescript
// Firebase Service
const predictions = await firebaseService.getSOCPredictions();
const batteryState = await firebaseService.getSOCModelStatus();

// API Calls
const response = await fetch('http://localhost:5000/api/soc/predict', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(inputData)
});
```

## 📱 Features Integration

### 1. Trip Planner (Flutter App)
- **Input**: Destination, distance, weather, rider weight
- **Output**: Consumption prediction, safety check, ETA
- **AI Integration**: Server-side calculation with fallback
- **Sync**: Auto-sync to web dashboard

### 2. Battery Monitor (Flutter App)
- **Real-time**: Current battery status, temperature, SoH
- **Historical**: 24-hour chart with trends
- **AI Prediction**: 24-hour SOC forecast
- **Health Monitoring**: Battery degradation tracking

### 3. Web Dashboard
- **Overview**: Real-time battery status across vehicles
- **AI Center**: SOC model status and predictions
- **Analytics**: Trip history and consumption patterns
- **Visualization**: Interactive charts and reports

## 🔧 Cấu hình

### Firebase Collections
```
battery_states/
├── {vehicleId}_{timestamp}
├── percentage, soh, estimatedRange, temp
├── timestamp, source

trip_predictions/
├── {predictionId}
├── vehicleId, from, to, distance
├── consumption, duration, isSafe
├── weather, temperature, riderWeight
├── reasoningText, confidence
├── timestamp, status
```

### API Configuration
```python
# Base URL
BASE_URL = "http://localhost:5000"

# Timeouts
TIMEOUT = 30 seconds

# Endpoints
SOC_PREDICT = "/api/soc/predict"
TRIP_PREDICT = "/api/trip/predict"
WEB_SYNC_BATTERY = "/api/web/sync/battery-state"
WEB_SYNC_TRIP = "/api/web/sync/trip-prediction"
```

## 🧪 Testing

### 1. API Testing
```bash
# Test SOC Status
curl -X GET "http://localhost:5000/api/soc/status"

# Test Trip Prediction
curl -X POST "http://localhost:5000/api/trip/predict" \
  -H "Content-Type: application/json" \
  -d '{"vehicleId":"test-001","from":"Hanoi","to":"Haiphong","distance":120,"currentBattery":75}'

# Test Sync
curl -X POST "http://localhost:5000/api/web/sync/battery-state" \
  -H "Content-Type: application/json" \
  -d '{"vehicleId":"test-001","percentage":75,"soh":95,"temp":25}'
```

### 2. Flutter App Testing
```dart
// Test API Connection
final isConnected = await BatteryStateService.testAPIConnection();

// Test Prediction
final prediction = await TripPredictionService.predictTrip(...);

// Test Sync
await BatteryStateService.syncWithWebDashboard(vehicleId);
```

## 🚨 Troubleshooting

### Common Issues

1. **API Connection Failed**
   - Check if server is running on port 5000
   - Verify network connectivity
   - Check firewall settings

2. **Firebase Index Errors**
   - Create composite indexes in Firebase Console
   - Use provided URLs from error messages

3. **SOC Model Not Loading**
   - Verify ev_soc_pipeline.pkl exists
   - Check file permissions
   - Restart API server

4. **Sync Failures**
   - Check Firebase credentials
   - Verify network connectivity
   - Check API server logs

### Debug Mode

```bash
# Enable debug logging
export FLASK_DEBUG=1
export FLASK_USE_RELOADER=1

# Run server with debug
python server.py
```

## 📈 Performance Optimization

### 1. Caching
- Battery state cached for 5 minutes
- Trip predictions cached for 1 hour
- Model predictions cached per vehicle

### 2. Batch Operations
- Sync multiple records in single API call
- Use Firestore batch writes
- Implement pagination for history

### 3. Background Sync
- Flutter background service for real-time updates
- Web dashboard WebSocket for live updates
- Scheduled sync every 15 minutes

## 🔐 Security

### API Security
- Firebase Admin SDK for server authentication
- Request validation and sanitization
- Rate limiting for API endpoints

### Data Security
- Encrypted Firebase connections
- Local data encryption in Flutter app
- Secure API key management

## 📚 Tài liệu tham khảo

1. [Flutter Documentation](https://flutter.dev/docs)
2. [Firebase Documentation](https://firebase.google.com/docs)
3. [Flask Documentation](https://flask.palletsprojects.com/)
4. [React Documentation](https://reactjs.org/docs)

## 🆘 Hỗ trợ

Nếu gặp vấn đề trong quá trình triển khai:

1. Kiểm tra logs của API server
2. Xem console của Flutter app
3. Kiểm tra Firebase Console
4. Test các API endpoints riêng lẻ

---

**Version**: 1.0.0  
**Last Updated**: 2026-04-16  
**Author**: VinFast Battery Development Team
