enum AuthState {
  authenticated,
  unauthenticated,
  /// Signed in but no tenant_id in app_metadata — user has a valid Supabase
  /// session but has not been provisioned to any EQ workspace. The custom
  /// access token hook on eq-canonical only injects tenant_id when the user
  /// exists in shell_control.users; a self-registered phone OTP user who
  /// bypassed the invite flow lands here.
  notProvisioned,
}
