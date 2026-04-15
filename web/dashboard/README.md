# VinFast Battery Management System Admin Dashboard

Hệ thống quản lý pin thông minh của VinFast - Giao diện quản trị viên hiện đại được xây dựng dựa trên thiết kế của ev-battery-admin.

## 🚀 Tính năng

### 📊 Tổng quan hệ thống
- **Dashboard chính**: Hiển thị KPI quan trọng về người dùng, xe hoạt động, trạng thái pin
- **Biểu đồ thời gian thực**: Theo dõi hoạt động hệ thống 24/7
- **Cảnh báo thông minh**: Hệ thống cảnh báo sự kiện bất thường

### 👥 Quản lý người dùng
- **Quản lý tài khoản**: Thêm, sửa, xóa người dùng
- **Phân quyền**: Admin/User với các quyền truy cập khác nhau
- **Theo dõi hoạt động**: Lịch sử đăng nhập và thao tác

### 🤖 AI Center
- **Mô hình dự đoán**: Battery Health Predictor, Consumption Optimizer, Anomaly Detector
- **Huấn luyện mô hình**: Tối ưu hóa các thuật toán AI
- **Theo dõi hiệu suất**: Độ chính xác và số lượng dự đoán

### 🔍 Hệ thống kiểm toán
- **Ghi log hoạt động**: Theo dõi tất cả thao tác hệ thống
- **Lọc và tìm kiếm**: Tìm kiếm logs theo nhiều tiêu chí
- **Báo cáo**: Xuất báo cáo hoạt động hệ thống

## 🛠️ Công nghệ sử dụng

### Frontend
- **React 19** với **TypeScript**
- **Vite** cho build tool
- **Tailwind CSS** cho styling
- **shadcn/ui** components
- **React Router** cho navigation
- **Recharts** cho biểu đồ
- **Framer Motion** cho animations
- **Firebase Auth** cho authentication

### Backend Integration
- **Firebase Authentication**
- **REST API** với Flask server (port 5000)
- **Telemetry data** và **AI models**

## 📦 Cài đặt

### Yêu cầu
- Node.js 18+
- npm hoặc yarn
- Firebase project (cho authentication)

### Các bước thực hiện

1. **Clone repository**
   ```bash
   cd "c:\Users\khanh\OneDrive\Desktop\Vinfast Batery\web\dashboard"
   ```

2. **Cài đặt dependencies**
   ```bash
   npm install
   ```

3. **Cấu hình environment**
   ```bash
   cp .env.example .env
   ```
   
   Chỉnh sửa file `.env` với thông tin Firebase của bạn:
   ```env
   VITE_FIREBASE_API_KEY=your-api-key-here
   VITE_FIREBASE_AUTH_DOMAIN=your-project.firebaseapp.com
   VITE_FIREBASE_PROJECT_ID=your-project-id
   VITE_FIREBASE_STORAGE_BUCKET=your-project.appspot.com
   VITE_FIREBASE_MESSAGING_SENDER_ID=123456789
   VITE_FIREBASE_APP_ID=your-app-id
   
   VITE_API_BASE_URL=http://localhost:5000
   VITE_AI_API_BASE_URL=http://localhost:5000
   VITE_ALLOW_MOCK_DATA=true
   ```

4. **Khởi động development server**
   ```bash
   npm run dev
   ```

   Ứng dụng sẽ chạy tại: `http://localhost:3000`

5. **Khởi động backend server** (nếu cần)
   ```bash
   # Trong thư mục parent
   cd ..
   python server.py
   ```

## 🎯 Sử dụng

### Đăng nhập
- **Demo account**: `admin@vinfast.com` / `admin123`
- Hoặc tạo tài khoản mới qua Firebase Console

### Navigation
- **Sidebar menu**: Điều hướng giữa các trang
- **Topbar search**: Tìm kiếm người dùng, xe, mã lỗi
- **User dropdown**: Quản lý tài khoản và đăng xuất

### Các trang chính
1. **Dashboard**: Tổng quan hệ thống
2. **User Management**: Quản lý người dùng
3. **AI Center**: Trung tâm AI và mô hình
4. **Audit System**: Kiểm toán hoạt động
5. **Settings**: Cài đặt hệ thống

## 🔧 Development

### Scripts
```bash
npm run dev      # Development server
npm run build    # Build production
npm run preview  # Preview production build
npm run lint     # TypeScript checking
npm run clean    # Clean dist folder
```

### Structure
```
src/
├── components/
│   ├── layout/          # Sidebar, Topbar
│   └── ui/             # shadcn/ui components
├── pages/              # Main pages
├── lib/                # Utilities
├── types.ts            # TypeScript types
├── App.tsx             # Main app component
├── main.jsx            # Entry point
└── firebase.ts         # Firebase config
```

### Customization
- **Theme**: Sửa `src/index.css` cho custom colors
- **Components**: Thêm components trong `src/components/ui/`
- **Pages**: Thêm pages mới trong `src/pages/`

## 🐛 Troubleshooting

### Common Issues
1. **Firebase Authentication Error**
   - Kiểm tra API keys trong `.env`
   - Đảm bảo Email/Password authentication được bật trong Firebase Console

2. **Build Errors**
   ```bash
   npm run clean
   npm install
   npm run build
   ```

3. **API Connection Issues**
   - Đảm bảo backend server đang chạy (port 5000)
   - Kiểm tra CORS configuration

## 📝 License

Apache License 2.0

## 🤝 Contributing

1. Fork repository
2. Create feature branch
3. Commit changes
4. Push to branch
5. Create Pull Request

---

**VinFast Battery Management System** - Xây dựng với ❤️ cho tương lai xe điện Việt Nam
