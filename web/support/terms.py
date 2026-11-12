"""Điều khoản sử dụng Pinova (QA 150, CNT-11).

The public page the app and the stores link to. Draft wording for the owner
to review: it only states what the app really does today (estimates, the
safety limits of the Shelly plug, plans activated by code while payments are
closed). Paid plans keep their own page, ``/dieu-khoan-premium``; personal
data is covered by ``/chinh-sach-bao-mat``. Bump ``VERSION`` on a change of
substance.
"""
from __future__ import annotations

import html

from .privacy import CONTACT_EMAIL, CONTROLLER

VERSION = "2026-11-12"

SECTIONS: list[tuple[str, list[str]]] = [
    ("Chấp nhận điều khoản", [
        f"Pinova là ứng dụng theo dõi pin và điều khiển sạc cho xe máy điện, do {CONTROLLER} phát triển và vận hành. Khi tạo tài khoản hoặc tiếp tục dùng Pinova, bạn đồng ý với các điều khoản này.",
        "Pinova là ứng dụng độc lập, không phải sản phẩm của VinFast hay Shelly và không được các hãng này bảo trợ. Tên xe và tên thiết bị chỉ dùng để mô tả sự tương thích.",
    ]),
    ("Tài khoản", [
        "Bạn cần đủ 16 tuổi và cung cấp thông tin đúng khi đăng ký.",
        "Bạn tự giữ bí mật mật khẩu và chịu trách nhiệm về hoạt động trong tài khoản của mình. Hãy báo cho chúng tôi nếu nghi ngờ tài khoản bị người khác dùng.",
        "Bạn có thể xóa tài khoản và dữ liệu bất cứ lúc nào tại Cài đặt → Hồ sơ → Xóa tài khoản.",
    ]),
    ("Số liệu trong app là ước tính", [
        "% pin, thời gian sạc, quãng đường còn lại, sức khỏe pin và lộ trình được tính từ số bạn nhập, điện năng ổ Shelly đo và thông số hãng công bố. Xe không gửi dữ liệu trực tiếp cho Pinova, nên các số này là ước tính và có thể lệch với thực tế.",
        "Trước khi đi xa, hãy xem số trên đồng hồ xe. Đừng chỉ dựa vào ước tính của app để quyết định có đủ pin hay không.",
        "Pinova Bot trả lời bằng AI và có thể sai. Các câu trả lời không thay cho hướng dẫn sử dụng của hãng xe hay ý kiến của kỹ thuật viên.",
    ]),
    ("Sạc thông minh và an toàn điện", [
        "Tính năng bật, ngắt và hẹn sạc cần ổ cắm thông minh Shelly do bạn tự mua và lắp. Bạn chịu trách nhiệm dùng bộ sạc chính hãng, ổ điện và dây dẫn đủ tải, lắp ổ Shelly đúng hướng dẫn của nhà sản xuất.",
        "Pinova giới hạn tải ở 12 A / 2500 W và tự ngắt khi phát hiện quá nhiệt, quá công suất hoặc mất kết nối kéo dài. Các lớp bảo vệ này phụ thuộc vào mạng, Shelly Cloud và thiết bị, nên không thay cho sự giám sát của bạn và các biện pháp phòng cháy thông thường.",
        "Không sạc gần vật dễ cháy, không để xe sạc ở nơi không thoát được khi có sự cố. Khi có khói, mùi khét, tiếng nổ hoặc pin nóng bất thường: ngắt điện nếu an toàn, rời khỏi khu vực và gọi 114.",
    ]),
    ("Gói Free, Pro và Ultra", [
        "Gói Free dùng được không thời hạn. Pro và Ultra mở thêm tính năng, có thời hạn và không tự gia hạn.",
        "Hiện Pinova chưa thu tiền; gói Pro và Ultra được kích hoạt bằng mã do Pinova phát. Khi mở thanh toán, điều kiện mua, đổi và hoàn tiền nằm ở trang Điều khoản gói Premium (/dieu-khoan-premium).",
        "Hết hạn gói, tài khoản về Free và dữ liệu của bạn vẫn được giữ. Dừng sạc và các lớp an toàn không bao giờ bị khóa theo gói.",
    ]),
    ("Điều bạn không được làm", [
        "Dùng Pinova để điều khiển thiết bị không phải của bạn hoặc không được chủ thiết bị cho phép.",
        "Tìm cách vượt giới hạn an toàn, can thiệp vào máy chủ, dò mã kết nối hoặc mã khuyến mãi, hoặc truy cập dữ liệu của tài khoản khác.",
        "Gửi nội dung vi phạm pháp luật, quấy rối hoặc spam qua Pinova Bot và phiếu hỗ trợ. Chúng tôi có thể tạm khóa tính năng hoặc tài khoản vi phạm.",
    ]),
    ("Dữ liệu cá nhân", [
        "Việc thu thập và xử lý dữ liệu cá nhân tuân theo Chính sách bảo mật (/chinh-sach-bao-mat).",
    ]),
    ("Giới hạn trách nhiệm", [
        "Pinova được cung cấp theo hiện trạng. Chúng tôi cố gắng giữ dịch vụ ổn định nhưng không cam kết dịch vụ không gián đoạn hay không có lỗi; dịch vụ còn phụ thuộc vào bên thứ ba như Firebase, Azure, Shelly Cloud và nhà mạng.",
        "Trong phạm vi pháp luật cho phép, chúng tôi không chịu trách nhiệm về thiệt hại do dùng sai hướng dẫn, do thiết bị điện, bộ sạc, pin hoặc việc lắp đặt không an toàn, hay do quyết định chỉ dựa vào số ước tính. Điều khoản này không loại trừ các quyền của người tiêu dùng theo pháp luật Việt Nam.",
    ]),
    ("Thay đổi và chấm dứt", [
        "Chúng tôi có thể thêm, đổi hoặc ngừng một tính năng. Thay đổi quan trọng với điều khoản này được báo trong app trước khi có hiệu lực.",
        "Bạn có thể ngừng dùng và xóa tài khoản bất cứ lúc nào. Chúng tôi có thể khóa tài khoản vi phạm điều khoản sau khi đã báo lý do, trừ trường hợp cần chặn ngay để giữ an toàn.",
    ]),
    ("Luật áp dụng và liên hệ", [
        "Điều khoản này theo pháp luật Việt Nam. Tranh chấp được ưu tiên giải quyết bằng thương lượng trước khi đưa ra cơ quan có thẩm quyền.",
        f"Liên hệ: {CONTACT_EMAIL}, hoặc gửi phiếu trong app tại Cài đặt → Trợ giúp.",
        f"Phiên bản {VERSION}.",
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
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Điều khoản sử dụng Pinova</title>
<style>body{{font:16px/1.6 system-ui,sans-serif;max-width:720px;margin:0 auto;padding:24px 16px;color:#16181a;background:#f6f7f5}}
h1{{font-size:1.6rem}}h2{{font-size:1.15rem;margin-top:1.6em}}li{{margin:4px 0}}.v{{color:#555}}</style></head><body>
<h1>Điều khoản sử dụng Pinova</h1><p class="v">Phiên bản {VERSION}</p>{body}</body></html>"""
