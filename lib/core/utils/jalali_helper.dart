// lib/core/utils/jalali_helper.dart

class JalaliHelper {
  static const List<String> _shamsiMonths = [
    'فروردین',
    'اردیبهشت',
    'خرداد',
    'تیر',
    'مرداد',
    'شهریور',
    'مهر',
    'آبان',
    'آذر',
    'دی',
    'بهمن',
    'اسفند',
  ];

  static const List<String> _weekDays = [
    'دوشنبه',
    'سه‌شنبه',
    'چهارشنبه',
    'پنج‌شنبه',
    'جمعه',
    'شنبه',
    'یک‌شنبه',
  ];

  /// تبدیل رشته YYYY-MM-DD به فرمت کامل شمسی (مثلاً: شنبه ۱۰ آبان ۱۴۰۵)
  static String formatToShamsi(String? gregorianDateStr) {
    if (gregorianDateStr == null || gregorianDateStr.trim().isEmpty) {
      return 'زمان نامشخص';
    }

    try {
      final date = DateTime.parse(gregorianDateStr);
      final gYear = date.year;
      final gMonth = date.month;
      final gDay = date.day;

      final gDaysInMonth = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
      if (gYear % 4 == 0 && (gYear % 100 != 0 || gYear % 400 == 0)) {
        gDaysInMonth[2] = 29;
      }

      int gy2 = (gMonth > 2) ? (gYear + 1) : gYear;
      int gDayNo =
          365 * gYear +
          ((gy2 + 3) ~/ 4) -
          ((gy2 + 99) ~/ 100) +
          ((gy2 + 399) ~/ 400) -
          80;
      for (int i = 0; i < gMonth; ++i) {
        gDayNo += gDaysInMonth[i];
      }
      gDayNo += gDay;

      int jNp = gDayNo ~/ 12053;
      gDayNo %= 12053;
      int jy = 979 + 33 * jNp + 4 * (gDayNo ~/ 1461);
      gDayNo %= 1461;

      if (gDayNo >= 366) {
        jy += ((gDayNo - 1) ~/ 365);
        gDayNo = (gDayNo - 1) % 365;
      }

      int jm, jd;
      if (gDayNo < 186) {
        jm = 1 + (gDayNo ~/ 31);
        jd = 1 + (gDayNo % 31);
      } else {
        jm = 7 + ((gDayNo - 186) ~/ 30);
        jd = 1 + ((gDayNo - 186) % 30);
      }

      final dayName = _weekDays[date.weekday - 1];
      final monthName = _shamsiMonths[jm - 1];

      return '$dayName $jd $monthName $jy';
    } catch (_) {
      return gregorianDateStr;
    }
  }
}
