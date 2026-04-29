import 'package:intl/intl.dart';

abstract class EqDates {
  static final _displayFormat = DateFormat('d MMM yyyy');

  static String display(DateTime date) => _displayFormat.format(date);

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
