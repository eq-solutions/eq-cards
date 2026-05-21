abstract class Routes {
  static const splash = '/';

  // Cards Unit 4 (2026-05-21) — replaces email/otp with iframe handoff.
  // The legacy /auth/email and /auth/otp routes are gone; any external
  // bookmark to them lands on /auth/handoff via the redirect logic.
  static const handoff = '/auth/handoff';

  static const home = '/home';
  static const profile = '/profile';
  static const profileEdit = '/profile/edit';
  static const licencesList = '/licences';
  static const licenceCreate = '/licences/new';
  static const licenceCapture = '/licences/capture';
  static const licenceDetail = '/licences/:id';
  static const licenceEdit = '/licences/:id/edit';
  static const settings = '/settings';
  static const privacyPolicy = '/legal/privacy';
  static const termsOfUse = '/legal/terms';

  /// URL builders for path-parameter routes. Use these instead of hand-rolled
  /// string interpolation so the route shapes stay in one place.
  static String licenceDetailFor(String id) => '/licences/$id';
  static String licenceEditFor(String id) => '/licences/$id/edit';
}
