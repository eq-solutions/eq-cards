import 'package:intl/intl.dart';

abstract class EqDates {
  static final _displayFormat = DateFormat('d MMM yyyy');

  static String display(DateTime date) => _displayFormat.format(date);

  /// Formats [date] as an ISO date string (`yyyy-MM-dd`) — the shape the
  /// backend RPCs and the data export expect. Date-only: time and timezone are
  /// intentionally dropped. Single source of truth for outbound date
  /// formatting, replacing the per-file `_isoDate` helpers that had drifted
  /// across the repositories and the export builder.
  static String iso(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static int daysUntil(DateTime expiry) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(expiry.year, expiry.month, expiry.day);
    return target.difference(today).inDays;
  }

  static bool isExpiringSoon(DateTime expiry, {int withinDays = 90}) {
    final days = daysUntil(expiry);
    return days >= 0 && days <= withinDays;
  }

  static bool isExpired(DateTime expiry) => daysUntil(expiry) < 0;
}
