import 'package:flutter/material.dart';

import '../theme/eq_colours.dart';
import '../theme/eq_typography.dart';

class EqTextField extends StatelessWidget {
  const EqTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.keyboardType,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      autofocus: autofocus,
      style: EqTypography.bodyL,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        labelStyle: EqTypography.label,
        filled: true,
        fillColor: EqColours.ice,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: EqColours.sky, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: EqColours.error, width: 2),
        ),
      ),
    );
  }
}
