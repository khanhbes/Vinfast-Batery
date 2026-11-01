"""Chính sách bảo mật and the owner's consent (QA 140).

One source for the public page (stores and the app link to it) and for the
version the app asks to accept. Written for Nghị định 13/2023/NĐ-CP and the
Luật Bảo vệ dữ liệu cá nhân 2025: who processes the data, which data and
why, who else receives it (and abroad), how long it is kept, the owner's
rights and how to use them. A change of substance bumps ``VERSION``; the app
then asks again.
"""
from __future__ import annotations

import html
from datetime import datetime, timezone

VERSION = "2026-11-01"
CONTROLLER = "Khanh Bes"
CONTACT_EMAIL = "khanhnhim21102004@gmail.com"

SECTIONS: list[tuple[str, list[str]]] = [
    ("Ai xử lý dữ liệu của bạn", [
        f"Pinova (ứng dụng quản lý pin xe máy điện) do {CONTROLLER} phát triển và vận hành, là bên kiểm soát và xử lý dữ liệu cá nhân của bạn. Liên hệ về dữ liệu cá nhân: {CONTACT_EMAIL}.",
    ]),
    ("Dữ liệu chúng tôi thu thập", [
        "Tài khoản: email, tên, số điện thoại (nếu bạn nhập), năm sinh để xác nhận đủ tuổi.",
        "Xe: dòng xe, tên gọi, biển số (nếu nhập), % pin và số ODO bạn nhập hoặc quét, tình trạng pin.",
        "Sạc: các phiên sạc, điện năng, công suất, điện áp, nhiệt độ do ổ Shelly đo; giờ bật, giờ ngắt, mức pin ước tính.",
        "Ổ Shelly: mã thiết bị và thông tin kết nối (khóa truy cập được mã hóa, chỉ máy chủ đọc).",
        "Vị trí: chỉ khi bạn dùng Lộ trình (\"Vị trí của tôi\") hoặc khi Android yêu cầu để tìm ổ Shelly trong mạng Wi-Fi; không theo dõi vị trí nền.",
        "Ảnh đồng hồ xe: đọc ngay trên điện thoại; khi bạn chọn đọc bằng AI, ảnh được gửi tới máy chủ để đọc rồi bỏ, không lưu.",
        "Pinova Bot: nội dung bạn hỏi được gửi tới dịch vụ AI để trả lời; bot chỉ ghi nhớ một số thông tin ngắn nếu bạn bật \"học cá nhân\" (xem, xóa hoặc tắt trong app); lịch sử trò chuyện lưu trên điện thoại.",
        "Thiết bị: mã nhận thông báo đẩy, phiên bản app; nhật ký kỹ thuật (thời điểm, mã lỗi) để vận hành an toàn.",
        "Gói dịch vụ và phiếu hỗ trợ bạn gửi.",
    ]),
    ("Mục đích", [
        "Điều khiển sạc an toàn (bật, ngắt, giới hạn an toàn, cảnh báo) và hiển thị trạng thái sạc.",
        "Ước tính % pin, thời gian sạc, quãng đường, sức khỏe pin và đánh giá thói quen sạc.",
        "Học mô hình riêng cho xe của bạn khi bạn cho phép (tắt được trong AI cá nhân).",
        "Gửi thông báo về phiên sạc, an toàn, bảo dưỡng; trả lời yêu cầu hỗ trợ; quản lý gói.",
        "Không bán dữ liệu, không dùng để quảng cáo của bên thứ ba.",
    ]),
    ("Bên nhận dữ liệu và chuyển ra nước ngoài", [
        "Google Firebase (xác thực, cơ sở dữ liệu Firestore đặt tại Hoa Kỳ, thông báo đẩy).",
        "Microsoft Azure (máy chủ ứng dụng tại Hồng Kông và cổng chuyển tiếp AI tại Nhật Bản; dịch vụ email).",
        "Google Gemini (trả lời Pinova Bot, đọc ảnh đồng hồ khi bạn chọn), qua máy chủ của Pinova.",
        "Shelly Cloud (Allterco) để điều khiển và đọc ổ Shelly của bạn.",
        "OpenStreetMap (OSRM, Nominatim) để tìm đường cho Lộ trình, qua máy chủ của Pinova; chỉ gửi điểm đi và điểm đến.",
        "Các bên trên xử lý dữ liệu theo hợp đồng và chính sách của họ. Việc dữ liệu được lưu và xử lý ngoài Việt Nam là cần thiết để cung cấp dịch vụ; khi đồng ý chính sách này bạn đồng ý với việc chuyển đó.",
    ]),
    ("Thời gian lưu trữ", [
        "Dữ liệu tài khoản, xe và lịch sử sạc được lưu trong thời gian bạn dùng Pinova và xóa khi bạn xóa tài khoản.",
        "Nhật ký kỹ thuật lưu tối đa 30 ngày. Ảnh gửi đọc bằng AI không được lưu.",
    ]),
    ("Quyền của bạn", [
        "Được biết, đồng ý hoặc rút lại đồng ý; xem, sửa, yêu cầu cung cấp; hạn chế hoặc phản đối xử lý; xóa dữ liệu; khiếu nại.",
        "Xóa tài khoản và toàn bộ dữ liệu: trong app tại Cài đặt → Hồ sơ → Xóa tài khoản, hoặc xem hướng dẫn tại /xoa-tai-khoan.",
        "Tắt học cá nhân của Pinova Bot và AI cá nhân, xóa dữ liệu đã học ngay trong app.",
        f"Mọi yêu cầu khác gửi tới {CONTACT_EMAIL}; chúng tôi trả lời trong vòng 72 giờ làm việc.",
    ]),
    ("Bảo vệ dữ liệu", [
        "Kết nối mã hóa (HTTPS); quyền truy cập theo tài khoản; khóa thiết bị Shelly được mã hóa; dữ liệu của bạn chỉ chính bạn đọc được trong app.",
        "Khi xảy ra sự cố lộ lọt dữ liệu, chúng tôi thông báo cho bạn và cơ quan chức năng theo quy định.",
    ]),
    ("Trẻ em", [
        "Pinova dành cho người đủ tuổi điều khiển xe; app kiểm tra tuổi tối thiểu khi đăng ký và không cố ý thu thập dữ liệu của trẻ em.",
    ]),
    ("Thay đổi chính sách", [
        f"Phiên bản {VERSION}. Khi có thay đổi quan trọng, app hỏi lại sự đồng ý của bạn trước khi tiếp tục.",
    ]),
]


