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
    this.textCapitalization = TextCapitalization.none,
    this.onEditingComplete,
    this.autofocus = false,
    this.validator,
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
  final TextCapitalization textCapitalization;
  final VoidCallback? onEditingComplete;
  final bool autofocus;

  /// Field-level validator. When non-null, the widget renders as a
  /// `TextFormField` so the parent `Form` picks it up. Use the validators
  /// from `core/validators/input_validators.dart` for consistency.
  final FormFieldValidator<String>? validator;

  InputDecoration _decoration() => InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        labelStyle: EqTypography.label,
        filled: true,
        fillColor: EqColours.surface,
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
      );

  @override
  Widget build(BuildContext context) {
    if (validator != null) {
      return TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        onEditingComplete: onEditingComplete,
        textInputAction: textInputAction,
        textCapitalization: textCapitalization,
        autofocus: autofocus,
        style: EqTypography.bodyL,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: validator,
        decoration: _decoration(),
      );
    }
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onEditingComplete: onEditingComplete,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      autofocus: autofocus,
      style: EqTypography.bodyL,
      decoration: _decoration(),
    );
  }
}
