"""App knowledge for BatteryBot: built-in entries + admin edits (Firestore).

Retrieval is a small keyword ranker over accent-folded text; the top entries
go into the prompt. Admin documents in ``assistantKnowledge`` override a
built-in entry with the same id or add new ones (enabled=false hides one).
"""
from __future__ import annotations

import re
import threading
import time
import unicodedata

BUILTIN: list[dict] = [
    # -- QA 135 ---------------------------------------------------------------
    {"id": "premium-plans", "title": "Gói Pinova Premium (Free / Pro / Ultra)",
     "keywords": ["premium", "gói", "pro", "ultra", "free", "nâng cấp", "giá", "trả phí", "dùng thử", "mua"],
     "body": "Free: sạc an toàn, hẹn giờ, quét đồng hồ, trợ giúp, 1 xe, lịch sử 30 ngày, Pinova Bot 10 tin/ngày. Pro (29.000đ/tháng, 249.000đ/năm): thêm sạc đến % tự ngắt, đổi mục tiêu khi đang sạc, Lộ trình (pin cần cho chuyến đi), % pin chai, giao diện tùy chọn, 2 xe, lịch sử đầy đủ + xuất CSV, 30 tin/ngày. Ultra (49.000đ/tháng, 449.000đ/năm): thêm sạc đêm an toàn, huấn luyện AI cá nhân, giao diện Aurora chuyển động, tối đa 10 xe, 100 tin/ngày. Chi phí theo tháng (tab Lịch sử) và việc xem, tắt, xóa dữ liệu AI có ở mọi gói. Dùng thử Ultra 7 ngày một lần. Thanh toán trong app chưa mở. Xem ở Cài đặt → Pinova Premium. Hết hạn gói không ngắt phiên đang sạc."},
    {"id": "promo-code", "title": "Mã khuyến mãi",
     "keywords": ["mã", "khuyến mãi", "giảm giá", "voucher", "coupon", "promo"],
     "body": "Nhập mã ở Cài đặt → Pinova Premium → 'Mã khuyến mãi'. Mã giảm một % cho gói và kỳ hạn mà admin chọn, có hạn dùng; giá đã giảm hiện gạch ngang trên thẻ gói. Mã được giữ cho lần mua đầu. Nhập sai nhiều lần sẽ phải chờ 10 phút."},
    {"id": "help-center", "title": "Trợ giúp & khắc phục sự cố",
     "keywords": ["trợ giúp", "hỗ trợ", "lỗi", "không được", "liên hệ", "email", "khắc phục", "báo lỗi"],
     "body": "Cài đặt → Trợ giúp & khắc phục sự cố (mọi gói): app tự kiểm tra mạng, máy chủ, tài khoản, xe, ổ Shelly, quyền thông báo, camera, chạy nền và có nút sửa từng mục. 'Gửi yêu cầu hỗ trợ' gửi câu hỏi tới đội Pinova kèm kết quả kiểm tra (không gồm mật khẩu); trả lời hiện trong app và thông báo."},
    {"id": "target-edit", "title": "Đổi mục tiêu khi đang sạc",
     "keywords": ["đổi mục tiêu", "sạc thêm", "lên 90", "giảm mục tiêu", "sửa mục tiêu"],
     "body": "Khi đang sạc đến % (gói Pro), bấm 'Đổi mục tiêu' dưới thẻ đang sạc. Giảm: máy chủ ngắt ở mức mới. Tăng: máy chủ gia hạn giới hạn an toàn của ổ Shelly (vẫn kiểm tra điện áp, dòng, nhiệt) rồi mới nhận mục tiêu mới; người dùng vuốt xác nhận vì sạc lâu hơn. Không gia hạn được thì giữ mục tiêu cũ."},
    {"id": "battery-health", "title": "% pin chai",
     "keywords": ["pin chai", "chai pin", "sức khỏe pin", "dung lượng còn", "pin còn tốt", "soh"],
     "body": "Giám sát pin → % pin chai (gói Pro): ước tính dung lượng pin còn lại từ điện năng ổ Shelly đo và % người dùng đọc trên đồng hồ sau mỗi lần sạc (hiệu suất ~90%). Càng nhiều lần nhập % thật càng tin cậy. Bài kiểm tra: đi xe tới ≤ 30%, quét đồng hồ ghi %, sạc đến khi máy chủ nhận pin đầy; app tính dung lượng thật. Dưới 70% nên đưa xe đi kiểm tra."},
    {"id": "night-charging", "title": "Sạc đêm an toàn",
     "keywords": ["sạc đêm", "ban đêm", "qua đêm", "sáng dậy", "giờ thức", "an toàn ban đêm", "cháy nổ"],
     "body": "Cài đặt → Sạc đêm an toàn (gói Ultra): nhập % pin hiện tại, mức 80/85/90% và giờ thức dậy, vuốt một lần để hẹn. Máy chủ bật sạc muộn nhất có thể để đầy khoảng 20 phút trước giờ thức (đúng giờ điện rẻ). Ban đêm ngắt ngay khi ổ trên 60°C, công suất cao bất thường hoặc sạc quá lâu; mọi điện thoại nhận cảnh báo kêu như báo thức. Ổ Shelly vẫn có hẹn giờ tự tắt. Nên cắm ổ ở nơi thoáng, không đặt xe gần vật dễ cháy."},
    {"id": "scan-tips", "title": "Quét đồng hồ xe",
     "keywords": ["quét", "camera", "đọc sai", "không nhận", "đồng hồ", "scan"],
     "body": "Đưa cả số % pin và ODO vào khung, tránh chói đèn, giữ máy yên 1–2 giây. App đọc ngay trên máy (nhiều ngưỡng sáng, nghiêng); sau khoảng 2,5 giây nếu chưa chắc sẽ nhờ AI đọc một ảnh xám vùng đồng hồ (không lưu ảnh, giới hạn lượt theo gói). Bấm 'Chụp ảnh' để đọc ảnh rõ hơn. Luôn so lại với đồng hồ xe trước khi Lưu."},
    {"id": "tabs", "title": "Các tab chính của app",
     "keywords": ["tab", "màn hình", "menu", "điều hướng", "ở đâu"],
     "body": "App có 4 tab dưới cùng: Tổng quan (pin, quãng đường ước tính, lối tắt), Sạc pin (sạc đến mức pin mục tiêu và Sạc hẹn giờ, trạng thái Shelly), Lịch sử (các phiên sạc, điện năng, chi phí theo tháng) và Cài đặt (xe, Shelly, thông báo, thành tựu, bảo dưỡng, trợ giúp). Nút Pinova Bot nổi ở góc phải dưới."},
    {"id": "overview", "title": "Tổng quan",
     "keywords": ["tổng quan", "pin hiện tại", "quãng đường", "km", "odo", "sức khỏe pin", "soh"],
     "body": "Tổng quan hiển thị xe đang chọn, % pin đã nhập, quãng đường ước tính, ODO, hiệu suất km/1% pin và sức khỏe pin. Quãng đường = (pin − 5% dự trữ) × km/1% × SoH; đây là ước tính, không phải số đo BMS."},
    {"id": "battery-input", "title": "Nhập mức pin",
     "keywords": ["nhập pin", "mức pin", "sửa pin", "cập nhật pin", "núm bạc"],
     "body": "App không đọc BMS của xe. Người dùng nhập mức pin (và ODO) theo đồng hồ xe: Tổng quan → 'Cập nhật % pin & ODO' (nhập tay, hoặc bấm 'Quét đồng hồ' rồi đưa camera vào đồng hồ xe — app tự nhận % pin và ODO ngay trên máy, người dùng kiểm lại rồi Lưu), kéo núm bạc ở tab Sạc pin, hoặc nhờ Pinova Bot cập nhật. Núm xanh là mức muốn sạc tới."},
    {"id": "charge-ai", "title": "Sạc đến mức pin mục tiêu",
     "keywords": ["sạc ai", "dự đoán", "bao lâu", "thời gian sạc", "mục tiêu", "sạc đến", "tự ngắt", "80%"],
     "body": "Chọn mức pin muốn sạc tới rồi bấm Dự đoán: máy chủ ước tính thời gian (kèm khoảng sai số) theo điện năng xe cần cho 1% pin và công suất sạc học từ chính xe bạn. Vuốt 'Sạc đến X%' để bật: máy chủ tự ngắt khi ước tính đạt X%, đồng thời Shelly có hẹn giờ trần an toàn (dự kiến ×1,5 + 20 phút, tối đa 10 giờ) để vẫn tự tắt nếu máy chủ mất kết nối. Nếu xe ngừng nhận điện (pin đầy hoặc chưa cắm) quá 3 phút, ổ cũng tự tắt. Ở mọi phiên (cả hẹn giờ), khi công suất sạc ở dưới 40 W suốt 5 phút sau khi đã sạc mạnh, app nhận biết pin đầy (100%) và tự ngắt. Trong lúc sạc, thông báo trên điện thoại hiện % ước tính · W · thời gian còn lại; nút Dừng sạc có ở thông báo khi app đang mở, còn khi app đã đóng thì chạm thông báo để mở app và dừng."},
    {"id": "charge-learning", "title": "App học từ dữ liệu của bạn (AI cá nhân)",
     "keywords": ["nhập %", "sau khi sạc", "đồng hồ xe", "sai lệch", "chính xác", "học", "fine-tune", "odo", "huấn luyện", "ai cá nhân"],
     "body": "Xe không có kết nối pin (BMS), nên sau mỗi lần sạc app hỏi 'Đồng hồ xe đang báo bao nhiêu %?'. Nhập đúng số trên xe (và ODO nếu muốn). Số bạn nhập, lúc app tự nhận biết pin đầy và các chuyến đi chỉ được lưu và XẾP HÀNG; mô hình không tự đổi. Khi đủ dữ liệu mới (3 lần sạc hoặc 10 chuyến), app báo một lần; bạn vào Cài đặt → AI cá nhân và bấm Huấn luyện. App chỉ dùng bản mới nếu nó không kém bản cũ trên dữ liệu kiểm tra, và cho xem kết quả so sánh. Có thể nhập lại % trong Lịch sử → chi tiết phiên."},
    {"id": "charge-timed", "title": "Sạc hẹn giờ",
     "keywords": ["hẹn giờ", "timer", "30 phút", "1 giờ", "tự ngắt"],
     "body": "Sạc hẹn giờ bật ổ Shelly kèm bộ đếm giờ nạp thẳng vào ổ (toggle_after); ổ tự ngắt khi hết giờ kể cả khi mất mạng. Tối đa 10 giờ. Bật sạc luôn cần vuốt để xác nhận và chỉ báo thành công sau khi đọc lại thấy relay bật và timer chạy."},
    {"id": "charge-stop", "title": "Dừng sạc",
     "keywords": ["dừng sạc", "tắt sạc", "ngắt", "stop"],
     "body": "Dừng sạc bằng nút Dừng sạc ở tab Sạc pin, thẻ đang sạc, hoặc nhờ Pinova Bot. Máy chủ gửi lệnh tắt và đọc lại; nếu Shelly Cloud báo chậm, phiên chuyển 'chờ xác nhận' và không gửi lại lệnh."},
    {"id": "charge-locked", "title": "Vì sao nút sạc bị khóa",
     "keywords": ["bị khóa", "không bật được", "khóa", "chưa sẵn sàng", "giám sát"],
     "body": "Nút sạc khóa khi: chưa liên kết Shelly, Shelly ngoại tuyến, chưa qua kiểm tra an toàn không tải, máy chủ giám sát sạc chưa sẵn sàng (thường vài phút sau khi cập nhật), ổ đang bật, đang có phiên khác, hoặc số đo ngoài ngưỡng an toàn (điện áp 190–255 V, ≤12 A, ≤2500 W, ≤75 °C)."},
    {"id": "safety", "title": "An toàn khi sạc",
     "keywords": ["an toàn", "quá nhiệt", "12a", "2500w", "điện áp", "ngưỡng"],
     "body": "Giới hạn an toàn: tối đa 12 A / 2500 W, điện áp 190–255 V, nhiệt độ ổ ≤75 °C. Máy chủ kiểm tra số đo trực tiếp trước mỗi lần bật; vượt ngưỡng sẽ không bật hoặc tự ngắt. Không để xe sạc không người trông ở nơi dễ cháy."},
    {"id": "shelly-connect", "title": "Kết nối ổ Shelly",
     "keywords": ["kết nối shelly", "liên kết", "mã kết nối", "6 ký tự", "shelly plug"],
     "body": "Vào Cài đặt → Sạc thông minh Shelly. Nhập mã kết nối 6 ký tự do quản trị viên cấp (hạn 24 giờ, dùng một lần). Sau khi liên kết cần chạy kiểm tra an toàn không tải: rút mọi thiết bị khỏi ổ rồi làm theo hướng dẫn. Mỗi ổ dùng chung tối đa 2 tài khoản."},
    {"id": "shelly-offline", "title": "Shelly mất kết nối",
     "keywords": ["mất kết nối", "ngoại tuyến", "offline", "tạm mất", "không đọc được"],
     "body": "Nếu app báo 'Tạm mất kết nối': kiểm tra ổ còn điện, đèn ổ, Wi-Fi nhà, và trong app Shelly chính hãng ổ có online không. Rút ra cắm lại để ổ khởi động lại và đồng bộ giờ. App tự đọc lại; trong lúc đó điều khiển bị khóa để an toàn."},
    {"id": "history", "title": "Lịch sử sạc",
     "keywords": ["lịch sử", "phiên sạc", "chi phí", "điện năng", "wh", "kwh", "báo cáo", "xuất"],
     "body": "Tab Lịch sử hiển thị tổng kết tháng (điện nạp, chi phí, thời gian, số phiên) và từng phiên theo ngày; lọc theo xe, khoảng ngày, Sạc AI/Hẹn giờ. Chạm phiên để xem chi tiết. Có nút Xuất báo cáo. Chi phí dùng giá điện bạn đặt."},
    {"id": "tariff", "title": "Giá điện",
     "keywords": ["giá điện", "đồng/kwh", "tiền điện", "biểu giá"],
     "body": "Giá điện (đồng/kWh) dùng để tính chi phí mỗi phiên sạc. Đặt trong phần thiết lập sạc hoặc nhờ Pinova Bot đổi."},
    {"id": "maintenance", "title": "Bảo dưỡng xe",
     "keywords": ["bảo dưỡng", "bảo hành", "lịch hẹn", "nhắc", "odo"],
     "body": "Cài đặt → Bảo dưỡng xe hiển thị lịch bảo dưỡng theo ODO theo khuyến nghị VinFast. Pinova Bot có thể tạo, đổi ngày hoặc hủy lịch nhắc bảo dưỡng/bảo hành; ngày hết bảo hành do bạn cung cấp, không phải xác nhận của hãng."},
    {"id": "achievements", "title": "Thành tựu",
     "keywords": ["thành tựu", "huy hiệu", "hạng", "điểm"],
     "body": "Thành tựu ghi nhận thói quen tốt: sạc đúng mức bảo vệ pin, dùng Pinova Bot, duy trì bảo dưỡng... Mỗi thành tựu cho điểm và nâng hạng (Đồng, Bạc, Vàng...). Xem trong Cài đặt → Thành tựu."},
    {"id": "garage", "title": "Xe của tôi / Gara",
     "keywords": ["xe của tôi", "gara", "thêm xe", "đổi xe", "chọn xe", "phương tiện"],
     "body": "Cài đặt → Xe của tôi để thêm xe, sửa thông tin (tên, biển số, ODO, dung lượng pin) và chọn xe đang dùng. Chọn xe nhanh bằng nút tên xe ở đầu màn hình. Mọi số liệu sạc, lịch sử, bảo dưỡng gắn theo xe đang chọn."},
    {"id": "specs", "title": "Thông số xe",
     "keywords": ["thông số", "dung lượng pin", "công suất sạc", "ảnh xe"],
     "body": "Thông số xe lấy từ danh mục VinFast: dung lượng pin (Wh), công suất sạc, quãng đường công bố, hiệu suất. Xem ở Cài đặt → Gara xe → Thông số. Ảnh xe giống nhau ở Tổng quan, Gara và Thông số (không còn chế độ xoay 360°)."},
    {"id": "trip", "title": "Lộ trình: đi được tới đâu",
     "keywords": ["hành trình", "chuyến đi", "đi xa", "đủ pin", "lộ trình", "hao pin", "đi được không", "bao nhiêu km"],
     "body": "Lộ trình (Tổng quan → lối tắt, hoặc Cài đặt) ước tính % pin hao cho chuyến đi: chọn điểm đi (gõ hoặc 'Vị trí của tôi') và điểm đến trên OpenStreetMap, hoặc nhập số km; chọn tốc độ, thời tiết, số người, hàng, đường dốc, khứ hồi. App cho biết % khi tới nơi, kết luận đủ/sát/không đủ và gợi ý: sạc trước đến X% (mở tab Sạc đã điền mục tiêu), chạy chậm, tuyến ngắn hơn, sạc ở điểm đến. Mức hao dựa trên km cho 1% học từ ODO + % bạn nhập sau sạc, chưa đủ dữ liệu thì theo định mức dòng xe."},
    {"id": "battery-monitor", "title": "Theo dõi pin",
     "keywords": ["theo dõi pin", "nhiệt độ pin", "xu hướng"],
     "body": "Màn Theo dõi pin hiển thị mức pin, SoH, quãng đường ước tính, lịch sử 24 giờ và ước tính thời gian sạc tới 80%/100%."},
    {"id": "notifications", "title": "Thông báo",
     "keywords": ["thông báo", "push", "chuông", "nhắc"],
     "body": "Chuông ở góc trên mở Trung tâm thông báo. App hiện thông báo đang sạc (% · W · còn lại) và báo khi phiên kết thúc ('Đã sạc đến khoảng X%', 'Đã sạc xong theo hẹn giờ', 'Đã dừng sạc'), cảnh báo an toàn và nhắc bảo dưỡng. Bật/tắt trong Cài đặt → Thông báo đẩy (hoặc nhờ Pinova Bot). Tắt thông báo đẩy thì điện thoại này cũng không nhận tín hiệu tức thì khi máy khác bật/tắt sạc; trạng thái vẫn cập nhật ở lần đọc kế tiếp."},
    {"id": "language", "title": "Ngôn ngữ",
     "keywords": ["ngôn ngữ", "tiếng anh", "english", "tiếng việt", "language"],
     "body": "App hiện chỉ có tiếng Việt; chưa có bản tiếng Anh nên không có tùy chọn đổi ngôn ngữ."},
    {"id": "multi-device", "title": "Dùng nhiều điện thoại",
     "keywords": ["điện thoại khác", "nhiều máy", "đồng bộ", "đăng nhập máy khác"],
     "body": "Đăng nhập cùng tài khoản trên nhiều điện thoại: dữ liệu xe, lịch sử và trạng thái sạc đồng bộ qua máy chủ. Khi một máy bật/tắt sạc, máy kia nhận tín hiệu và cập nhật trong vài giây; mất tín hiệu thì cập nhật ở lần đọc kế tiếp (tối đa 60 giây)."},
    {"id": "battery-care", "title": "Mẹo giữ pin bền",
     "keywords": ["giữ pin", "bền pin", "80%", "chai pin", "mẹo"],
     "body": "Sạc tới 80% cho dùng hằng ngày giúp pin bền hơn; chỉ sạc 100% khi cần đi xa. Tránh để pin cạn dưới 10% lâu, tránh sạc ngay khi pin còn nóng sau khi chạy, đỗ xe nơi thoáng mát."},
    {"id": "privacy", "title": "Pinova Bot nhớ gì",
     "keywords": ["nhớ gì", "quyền riêng tư", "xóa dữ liệu", "học", "bộ nhớ"],
     "body": "Pinova Bot ghi nhớ những điều bạn kể (ví dụ quãng đường đi làm) và thói quen sạc để trả lời sát hơn. Xem, xóa từng mục hoặc tắt học trong Cài đặt → Trợ lý AI → 'Pinova Bot đang nhớ gì'. Câu hỏi được xử lý bởi Google Gemini qua máy chủ của app; bot không lưu toàn bộ cuộc trò chuyện lên máy chủ. Mỗi ngày có 50 lượt AI, hết lượt bot trả lời ở chế độ cơ bản."},
    {"id": "bot-scope", "title": "Pinova Bot làm được gì",
     "keywords": ["bot làm được gì", "giúp gì", "trợ lý", "batterybot"],
     "body": "Pinova Bot trả lời về app, xe, pin, sạc và Shelly; đọc trạng thái sạc và lịch sử của bạn; mở đúng màn hình; ước tính pin cho chuyến đi và thời gian sạc; chuẩn bị sạc đến X% hoặc bật sạc hẹn giờ (cần vuốt xác nhận), dừng sạc; cập nhật mức pin, ODO, xe đang chọn, mục tiêu sạc, giá điện; tạo/đổi/hủy lịch nhắc bảo dưỡng; bật/tắt thông báo đẩy. Thay đổi dữ liệu luôn có thẻ xác nhận."},
]


