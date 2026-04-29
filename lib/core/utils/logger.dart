import 'package:flutter/foundation.dart';

void logD(Object? message) {
  if (kDebugMode) debugPrint('[D] $message');
}

void logI(Object? message) {
  if (kDebugMode) debugPrint('[I] $message');
}

void logW(Object? message) {
  if (kDebugMode) debugPrint('[W] $message');
}
