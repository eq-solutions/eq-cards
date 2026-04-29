import 'package:flutter/material.dart';

import '../theme/eq_colours.dart';

abstract class EqSnackbar {
  static void show(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(milliseconds: 1500),
    Color? background,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        backgroundColor: background ?? EqColours.ink,
      ),
    );
  }
}