def fold(text: str) -> str:
    text = unicodedata.normalize("NFD", (text or "").lower()).replace("đ", "d")
    text = "".join(ch for ch in text if unicodedata.category(ch) != "Mn")
    return re.sub(r"[^a-z0-9%]+", " ", text).strip()


def _tokens(text: str) -> set[str]:
    return {token for token in fold(text).split() if len(token) > 1}


class KnowledgeBase:
    COLLECTION = "assistantKnowledge"

    def __init__(self, db=None, *, ttl_seconds: float = 60):
        self.db = db
        self.ttl = ttl_seconds
        self._cache: tuple[float, list[dict]] | None = None
        self._lock = threading.Lock()

    def entries(self) -> list[dict]:
        with self._lock:
            if self._cache and time.monotonic() - self._cache[0] <= self.ttl:
                return self._cache[1]
        merged = {entry["id"]: dict(entry, source="builtin") for entry in BUILTIN}
        if self.db is not None:
            try:
                for snapshot in self.db.collection(self.COLLECTION).limit(200).stream():
                    data = snapshot.to_dict() or {}
                    if data.get("enabled") is False:
                        merged.pop(snapshot.id, None)
                        continue
                    if not data.get("title") or not data.get("body"):
                        continue
                    merged[snapshot.id] = {
                        "id": snapshot.id, "title": str(data["title"])[:120],
                        "keywords": [str(k)[:60] for k in (data.get("keywords") or [])][:20],
                        "body": str(data["body"])[:2000], "source": "admin",
                    }
            except Exception:
                pass  # built-in knowledge still answers
        values = list(merged.values())
        with self._lock:
            self._cache = (time.monotonic(), values)
        return values

    def admin_entries(self) -> list[dict]:
        """Every entry for the dashboard, including hidden ones."""
        merged = {entry["id"]: dict(entry, source="builtin", enabled=True) for entry in BUILTIN}
        if self.db is not None:
            for snapshot in self.db.collection(self.COLLECTION).limit(200).stream():
                data = snapshot.to_dict() or {}
                base = merged.get(snapshot.id, {})
                merged[snapshot.id] = {
                    "id": snapshot.id,
                    "title": str(data.get("title") or base.get("title") or "")[:120],
                    "keywords": [str(k)[:60] for k in (data.get("keywords") or base.get("keywords") or [])][:20],
                    "body": str(data.get("body") or base.get("body") or "")[:2000],
                    "source": "admin", "enabled": data.get("enabled") is not False,
                }
        return list(merged.values())

    def invalidate(self) -> None:
        with self._lock:
            self._cache = None

    def search(self, query: str, limit: int = 4) -> list[dict]:
        words = _tokens(query)
        folded = f" {fold(query)} "
        scored = []
        for entry in self.entries():
            score = 0.0
            for keyword in entry.get("keywords") or []:
                key = fold(keyword)
                if key and f" {key} " in folded:
                    score += 3 + len(key.split())
            score += 0.6 * len(words & _tokens(entry["title"]))
            score += 0.15 * len(words & _tokens(entry["body"]))
            if score > 0:
                scored.append((score, entry))
        scored.sort(key=lambda item: -item[0])
        return [entry for _, entry in scored[:limit]]
