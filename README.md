<p align="center">
  <img src="app/assets/icons/app_icon.png" alt="VinFast Battery Logo" width="120" height="120" style="border-radius: 24px;" />
</p>

<h1 align="center">⚡ VinFast Battery</h1>

<p align="center">
  <strong>Hệ thống quản lý pin & sạc thông minh AI cho xe máy điện VinFast</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.32+-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.11+-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Python-3.11+-3776AB?logo=python&logoColor=white" alt="Python" />
  <img src="https://img.shields.io/badge/Firebase-Firestore-FFCA28?logo=firebase&logoColor=black" alt="Firebase" />
  <img src="https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white" alt="Docker" />
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License" />
  <img src="https://img.shields.io/badge/Version-1.1.3-blue" alt="Version" />
</p>

<p align="center">
  <em>Full-stack Android app + AI backend + IoT gateway — biến bộ sạc thường thành trạm sạc thông minh.</em>
</p>

---

## 📋 Mục lục

- [Tổng quan](#-tổng-quan)
- [Tính năng nổi bật](#-tính-năng-nổi-bật)
- [Kiến trúc hệ thống](#-kiến-trúc-hệ-thống)
- [Cấu trúc dự án](#-cấu-trúc-dự-án)
- [Yêu cầu hệ thống](#-yêu-cầu-hệ-thống)
- [Cài đặt & Chạy](#-cài-đặt--chạy)
  - [Mobile App (Flutter)](#1-mobile-app-flutter)
  - [Backend Server (Python)](#2-backend-server-python)
  - [Smart Charger Gateway](#3-smart-charger-gateway)
  - [Admin Dashboard (React)](#4-admin-dashboard-react)
- [Mô hình AI](#-mô-hình-ai)
- [Tích hợp phần cứng](#-tích-hợp-phần-cứng)
- [API Reference](#-api-reference)
- [Testing](#-testing)
- [Deployment](#-deployment)
- [Đóng góp](#-đóng-góp)
- [Giấy phép](#-giấy-phép)

---

## 🌟 Tổng quan

**VinFast Battery** là hệ thống quản lý pin và sạc thông minh toàn diện, được thiết kế riêng cho hệ sinh thái xe máy điện VinFast (Feliz, Klara, Evo, Vento, Theon, Tempest, Ludo).

Hệ thống kết hợp **ứng dụng di động Flutter**, **backend AI Python**, **IoT gateway** điều khiển relay Shelly, và **admin dashboard React** — tạo nên một trải nghiệm sạc thông minh hoàn chỉnh từ dự đoán thời gian sạc chính xác bằng AI đến tự động ngắt sạc khi đạt mức pin mong muốn.

### Vấn đề giải quyết

| Vấn đề | Giải pháp |
|--------|-----------|
| Xe máy điện VinFast không có app quản lý pin chi tiết | Dashboard theo dõi pin, lịch sử sạc, thống kê tiêu thụ |
| Không biết bao lâu thì đầy pin | AI dự đoán thời gian sạc chính xác (± 5 phút) |
| Sạc qua đêm gây chai pin LFP | Tự động ngắt sạc khi đạt mức tối ưu 80% |
| Không có cách giám sát sạc từ xa | Real-time telemetry qua Shelly smart relay |
| Mỗi xe sạc khác nhau, AI chung không chính xác | Per-vehicle AI personalization: AI học riêng cho từng xe |

---

## ✨ Tính năng nổi bật

### 📱 Mobile App
- **Dashboard thông minh** — tổng quan pin, SoH, quãng đường còn lại, thống kê tiêu thụ
- **Sạc thông minh AI** — chọn mức pin mong muốn, AI tính thời gian & tự ngắt sạc
- **Sạc hẹn giờ** — 6 preset thời gian + chế độ sạc ngay lập tức (tự ngắt sau 7 giờ)
- **EV Cockpit UI** — giao diện dark mode premium, circular gauge, battery track animation
- **Garage đa xe** — quản lý nhiều xe, tự động nhận diện model từ catalog VinFast
- **Trip planner** — lập kế hoạch chuyến đi với bản đồ, dự đoán pin tiêu thụ
- **Lịch sử sạc** — log chi tiết mỗi phiên sạc với biểu đồ năng lượng
- **Thống kê nâng cao** — biểu đồ FL Chart: chi phí, hiệu suất, xu hướng SoH
- **Bảo trì xe** — nhắc nhở bảo dưỡng định kỳ, ghi lịch sử bảo trì
- **Thông báo thông minh** — cảnh báo pin thấp, sạc hoàn tất, bất thường

### 🤖 AI & Machine Learning
- **11 mô hình AI** — charging time, SoC estimation, SoH degradation, anomaly detection, DTE, eco-driving, trip labeling, user behavior, charging recommender, eco-routing, lifecycle
- **Per-vehicle personalization** — online calibration qua 3 giai đoạn: Base → Calibrating → Personalized
- **Physics fallback** — luôn có dự đoán khi server AI không khả dụng
- **On-device TFLite** — inference trên điện thoại, không cần internet
- **Shadow promotion** — mô hình mới chạy song song, chỉ thay thế khi tốt hơn

### 🔌 Smart Charging
- **Điều khiển relay Shelly** — bật/tắt sạc từ xa qua Cloud API hoặc LAN
- **Real-time telemetry** — giám sát công suất, năng lượng, điện áp mỗi 30 giây
- **Graduation policy** — chế độ an toàn nhiều cấp: safe boot → LAN → Cloud
- **Safety monitor** — tự ngắt khi phát hiện bất thường (quá áp, quá dòng, quá nhiệt)
- **Session recovery** — tự phục hồi phiên sạc khi mất kết nối

### 🖥️ Admin Dashboard
- **React + TypeScript + Vite** — SPA quản trị với Tailwind CSS & shadcn/ui
- **Quản lý người dùng** — xem, tìm kiếm, theo dõi hoạt động
- **Giám sát hệ thống** — model health, telemetry coverage, error rates
- **AI model management** — lifecycle, training logs, A/B testing results

---

## 🏗 Kiến trúc hệ thống

```
┌─────────────────────────────────────────────────────────────────┐
│                        Mobile App (Flutter)                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐ │
│  │ Dashboard │  │Smart     │  │ Trip     │  │ Settings/Garage  │ │
│  │ & Stats   │  │Charging  │  │ Planner  │  │ & Maintenance    │ │
│  └─────┬─────┘  └────┬─────┘  └────┬─────┘  └────────┬────────┘ │
│        └──────────────┼──────────────┼─────────────────┘          │
│                       ▼                                           │
│              ┌─────────────────┐     ┌─────────────────┐         │
│              │ Riverpod State  │     │ TFLite On-Device │         │
│              │ Management      │     │ ML Inference     │         │
│              └────────┬────────┘     └─────────────────┘         │
└───────────────────────┼─────────────────────────────────────────┘
                        │ HTTPS / WebSocket
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Backend (Docker Compose)                       │
│                                                                   │
│  ┌──────────────────────┐    ┌──────────────────────────┐        │
│  │  Flask API (server.py)│◄──►│  FastAPI AI Server       │        │
│  │  Port 5000            │    │  Port 8001 (internal)    │        │
│  │  • Smart Charge API   │    │  • Model Registry        │        │
│  │  • Shelly Proxy       │    │  • Prediction Service    │        │
│  │  • Telemetry Ingest   │    │  • Fine-tune Pipeline    │        │
│  │  • User Management    │    │  • Vehicle Adapter       │        │
│  └──────────┬───────────┘    └──────────────────────────┘        │
│             │                                                     │
│  ┌──────────▼───────────┐    ┌──────────────────────────┐        │
│  │  Caddy Reverse Proxy │    │  Admin Dashboard (React) │        │
│  │  TLS + CORS          │    │  Port 3000               │        │
│  └──────────────────────┘    └──────────────────────────┘        │
└─────────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Cloud Services                                │
│  ┌────────────────┐  ┌────────────────┐  ┌─────────────────┐    │
│  │ Firebase Auth   │  │ Cloud Firestore│  │ Shelly Cloud API│    │
│  └────────────────┘  └────────────────┘  └─────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│              Smart Charger Gateway (On-premise)                  │
│  ┌────────────────┐  ┌────────────────┐  ┌─────────────────┐    │
│  │ Shelly Control  │  │ Safety Monitor │  │ Telemetry Writer│    │
│  │ (LAN/Cloud)     │  │ (Auto-cutoff)  │  │ (Firestore Sync)│    │
│  └────────────────┘  └────────────────┘  └─────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📂 Cấu trúc dự án

```
Vinfast-Batery/
├── app/                            # 📱 Flutter Mobile App
│   ├── lib/
│   │   ├── core/                   #   ├── Theme, constants, providers, widgets
│   │   ├── data/                   #   ├── Models, repositories, services
│   │   │   ├── models/             #   │   ├── VehicleModel, SmartChargingSession, ...
│   │   │   ├── repositories/       #   │   ├── ChargeLog, SmartCharger, VehicleSpec
│   │   │   └── services/           #   │   └── SmartCharger, Prediction, Telemetry
│   │   ├── features/               #   ├── Feature modules
│   │   │   ├── ai/                 #   │   ├── Smart Charging control + AI widgets
│   │   │   ├── auth/               #   │   ├── Login, register, forgot password
│   │   │   ├── battery_monitor/    #   │   ├── Real-time battery monitoring
│   │   │   ├── charge/             #   │   ├── Manual charge tracking
│   │   │   ├── dashboard/          #   │   ├── Trip logging & daily dashboard
│   │   │   ├── home/               #   │   ├── Home screen with overview cards
│   │   │   ├── maintenance/        #   │   ├── Maintenance reminders & logs
│   │   │   ├── settings/           #   │   ├── Vehicle garage, AI settings, profile
│   │   │   ├── smart_charging/     #   │   ├── Shelly setup hub & verification
│   │   │   ├── statistics/         #   │   ├── Charts, cost analysis, trends
│   │   │   └── trip_planner/       #   │   └── Route planning with battery prediction
│   │   ├── l10n/                   #   ├── Localization (Vietnamese)
│   │   ├── navigation/             #   └── Navigation & routing
│   │   ├── main.dart               #   Entry point
│   │   └── app.dart                #   App widget & theme
│   ├── assets/                     #   Icons, models, VinFast specs catalog
│   ├── android/                    #   Android platform config
│   └── pubspec.yaml                #   Dependencies
│
├── web/                            # 🖥️ Backend & Dashboard
│   ├── server.py                   #   Flask unified API (~4000 LOC)
│   ├── ai_server/                  #   FastAPI AI microservice
│   │   ├── main.py                 #     API routes & health checks
│   │   ├── model_runtime.py        #     Multi-framework model loading
│   │   ├── registry.py             #     Model registry & versioning
│   │   ├── vehicle_adapter.py      #     Per-vehicle personalization adapter
│   │   ├── fine_tune.py            #     Online fine-tuning pipeline
│   │   └── lifecycle.py            #     Model lifecycle management
│   ├── shelly/                     #   Shelly smart relay integration
│   │   ├── service.py              #     Smart charging orchestration
│   │   ├── repositories.py         #     Firestore persistence
│   │   ├── personalization.py      #     Per-vehicle learning & calibration
│   │   ├── charging_fusion.py      #     Multi-source ETA fusion
│   │   └── models.py               #     Domain models
│   ├── dashboard/                  #   React admin dashboard (Vite + shadcn)
│   ├── models/                     #   Trained ML model artifacts (11 domains)
│   ├── tests/                      #   Pytest test suite
│   ├── docker-compose.yml          #   Production deployment
│   ├── docker-compose.laptop.yml   #   Local development
│   └── Caddyfile                   #   Reverse proxy + TLS
│
├── smart_charger_gateway/          # 🔌 On-premise IoT Gateway
│   ├── main.py                     #   FastAPI gateway server
│   ├── smart_charging.py           #   Core charging logic & state machine
│   ├── shelly.py                   #   Shelly device communication
│   ├── safety_monitor.py           #   Hardware safety watchdog
│   ├── graduation_policy.py        #   Safe boot → LAN → Cloud progression
│   ├── telemetry_writer.py         #   Firestore telemetry sync
│   └── tests/                      #   Gateway unit tests
│
├── build_app.ps1                   # 🔨 Android APK build script
├── start_server_local.ps1          # 💻 Khởi chạy server trực tiếp (Cách 1 - Local Dev)
├── start_server_docker.ps1         # 🐳 Khởi chạy server qua Docker + Tailscale (Cách 2)
├── deploy_web.ps1                  # 🚀 Alias chuyển tiếp tới start_server_docker.ps1
├── ev_soc_pipeline.pkl             # 🧠 Pre-trained SoC estimation model
└── SMART_CHARGE_SETUP_GUIDE.md     # 📖 Hardware setup guide
```

---

## ⚙️ Yêu cầu hệ thống

### Mobile App
| Component | Phiên bản |
|-----------|-----------|
| Flutter SDK | ≥ 3.32 |
| Dart SDK | ≥ 3.11 |
| Android SDK | ≥ API 23 (Android 6.0) |
| Java/JDK | 17+ |

### Backend
| Component | Phiên bản |
|-----------|-----------|
| Python | ≥ 3.11 |
| Docker & Docker Compose | Latest |
| Node.js (Dashboard) | ≥ 18 |

### Cloud Services
| Service | Mục đích |
|---------|----------|
| Firebase Authentication | Xác thực người dùng |
| Cloud Firestore | Database chính |
| Shelly Cloud API | Điều khiển relay IoT |

---

## 🚀 Cài đặt & Chạy

### 1. Mobile App (Flutter)

```bash
# Clone repository
git clone https://github.com/khanhbes/Vinfast-Batery.git
cd Vinfast-Batery

# Cài đặt Flutter dependencies
cd app
flutter pub get

# Chạy debug mode
flutter run

# Hoặc build APK bằng script tự động
cd ..
.\build_app.ps1 -Mode debug          # Debug APK
.\build_app.ps1                       # Release APK (signed)
.\build_app.ps1 -SplitAbi            # Release chia theo chip ARM
.\build_app.ps1 -Clean               # Clean build
```

#### Cấu hình Firebase
1. Tạo project trên [Firebase Console](https://console.firebase.google.com/)
2. Thêm app Android với package name: `com.khanhbes.vinfast_battery`
3. Download `google-services.json` → `app/android/app/`
4. Enable **Authentication** (Email/Password) và **Cloud Firestore**

### 2. Backend Server (Python)

```bash
cd web

# Tạo file cấu hình từ template
cp .env.docker.example .env
# Chỉnh sửa .env với thông tin thật

# Khởi chạy toàn bộ backend bằng Docker
docker compose up -d

# Hoặc chạy local (development)
python -m venv .venv
.venv\Scripts\activate           # Windows
source .venv/bin/activate        # macOS/Linux
pip install -r requirements.txt
python server.py
```

#### Biến môi trường quan trọng (`.env`)

| Biến | Mô tả |
|------|--------|
| `FIREBASE_CREDENTIALS_JSON` | Firebase Admin SDK credentials (JSON string) |
| `AI_SERVER_INTERNAL_TOKEN` | Token bảo mật giữa API ↔ AI Server |
| `ADMIN_EMAILS` | Danh sách email admin (comma-separated) |
| `SHELLY_PROVIDER` | `integrator` hoặc `legacy` |
| `SHELLY_INTEGRATOR_TAG` | Shelly Cloud integration tag |
| `CORS_ORIGINS` | Allowed origins cho CORS |

### 3. Smart Charger Gateway

```bash
cd smart_charger_gateway

# Tạo cấu hình
cp .env.example .env
# Chỉnh sửa .env

# Cài đặt & chạy
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
python main.py
```

> 📖 Hướng dẫn chi tiết setup phần cứng Shelly: xem [`SMART_CHARGE_SETUP_GUIDE.md`](SMART_CHARGE_SETUP_GUIDE.md)

### 4. Admin Dashboard (React)

```bash
cd web/dashboard

# Cài đặt dependencies
npm install

# Chạy development server
npm run dev          # http://localhost:3000

# Build production
npm run build
```

---

## 🧠 Mô hình AI

Hệ thống sử dụng **11 mô hình AI** được tổ chức trong Model Registry với lifecycle management hoàn chỉnh:

| # | Model | Framework | Mô tả |
|---|-------|-----------|--------|
| 1 | `charging_time` | XGBoost / TFLite | Dự đoán thời gian sạc (phút) từ SoC hiện tại → mục tiêu |
| 2 | `soc` | Scikit-learn | Ước lượng State of Charge từ điện áp, dòng, nhiệt độ |
| 3 | `soh_degradation` | XGBoost | Dự đoán xu hướng chai pin dựa trên lịch sử sạc/xả |
| 4 | `dte` | XGBoost | Distance to Empty — quãng đường còn lại |
| 5 | `anomaly_detection` | Isolation Forest | Phát hiện bất thường trong dữ liệu sạc/pin |
| 6 | `charging_recommender` | Rule + ML | Gợi ý mức sạc tối ưu cho LFP |
| 7 | `eco_driving` | Gradient Boosting | Đánh giá phong cách lái tiết kiệm |
| 8 | `eco_routing` | Gradient Boosting | Tối ưu tuyến đường theo năng lượng tiêu thụ |
| 9 | `trip_labeling` | Classification | Phân loại chuyến đi (commute, errands, leisure) |
| 10 | `user_behavior` | Clustering | Phân tích hành vi sử dụng xe |
| 11 | `lifecycle` | Regression | Dự đoán tuổi thọ pin còn lại |

### Per-Vehicle Personalization Pipeline

```
Phiên sạc mới → evaluate_training() → update_profile()
                     │                        │
                     ▼                        ▼
              ┌─────────────┐         ┌──────────────────┐
              │ Eligibility │         │ Online Calibration│
              │ Check:      │         │ • global_time_scale
              │ • ≥20 min   │         │ • soc_band params
              │ • ≥10% gain │         │ • effective_capacity
              │ • telemetry │         │ • power_scale
              │   ≥70%      │         └──────────────────┘
              └─────────────┘                  │
                                               ▼
                                 ┌─────────────────────────┐
                                 │ Stage Progression:       │
                                 │ 0-2 sessions  → base    │
                                 │ 3-9 sessions  → calibrating
                                 │ 10+ sessions  → personalized
                                 └─────────────────────────┘
```

---

## 🔌 Tích hợp phần cứng

### Shelly Smart Relay

Hệ thống hỗ trợ relay thông minh **Shelly 1PM Mini Gen3** (hoặc tương đương) để điều khiển bật/tắt sạc:

| Tính năng | Chi tiết |
|-----------|----------|
| **Giao thức** | REST API (Cloud) / mDNS (LAN) |
| **Telemetry** | Công suất (W), năng lượng (Wh), điện áp (V) — mỗi 30s |
| **An toàn** | Auto-cutoff khi quá áp, quá dòng, mất kết nối |
| **Graduation** | Safe boot → LAN verified → Cloud verified |

### Xe VinFast hỗ trợ

| Model | Dung lượng pin | Công suất sạc max |
|-------|---------------|-------------------|
| Evo 200 | 1,872 Wh | 480W |
| Evo Lite Neo | 1,488 Wh | 360W |
| Evo Grand | 2,400 Wh | 600W |
| **Feliz 2025** | **2,600 Wh** | **600W** |
| Feliz S | 1,440 Wh | 360W |
| Klara S | 1,920 Wh | 480W |
| Klara A2 | 1,680 Wh | 420W |
| Vento S | 1,872 Wh | 480W |
| Theon S | 3,500 Wh | 700W |
| Tempest | 2,880 Wh | 720W |
| Ludo | 1,056 Wh | 264W |

---

## 📡 API Reference

### Smart Charging Endpoints

| Method | Endpoint | Mô tả |
|--------|----------|--------|
| `POST` | `/api/smart-charging/preview` | Tạo preview dự đoán thời gian sạc |
| `POST` | `/api/smart-charging/start` | Bắt đầu phiên sạc thông minh |
| `POST` | `/api/smart-charging/stop` | Dừng phiên sạc |
| `GET` | `/api/smart-charging/status` | Trạng thái phiên sạc hiện tại |
| `GET` | `/api/smart-charging/history` | Lịch sử phiên sạc |

### Shelly Integration

| Method | Endpoint | Mô tả |
|--------|----------|--------|
| `POST` | `/api/shelly/relay/on` | Bật relay (bắt đầu sạc) |
| `POST` | `/api/shelly/relay/off` | Tắt relay (dừng sạc) |
| `GET` | `/api/shelly/status` | Trạng thái thiết bị & telemetry |
| `POST` | `/api/shelly/verify-cloud` | Xác minh kết nối Cloud |

### AI & Model Management

| Method | Endpoint | Mô tả |
|--------|----------|--------|
| `GET` | `/api/ai/models` | Danh sách model đã đăng ký |
| `GET` | `/api/ai/models/{key}/health` | Health check model cụ thể |
| `POST` | `/api/ai/predict` | Inference trực tiếp |
| `GET` | `/api/ai/adapter/{vehicleId}` | Per-vehicle adapter data |

---

## 🧪 Testing

### Backend (Python)

```bash
cd web
python -m pytest tests/ -v

# Test cụ thể
python -m pytest tests/test_shelly_cloud_first.py -v
python -m pytest tests/test_vehicle_adapter.py -v
python -m pytest tests/test_personal_smart_charge_v3.py -v
```

### Smart Charger Gateway

```bash
cd smart_charger_gateway
python -m pytest tests/ -v
```

### Flutter App

```bash
cd app
flutter test
flutter test test/unit/battery_capacity_test.dart
```

---

## 🚢 Deployment

### Production (Docker Compose)

```bash
cd web

# Build & deploy tất cả services
docker compose up -d --build

# Kiểm tra health
docker compose ps
curl https://your-domain/api/health
```

**Services trong Docker Compose:**

| Service | Port (internal) | Mô tả |
|---------|----------------|--------|
| `ai` | 8001 | FastAPI AI prediction server |
| `api` | 5000 | Flask unified API |
| `dashboard` | 3000 | React admin dashboard |
| `caddy` | 80/443 | Reverse proxy + auto TLS |

### APK Distribution

```powershell
# Build release APK
.\build_app.ps1

# APK sẽ được tự động copy sang:
# - app/releases/         (archive)
# - web/apk/              (OTA distribution)
```

---

## 🤝 Đóng góp

1. Fork repository
2. Tạo feature branch: `git checkout -b feature/ten-tinh-nang`
3. Commit changes: `git commit -m "feat: mô tả ngắn gọn"`
4. Push to branch: `git push origin feature/ten-tinh-nang`
5. Tạo Pull Request

### Quy ước commit

| Prefix | Ý nghĩa |
|--------|---------|
| `feat:` | Tính năng mới |
| `fix:` | Sửa lỗi |
| `docs:` | Cập nhật tài liệu |
| `refactor:` | Refactor code |
| `test:` | Thêm/sửa test |
| `chore:` | Công việc bảo trì |

---

## 📄 Giấy phép

Dự án này được phân phối dưới giấy phép **MIT License**. Xem file [LICENSE](LICENSE) để biết thêm chi tiết.

---

<p align="center">
  <strong>Được phát triển bởi <a href="https://github.com/khanhbes">@khanhbes</a></strong>
  <br />
  <em>VinFast Battery — Sạc thông minh, pin bền lâu ⚡</em>
</p>
