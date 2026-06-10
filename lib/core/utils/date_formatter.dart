/// Utility class for formatting dates and times in Arabic context.
///
/// All methods return strings suitable for display in RTL layouts.
class DateFormatter {
  DateFormatter._();

  /// Formats [date] as `DD/MM/YYYY`.
  ///
  /// Example: `formatDate(DateTime(2025, 3, 5))` → `'05/03/2025'`
  static String formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  /// Formats [date] as `DD/MM/YYYY HH:MM`.
  ///
  /// Example: `formatDateTime(DateTime(2025, 3, 5, 14, 7))` → `'05/03/2025 14:07'`
  static String formatDateTime(DateTime date) {
    return '${formatDate(date)} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  /// Formats [date] as `HH:MM`.
  ///
  /// Example: `formatTime(DateTime(2025, 3, 5, 9, 5))` → `'09:05'`
  static String formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  /// (B-1/A-5) يبني timestamp كامل للتخزين من اليوم الذي اختاره
  /// المستخدم + وقت اللحظة الحالية، بصيغة ISO-8601.
  ///
  /// الجذر التاريخي: شاشات السندات كانت تخزن `date` بصيغة يوم-فقط
  /// (`2026-06-10`) بينما بقية النظام يخزن timestamp كاملاً، مما كسر
  /// الفرز الزمني والرصيد التراكمي عند اختلاط الصيغتين في نفس اليوم.
  ///
  /// القاعدة المعتمدة: التاريخ المحاسبي = اليوم الذي اختاره المستخدم
  /// (يُحترم حتى لو كان ماضياً)، والوقت = لحظة الحفظ الفعلية — فيبقى
  /// الترتيب داخل اليوم الواحد بترتيب الإدخال الحقيقي.
  static String storageTimestamp(DateTime selectedDay, {DateTime? now}) {
    final t = now ?? DateTime.now();
    return DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day,
      t.hour,
      t.minute,
      t.second,
      t.millisecond,
      t.microsecond,
    ).toIso8601String();
  }

  /// Returns a time-of-day greeting in Arabic.
  ///
  /// - Before 12:00 → `'صباح الخير'`
  /// - 12:00–16:59  → `'مساء الخير'`
  /// - 17:00+        → `'مساء الخير'`
  static String getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'صباح الخير';
    return 'مساء الخير';
  }

  /// Returns a human-readable relative time string in Arabic.
  ///
  /// Examples:
  /// - `5 seconds ago` → `'منذ ٥ ثوانٍ'`
  /// - `3 minutes ago` → `'منذ ٣ دقائق'`
  /// - `2 hours ago`   → `'منذ ساعتين'`
  /// - `1 day ago`     → `'منذ يوم'`
  /// - `5 days ago`    → `'منذ ٥ أيام'`
  static String timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);

    if (diff.inSeconds < 60) {
      return 'منذ ${_toArabicNumeral(diff.inSeconds)} ثانية';
    }
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      if (m == 1) return 'منذ دقيقة';
      if (m == 2) return 'منذ دقيقتين';
      if (m <= 10) return 'منذ ${_toArabicNumeral(m)} دقائق';
      return 'منذ ${_toArabicNumeral(m)} دقيقة';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      if (h == 1) return 'منذ ساعة';
      if (h == 2) return 'منذ ساعتين';
      if (h <= 10) return 'منذ ${_toArabicNumeral(h)} ساعات';
      return 'منذ ${_toArabicNumeral(h)} ساعة';
    }
    if (diff.inDays < 30) {
      final d = diff.inDays;
      if (d == 1) return 'منذ يوم';
      if (d == 2) return 'منذ يومين';
      if (d <= 10) return 'منذ ${_toArabicNumeral(d)} أيام';
      return 'منذ ${_toArabicNumeral(d)} يوماً';
    }
    if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      if (months == 1) return 'منذ شهر';
      if (months == 2) return 'منذ شهرين';
      if (months <= 10) return 'منذ ${_toArabicNumeral(months)} أشهر';
      return 'منذ ${_toArabicNumeral(months)} شهراً';
    }
    final years = (diff.inDays / 365).floor();
    if (years == 1) return 'منذ سنة';
    if (years == 2) return 'منذ سنتين';
    return 'منذ ${_toArabicNumeral(years)} سنة';
  }

  /// Returns the day-of-week name in Arabic.
  static String dayName(DateTime date) {
    const days = [
      'الأحد',
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
    ];
    return days[date.weekday % 7];
  }

  /// Returns the month name in Arabic.
  static String monthName(DateTime date) {
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    return months[date.month - 1];
  }

  /// Formats [date] as `DD monthName YYYY` in Arabic.
  ///
  /// Example: `'05 مارس 2025'`
  static String formatDateLong(DateTime date) {
    return '${date.day} ${monthName(date)} ${date.year}';
  }

  // ── Private helpers ────────────────────────────────────────────

  /// Converts Western numerals to Eastern Arabic numerals.
  static String _toArabicNumeral(int number) {
    const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    var result = number.toString();
    for (var i = 0; i < western.length; i++) {
      result = result.replaceAll(western[i], eastern[i]);
    }
    return result;
  }
}
