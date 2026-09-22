---
description: Quy định nghiêm ngặt về quản lý tài liệu Markdown và cập nhật tiến độ sau mỗi task
globs: **/*
---

# QUY ĐỊNH QUẢN LÝ TÀI LIỆU MARKDOWN VÀ CẬP NHẬT TIẾN ĐỘ

Để tránh tình trạng dự án bị phân tán quá nhiều file `.md` gây quá tải ngữ cảnh (context overload) cho các Agent tiếp theo, mọi AI Agent (Antigravity, Claude, Cursor, Gemini, Copilot...) khi làm việc trong repository này **BẮT BUỘC** tuân thủ các quy tắc sau:

## 1. TUYỆT ĐỐI KHÔNG TỰ Ý TẠO FILE `.md` MỚI
- **NGHIÊM CẤM** tạo các file kế hoạch dạng `PLAN.md`, `PLANx.md`, `TODO.md` ở thư mục gốc hoặc các thư mục con.
- **NGHIÊM CẤM** tạo các file báo cáo kiểm thử/audit dạng `QA_AUDIT_xxx.md`, `UIUX_FIXES_xxx.md`, `REPORT_xxx.md`, `AUDIT_REPORT.md`...
- Bất kỳ tài liệu phân tích nào nếu cần trình bày cho người dùng hãy trả lời trực tiếp trong khung hội thoại hoặc cập nhật vào các file chuẩn đã được quy hoạch.

## 2. NGUỒN NGỮ CẢNH DUY NHẤT (SINGLE SOURCE OF TRUTH)
- **Đọc hiểu dự án**: Luôn đọc file [`AGENTS.md`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/AGENTS.md) ở thư mục gốc để nắm 100% kiến trúc hệ thống, file map, các API endpoints, schema pin và lệnh test.
- **Nắm bắt tiến độ & backlog**: Luôn đọc file [`PROJECT_STATUS.md`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/PROJECT_STATUS.md) để biết phiên bản hiện tại, các cổng kiểm soát (release gates) và các task đang chờ xử lý.

## 3. QUY TRÌNH BẮT BUỘC SAU KHI HOÀN THÀNH MỖI TASK
Trước khi kết thúc câu trả lời hoặc báo hoàn thành nhiệm vụ cho người dùng, Agent **PHẢI**:
1. Chạy các lệnh kiểm thử tự động tương ứng (pytest, flutter test...) để xác minh không có lỗi hồi quy.
2. Mở file [`PROJECT_STATUS.md`](file:///c:/Users/khanh/OneDrive/Desktop/Vinfast%20Batery/PROJECT_STATUS.md).
3. Thêm 1 dòng mới vào bảng **"3. Nhật Ký Hoàn Thành Task (Changelog)"** ghi rõ:
   - Ngày thực hiện (theo ngày hệ thống).
   - Tên nhiệm vụ.
   - Nội dung chi tiết thay đổi và danh sách file đã tác động.
   - Lệnh và kết quả kiểm thử (Test pass rate).
   - Trạng thái hoàn thành.
4. Đánh dấu hoặc cập nhật các mục trong checklist P0/P1/P2 nếu task liên quan đã được giải quyết.
