import 'package:freezed_annotation/freezed_annotation.dart';

part 'licence_type.freezed.dart';
part 'licence_type.g.dart';

@freezed
class LicenceType with _$LicenceType {
  const factory LicenceType({
    required String id,
    required String code,
    required String label,
    @Default(false) bool requiresState,
    int? defaultValidityMonths,
    @Default(false) bool isCustom,
    String? userId,
    DateTime? createdAt,
  }) = _LicenceType;

  factory LicenceType.fromJson(Map<String, dynamic> json) =>
      _$LicenceTypeFromJson(json);
}
