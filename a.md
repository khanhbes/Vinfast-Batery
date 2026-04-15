Đây là bản mô tả đầy đủ cho ứng dụng **EV Battery Consumption Predictor**. Dưới đây là tóm tắt các phần chính:

---

**Mục đích cốt lõi:** Dự đoán mức tiêu thụ pin (SoC) cho các chuyến đi xe điện, sử dụng dữ liệu thực từ EV Trip Logger và các mô hình học máy.

**6 tính năng chính:**
- Dự đoán SoC theo thời gian thực dựa trên tốc độ, gia tốc, địa hình
- Dashboard phân tích hiệu suất pin trực quan
- Lập kế hoạch sạc thông minh theo lộ trình
- Import trực tiếp dữ liệu từ EV Trip Logger (GPS, tốc độ, gia tốc)
- Phân tích hành vi lái xe và tác động đến pin
- REST API đầy đủ + xuất báo cáo PDF/CSV

**Bộ 3 mô hình ML:** Random Forest (độ chính xác cao), XGBoost (tốc độ xử lý), LSTM (phân tích chuỗi thời gian) — có thể chọn hoặc ensemble.

**Luồng dữ liệu:** EV Trip Logger → Tiền xử lý → ML Engine → Dự đoán SoC → Gợi ý kế hoạch sạc.

Bạn muốn tôi đi sâu vào phần nào — ví dụ thiết kế màn hình dashboard, thiết kế API, hay kiến trúc mô hình ML cụ thể?