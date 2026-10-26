/// Number text shared by every screen (QA 129).
///
/// The app writes decimals with a dot ("1.21 km / 1% pin", "1.5 kWh"), so a
/// dot cannot also group thousands: "4.804 km ODO" next to "1.20" read as two
/// different kinds of number. Thousands use a narrow no-break space instead
/// ("4 804 km", "12 500 đ"), which no one reads as a decimal.
const String thousandsSeparator = ' ';

String groupThousands(num value) {
  final negative = value < 0;
  final digits = value.abs().round().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(thousandsSeparator);
    out.write(digits[i]);
  }
  return negative ? '-$out' : out.toString();
}

/// Money (QA 137, owner's choice): the Vietnamese way, "249.000đ" — dots
/// group thousands and "đ" follows the number. Only money: VND has no
/// decimals here, so the dot cannot be misread, while every other number
/// keeps [groupThousands] and the decimal point.
String formatVnd(num value) {
  final digits = value.abs().round().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return '$outđ';
}