def render_page() -> str:
    body = "".join(
        f"<h2>{html.escape(title)}</h2><ul>"
        + "".join(f"<li>{html.escape(item)}</li>" for item in items)
        + "</ul>"
        for title, items in SECTIONS
    )
    return f"""<!doctype html><html lang="vi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Chính sách bảo mật Pinova</title>
<style>body{{font:16px/1.6 system-ui,sans-serif;max-width:720px;margin:0 auto;padding:24px 16px;color:#16181a;background:#f6f7f5}}
h1{{font-size:1.6rem}}h2{{font-size:1.15rem;margin-top:1.6em}}li{{margin:4px 0}}.v{{color:#555}}</style></head><body>
<h1>Chính sách bảo mật Pinova</h1><p class="v">Phiên bản {VERSION}</p>{body}</body></html>"""


class PrivacyConsents:
    """``users/{uid}.privacyConsent`` = {version, at, source}; written only by
    the server (Admin SDK), as the client rules forbid that field."""

    def __init__(self, db=None, clock=None):
        self.db = db
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        self._local: dict[str, dict] = {}

    def get(self, uid: str) -> dict | None:
        if self.db is None:
            return self._local.get(uid)
        data = self.db.collection("users").document(uid).get().to_dict() or {}
        value = data.get("privacyConsent")
        return value if isinstance(value, dict) else None

    def record(self, uid: str, version: str, source: str) -> dict:
        if version != VERSION:
            raise ValueError("privacyVersionOutdated")
        value = {"version": VERSION, "at": self.clock().isoformat(), "source": source[:20] or "app"}
        if self.db is None:
            self._local[uid] = value
        else:
            self.db.collection("users").document(uid).set({"privacyConsent": value}, merge=True)
        return value

    def status(self, uid: str) -> dict:
        current = self.get(uid)
        return {"version": VERSION, "accepted": bool(current and current.get("version") == VERSION),
                "acceptedAt": (current or {}).get("at"), "url": "/chinh-sach-bao-mat"}
